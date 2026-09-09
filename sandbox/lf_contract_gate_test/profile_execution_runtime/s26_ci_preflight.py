#!/usr/bin/env python3
"""S26 deterministic cheap preflight. Standard-library only and fail-closed."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Iterable

MANIFEST_SCHEMA = "S26_CI_PREFLIGHT_MANIFEST_V1"
REQUIRED_TOP_LEVEL = {
    "schema", "run_scope", "required_files", "required_scripts", "required_validators",
    "schemas", "authority_sources", "bindings", "inputs", "workflow_guards",
}
RUN_ID_RE = re.compile(r"^S\d+$")


class PreflightError(ValueError):
    pass


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PreflightError(code)
    return value.strip()


def _list(value: Any, code: str) -> list[Any]:
    if not isinstance(value, list) or not value:
        raise PreflightError(code)
    return value


def _repo_path(repo_root: Path, raw: Any, code: str) -> Path:
    rel = _text(raw, code)
    candidate = Path(rel)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise PreflightError("PATH_NOT_REPRODUCIBLE:" + rel)
    resolved_root = repo_root.resolve()
    resolved = (resolved_root / candidate).resolve()
    try:
        resolved.relative_to(resolved_root)
    except ValueError as exc:
        raise PreflightError("PATH_ESCAPES_REPO:" + rel) from exc
    return resolved


def _require_file(repo_root: Path, raw: Any, code: str) -> Path:
    path = _repo_path(repo_root, raw, code)
    if not path.is_file():
        raise PreflightError("REQUIRED_FILE_MISSING:" + str(raw))
    return path


def _validate_run_binding(item: dict[str, Any], run_scope: str, label: str) -> None:
    run_id = _text(item.get("run_id"), f"{label}_RUN_ID_MISSING")
    if run_id != run_scope:
        raise PreflightError(f"CROSS_RUN_REFERENCE:{label}:{run_id}")


def _validate_schema_file(path: Path) -> None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise PreflightError("SCHEMA_INVALID_JSON:" + str(path)) from exc
    if not isinstance(payload, dict):
        raise PreflightError("SCHEMA_NOT_OBJECT:" + str(path))
    meta = payload.get("$schema")
    if not isinstance(meta, str) or "json-schema.org" not in meta:
        raise PreflightError("SCHEMA_META_INVALID:" + str(path))
    if payload.get("type") not in {"object", "array", "string", "number", "integer", "boolean", "null"}:
        raise PreflightError("SCHEMA_TYPE_INVALID:" + str(path))


def _job_segment(workflow_text: str, job_name: str) -> str:
    marker = f"  {job_name}:"
    start = workflow_text.find(marker)
    if start < 0:
        raise PreflightError("WORKFLOW_JOB_MISSING:" + job_name)
    tail = workflow_text[start + len(marker):]
    next_job = re.search(r"(?m)^  [A-Za-z0-9_-]+:\s*$", tail)
    return workflow_text[start:] if next_job is None else workflow_text[start:start + len(marker) + next_job.start()]


def validate_manifest(repo_root: Path, manifest: Any) -> dict[str, Any]:
    if not isinstance(manifest, dict):
        raise PreflightError("MANIFEST_NOT_OBJECT")
    missing = sorted(REQUIRED_TOP_LEVEL - set(manifest))
    if missing:
        raise PreflightError("MANIFEST_INCOMPLETE:" + ",".join(missing))
    if manifest.get("schema") != MANIFEST_SCHEMA:
        raise PreflightError("MANIFEST_SCHEMA_INVALID")
    run_scope = _text(manifest.get("run_scope"), "RUN_SCOPE_MISSING")
    if not RUN_ID_RE.fullmatch(run_scope):
        raise PreflightError("RUN_SCOPE_INVALID")
    if run_scope != "S26":
        raise PreflightError("RUN_SCOPE_NOT_S26")

    checked_paths: set[str] = set()
    for field in ("required_files", "required_scripts", "required_validators"):
        for raw in _list(manifest.get(field), field.upper() + "_INVALID"):
            path = _require_file(repo_root, raw, field.upper() + "_PATH_INVALID")
            checked_paths.add(str(path.relative_to(repo_root.resolve())))

    scripts = manifest["required_scripts"]
    if not all(str(item).endswith((".py", ".sh")) for item in scripts):
        raise PreflightError("REQUIRED_SCRIPT_TYPE_INVALID")

    validators = manifest["required_validators"]
    if len(set(validators)) != len(validators):
        raise PreflightError("VALIDATOR_DUPLICATE")

    for index, raw in enumerate(_list(manifest.get("schemas"), "SCHEMAS_INVALID")):
        if not isinstance(raw, dict):
            raise PreflightError(f"SCHEMA_{index}_NOT_OBJECT")
        _validate_run_binding(raw, run_scope, f"SCHEMA_{index}")
        path = _require_file(repo_root, raw.get("path"), f"SCHEMA_{index}_PATH_MISSING")
        _validate_schema_file(path)
        checked_paths.add(str(path.relative_to(repo_root.resolve())))

    authority_types: set[str] = set()
    for index, raw in enumerate(_list(manifest.get("authority_sources"), "AUTHORITY_SOURCES_INVALID")):
        if not isinstance(raw, dict):
            raise PreflightError(f"AUTHORITY_{index}_NOT_OBJECT")
        _validate_run_binding(raw, run_scope, f"AUTHORITY_{index}")
        authority_type = _text(raw.get("authority_type"), f"AUTHORITY_{index}_TYPE_MISSING")
        authority_types.add(authority_type)
        ref = _text(raw.get("source_ref"), f"AUTHORITY_{index}_SOURCE_REF_MISSING")
        if not ref.startswith("input:"):
            path = _require_file(repo_root, ref, f"AUTHORITY_{index}_SOURCE_REF_INVALID")
            checked_paths.add(str(path.relative_to(repo_root.resolve())))
    missing_authority = {"CI_CONTRACT", "RUNTIME_CONTRACT"} - authority_types
    if missing_authority:
        raise PreflightError("SOURCE_AUTHORITY_MISSING:" + ",".join(sorted(missing_authority)))

    binding_ids: set[str] = set()
    for index, raw in enumerate(_list(manifest.get("bindings"), "BINDINGS_INVALID")):
        if not isinstance(raw, dict):
            raise PreflightError(f"BINDING_{index}_NOT_OBJECT")
        _validate_run_binding(raw, run_scope, f"BINDING_{index}")
        binding_id = _text(raw.get("binding_id"), f"BINDING_{index}_ID_MISSING")
        if binding_id in binding_ids:
            raise PreflightError("BINDING_DUPLICATE:" + binding_id)
        binding_ids.add(binding_id)
        path = _require_file(repo_root, raw.get("target_ref"), f"BINDING_{index}_TARGET_MISSING")
        checked_paths.add(str(path.relative_to(repo_root.resolve())))
    required_binding_ids = {"PROFILE_EXECUTION_VALIDATOR", "SEMANTIC_MANIFEST_VALIDATOR"}
    missing_bindings = required_binding_ids - binding_ids
    if missing_bindings:
        raise PreflightError("REQUIRED_BINDING_MISSING:" + ",".join(sorted(missing_bindings)))

    input_ids: set[str] = set()
    for index, raw in enumerate(_list(manifest.get("inputs"), "INPUTS_INVALID")):
        if not isinstance(raw, dict):
            raise PreflightError(f"INPUT_{index}_NOT_OBJECT")
        _validate_run_binding(raw, run_scope, f"INPUT_{index}")
        input_id = _text(raw.get("input_id"), f"INPUT_{index}_ID_MISSING")
        input_ids.add(input_id)
        path = _require_file(repo_root, raw.get("path"), f"INPUT_{index}_PATH_MISSING")
        checked_paths.add(str(path.relative_to(repo_root.resolve())))
    if "CANONICAL_PREFLIGHT_MANIFEST" not in input_ids:
        raise PreflightError("DECLARED_INPUT_MISSING:CANONICAL_PREFLIGHT_MANIFEST")

    for index, raw in enumerate(_list(manifest.get("workflow_guards"), "WORKFLOW_GUARDS_INVALID")):
        if not isinstance(raw, dict):
            raise PreflightError(f"WORKFLOW_GUARD_{index}_NOT_OBJECT")
        _validate_run_binding(raw, run_scope, f"WORKFLOW_GUARD_{index}")
        workflow_path = _require_file(repo_root, raw.get("workflow_path"), f"WORKFLOW_GUARD_{index}_PATH_MISSING")
        job_name = _text(raw.get("job"), f"WORKFLOW_GUARD_{index}_JOB_MISSING")
        preflight_marker = _text(raw.get("preflight_marker"), f"WORKFLOW_GUARD_{index}_PREFLIGHT_MARKER_MISSING")
        heavy_markers = _list(raw.get("heavy_markers"), f"WORKFLOW_GUARD_{index}_HEAVY_MARKERS_INVALID")
        segment = _job_segment(workflow_path.read_text(encoding="utf-8"), job_name)
        preflight_pos = segment.find(preflight_marker)
        if preflight_pos < 0:
            raise PreflightError("PREFLIGHT_NOT_IN_JOB:" + job_name)
        for heavy in heavy_markers:
            heavy_text = _text(heavy, f"WORKFLOW_GUARD_{index}_HEAVY_MARKER_INVALID")
            heavy_pos = segment.find(heavy_text)
            if heavy_pos < 0:
                raise PreflightError("HEAVY_STAGE_MARKER_MISSING:" + job_name + ":" + heavy_text)
            if preflight_pos > heavy_pos:
                raise PreflightError("PREFLIGHT_AFTER_HEAVY_STAGE:" + job_name + ":" + heavy_text)

    return {
        "status": "PASS_S26_CHEAP_PREFLIGHT",
        "run_scope": run_scope,
        "checked_paths": sorted(checked_paths),
        "workflow_guards": len(manifest["workflow_guards"]),
    }


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("sandbox/lf_contract_gate_test/profile_execution_runtime/s26_ci_preflight_manifest_v1.json"),
    )
    args = parser.parse_args(list(argv) if argv is not None else None)
    try:
        payload = json.loads((args.repo_root / args.manifest).read_text(encoding="utf-8"))
        result = validate_manifest(args.repo_root, payload)
    except (OSError, json.JSONDecodeError, PreflightError) as exc:
        print(json.dumps({"status": "BLOCK_S26_CHEAP_PREFLIGHT", "error": str(exc)}, sort_keys=True))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
