#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

RESULT_SCHEMA = "LF_PACK_VALIDATION_RESULT_V1"
FLOOR_SCHEMA = "LF_PACK_VALIDATION_FLOOR_V1"
POLICY_CODE = "POL-PACK-VALIDATION-FLOOR"
ALLOWED_STATES = {"ENFORCED", "REPORT_ONLY", "NOT_ENFORCED"}


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def safe_repo_path(repo_root: Path, raw: str, *, prefix: str | None = None) -> Path:
    if not isinstance(raw, str) or not raw or raw.startswith("/"):
        raise ValueError("PATH_INVALID")
    rel = Path(raw)
    if ".." in rel.parts:
        raise ValueError("PATH_TRAVERSAL")
    unresolved = repo_root / rel
    if unresolved.is_symlink():
        raise ValueError("SYMLINK_FORBIDDEN")
    resolved = unresolved.resolve()
    try:
        resolved.relative_to(repo_root)
    except ValueError as exc:
        raise ValueError("PATH_ESCAPE") from exc
    if prefix is not None:
        expected = (repo_root / prefix).resolve()
        try:
            resolved.relative_to(expected)
        except ValueError as exc:
            raise ValueError("PATH_OWNER_MISMATCH") from exc
    return resolved


def profile_slug_from_inventory_path(raw: Any) -> str | None:
    if not isinstance(raw, str):
        return None
    parts = Path(raw).parts
    if len(parts) < 2 or parts[0] != "profiles":
        return None
    slug = parts[1]
    if not slug or slug.startswith("_"):
        return None
    return slug


def parse_suite_stdout(stdout: str) -> dict[str, Any]:
    try:
        obj = json.loads(stdout)
    except Exception as exc:
        raise ValueError("SUITE_OUTPUT_NOT_JSON") from exc
    if not isinstance(obj, dict):
        raise ValueError("SUITE_OUTPUT_NOT_OBJECT")
    if obj.get("passed") is not True and obj.get("passed") is not False:
        raise ValueError("SUITE_PASSED_NOT_BOOLEAN")
    count = obj.get("case_count")
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        raise ValueError("SUITE_CASE_COUNT_INVALID")
    return obj


def run_python(path: Path, cwd: Path, timeout_seconds: int) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            [sys.executable, str(path)],
            cwd=cwd,
            text=True,
            capture_output=True,
            timeout=timeout_seconds,
            env=os.environ.copy(),
        )
    except subprocess.TimeoutExpired as exc:
        return {
            "returncode": None,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
            "timed_out": True,
        }
    return {
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "timed_out": False,
    }


def policy_snapshot(path: Path) -> tuple[dict[str, Any], dict[str, Any], str]:
    raw = path.read_bytes()
    obj = json.loads(raw)
    if not isinstance(obj, dict):
        raise ValueError("POLICY_SNAPSHOT_NOT_OBJECT")
    if obj.get("policy_code") != POLICY_CODE:
        raise ValueError("POLICY_CODE_INVALID")
    version = obj.get("policy_version")
    digest = obj.get("policy_sha")
    payload = obj.get("policy_payload")
    if not isinstance(version, str) or not version:
        raise ValueError("POLICY_VERSION_INVALID")
    if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest.lower()):
        raise ValueError("POLICY_SHA_INVALID")
    if not isinstance(payload, dict) or payload.get("schema") != FLOOR_SCHEMA:
        raise ValueError("POLICY_PAYLOAD_INVALID")
    req = payload.get("requirements")
    if not isinstance(req, dict):
        raise ValueError("POLICY_REQUIREMENTS_MISSING")
    mandatory_true = [
        "inventory_reconciliation_required",
        "direct_suite_execution_required",
        "external_holdout_required_for_enforced",
        "hashes_computed_by_harness",
        "producer_self_exclusion_forbidden",
        "runtime_authorized_false",
        "automatic_impact_authorized_false",
    ]
    missing = [k for k in mandatory_true if req.get(k) is not True]
    if missing:
        raise ValueError("POLICY_REQUIRED_INVARIANT_DISABLED:" + ",".join(missing))
    profiles = payload.get("profiles")
    if not isinstance(profiles, dict):
        raise ValueError("POLICY_PROFILES_MISSING")
    return obj, payload, sha256_bytes(raw)


