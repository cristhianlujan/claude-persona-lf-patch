#!/usr/bin/env python3
"""S26 deterministic cheap preflight. Standard-library only and fail-closed."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable

RUN_SCOPE = "S26"
EXECUTION_SCOPE_ID = "S26-CI-PREFLIGHT-V1"
MANIFEST_SCHEMA = "S26_CI_PREFLIGHT_MANIFEST_V1"
BASE = "sandbox/lf_contract_gate_test/profile_execution_runtime"
WORKFLOW_PATH = ".github/workflows/story-agent-evidence-verifier.yml"
MANIFEST_PATH = f"{BASE}/s26_ci_preflight_manifest_v1.json"
MANIFEST_SCHEMA_PATH = f"{BASE}/s26_ci_preflight_manifest.schema.json"

REQUIRED_TOP_LEVEL = {
    "schema", "run_scope", "execution_scope_id", "required_files", "required_scripts", "required_validators",
    "schemas", "authority_sources", "bindings", "inputs", "workflow_guards", "integrity_pins",
}
RUN_ID_RE = re.compile(r"^S\d+(?:-[A-Z0-9-]+)?$")
GIT_BLOB_SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
PREFLIGHT_COMMAND = f"python3 {BASE}/s26_ci_preflight.py --repo-root ."

CANONICAL_REQUIRED_FILES = frozenset({
    "CLAUDE.md",
    WORKFLOW_PATH,
    f"{BASE}/README.md",
    MANIFEST_PATH,
})
CANONICAL_REQUIRED_SCRIPTS = frozenset({
    f"{BASE}/s26_ci_preflight.py",
    f"{BASE}/run_s26_ci_preflight_tests.py",
    f"{BASE}/run_tests.py",
    f"{BASE}/run_semantic_mini_judge_tests.py",
    f"{BASE}/run_profile_runtime_optimization_tests.py",
})
CANONICAL_REQUIRED_VALIDATORS = frozenset({
    f"{BASE}/validate_profile_execution.py",
    f"{BASE}/semantic_obligation_manifest.py",
})
CANONICAL_INTEGRITY_PATHS = frozenset(
    (CANONICAL_REQUIRED_FILES - {MANIFEST_PATH})
    | CANONICAL_REQUIRED_SCRIPTS
    | CANONICAL_REQUIRED_VALIDATORS
    | {MANIFEST_SCHEMA_PATH}
)
CANONICAL_AUTHORITIES = {
    "CI_CONTRACT": "CLAUDE.md",
    "RUNTIME_CONTRACT": f"{BASE}/README.md",
}
CANONICAL_BINDINGS = {
    "PROFILE_EXECUTION_VALIDATOR": {
        "target_ref": f"{BASE}/validate_profile_execution.py",
        "callable": "validate_receipt",
        "probe_mode": "RETURNS_NONEMPTY_ERROR_LIST",
        "expected_error": None,
    },
    "SEMANTIC_MANIFEST_VALIDATOR": {
        "target_ref": f"{BASE}/semantic_obligation_manifest.py",
        "callable": "validate_obligation_manifest",
        "probe_mode": "RAISES_EXPECTED_ERROR",
        "expected_error": "MANIFEST_SCHEMA_INVALID",
    },
}
CANONICAL_INPUTS = {
    "CANONICAL_PREFLIGHT_MANIFEST": MANIFEST_PATH,
}
CANONICAL_WORKFLOW_GUARDS = {
    "semantic-mini-judge-smoke": (
        "Build pinned llama.cpp server from source",
        "Download and verify pinned semantic judge model",
    ),
    "run-zero-cost-profile-runtime": (
        "Build pinned llama.cpp from source",
        "Download and verify pinned multimodal model",
    ),
    "run-zero-cost-profile-batch": (
        "Build pinned llama.cpp runtime bundle on cache miss",
        "Download pinned model on cache miss",
    ),
}
HEAVY_BEFORE_PREFLIGHT_RE = re.compile(
    r"(?i)(curl\s|wget\s|git\s+clone|cmake\s+--build|pip\s+install|"
    r"huggingface|\.gguf\b|\.safetensors\b|llama-(?:cli|server)|"
    r"live[_ -]smoke|model[_ -]download)"
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


def _git_blob_sha1(path: Path) -> str:
    raw = path.read_bytes()
    header = f"blob {len(raw)}\0".encode("ascii")
    return hashlib.sha1(header + raw).hexdigest()


def _declared_strings(value: Any, code: str) -> set[str]:
    items = _list(value, code)
    if any(not isinstance(item, str) or not item.strip() for item in items):
        raise PreflightError(code)
    normalized = [item.strip() for item in items]
    if len(set(normalized)) != len(normalized):
        raise PreflightError(code + "_DUPLICATE")
    return set(normalized)


def _require_declared_subset(value: Any, required: frozenset[str], code: str) -> None:
    declared = _declared_strings(value, code + "_INVALID")
    missing = sorted(required - declared)
    if missing:
        raise PreflightError(code + ":" + ",".join(missing))


def _validate_run_binding(item: dict[str, Any], execution_scope_id: str, label: str) -> None:
    run_id = _text(item.get("run_id"), f"{label}_RUN_ID_MISSING")
    if run_id != execution_scope_id:
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
    prefix = segment[:position]
    if HEAVY_BEFORE_PREFLIGHT_RE.search(prefix):
        raise PreflightError("HEAVY_STAGE_BEFORE_PREFLIGHT:" + job_name)
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


def _validate_integrity_pins(
    repo_root: Path,
    manifest: dict[str, Any],
    execution_scope_id: str,
    checked_paths: set[str],
) -> int:
    rows = _list(manifest.get("integrity_pins"), "INTEGRITY_PINS_INVALID")
    if len(rows) != len(CANONICAL_INTEGRITY_PATHS):
        raise PreflightError("INTEGRITY_PIN_SET_INVALID")
    seen: set[str] = set()
    for index, raw in enumerate(rows):
        if not isinstance(raw, dict):
            raise PreflightError(f"INTEGRITY_PIN_{index}_NOT_OBJECT")
        _validate_run_binding(raw, execution_scope_id, f"INTEGRITY_PIN_{index}")
        ref = _text(raw.get("path"), f"INTEGRITY_PIN_{index}_PATH_MISSING")
        if ref in seen:
            raise PreflightError("INTEGRITY_PIN_DUPLICATE:" + ref)
        seen.add(ref)
        if ref not in CANONICAL_INTEGRITY_PATHS:
            raise PreflightError("INTEGRITY_PIN_UNKNOWN_PATH:" + ref)
        expected = _text(raw.get("git_blob_sha1"), f"INTEGRITY_PIN_{index}_SHA_MISSING")
        if not GIT_BLOB_SHA1_RE.fullmatch(expected):
            raise PreflightError("INTEGRITY_PIN_SHA_INVALID:" + ref)
        path = _require_file(repo_root, ref, f"INTEGRITY_PIN_{index}_FILE_MISSING")
        actual = _git_blob_sha1(path)
        if actual != expected:
            raise PreflightError("INTEGRITY_PIN_MISMATCH:" + ref)
        checked_paths.add(str(path.relative_to(repo_root.resolve())))
    missing = sorted(CANONICAL_INTEGRITY_PATHS - seen)
    extra = sorted(seen - CANONICAL_INTEGRITY_PATHS)
    if missing or extra:
        raise PreflightError(
            "INTEGRITY_PIN_SET_INVALID:missing=" + ",".join(missing) + ":extra=" + ",".join(extra)
        )
    return len(rows)


def _validate_canonical_authorities(repo_root: Path, manifest: dict[str, Any], execution_scope_id: str, checked_paths: set[str]) -> None:
    seen: set[str] = set()
    rows = _list(manifest.get("authority_sources"), "AUTHORITY_SOURCES_INVALID")
    if len(rows) != len(CANONICAL_AUTHORITIES):
        raise PreflightError("SOURCE_AUTHORITY_SET_INVALID")
    for index, raw in enumerate(rows):
        if not isinstance(raw, dict):
            raise PreflightError(f"AUTHORITY_{index}_NOT_OBJECT")
        _validate_run_binding(raw, execution_scope_id, f"AUTHORITY_{index}")
        authority_type = _text(raw.get("authority_type"), f"AUTHORITY_{index}_TYPE_MISSING")
        if authority_type in seen:
            raise PreflightError("SOURCE_AUTHORITY_DUPLICATE:" + authority_type)
        seen.add(authority_type)
        expected_ref = CANONICAL_AUTHORITIES.get(authority_type)
        if expected_ref is None:
            raise PreflightError("SOURCE_AUTHORITY_UNKNOWN:" + authority_type)
        ref = _text(raw.get("source_ref"), f"AUTHORITY_{index}_SOURCE_REF_MISSING")
        if ref != expected_ref:
            raise PreflightError("SOURCE_AUTHORITY_REF_MISMATCH:" + authority_type)
        path = _require_file(repo_root, ref, f"AUTHORITY_{index}_SOURCE_REF_INVALID")
        checked_paths.add(str(path.relative_to(repo_root.resolve())))
    if seen != set(CANONICAL_AUTHORITIES):
        raise PreflightError("SOURCE_AUTHORITY_SET_INVALID")


def _validate_canonical_bindings(repo_root: Path, manifest: dict[str, Any], execution_scope_id: str, checked_paths: set[str]) -> None:
    seen: set[str] = set()
    rows = _list(manifest.get("bindings"), "BINDINGS_INVALID")
    if len(rows) != len(CANONICAL_BINDINGS):
        raise PreflightError("REQUIRED_BINDING_SET_INVALID")
    for index, raw in enumerate(rows):
        if not isinstance(raw, dict):
            raise PreflightError(f"BINDING_{index}_NOT_OBJECT")
        _validate_run_binding(raw, execution_scope_id, f"BINDING_{index}")
        binding_id = _text(raw.get("binding_id"), f"BINDING_{index}_ID_MISSING")
        if binding_id in seen:
            raise PreflightError("BINDING_DUPLICATE:" + binding_id)
        seen.add(binding_id)
        expected = CANONICAL_BINDINGS.get(binding_id)
        if expected is None:
            raise PreflightError("BINDING_UNKNOWN:" + binding_id)
        for field in ("target_ref", "callable", "probe_mode"):
            if raw.get(field) != expected[field]:
                raise PreflightError(f"VALIDATOR_BINDING_MISMATCH:{binding_id}:{field}")
        if expected["expected_error"] is None:
            if raw.get("expected_error") not in (None, ""):
                raise PreflightError(f"VALIDATOR_BINDING_MISMATCH:{binding_id}:expected_error")
        elif raw.get("expected_error") != expected["expected_error"]:
            raise PreflightError(f"VALIDATOR_BINDING_MISMATCH:{binding_id}:expected_error")
        path = _require_file(repo_root, raw.get("target_ref"), f"BINDING_{index}_TARGET_MISSING")
        _execute_validator_probe(path, raw, binding_id)
        checked_paths.add(str(path.relative_to(repo_root.resolve())))
    if seen != set(CANONICAL_BINDINGS):
        raise PreflightError("REQUIRED_BINDING_SET_INVALID")


def _validate_canonical_inputs(repo_root: Path, manifest: dict[str, Any], execution_scope_id: str, checked_paths: set[str]) -> None:
    rows = _list(manifest.get("inputs"), "INPUTS_INVALID")
    if len(rows) != len(CANONICAL_INPUTS):
        raise PreflightError("DECLARED_INPUT_SET_INVALID")
    seen: set[str] = set()
    for index, raw in enumerate(rows):
        if not isinstance(raw, dict):
            raise PreflightError(f"INPUT_{index}_NOT_OBJECT")
        _validate_run_binding(raw, execution_scope_id, f"INPUT_{index}")
        input_id = _text(raw.get("input_id"), f"INPUT_{index}_ID_MISSING")
        if input_id in seen:
            raise PreflightError("INPUT_DUPLICATE:" + input_id)
        seen.add(input_id)
        expected_path = CANONICAL_INPUTS.get(input_id)
        if expected_path is None or raw.get("path") != expected_path:
            raise PreflightError("DECLARED_INPUT_REF_MISMATCH:" + input_id)
        path = _require_file(repo_root, raw.get("path"), f"INPUT_{index}_PATH_MISSING")
        checked_paths.add(str(path.relative_to(repo_root.resolve())))
    if seen != set(CANONICAL_INPUTS):
        raise PreflightError("DECLARED_INPUT_SET_INVALID")


def _validate_workflow_guards(repo_root: Path, manifest: dict[str, Any], execution_scope_id: str) -> None:
    rows = _list(manifest.get("workflow_guards"), "WORKFLOW_GUARDS_INVALID")
    if len(rows) != len(CANONICAL_WORKFLOW_GUARDS):
        raise PreflightError("WORKFLOW_GUARD_SET_INVALID")
    seen: set[str] = set()
    for index, raw in enumerate(rows):
        if not isinstance(raw, dict):
            raise PreflightError(f"WORKFLOW_GUARD_{index}_NOT_OBJECT")
        _validate_run_binding(raw, execution_scope_id, f"WORKFLOW_GUARD_{index}")
        workflow_ref = _text(raw.get("workflow_path"), f"WORKFLOW_GUARD_{index}_PATH_MISSING")
        if workflow_ref != WORKFLOW_PATH:
            raise PreflightError("WORKFLOW_GUARD_PATH_MISMATCH")
        workflow_path = _require_file(repo_root, workflow_ref, f"WORKFLOW_GUARD_{index}_PATH_MISSING")
        job_name = _text(raw.get("job"), f"WORKFLOW_GUARD_{index}_JOB_MISSING")
        if job_name in seen:
            raise PreflightError("WORKFLOW_GUARD_DUPLICATE:" + job_name)
        seen.add(job_name)
        expected_heavy = CANONICAL_WORKFLOW_GUARDS.get(job_name)
        if expected_heavy is None:
            raise PreflightError("WORKFLOW_GUARD_JOB_UNKNOWN:" + job_name)
        preflight_marker = _text(raw.get("preflight_marker"), f"WORKFLOW_GUARD_{index}_PREFLIGHT_MARKER_MISSING")
        if preflight_marker != "S26 cheap deterministic preflight":
            raise PreflightError("WORKFLOW_GUARD_PREFLIGHT_MISMATCH:" + job_name)
        heavy_markers = tuple(
            _text(item, f"WORKFLOW_GUARD_{index}_HEAVY_MARKER_INVALID")
            for item in _list(raw.get("heavy_markers"), f"WORKFLOW_GUARD_{index}_HEAVY_MARKERS_INVALID")
        )
        if heavy_markers != expected_heavy:
            raise PreflightError("WORKFLOW_GUARD_HEAVY_SET_MISMATCH:" + job_name)
        segment = _job_segment(workflow_path.read_text(encoding="utf-8"), job_name)
        preflight_pos = _validate_executable_preflight(segment, job_name, preflight_marker)
        for heavy_text in expected_heavy:
            try:
                heavy_pos, _ = _named_step(segment, heavy_text)
            except PreflightError as exc:
                raise PreflightError("HEAVY_STAGE_STEP_MISSING:" + job_name + ":" + heavy_text) from exc
            if preflight_pos > heavy_pos:
                raise PreflightError("PREFLIGHT_AFTER_HEAVY_STAGE:" + job_name + ":" + heavy_text)
    if seen != set(CANONICAL_WORKFLOW_GUARDS):
        raise PreflightError("WORKFLOW_GUARD_SET_INVALID")


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
    if run_scope != RUN_SCOPE:
        raise PreflightError("RUN_SCOPE_NOT_S26")
    execution_scope_id = _text(manifest.get("execution_scope_id"), "EXECUTION_SCOPE_ID_MISSING")
    if execution_scope_id != EXECUTION_SCOPE_ID:
        raise PreflightError("EXECUTION_SCOPE_ID_INVALID:" + execution_scope_id)

    _require_declared_subset(manifest.get("required_files"), CANONICAL_REQUIRED_FILES, "REQUIRED_FILE_DECLARATION_MISSING")
    _require_declared_subset(manifest.get("required_scripts"), CANONICAL_REQUIRED_SCRIPTS, "REQUIRED_SCRIPT_DECLARATION_MISSING")
    _require_declared_subset(manifest.get("required_validators"), CANONICAL_REQUIRED_VALIDATORS, "REQUIRED_VALIDATOR_DECLARATION_MISSING")

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

    rows = _list(manifest.get("schemas"), "SCHEMAS_INVALID")
    if len(rows) != 1 or not isinstance(rows[0], dict):
        raise PreflightError("PREFLIGHT_MANIFEST_SCHEMA_BINDING_INVALID")
    raw_schema = rows[0]
    _validate_run_binding(raw_schema, execution_scope_id, "SCHEMA_0")
    if raw_schema.get("path") != MANIFEST_SCHEMA_PATH or raw_schema.get("schema_role") != "PREFLIGHT_MANIFEST":
        raise PreflightError("PREFLIGHT_MANIFEST_SCHEMA_BINDING_INVALID")
    schema_path = _require_file(repo_root, raw_schema.get("path"), "SCHEMA_0_PATH_MISSING")
    checked_paths.add(str(schema_path.relative_to(repo_root.resolve())))

    integrity_count = _validate_integrity_pins(repo_root, manifest, execution_scope_id, checked_paths)
    manifest_schema_payload = _load_schema(schema_path)
    _apply_json_schema(manifest, manifest_schema_payload)

    _validate_canonical_authorities(repo_root, manifest, execution_scope_id, checked_paths)
    _validate_canonical_bindings(repo_root, manifest, execution_scope_id, checked_paths)
    _validate_canonical_inputs(repo_root, manifest, execution_scope_id, checked_paths)
    _validate_workflow_guards(repo_root, manifest, execution_scope_id)

    return {
        "status": "PASS_S26_CHEAP_PREFLIGHT",
        "run_scope": run_scope,
        "execution_scope_id": execution_scope_id,
        "checked_paths": sorted(checked_paths),
        "workflow_guards": len(manifest["workflow_guards"]),
        "manifest_schema_applied": True,
        "validator_bindings_executed": len(manifest["bindings"]),
        "canonical_authorities_pinned": True,
        "canonical_workflow_guard_set_pinned": True,
        "integrity_pins_verified": integrity_count,
    }


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(MANIFEST_PATH),
    )
    args = parser.parse_args(list(argv) if argv is not None else None)
    try:
        if args.manifest.is_absolute() or ".." in args.manifest.parts:
            raise PreflightError("MANIFEST_PATH_NOT_REPRODUCIBLE")
        payload = json.loads((args.repo_root / args.manifest).read_text(encoding="utf-8"))
        result = validate_manifest(args.repo_root, payload)
    except (OSError, json.JSONDecodeError, PreflightError) as exc:
        print(json.dumps({"status": "BLOCK_S26_CHEAP_PREFLIGHT", "error": str(exc)}, sort_keys=True))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
