#!/usr/bin/env python3
"""S26 deterministic cheap preflight. Standard-library only and fail-closed."""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable

MANIFEST_SCHEMA = "S26_CI_PREFLIGHT_MANIFEST_V1"
REQUIRED_TOP_LEVEL = {
    "schema", "run_scope", "required_files", "required_scripts", "required_validators",
    "schemas", "authority_sources", "bindings", "inputs", "workflow_guards",
}
RUN_ID_RE = re.compile(r"^S\d+$")
PREFLIGHT_COMMAND = (
    "python3 sandbox/lf_contract_gate_test/profile_execution_runtime/"
    "s26_ci_preflight.py --repo-root ."
)


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


def _load_schema(path: Path) -> dict[str, Any]:
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
    return payload


def _schema_type_matches(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    return False


def _apply_json_schema(value: Any, schema: dict[str, Any], pointer: str = "$") -> None:
    expected_type = schema.get("type")
    if expected_type is not None:
        if not isinstance(expected_type, str) or not _schema_type_matches(value, expected_type):
            raise PreflightError(f"MANIFEST_SCHEMA_VALIDATION_FAILED:{pointer}:type")
    if "const" in schema and value != schema["const"]:
        raise PreflightError(f"MANIFEST_SCHEMA_VALIDATION_FAILED:{pointer}:const")
    if "enum" in schema:
        enum = schema["enum"]
        if not isinstance(enum, list) or value not in enum:
            raise PreflightError(f"MANIFEST_SCHEMA_VALIDATION_FAILED:{pointer}:enum")
    if isinstance(value, str) and "minLength" in schema:
        minimum = schema["minLength"]
        if not isinstance(minimum, int) or len(value) < minimum:
            raise PreflightError(f"MANIFEST_SCHEMA_VALIDATION_FAILED:{pointer}:minLength")
    if isinstance(value, list):
        if "minItems" in schema:
            minimum = schema["minItems"]
            if not isinstance(minimum, int) or len(value) < minimum:
                raise PreflightError(f"MANIFEST_SCHEMA_VALIDATION_FAILED:{pointer}:minItems")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                _apply_json_schema(item, item_schema, f"{pointer}/{index}")
    if isinstance(value, dict):
        required = schema.get("required", [])
        if not isinstance(required, list) or any(not isinstance(key, str) for key in required):
            raise PreflightError(f"SCHEMA_DEFINITION_INVALID:{pointer}:required")
        missing = [key for key in required if key not in value]
        if missing:
            raise PreflightError(
                f"MANIFEST_SCHEMA_VALIDATION_FAILED:{pointer}:required:" + ",".join(sorted(missing))
            )
        properties = schema.get("properties", {})
        if not isinstance(properties, dict):
            raise PreflightError(f"SCHEMA_DEFINITION_INVALID:{pointer}:properties")
        for key, child_schema in properties.items():
            if key in value and isinstance(child_schema, dict):
                _apply_json_schema(value[key], child_schema, f"{pointer}/{key}")
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise PreflightError(
                    f"MANIFEST_SCHEMA_VALIDATION_FAILED:{pointer}:additionalProperties:" + ",".join(extras)
                )


def _job_segment(workflow_text: str, job_name: str) -> str:
    marker = f"  {job_name}:"
    start = workflow_text.find(marker)
    if start < 0:
        raise PreflightError("WORKFLOW_JOB_MISSING:" + job_name)
    tail = workflow_text[start + len(marker):]
    next_job = re.search(r"(?m)^  [A-Za-z0-9_-]+:\s*$", tail)
    return workflow_text[start:] if next_job is None else workflow_text[start:start + len(marker) + next_job.start()]


def _named_step(segment: str, step_name: str) -> tuple[int, str]:
    pattern = re.compile(rf"(?m)^      - name: {re.escape(step_name)}\s*$")
    matches = list(pattern.finditer(segment))
    if len(matches) != 1:
        raise PreflightError("WORKFLOW_STEP_COUNT_INVALID:" + step_name + f":{len(matches)}")
    match = matches[0]
    tail = segment[match.end():]
    next_step = re.search(r"(?m)^      - name: ", tail)
    end = len(segment) if next_step is None else match.end() + next_step.start()
    return match.start(), segment[match.start():end]


def _validate_executable_preflight(segment: str, job_name: str, step_name: str) -> int:
    try:
        position, block = _named_step(segment, step_name)
    except PreflightError as exc:
        raise PreflightError("PREFLIGHT_EXECUTABLE_STEP_MISSING:" + job_name) from exc
    run_match = re.search(r"(?m)^        run:\s*\|\s*$", block)
    if run_match is None:
        raise PreflightError("PREFLIGHT_RUN_BLOCK_MISSING:" + job_name)
    command_match = re.search(rf"(?m)^          {re.escape(PREFLIGHT_COMMAND)}\s*$", block)
    if command_match is None or command_match.start() < run_match.end():
        raise PreflightError("PREFLIGHT_EXECUTABLE_COMMAND_MISSING:" + job_name)
    return position


def _load_module(path: Path, binding_id: str):
    module_name = "_s26_preflight_" + re.sub(r"[^A-Za-z0-9_]", "_", binding_id.lower())
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise PreflightError("VALIDATOR_IMPORT_SPEC_INVALID:" + binding_id)
    module = importlib.util.module_from_spec(spec)
    sys_path_added = False
    parent = str(path.parent)
    if parent not in sys.path:
        sys.path.insert(0, parent)
        sys_path_added = True
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        raise PreflightError("VALIDATOR_IMPORT_FAILED:" + binding_id + ":" + type(exc).__name__) from exc
    finally:
        if sys_path_added and sys.path and sys.path[0] == parent:
            sys.path.pop(0)
    return module


def _execute_validator_probe(path: Path, raw: dict[str, Any], binding_id: str) -> None:
    callable_name = _text(raw.get("callable"), "VALIDATOR_CALLABLE_MISSING:" + binding_id)
    probe_mode = _text(raw.get("probe_mode"), "VALIDATOR_PROBE_MODE_MISSING:" + binding_id)
    module = _load_module(path, binding_id)
    function = getattr(module, callable_name, None)
    if not callable(function):
        raise PreflightError("VALIDATOR_CALLABLE_MISSING:" + binding_id + ":" + callable_name)
    if probe_mode == "RETURNS_NONEMPTY_ERROR_LIST":
        try:
            result = function({})
        except Exception as exc:
            raise PreflightError("VALIDATOR_PROBE_UNEXPECTED_EXCEPTION:" + binding_id) from exc
        if not isinstance(result, list) or not result or not all(isinstance(item, str) for item in result):
            raise PreflightError("VALIDATOR_PROBE_CONTRACT_FAILED:" + binding_id)
        return
    if probe_mode == "RAISES_EXPECTED_ERROR":
        expected = _text(raw.get("expected_error"), "VALIDATOR_EXPECTED_ERROR_MISSING:" + binding_id)
        try:
            function({})
        except Exception as exc:
            if expected not in str(exc):
                raise PreflightError(
                    "VALIDATOR_PROBE_WRONG_ERROR:" + binding_id + ":" + type(exc).__name__
                ) from exc
            return
        raise PreflightError("VALIDATOR_PROBE_DID_NOT_FAIL:" + binding_id)
    raise PreflightError("VALIDATOR_PROBE_MODE_INVALID:" + binding_id + ":" + probe_mode)


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

    manifest_schema_payload: dict[str, Any] | None = None
    manifest_schema_count = 0
    for index, raw in enumerate(_list(manifest.get("schemas"), "SCHEMAS_INVALID")):
        if not isinstance(raw, dict):
            raise PreflightError(f"SCHEMA_{index}_NOT_OBJECT")
        _validate_run_binding(raw, run_scope, f"SCHEMA_{index}")
        path = _require_file(repo_root, raw.get("path"), f"SCHEMA_{index}_PATH_MISSING")
        schema_payload = _load_schema(path)
        role = _text(raw.get("schema_role"), f"SCHEMA_{index}_ROLE_MISSING")
        if role == "PREFLIGHT_MANIFEST":
            manifest_schema_count += 1
            manifest_schema_payload = schema_payload
        checked_paths.add(str(path.relative_to(repo_root.resolve())))
    if manifest_schema_count != 1 or manifest_schema_payload is None:
        raise PreflightError("PREFLIGHT_MANIFEST_SCHEMA_BINDING_INVALID")
    _apply_json_schema(manifest, manifest_schema_payload)

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
        _execute_validator_probe(path, raw, binding_id)
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
        preflight_pos = _validate_executable_preflight(segment, job_name, preflight_marker)
        for heavy in heavy_markers:
            heavy_text = _text(heavy, f"WORKFLOW_GUARD_{index}_HEAVY_MARKER_INVALID")
            try:
                heavy_pos, _ = _named_step(segment, heavy_text)
            except PreflightError as exc:
                raise PreflightError("HEAVY_STAGE_STEP_MISSING:" + job_name + ":" + heavy_text) from exc
            if preflight_pos > heavy_pos:
                raise PreflightError("PREFLIGHT_AFTER_HEAVY_STAGE:" + job_name + ":" + heavy_text)

    return {
        "status": "PASS_S26_CHEAP_PREFLIGHT",
        "run_scope": run_scope,
        "checked_paths": sorted(checked_paths),
        "workflow_guards": len(manifest["workflow_guards"]),
        "manifest_schema_applied": True,
        "validator_bindings_executed": len(manifest["bindings"]),
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
