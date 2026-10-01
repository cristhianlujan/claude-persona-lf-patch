#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Mapping

SCHEMA_VALUE = "LF_UNIFIED_EXECUTION_TASK_V1"
REQUIRED_FIELDS = (
    "schema",
    "execution_id",
    "operation_code",
    "operation_spec_digest",
    "task_id",
    "step_id",
    "attempt_no",
    "profile_code",
    "profile_source_sha",
    "executor_binding_id",
    "executor_binding_digest",
    "required_capabilities",
    "input_refs",
    "evidence_refs",
    "lease_required",
)
IDENTITY_FIELDS = (
    "execution_id",
    "operation_code",
    "operation_spec_digest",
    "profile_code",
    "profile_source_sha",
    "executor_binding_id",
    "executor_binding_digest",
)
ARRAY_FIELDS = ("required_capabilities", "input_refs", "evidence_refs")
ROUTING_KEYS = {"route", "routing", "selected_next_task", "selected_next_step"}
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")


def _nonempty_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_task_envelope(
    envelope: Any,
    expected_identity: Mapping[str, Any] | None = None,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(envelope, dict):
        return ["TASK_ENVELOPE_NOT_OBJECT"]

    for field in REQUIRED_FIELDS:
        if field not in envelope:
            errors.append(f"TASK_ENVELOPE_MISSING_{field.upper()}")

    if envelope.get("schema") != SCHEMA_VALUE:
        errors.append("TASK_ENVELOPE_SCHEMA_MISMATCH")

    for field in ("execution_id", "operation_code", "task_id", "step_id", "profile_code", "executor_binding_id"):
        if field in envelope and not _nonempty_text(envelope[field]):
            errors.append(f"TASK_ENVELOPE_INVALID_{field.upper()}")

    if "operation_spec_digest" in envelope and (
        not isinstance(envelope["operation_spec_digest"], str)
        or not SHA64.fullmatch(envelope["operation_spec_digest"])
    ):
        errors.append("TASK_ENVELOPE_INVALID_OPERATION_SPEC_DIGEST")

    if "profile_source_sha" in envelope and (
        not isinstance(envelope["profile_source_sha"], str)
        or not SHA40.fullmatch(envelope["profile_source_sha"])
    ):
        errors.append("TASK_ENVELOPE_INVALID_PROFILE_SOURCE_SHA")

    if "executor_binding_digest" in envelope and (
        not isinstance(envelope["executor_binding_digest"], str)
        or not SHA64.fullmatch(envelope["executor_binding_digest"])
    ):
        errors.append("TASK_ENVELOPE_INVALID_EXECUTOR_BINDING_DIGEST")

    if "attempt_no" in envelope:
        attempt_no = envelope["attempt_no"]
        if type(attempt_no) is not int or attempt_no < 1:
            errors.append("TASK_ENVELOPE_INVALID_ATTEMPT_NO")

    for field in ARRAY_FIELDS:
        if field in envelope and not isinstance(envelope[field], list):
            errors.append(f"TASK_ENVELOPE_INVALID_{field.upper()}_TYPE")

    if envelope.get("lease_required") is not True:
        errors.append("TASK_ENVELOPE_LEASE_REQUIRED_MUST_BE_TRUE")

    for key in envelope:
        if key.startswith("next_") or key.startswith("selected_next_") or key in ROUTING_KEYS:
            errors.append(f"TASK_ENVELOPE_FORBIDDEN_ROUTING_FIELD:{key}")

    if expected_identity is not None:
        missing_expected = [field for field in IDENTITY_FIELDS if field not in expected_identity]
        if missing_expected:
            errors.append("EXPECTED_EXECUTION_IDENTITY_INCOMPLETE:" + ",".join(missing_expected))
        else:
            for field in IDENTITY_FIELDS:
                if envelope.get(field) != expected_identity[field]:
                    errors.append(f"TASK_ENVELOPE_IDENTITY_MISMATCH:{field}")

    return sorted(set(errors))


def validate_schema_contract(schema_doc: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(schema_doc, dict):
        return ["TASK_SCHEMA_NOT_OBJECT"]
    required = schema_doc.get("required")
    if required != list(REQUIRED_FIELDS):
        errors.append("TASK_SCHEMA_REQUIRED_FIELDS_DRIFT")
    properties = schema_doc.get("properties")
    if not isinstance(properties, dict):
        errors.append("TASK_SCHEMA_PROPERTIES_MISSING")
        return errors
    if properties.get("schema", {}).get("const") != SCHEMA_VALUE:
        errors.append("TASK_SCHEMA_VALUE_DRIFT")
    if properties.get("attempt_no", {}).get("minimum") != 1:
        errors.append("TASK_SCHEMA_ATTEMPT_MIN_DRIFT")
    if properties.get("lease_required", {}).get("const") is not True:
        errors.append("TASK_SCHEMA_LEASE_REQUIRED_DRIFT")
    authority = schema_doc.get("x-lf-authority")
    if not isinstance(authority, dict):
        errors.append("TASK_SCHEMA_AUTHORITY_MISSING")
    else:
        if authority.get("next_task_owner") != "advance_execution":
            errors.append("TASK_SCHEMA_NEXT_TASK_OWNER_DRIFT")
        if authority.get("executor_selects_next_task") is not False:
            errors.append("TASK_SCHEMA_EXECUTOR_ROUTING_DRIFT")
    return sorted(set(errors))


def load_schema(path: str | Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    schema_path = root / "gobernanza/contratos/lf_unified_execution_task_v1.schema.json"
    errors = validate_schema_contract(load_schema(schema_path))
    print(json.dumps({"status": "PASS" if not errors else "FAIL", "errors": errors}, sort_keys=True))
    raise SystemExit(0 if not errors else 1)