def inventory_snapshot(path: Path) -> tuple[list[dict[str, Any]], str]:
    raw = path.read_bytes()
    obj = json.loads(raw)
    if not isinstance(obj, list):
        raise ValueError("INVENTORY_NOT_ARRAY")
    seen_codes: set[str] = set()
    seen_slugs: set[str] = set()
    rows: list[dict[str, Any]] = []
    for item in obj:
        if not isinstance(item, dict):
            raise ValueError("INVENTORY_ROW_NOT_OBJECT")
        code = item.get("codigo_activo")
        slug = profile_slug_from_inventory_path(item.get("ruta_esperada"))
        if not isinstance(code, str) or not code or not slug:
            raise ValueError("INVENTORY_ROW_IDENTITY_INVALID")
        if code in seen_codes or slug in seen_slugs:
            raise ValueError("INVENTORY_DUPLICATE_IDENTITY")
        seen_codes.add(code)
        seen_slugs.add(slug)
        rows.append({**item, "profile_slug": slug})
    return rows, sha256_bytes(raw)


def disk_profiles(repo_root: Path) -> set[str]:
    root = repo_root / "profiles"
    if not root.is_dir():
        raise ValueError("PROFILES_ROOT_MISSING")
    return {
        p.name for p in root.iterdir()
        if p.is_dir() and not p.name.startswith("_") and not p.is_symlink()
    }


