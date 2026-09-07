#!/usr/bin/env python3
"""Governed, fail-closed, sandbox-only canary orchestrator for LF."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import source_first_main_parity_guard as source_first

VERSION = "LF_GOVERNED_CANARY_RUNNER_V1"
ALLOWED_ENVIRONMENTS = {"sandbox", "ephemeral", "test"}
ALLOWED_CHANGE_MODES = {"MIGRATION_EXACT_VERSION", "RUNTIME_CANDIDATE", "REPOSITORY_ONLY", "GENERIC_SANDBOX"}
PHASES = ("preflight", "forward", "tests", "rollback", "post_readback")
VERSION_RE = re.compile(r"^20\d{12}$")
ID_RE = re.compile(r"^[A-Z0-9][A-Z0-9_.:-]{2,127}$")
TOKEN_RE = re.compile(r"^[A-Z0-9][A-Z0-9_.:-]{2,127}$")
SAFE_BASE_ENV = ("PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "TEMP", "TMP")
SHELL_INTERPRETERS = {"sh", "bash", "zsh", "cmd", "powershell", "pwsh"}
CLAIM_CEILING = "SANDBOX_CANARY_EVIDENCE_ONLY_NO_PRODUCTION_OR_GOLDEN_CLAIM"


class ContractError(ValueError):
    pass


@dataclass
class StepOutcome:
    phase: str
    step_id: str
    status: str
    returncode: int | None
    elapsed_ms: float
    stdout_sha256: str | None
    stderr_sha256: str | None
    failure: str | None

    def as_dict(self) -> dict[str, Any]:
        return {
            "phase": self.phase,
            "step_id": self.step_id,
            "status": self.status,
            "returncode": self.returncode,
            "elapsed_ms": round(self.elapsed_ms, 3),
            "stdout_sha256": self.stdout_sha256,
            "stderr_sha256": self.stderr_sha256,
            "failure": self.failure,
        }


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_json(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return _sha256_bytes(raw)


def _load_manifest(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"MANIFEST_READ_ERROR:{type(exc).__name__}") from exc
    if not isinstance(data, dict):
        raise ContractError("MANIFEST_ROOT_NOT_OBJECT")
    return data


def _require_object(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise ContractError(f"{key.upper()}_NOT_OBJECT")
    return value


def _require_steps(manifest: dict[str, Any], phase: str) -> list[dict[str, Any]]:
    steps = _require_object(manifest, "steps").get(phase)
    if not isinstance(steps, list) or not steps:
        raise ContractError(f"{phase.upper()}_STEPS_INVALID")
    if not all(isinstance(step, dict) for step in steps):
        raise ContractError(f"{phase.upper()}_STEP_NOT_OBJECT")
    return steps


def _validate_source_first(manifest: dict[str, Any], forward: str, rollback: str) -> None:
    source_first_contract = manifest.get("source_first")
    if not isinstance(source_first_contract, dict):
        raise ContractError("SOURCE_FIRST_REQUIRED")
    if source_first_contract.get("main_ref") != "origin/main":
        raise ContractError("SOURCE_FIRST_MAIN_REF_INVALID")
    if source_first_contract.get("require_identical_git_blob") is not True:
        raise ContractError("SOURCE_FIRST_IDENTICAL_BLOB_REQUIRED")
    if source_first_contract.get("fetch_main") is not True:
        raise ContractError("SOURCE_FIRST_FETCH_MAIN_REQUIRED")
    paths = source_first_contract.get("paths")
    if not isinstance(paths, list) or len(paths) != 2 or not all(isinstance(path, str) and path for path in paths):
        raise ContractError("SOURCE_FIRST_PATHS_INVALID")
    if len(set(paths)) != 2:
        raise ContractError("SOURCE_FIRST_PATHS_DUPLICATE")
    for path in paths:
        p = Path(path)
        if p.is_absolute() or ".." in p.parts or not path.startswith("supabase/migrations/"):
            raise ContractError("SOURCE_FIRST_PATH_NOT_GOVERNED_MIGRATION")
    if not Path(paths[0]).name.startswith(forward + "_"):
        raise ContractError("SOURCE_FIRST_FORWARD_PATH_VERSION_MISMATCH")
    if not Path(paths[1]).name.startswith(rollback + "_"):
        raise ContractError("SOURCE_FIRST_ROLLBACK_PATH_VERSION_MISMATCH")


def validate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    if manifest.get("contract_version") != VERSION:
        raise ContractError("CONTRACT_VERSION_MISMATCH")
    canary_id = manifest.get("canary_id")
    if not isinstance(canary_id, str) or not ID_RE.fullmatch(canary_id):
        raise ContractError("CANARY_ID_INVALID")

    target = _require_object(manifest, "target")
    if target.get("environment") not in ALLOWED_ENVIRONMENTS:
        raise ContractError("TARGET_ENVIRONMENT_NOT_SANDBOX")
    if target.get("production") is not False:
        raise ContractError("PRODUCTION_MUST_BE_FALSE")
    if target.get("merge_authorized") is not False:
        raise ContractError("MERGE_AUTHORIZED_MUST_BE_FALSE")
    if target.get("automatic_promotion") is not False:
        raise ContractError("AUTOMATIC_PROMOTION_MUST_BE_FALSE")

    mode = manifest.get("change_mode")
    if mode not in ALLOWED_CHANGE_MODES:
        raise ContractError("CHANGE_MODE_INVALID")
    if mode == "MIGRATION_EXACT_VERSION":
        exact = manifest.get("exact_versions")
        if not isinstance(exact, dict):
            raise ContractError("EXACT_VERSIONS_REQUIRED")
        forward, rollback = exact.get("forward"), exact.get("rollback")
        if not isinstance(forward, str) or not VERSION_RE.fullmatch(forward):
            raise ContractError("FORWARD_VERSION_INVALID")
        if not isinstance(rollback, str) or not VERSION_RE.fullmatch(rollback):
            raise ContractError("ROLLBACK_VERSION_INVALID")
        if forward == rollback:
            raise ContractError("FORWARD_ROLLBACK_VERSION_COLLISION")
        _validate_source_first(manifest, forward, rollback)

    all_ids: set[str] = set()
    for phase in PHASES:
        for index, step in enumerate(_require_steps(manifest, phase)):
            step_id = step.get("id")
            if not isinstance(step_id, str) or not ID_RE.fullmatch(step_id):
                raise ContractError(f"{phase.upper()}_STEP_ID_INVALID:{index}")
            if step_id in all_ids:
                raise ContractError(f"DUPLICATE_STEP_ID:{step_id}")
            all_ids.add(step_id)
            argv = step.get("argv")
            if not isinstance(argv, list) or not argv or not all(isinstance(x, str) and x and "\x00" not in x for x in argv):
                raise ContractError(f"ARGV_INVALID:{step_id}")
            if argv[0] in SHELL_INTERPRETERS and step.get("allow_shell_interpreter") is not True:
                raise ContractError(f"SHELL_INTERPRETER_FORBIDDEN:{step_id}")
            timeout = step.get("timeout_seconds")
            if not isinstance(timeout, int) or timeout < 1 or timeout > 1800:
                raise ContractError(f"TIMEOUT_INVALID:{step_id}")
            env_names = step.get("env_names", [])
            if not isinstance(env_names, list) or not all(isinstance(x, str) and re.fullmatch(r"[A-Z_][A-Z0-9_]*", x) for x in env_names):
                raise ContractError(f"ENV_NAMES_INVALID:{step_id}")
            expect = step.get("expect", {})
            if not isinstance(expect, dict):
                raise ContractError(f"EXPECT_INVALID:{step_id}")
            exit_codes = expect.get("exit_codes", [0])
            if not isinstance(exit_codes, list) or not exit_codes or not all(isinstance(x, int) for x in exit_codes):
                raise ContractError(f"EXIT_CODES_INVALID:{step_id}")
            for field in ("stdout_contains", "stderr_contains"):
                values = expect.get(field, [])
                if not isinstance(values, list) or not all(isinstance(x, str) for x in values):
                    raise ContractError(f"{field.upper()}_INVALID:{step_id}")

    evidence = _require_object(manifest, "evidence")
    output = evidence.get("output_path")
    if not isinstance(output, str) or not output.strip():
        raise ContractError("EVIDENCE_OUTPUT_PATH_INVALID")
    if evidence.get("include_raw_output") is not False:
        raise ContractError("RAW_OUTPUT_MUST_BE_DISABLED")
    if evidence.get("require_post_readback") is not True:
        raise ContractError("POST_READBACK_MUST_BE_REQUIRED")
    if evidence.get("require_zero_residue") is not True:
        raise ContractError("ZERO_RESIDUE_MUST_BE_REQUIRED")
    zero_token = evidence.get("zero_residue_token")
    if not isinstance(zero_token, str) or not TOKEN_RE.fullmatch(zero_token):
        raise ContractError("ZERO_RESIDUE_TOKEN_INVALID")
    post_assertions = [
        token
        for step in manifest["steps"]["post_readback"]
        for token in step.get("expect", {}).get("stdout_contains", [])
    ]
    if zero_token not in post_assertions:
        raise ContractError("ZERO_RESIDUE_TOKEN_NOT_ASSERTED")
    return manifest


def _step_env(step: dict[str, Any]) -> dict[str, str]:
    env: dict[str, str] = {}
    for name in SAFE_BASE_ENV:
        value = os.environ.get(name)
        if value is not None:
            env[name] = value
    for name in step.get("env_names", []):
        value = os.environ.get(name)
        if value is None:
            raise ContractError(f"REQUIRED_ENV_MISSING:{step['id']}:{name}")
        env[name] = value
    return env


def _run_step(phase: str, step: dict[str, Any]) -> StepOutcome:
    started = time.monotonic()
    stdout = b""
    stderr = b""
    try:
        proc = subprocess.run(
            step["argv"], cwd=step.get("cwd") or None, env=_step_env(step),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            timeout=step["timeout_seconds"],
        )
        stdout, stderr = proc.stdout or b"", proc.stderr or b""
        expect = step.get("expect", {})
        failure = None
        if proc.returncode not in expect.get("exit_codes", [0]):
            failure = f"EXIT_CODE:{proc.returncode}"
        else:
            text_out, text_err = stdout.decode("utf-8", "replace"), stderr.decode("utf-8", "replace")
            for token in expect.get("stdout_contains", []):
                if token not in text_out:
                    failure = f"STDOUT_TOKEN_MISSING:{token}"
                    break
            if failure is None:
                for token in expect.get("stderr_contains", []):
                    if token not in text_err:
                        failure = f"STDERR_TOKEN_MISSING:{token}"
                        break
        return StepOutcome(phase, step["id"], "PASS" if failure is None else "FAIL", proc.returncode,
                           (time.monotonic() - started) * 1000, _sha256_bytes(stdout), _sha256_bytes(stderr), failure)
    except subprocess.TimeoutExpired as exc:
        stdout, stderr = exc.stdout or b"", exc.stderr or b""
        return StepOutcome(phase, step["id"], "FAIL", None, (time.monotonic() - started) * 1000,
                           _sha256_bytes(stdout), _sha256_bytes(stderr), "TIMEOUT")
    except (OSError, ContractError) as exc:
        return StepOutcome(phase, step["id"], "FAIL", None, (time.monotonic() - started) * 1000,
                           None, None, f"EXECUTION_ERROR:{type(exc).__name__}:{exc}")


def _run_phase(manifest: dict[str, Any], phase: str, evidence_steps: list[dict[str, Any]], *, stop_on_failure: bool = True) -> bool:
    ok = True
    for step in manifest["steps"][phase]:
        outcome = _run_step(phase, step)
        evidence_steps.append(outcome.as_dict())
        if outcome.status != "PASS":
            ok = False
            if stop_on_failure:
                break
    return ok


def _write_evidence(path: Path, packet: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(packet, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temp, path)


def execute_manifest(manifest: dict[str, Any], *, dry_run: bool = False) -> dict[str, Any]:
    validate_manifest(manifest)
    packet: dict[str, Any] = {
        "evidence_version": VERSION,
        "canary_id": manifest["canary_id"],
        "manifest_sha256": _sha256_json(manifest),
        "change_mode": manifest["change_mode"],
        "target": manifest["target"],
        "started_at_epoch_ms": int(time.time() * 1000),
        "steps": [],
        "rollback_attempted": False,
        "post_readback_attempted": False,
        "forward_started": False,
        "result": "DRY_RUN" if dry_run else "IN_PROGRESS",
        "claim_ceiling": CLAIM_CEILING,
    }
    if dry_run:
        packet["finished_at_epoch_ms"] = int(time.time() * 1000)
        return packet

    if manifest["change_mode"] == "MIGRATION_EXACT_VERSION":
        source_contract = manifest["source_first"]
        try:
            receipt = source_first.verify_paths(
                source_contract["paths"],
                main_ref=source_contract["main_ref"],
                fetch_main=source_contract["fetch_main"],
            )
        except (source_first.SourceFirstParityError, subprocess.TimeoutExpired, OSError) as exc:
            packet["source_first_parity"] = {"result": "FAIL", "reason": str(exc)}
            packet["result"] = "FAIL_SOURCE_FIRST_PARITY"
            packet["finished_at_epoch_ms"] = int(time.time() * 1000)
            _write_evidence(Path(manifest["evidence"]["output_path"]), packet)
            return packet
        packet["source_first_parity"] = receipt

    steps: list[dict[str, Any]] = packet["steps"]
    if not _run_phase(manifest, "preflight", steps):
        packet["result"] = "FAIL_PREFLIGHT"
        packet["finished_at_epoch_ms"] = int(time.time() * 1000)
        _write_evidence(Path(manifest["evidence"]["output_path"]), packet)
        return packet

    primary_ok = True
    try:
        packet["forward_started"] = True
        if not _run_phase(manifest, "forward", steps):
            primary_ok = False
        if primary_ok and not _run_phase(manifest, "tests", steps):
            primary_ok = False
    finally:
        packet["rollback_attempted"] = True
        rollback_ok = _run_phase(manifest, "rollback", steps, stop_on_failure=False)
        packet["post_readback_attempted"] = True
        post_ok = _run_phase(manifest, "post_readback", steps, stop_on_failure=False)

    if primary_ok and rollback_ok and post_ok:
        packet["result"] = "PASS"
    elif not rollback_ok:
        packet["result"] = "FAIL_ROLLBACK"
    elif not post_ok:
        packet["result"] = "FAIL_POST_READBACK"
    else:
        packet["result"] = "FAIL_CANARY"
    packet["finished_at_epoch_ms"] = int(time.time() * 1000)
    _write_evidence(Path(manifest["evidence"]["output_path"]), packet)
    return packet


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--plan", action="store_true")
    args = parser.parse_args(argv)
    try:
        manifest = validate_manifest(_load_manifest(args.manifest))
        packet = execute_manifest(manifest, dry_run=args.plan)
    except ContractError as exc:
        print(f"FAIL_CONTRACT:{exc}", file=sys.stderr)
        return 2
    print(json.dumps(packet, sort_keys=True, separators=(",", ":")))
    return 0 if packet["result"] in {"PASS", "DRY_RUN"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
