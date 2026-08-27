#!/usr/bin/env python3
"""Generic fail-closed runtime harness for LF profile execution.

This runner never manufactures a profile response. A real executor command is
mandatory and must read one JSON envelope from stdin and emit one JSON value to
stdout. Raw stdout is persisted before parsing or validation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_BLOCKED = 2


class RuntimeBlocked(RuntimeError):
    pass


class RuntimeFailed(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeBlocked(f"json_load_failed:{path}:{type(exc).__name__}:{exc}") from exc


def require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RuntimeBlocked(f"{label}_must_be_object")
    return value


def require_nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise RuntimeBlocked(f"{label}_must_be_nonempty_string")
    return value.strip()


def resolve_repo_path(repo_root: Path, relative_path: str) -> Path:
    raw = require_nonempty_string(relative_path, "source_path")
    path = (repo_root / raw).resolve()
    root = repo_root.resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise RuntimeBlocked(f"source_path_outside_repo:{raw}") from exc
    if not path.is_file():
        raise RuntimeBlocked(f"source_file_missing:{raw}")
    return path


def source_record(repo_root: Path, relative_path: str) -> dict[str, Any]:
    path = resolve_repo_path(repo_root, relative_path)
    text = path.read_text(encoding="utf-8")
    return {
        "path": path.relative_to(repo_root.resolve()).as_posix(),
        "sha256": sha256_text(text),
        "content": text,
    }


def load_source_pack(repo_root: Path, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    ordered: list[str] = []
    entrypoint = manifest.get("entrypoint")
    if entrypoint:
        ordered.append(require_nonempty_string(entrypoint, "manifest.entrypoint"))
    for key in ("load_paths", "adapters"):
        values = manifest.get(key, [])
        if not isinstance(values, list):
            raise RuntimeBlocked(f"manifest.{key}_must_be_array")
        for value in values:
            ordered.append(require_nonempty_string(value, f"manifest.{key}[]"))
    deduped: list[str] = []
    seen: set[str] = set()
    for item in ordered:
        if item not in seen:
            seen.add(item)
            deduped.append(item)
    if not deduped:
        raise RuntimeBlocked("manifest_has_no_profile_sources")
    return [source_record(repo_root, item) for item in deduped]


def command_from_text(value: str) -> list[str]:
    parts = shlex.split(require_nonempty_string(value, "executor_command"))
    if not parts:
        raise RuntimeBlocked("executor_command_empty")
    return parts


def run_command(
    command: list[str],
    *,
    stdin_text: str,
    cwd: Path,
    timeout_seconds: int,
) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            command,
            input=stdin_text,
            capture_output=True,
            text=True,
            cwd=str(cwd),
            timeout=timeout_seconds,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RuntimeBlocked(f"command_not_found:{command[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeFailed(f"command_timeout:{command[0]}:{timeout_seconds}s") from exc
    return proc.returncode, proc.stdout, proc.stderr


def resolve_context(
    *,
    repo_root: Path,
    request: dict[str, Any],
    resolver_command: str | None,
    timeout_seconds: int,
    evidence_dir: Path,
) -> tuple[dict[str, Any], list[str], dict[str, Any]]:
    if resolver_command:
        command = command_from_text(resolver_command)
        resolver_input = {
            "runtime_contract": "PROFILE_RUNTIME_CONTEXT_V1",
            "request": request,
        }
        code, stdout, stderr = run_command(
            command,
            stdin_text=canonical_json(resolver_input),
            cwd=repo_root,
            timeout_seconds=timeout_seconds,
        )
        (evidence_dir / "context_raw.stdout.txt").write_text(stdout, encoding="utf-8")
        (evidence_dir / "context_raw.stderr.txt").write_text(stderr, encoding="utf-8")
        if code != 0:
            raise RuntimeBlocked(f"context_resolver_nonzero_exit:{code}")
        if not stdout.strip():
            raise RuntimeBlocked("context_resolver_empty_stdout")
        try:
            resolved = json.loads(stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeBlocked(f"context_resolver_invalid_json:{exc}") from exc
        resolved_map = require_mapping(resolved, "resolved_context")
        context = require_mapping(resolved_map.get("canonical_context"), "canonical_context")
        refs = resolved_map.get("source_refs")
        if not isinstance(refs, list) or not refs or any(not isinstance(x, str) or not x.strip() for x in refs):
            raise RuntimeBlocked("context_resolver_source_refs_missing")
        meta = {
            "mode": "EXTERNAL_RESOLVER",
            "command_sha256": sha256_text(" ".join(command)),
            "stdout_sha256": sha256_text(stdout),
            "source_refs": refs,
        }
        return context, [x.strip() for x in refs], meta

    context = request.get("canonical_context")
    refs = request.get("canonical_source_refs")
    if not isinstance(context, dict) or not context:
        raise RuntimeBlocked(
            "canonical_context_missing:provide request.canonical_context or PROFILE_RUNTIME_CONTEXT_RESOLVER"
        )
    if not isinstance(refs, list) or not refs or any(not isinstance(x, str) or not x.strip() for x in refs):
        raise RuntimeBlocked("canonical_source_refs_missing")
    return context, [x.strip() for x in refs], {
        "mode": "REQUEST_SUPPLIED",
        "source_refs": [x.strip() for x in refs],
    }


@dataclass
class ExecutorResult:
    phase: str
    activation_path: str
    raw_stdout: str
    raw_stderr: str
    parsed: dict[str, Any]
    command_sha256: str


def invoke_executor(
    *,
    repo_root: Path,
    executor_command: str,
    envelope: dict[str, Any],
    phase: str,
    activation_path: str,
    timeout_seconds: int,
    evidence_dir: Path,
) -> ExecutorResult:
    command = command_from_text(executor_command)
    code, stdout, stderr = run_command(
        command,
        stdin_text=canonical_json(envelope),
        cwd=repo_root,
        timeout_seconds=timeout_seconds,
    )

    stem = f"{phase.lower()}_{activation_path.lower()}"
    raw_stdout_path = evidence_dir / f"{stem}.raw.stdout.txt"
    raw_stderr_path = evidence_dir / f"{stem}.raw.stderr.txt"
    raw_stdout_path.write_text(stdout, encoding="utf-8")
    raw_stderr_path.write_text(stderr, encoding="utf-8")

    if code != 0:
        raise RuntimeFailed(f"executor_nonzero_exit:{phase}:{activation_path}:{code}")
    if not stdout.strip():
        raise RuntimeFailed(f"executor_empty_stdout:{phase}:{activation_path}")

    try:
        parsed = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeFailed(f"executor_invalid_json:{phase}:{activation_path}:{exc}") from exc
    parsed_map = require_mapping(parsed, f"executor_output:{phase}:{activation_path}")
    return ExecutorResult(
        phase=phase,
        activation_path=activation_path,
        raw_stdout=stdout,
        raw_stderr=stderr,
        parsed=parsed_map,
        command_sha256=sha256_text(" ".join(command)),
    )


def render_command(template: list[Any], replacements: dict[str, str]) -> list[str]:
    rendered: list[str] = []
    for token in template:
        if not isinstance(token, str):
            raise RuntimeBlocked("validator_command_tokens_must_be_strings")
        value = token
        for key, replacement in replacements.items():
            value = value.replace("{" + key + "}", replacement)
        rendered.append(value)
    return rendered


def run_validators(
    *,
    repo_root: Path,
    manifest: dict[str, Any],
    parsed_output_path: Path,
    activation_path: str,
    timeout_seconds: int,
    evidence_dir: Path,
) -> list[dict[str, Any]]:
    validators = manifest.get("deterministic_validators", [])
    if not isinstance(validators, list):
        raise RuntimeBlocked("manifest.deterministic_validators_must_be_array")
    results: list[dict[str, Any]] = []
    for index, item in enumerate(validators):
        cfg = require_mapping(item, f"validator[{index}]")
        name = require_nonempty_string(cfg.get("name"), f"validator[{index}].name")
        template = cfg.get("command")
        if not isinstance(template, list) or not template:
            raise RuntimeBlocked(f"validator_command_missing:{name}")
        command = render_command(
            template,
            {
                "parsed_output": str(parsed_output_path),
                "repo_root": str(repo_root),
            },
        )
        code, stdout, stderr = run_command(
            command,
            stdin_text="",
            cwd=repo_root,
            timeout_seconds=timeout_seconds,
        )
        result = {
            "name": name,
            "required": bool(cfg.get("required", True)),
            "exit_code": code,
            "passed": code == 0,
            "stdout": stdout,
            "stderr": stderr,
        }
        results.append(result)
        prefix = f"validator_{activation_path.lower()}_{index:02d}_{name}"
        (evidence_dir / f"{prefix}.stdout.txt").write_text(stdout, encoding="utf-8")
        (evidence_dir / f"{prefix}.stderr.txt").write_text(stderr, encoding="utf-8")
    return results


def required_validators_pass(results: list[dict[str, Any]]) -> bool:
    return all((not item["required"]) or item["passed"] for item in results)


def semantic_judge_required(manifest: dict[str, Any], request: dict[str, Any]) -> bool:
    cfg = manifest.get("semantic_judge")
    if not isinstance(cfg, dict) or not cfg.get("enabled", False):
        return False
    modes = cfg.get("required_for_modes", [])
    if not isinstance(modes, list):
        raise RuntimeBlocked("manifest.semantic_judge.required_for_modes_must_be_array")
    if not modes:
        return True
    mode = request.get("task_mode") or request.get("target_mode")
    return mode in modes


def semantic_judge_source(repo_root: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    cfg = require_mapping(manifest.get("semantic_judge"), "manifest.semantic_judge")
    judge_file = require_nonempty_string(cfg.get("judge_file"), "manifest.semantic_judge.judge_file")
    return source_record(repo_root, judge_file)


def judge_passes(manifest: dict[str, Any], judge_output: dict[str, Any]) -> bool:
    cfg = require_mapping(manifest.get("semantic_judge"), "manifest.semantic_judge")
    allowed = cfg.get("pass_verdicts")
    if not isinstance(allowed, list) or not allowed:
        raise RuntimeBlocked("manifest.semantic_judge.pass_verdicts_missing")
    verdict = judge_output.get("verdict")
    return isinstance(verdict, str) and verdict in allowed


def remediation_projection(output: dict[str, Any]) -> Any:
    deliverable = output.get("deliverable_created")
    if isinstance(deliverable, dict):
        return deliverable.get("remediation_actions")
    return None


def comparable_shell_binding(output: dict[str, Any]) -> Any:
    binding = output.get("shell_binding")
    if not isinstance(binding, dict):
        return binding
    copy = json.loads(json.dumps(binding))
    refs = copy.get("source_refs")
    if isinstance(refs, list):
        copy["source_refs"] = [
            value for value in refs
            if not (isinstance(value, str) and value.startswith("router:"))
        ]
    return copy


def compare_pair(direct: dict[str, Any], router: dict[str, Any]) -> dict[str, Any]:
    actions_equal = remediation_projection(direct) == remediation_projection(router)
    shell_equal = comparable_shell_binding(direct) == comparable_shell_binding(router)
    return {
        "remediation_actions_materially_equal": actions_equal,
        "shell_binding_equal_except_router_provenance": shell_equal,
        "materially_consistent": actions_equal and shell_equal,
    }


def build_profile_envelope(
    *,
    manifest: dict[str, Any],
    request: dict[str, Any],
    canonical_context: dict[str, Any],
    canonical_source_refs: list[str],
    source_pack: list[dict[str, Any]],
    activation_path: str,
) -> dict[str, Any]:
    router_cfg = manifest.get("router") if activation_path == "ROUTER" else None
    if activation_path == "ROUTER" and not isinstance(router_cfg, dict):
        raise RuntimeBlocked("router_activation_requested_but_manifest.router_missing")
    return {
        "runtime_contract": "PROFILE_RUNTIME_EXECUTOR_V1",
        "phase": "PROFILE_EXECUTION",
        "activation_path": activation_path,
        "profile": {
            "profile_id": manifest.get("profile_id"),
            "profile_slug": manifest.get("profile_slug"),
        },
        "router_context": router_cfg if activation_path == "ROUTER" else None,
        "request": request,
        "canonical_context": canonical_context,
        "canonical_source_refs": canonical_source_refs,
        "source_pack": source_pack,
        "executor_rules": {
            "return_exactly_one_json_object": True,
            "no_markdown_fences": True,
            "no_fixture_or_expected_output_substitution": True,
            "follow_loaded_profile_and_adapter_authority": True,
        },
    }


def build_judge_envelope(
    *,
    manifest: dict[str, Any],
    request: dict[str, Any],
    canonical_context: dict[str, Any],
    canonical_source_refs: list[str],
    judge_source: dict[str, Any],
    direct_output: dict[str, Any] | None,
    router_output: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "runtime_contract": "PROFILE_RUNTIME_EXECUTOR_V1",
        "phase": "SEMANTIC_JUDGE",
        "activation_path": "PAIR" if direct_output is not None and router_output is not None else "SINGLE",
        "profile": {
            "profile_id": manifest.get("profile_id"),
            "profile_slug": manifest.get("profile_slug"),
        },
        "request": request,
        "canonical_context": canonical_context,
        "canonical_source_refs": canonical_source_refs,
        "judge_source": judge_source,
        "direct_output": direct_output,
        "router_output": router_output,
        "executor_rules": {
            "return_exactly_one_json_object": True,
            "no_markdown_fences": True,
            "judge_independently_from_profile_self_score": True,
            "fail_closed_on_insufficient_material_evidence": True,
        },
    }


def persist_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--activation-path", choices=["DIRECT", "ROUTER", "BOTH"], default="BOTH")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--executor-command", default=None)
    parser.add_argument("--executor-kind", choices=["REAL_MODEL", "SYNTHETIC_TEST"], default="REAL_MODEL")
    parser.add_argument("--context-resolver-command", default=None)
    parser.add_argument("--timeout-seconds", type=int, default=120)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    manifest_path = (repo_root / args.manifest).resolve()
    request_path = (repo_root / args.request).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    receipt: dict[str, Any] = {
        "runtime_contract": "PROFILE_RUNTIME_RECEIPT_V1",
        "status": "IN_PROGRESS",
        "manifest": args.manifest,
        "request": args.request,
        "activation_path": args.activation_path,
        "runtime_enabled": False,
        "production_authorized": False,
        "fixture_output_used": False,
        "executor_kind": args.executor_kind,
    }

    try:
        manifest = require_mapping(load_json(manifest_path), "manifest")
        request = require_mapping(load_json(request_path), "request")
        require_nonempty_string(manifest.get("profile_id"), "manifest.profile_id")
        require_nonempty_string(manifest.get("profile_slug"), "manifest.profile_slug")
        source_pack = load_source_pack(repo_root, manifest)

        executor_command = args.executor_command or os.environ.get("PROFILE_RUNTIME_EXECUTOR")
        if not executor_command:
            raise RuntimeBlocked(
                "real_executor_missing:set --executor-command or PROFILE_RUNTIME_EXECUTOR; fixtures are forbidden"
            )
        resolver_command = (
            args.context_resolver_command
            or os.environ.get("PROFILE_RUNTIME_CONTEXT_RESOLVER")
            or None
        )
        canonical_context, canonical_source_refs, context_meta = resolve_context(
            repo_root=repo_root,
            request=request,
            resolver_command=resolver_command,
            timeout_seconds=args.timeout_seconds,
            evidence_dir=output_dir,
        )

        receipt["profile_id"] = manifest["profile_id"]
        receipt["profile_slug"] = manifest["profile_slug"]
        receipt["source_pack"] = [
            {"path": item["path"], "sha256": item["sha256"]}
            for item in source_pack
        ]
        receipt["source_pack_sha256"] = sha256_text(
            canonical_json(receipt["source_pack"])
        )
        receipt["context_resolution"] = context_meta
        receipt["executor_command_sha256"] = sha256_text(
            " ".join(command_from_text(executor_command))
        )

        paths = ["DIRECT", "ROUTER"] if args.activation_path == "BOTH" else [args.activation_path]
        outputs: dict[str, dict[str, Any]] = {}
        validators: dict[str, list[dict[str, Any]]] = {}

        for activation_path in paths:
            envelope = build_profile_envelope(
                manifest=manifest,
                request=request,
                canonical_context=canonical_context,
                canonical_source_refs=canonical_source_refs,
                source_pack=source_pack,
                activation_path=activation_path,
            )
            persist_json(output_dir / f"input_{activation_path.lower()}.json", envelope)
            result = invoke_executor(
                repo_root=repo_root,
                executor_command=executor_command,
                envelope=envelope,
                phase="PROFILE_EXECUTION",
                activation_path=activation_path,
                timeout_seconds=args.timeout_seconds,
                evidence_dir=output_dir,
            )
            parsed_path = output_dir / f"parsed_{activation_path.lower()}.json"
            persist_json(parsed_path, result.parsed)
            outputs[activation_path] = result.parsed
            validator_results = run_validators(
                repo_root=repo_root,
                manifest=manifest,
                parsed_output_path=parsed_path,
                activation_path=activation_path,
                timeout_seconds=args.timeout_seconds,
                evidence_dir=output_dir,
            )
            validators[activation_path] = validator_results

        validator_pass = all(required_validators_pass(items) for items in validators.values())
        receipt["deterministic_validators"] = validators
        receipt["deterministic_validator_pass"] = validator_pass

        pair_result: dict[str, Any] | None = None
        if "DIRECT" in outputs and "ROUTER" in outputs:
            pair_result = compare_pair(outputs["DIRECT"], outputs["ROUTER"])
            receipt["direct_router_comparison"] = pair_result

        judge_result: dict[str, Any] | None = None
        judge_pass = True
        if semantic_judge_required(manifest, request):
            judge_source = semantic_judge_source(repo_root, manifest)
            judge_envelope = build_judge_envelope(
                manifest=manifest,
                request=request,
                canonical_context=canonical_context,
                canonical_source_refs=canonical_source_refs,
                judge_source=judge_source,
                direct_output=outputs.get("DIRECT"),
                router_output=outputs.get("ROUTER"),
            )
            persist_json(output_dir / "input_semantic_judge.json", judge_envelope)
            judge_exec = invoke_executor(
                repo_root=repo_root,
                executor_command=executor_command,
                envelope=judge_envelope,
                phase="SEMANTIC_JUDGE",
                activation_path="PAIR" if len(outputs) == 2 else paths[0],
                timeout_seconds=args.timeout_seconds,
                evidence_dir=output_dir,
            )
            judge_result = judge_exec.parsed
            persist_json(output_dir / "semantic_judge.json", judge_result)
            judge_pass = judge_passes(manifest, judge_result)
            receipt["semantic_judge"] = judge_result
            receipt["semantic_judge_pass"] = judge_pass

        pair_pass = pair_result is None or bool(pair_result["materially_consistent"])
        receipt["direct_router_consistency_pass"] = pair_pass

        if validator_pass and judge_pass and pair_pass:
            if args.executor_kind == "REAL_MODEL":
                receipt["status"] = "PASS_WITH_EVIDENCE"
                receipt["behavioral_evidence_eligible"] = True
            else:
                receipt["status"] = "PASS_HARNESS_ONLY"
                receipt["behavioral_evidence_eligible"] = False
            code = EXIT_PASS
        else:
            receipt["status"] = "FAIL"
            receipt["behavioral_evidence_eligible"] = args.executor_kind == "REAL_MODEL"
            code = EXIT_FAIL

    except RuntimeBlocked as exc:
        receipt["status"] = "BLOCKED"
        receipt["behavioral_evidence_eligible"] = False
        receipt["blocking_reason"] = str(exc)
        code = EXIT_BLOCKED
    except RuntimeFailed as exc:
        receipt["status"] = "FAIL"
        receipt["behavioral_evidence_eligible"] = True
        receipt["failure_reason"] = str(exc)
        code = EXIT_FAIL
    except Exception as exc:
        receipt["status"] = "FAIL"
        receipt["behavioral_evidence_eligible"] = False
        receipt["failure_reason"] = f"UNHANDLED:{type(exc).__name__}:{exc}"
        code = EXIT_FAIL

    persist_json(output_dir / "receipt.json", receipt)
    print(json.dumps(receipt, ensure_ascii=False, indent=2))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
