#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

SCHEMA_VALUE = "LF_UNIFIED_EXECUTION_RESULT_V1"
OUTCOMES = ("SUCCEEDED", "BLOCKED", "FAILED", "RETRYABLE_FAILURE")
REQUIRED_FIELDS = (
    "schema",
    "execution_id",
    "task_id",
    "step_id",
    "attempt_no",
    "lease_owner",
    "lease_fence",
    "outcome",
    "result_digest",
    "evidence_refs",
)
TASK_IDENTITY_FIELDS = ("execution_id", "task_id", "step_id", "attempt_no")
LEASE_IDENTITY_FIELDS = ("lease_owner", "lease_fence")
FORBIDDEN_STATE_KEYS = {"canonical_state", "execution_state", "execution_status"}


def _nonempty_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_result_envelope(
    envelope: Any,
    expected_task_identity: Mapping[str, Any] | None = None,
    expected_current_lease: Mapping[str, Any] | None = None,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(envelope, dict):
        return ["RESULT_ENVELOPE_NOT_OBJECT"]

    for field in REQUIRED_FIELDS:
        if field not in envelope:
            errors.append(f"RESULT_ENVELOPE_MISSING_{field.upper()}")

    if envelope.get("schema") != SCHEMA_VALUE:
        errors.append("RESULT_ENVELOPE_SCHEMA_MISMATCH")

    for field in ("execution_id", "task_id", "step_id", "lease_owner", "result_digest"):
        if field in envelope and not _nonempty_text(envelope[field]):
            errors.append(f"RESULT_ENVELOPE_INVALID_{field.upper()}")

    if "attempt_no" in envelope:
        attempt_no = envelope["attempt_no"]
        if type(attempt_no) is not int or attempt_no < 1:
            errors.append("RESULT_ENVELOPE_INVALID_ATTEMPT_NO")

    if "lease_fence" in envelope:
        lease_fence = envelope["lease_fence"]
        if type(lease_fence) is not int or lease_fence < 0:
            errors.append("RESULT_ENVELOPE_INVALID_LEASE_FENCE")

    if "outcome" in envelope and envelope["outcome"] not in OUTCOMES:
        errors.append("RESULT_ENVELOPE_INVALID_OUTCOME")

    if "evidence_refs" in envelope and not isinstance(envelope["evidence_refs"], list):
        errors.append("RESULT_ENVELOPE_INVALID_EVIDENCE_REFS_TYPE")

    for key in envelope:
        if (
            key.startswith("next_")
            or key.startswith("selected_next_")
            or key.startswith("advance_")
            or key in FORBIDDEN_STATE_KEYS
        ):
            errors.append(f"RESULT_ENVELOPE_FORBIDDEN_STATE_FIELD:{key}")

    if expected_task_identity is not None:
        missing_expected = [field for field in TASK_IDENTITY_FIELDS if field not in expected_task_identity]
        if missing_expected:
            errors.append("EXPECTED_TASK_IDENTITY_INCOMPLETE:" + ",".join(missing_expected))
        else:
            for field in TASK_IDENTITY_FIELDS:
                if envelope.get(field) != expected_task_identity[field]:
                    errors.append(f"RESULT_ENVELOPE_TASK_IDENTITY_MISMATCH:{field}")

    if expected_current_lease is not None:
        missing_expected = [field for field in LEASE_IDENTITY_FIELDS if field not in expected_current_lease]
        if missing_expected:
            errors.append("EXPECTED_CURRENT_LEASE_INCOMPLETE:" + ",".join(missing_expected))
        else:
            for field in LEASE_IDENTITY_FIELDS:
                if envelope.get(field) != expected_current_lease[field]:
                    errors.append(f"RESULT_ENVELOPE_CURRENT_LEASE_MISMATCH:{field}")

    return sorted(set(errors))


def validate_schema_contract(schema_doc: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(schema_doc, dict):
        return ["RESULT_SCHEMA_NOT_OBJECT"]
    if schema_doc.get("required") != list(REQUIRED_FIELDS):
        errors.append("RESULT_SCHEMA_REQUIRED_FIELDS_DRIFT")
    properties = schema_doc.get("properties")
    if not isinstance(properties, dict):
        errors.append("RESULT_SCHEMA_PROPERTIES_MISSING")
        return errors
    if properties.get("schema", {}).get("const") != SCHEMA_VALUE:
        errors.append("RESULT_SCHEMA_VALUE_DRIFT")
    if properties.get("attempt_no", {}).get("minimum") != 1:
        errors.append("RESULT_SCHEMA_ATTEMPT_MIN_DRIFT")
    if properties.get("lease_fence", {}).get("minimum") != 0:
        errors.append("RESULT_SCHEMA_LEASE_FENCE_MIN_DRIFT")
    if properties.get("outcome", {}).get("enum") != list(OUTCOMES):
        errors.append("RESULT_SCHEMA_OUTCOME_ENUM_DRIFT")
    authority = schema_doc.get("x-lf-authority")
    if not isinstance(authority, dict):
        errors.append("RESULT_SCHEMA_AUTHORITY_MISSING")
    else:
        if authority.get("current_lease_authority") != "public.lf_operation_execution":
            errors.append("RESULT_SCHEMA_LEASE_AUTHORITY_DRIFT")
        if authority.get("live_lease_fence_type") != "bigint":
            errors.append("RESULT_SCHEMA_LEASE_FENCE_TYPE_DRIFT")
        if authority.get("executor_can_advance_execution_state") is not False:
            errors.append("RESULT_SCHEMA_EXECUTOR_STATE_OWNER_DRIFT")
        if authority.get("submission_persistence_owner") != "future_G06_submit_result":
            errors.append("RESULT_SCHEMA_SUBMISSION_OWNER_DRIFT")
    return sorted(set(errors))


def load_schema(path: str | Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    schema_path = root / "gobernanza/contratos/lf_unified_execution_result_v1.schema.json"
    errors = validate_schema_contract(load_schema(schema_path))
    print(json.dumps({"status": "PASS" if not errors else "FAIL", "errors": errors}, sort_keys=True))
    raise SystemExit(0 if not errors else 1)