def manifest_validation_config(profile_dir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    manifest_path = profile_dir / "manifest.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise ValueError("MANIFEST_MISSING")
    manifest = load_json(manifest_path)
    if not isinstance(manifest, dict):
        raise ValueError("MANIFEST_NOT_OBJECT")
    cfg = manifest.get("pack_validation")
    if not isinstance(cfg, dict):
        raise ValueError("PACK_VALIDATION_DECLARATION_MISSING")
    return manifest, cfg


def result_hash(parts: list[bytes]) -> str:
    h = hashlib.sha256()
    for raw in parts:
        h.update(len(raw).to_bytes(8, "big"))
        h.update(raw)
    return h.hexdigest()


def add_block(blocking: list[str], code: str) -> None:
    if code not in blocking:
        blocking.append(code)


def validate_profile(
    *,
    repo_root: Path,
    inventory_row: dict[str, Any],
    policy_entry: dict[str, Any] | None,
    disk_slugs: set[str],
    timeout_seconds: int,
) -> dict[str, Any]:
    code = inventory_row["codigo_activo"]
    slug = inventory_row["profile_slug"]
    blocking: list[str] = []
    warnings: list[str] = []
    pack_id: str | None = None
    validator_sha: str | None = None
    suite_sha: str | None = None
    holdout_sha: str | None = None
    case_count: int | None = None
    holdout_case_count: int | None = None
    results_parts: list[bytes] = []
    thresholds_applied: dict[str, Any] = {}

    if policy_entry is None:
        state = "ENFORCED"
        add_block(blocking, "EXTERNAL_FLOOR_ENTRY_MISSING")
        policy_entry = {}
    else:
        state = policy_entry.get("enforcement_state")
        if state not in ALLOWED_STATES:
            state = "ENFORCED"
            add_block(blocking, "ENFORCEMENT_STATE_INVALID")

    materialized = slug in disk_slugs
    allow_missing = policy_entry.get("allow_missing_materialization") is True
    if not materialized:
        if state == "NOT_ENFORCED" and allow_missing:
            reason = policy_entry.get("reason")
            if not isinstance(reason, str) or len(reason.strip()) < 8:
                add_block(blocking, "NOT_ENFORCED_REASON_MISSING")
        else:
            add_block(blocking, "INVENTORY_PROFILE_MISSING_ON_DISK")

    if state == "NOT_ENFORCED":
        reason = policy_entry.get("reason")
        if not isinstance(reason, str) or len(reason.strip()) < 8:
            add_block(blocking, "NOT_ENFORCED_REASON_MISSING")
        return {
            "profile_code": code,
            "profile_slug": slug,
            "pack_id": None,
            "enforcement_state": state,
            "status": "FAIL" if blocking else "NOT_ENFORCED",
            "blocking_codes": blocking,
            "warnings": warnings,
            "thresholds_applied": {},
            "validator_sha256": None,
            "suite_sha256": None,
            "holdout_sha256": None,
            "case_count": None,
            "holdout_case_count": None,
            "results_sha256": None,
            "runtime_authorized": False,
            "automatic_impact_authorized": False,
        }

    if not materialized:
        return {
            "profile_code": code,
            "profile_slug": slug,
            "pack_id": None,
            "enforcement_state": state,
            "status": "FAIL" if state == "ENFORCED" else "REPORT_ONLY",
            "blocking_codes": blocking,
            "warnings": warnings,
            "thresholds_applied": {},
            "validator_sha256": None,
            "suite_sha256": None,
            "holdout_sha256": None,
            "case_count": None,
            "holdout_case_count": None,
            "results_sha256": None,
            "runtime_authorized": False,
            "automatic_impact_authorized": False,
        }

    profile_dir = (repo_root / "profiles" / slug).resolve()
    try:
        manifest, cfg = manifest_validation_config(profile_dir)
        pack_id_raw = manifest.get("profile_pack_id")
        target_code = manifest.get("target_code")
        if not isinstance(pack_id_raw, str) or not pack_id_raw:
            raise ValueError("PROFILE_PACK_ID_MISSING")
        pack_id = pack_id_raw
        if target_code != code:
            add_block(blocking, "MANIFEST_INVENTORY_IDENTITY_MISMATCH")

        validator_rel = cfg.get("validator_path")
        suite_rel = cfg.get("suite_path")
        thresholds = cfg.get("thresholds")
        if not isinstance(validator_rel, str) or not isinstance(suite_rel, str):
            raise ValueError("VALIDATION_PATH_DECLARATION_INVALID")
        if not isinstance(thresholds, dict):
            raise ValueError("PROFILE_THRESHOLDS_MISSING")
        requested_min = thresholds.get("min_profile_cases")
        floor_min = policy_entry.get("min_profile_cases")
        holdout_min = policy_entry.get("min_holdout_cases")
        if not isinstance(requested_min, int) or isinstance(requested_min, bool) or requested_min < 1:
            raise ValueError("PROFILE_MIN_CASES_INVALID")
        if not isinstance(floor_min, int) or isinstance(floor_min, bool) or floor_min < 1:
            raise ValueError("EXTERNAL_PROFILE_FLOOR_INVALID")
        if requested_min < floor_min:
            add_block(blocking, "PROFILE_THRESHOLD_BELOW_EXTERNAL_FLOOR")
        if state == "ENFORCED" and (not isinstance(holdout_min, int) or isinstance(holdout_min, bool) or holdout_min < 1):
            raise ValueError("EXTERNAL_HOLDOUT_FLOOR_INVALID")
        thresholds_applied = {
            "profile_requested_min_cases": requested_min,
            "external_min_profile_cases": floor_min,
            "external_min_holdout_cases": holdout_min,
        }

        validator = safe_repo_path(repo_root, f"profiles/{slug}/{validator_rel}", prefix=f"profiles/{slug}")
        suite = safe_repo_path(repo_root, f"profiles/{slug}/{suite_rel}", prefix=f"profiles/{slug}")
        if not validator.is_file():
            raise ValueError("VALIDATOR_MISSING")
        if not suite.is_file():
            raise ValueError("SUITE_MISSING")
        validator_sha = sha256_file(validator)
        suite_sha = sha256_file(suite)

        validator_run = run_python(validator, profile_dir, timeout_seconds)
        results_parts.extend([
            validator_run["stdout"].encode("utf-8"),
            validator_run["stderr"].encode("utf-8"),
        ])
        if validator_run["timed_out"]:
            add_block(blocking, "VALIDATOR_TIMEOUT")
        elif validator_run["returncode"] != 0:
            add_block(blocking, "VALIDATOR_FAILED")

        suite_run = run_python(suite, repo_root, timeout_seconds)
        results_parts.extend([
            suite_run["stdout"].encode("utf-8"),
            suite_run["stderr"].encode("utf-8"),
        ])
        if suite_run["timed_out"]:
            add_block(blocking, "SUITE_TIMEOUT")
        else:
            try:
                suite_result = parse_suite_stdout(suite_run["stdout"])
                case_count = suite_result["case_count"]
                if suite_run["returncode"] != 0 or suite_result["passed"] is not True:
                    add_block(blocking, "PROFILE_SUITE_FAILED")
                if case_count < floor_min:
                    add_block(blocking, "PROFILE_SUITE_CASE_COUNT_BELOW_EXTERNAL_FLOOR")
                if case_count < requested_min:
                    add_block(blocking, "PROFILE_SUITE_CASE_COUNT_BELOW_DECLARED_THRESHOLD")
            except ValueError as exc:
                add_block(blocking, str(exc))

        holdout_rel = policy_entry.get("holdout_path")
        if state == "ENFORCED":
            if not isinstance(holdout_rel, str) or not holdout_rel:
                add_block(blocking, "EXTERNAL_HOLDOUT_PATH_MISSING")
            else:
                try:
                    holdout = safe_repo_path(
                        repo_root,
                        holdout_rel,
                        prefix="sandbox/lf_contract_gate_test/pack_validation_harness/holdouts",
                    )
                    if not holdout.is_file():
                        raise ValueError("EXTERNAL_HOLDOUT_MISSING")
                    holdout_sha = sha256_file(holdout)
                    holdout_run = run_python(holdout, repo_root, timeout_seconds)
                    results_parts.extend([
                        holdout_run["stdout"].encode("utf-8"),
                        holdout_run["stderr"].encode("utf-8"),
                    ])
                    if holdout_run["timed_out"]:
                        add_block(blocking, "EXTERNAL_HOLDOUT_TIMEOUT")
                    else:
                        holdout_result = parse_suite_stdout(holdout_run["stdout"])
                        holdout_case_count = holdout_result["case_count"]
                        if holdout_run["returncode"] != 0 or holdout_result["passed"] is not True:
                            add_block(blocking, "EXTERNAL_HOLDOUT_FAILED")
                        if isinstance(holdout_min, int) and holdout_case_count < holdout_min:
                            add_block(blocking, "EXTERNAL_HOLDOUT_CASE_COUNT_BELOW_FLOOR")
                except ValueError as exc:
                    add_block(blocking, str(exc))
        else:
            warnings.append("REPORT_ONLY_NOT_AUTHORITY")

    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        add_block(blocking, str(exc))

    result_digest = result_hash(results_parts) if results_parts else None
    if state == "ENFORCED":
        status = "PASS" if not blocking else "FAIL"
    else:
        status = "REPORT_ONLY"
    return {
        "profile_code": code,
        "profile_slug": slug,
        "pack_id": pack_id,
        "enforcement_state": state,
        "status": status,
        "blocking_codes": blocking,
        "warnings": warnings,
        "thresholds_applied": thresholds_applied,
        "validator_sha256": validator_sha,
        "suite_sha256": suite_sha,
        "holdout_sha256": holdout_sha,
        "case_count": case_count,
        "holdout_case_count": holdout_case_count,
        "results_sha256": result_digest,
        "runtime_authorized": False,
        "automatic_impact_authorized": False,
    }


def validate_result_envelope(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if result.get("schema_version") != RESULT_SCHEMA:
        errors.append("RESULT_SCHEMA_VERSION_INVALID")
    if result.get("status") not in {"PASS", "FAIL"}:
        errors.append("RESULT_STATUS_INVALID")
    if result.get("runtime_authorized") is not False:
        errors.append("RESULT_RUNTIME_AUTHORIZATION_INVALID")
    if result.get("automatic_impact_authorized") is not False:
        errors.append("RESULT_AUTOMATIC_IMPACT_INVALID")
    if not isinstance(result.get("profiles"), list):
        errors.append("RESULT_PROFILES_INVALID")
    if not isinstance(result.get("blocking_codes"), list):
        errors.append("RESULT_BLOCKING_CODES_INVALID")
    for key in ("inventory_snapshot_sha256", "policy_snapshot_sha256"):
        value = result.get(key)
        if not isinstance(value, str) or len(value) != 64:
            errors.append("RESULT_DIGEST_INVALID:" + key)
    return errors


def evaluate(repo_root: Path, inventory_path: Path, policy_path: Path, tested_revision: str, timeout_seconds: int) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    policy_obj, payload, policy_snapshot_sha = policy_snapshot(policy_path)
    inventory, inventory_sha = inventory_snapshot(inventory_path)
    disk_slugs = disk_profiles(repo_root)
    inventory_by_slug = {row["profile_slug"]: row for row in inventory}
    blocking: list[str] = []

    for slug in sorted(disk_slugs - set(inventory_by_slug)):
        add_block(blocking, "DISK_PROFILE_NOT_IN_GOVERNED_INVENTORY:" + slug)

    profile_results: list[dict[str, Any]] = []
    policy_profiles = payload["profiles"]
    inventory_codes = {row["codigo_activo"] for row in inventory}
    for unknown_code in sorted(set(policy_profiles) - inventory_codes):
        add_block(blocking, "POLICY_PROFILE_NOT_IN_INVENTORY:" + unknown_code)

    for row in sorted(inventory, key=lambda x: x["codigo_activo"]):
        profile_results.append(validate_profile(
            repo_root=repo_root,
            inventory_row=row,
            policy_entry=policy_profiles.get(row["codigo_activo"]),
            disk_slugs=disk_slugs,
            timeout_seconds=timeout_seconds,
        ))

    for item in profile_results:
        if item["enforcement_state"] == "ENFORCED" and item["status"] != "PASS":
            for code in item["blocking_codes"]:
                add_block(blocking, f"{item['profile_code']}:{code}")
        if item["enforcement_state"] == "NOT_ENFORCED" and item["status"] == "FAIL":
            for code in item["blocking_codes"]:
                add_block(blocking, f"{item['profile_code']}:{code}")

    result = {
        "schema_version": RESULT_SCHEMA,
        "status": "PASS" if not blocking else "FAIL",
        "tested_revision": tested_revision,
        "policy": {
            "policy_code": policy_obj["policy_code"],
            "policy_version": policy_obj["policy_version"],
            "policy_sha256": policy_obj["policy_sha"],
        },
        "policy_snapshot_sha256": policy_snapshot_sha,
        "inventory_snapshot_sha256": inventory_sha,
        "profiles": profile_results,
        "blocking_codes": blocking,
        "runtime_authorized": False,
        "automatic_impact_authorized": False,
    }
    schema_errors = validate_result_envelope(result)
    if schema_errors:
        result["status"] = "FAIL"
        for code in schema_errors:
            add_block(result["blocking_codes"], code)
    result["result_sha256"] = sha256_bytes(canonical_json_bytes({k: v for k, v in result.items() if k != "result_sha256"}))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--inventory-json", required=True)
    parser.add_argument("--policy-json", required=True)
    parser.add_argument("--tested-revision", required=True)
    parser.add_argument("--output-json")
    parser.add_argument("--timeout-seconds", type=int, default=120)
    args = parser.parse_args()

    try:
        result = evaluate(
            Path(args.repo_root),
            Path(args.inventory_json),
            Path(args.policy_json),
            args.tested_revision,
            args.timeout_seconds,
        )
    except Exception as exc:
        result = {
            "schema_version": RESULT_SCHEMA,
            "status": "FAIL",
            "tested_revision": args.tested_revision,
            "policy": None,
            "policy_snapshot_sha256": "0" * 64,
            "inventory_snapshot_sha256": "0" * 64,
            "profiles": [],
            "blocking_codes": ["HARNESS_INPUT_OR_EXECUTION_ERROR:" + type(exc).__name__ + ":" + str(exc)],
            "runtime_authorized": False,
            "automatic_impact_authorized": False,
        }
        result["result_sha256"] = sha256_bytes(canonical_json_bytes(result))

    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.output_json:
        Path(args.output_json).write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
