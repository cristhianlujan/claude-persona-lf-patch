#!/usr/bin/env python3
"""Typed projection for OPERATION_TEST_COVERAGE.

Consumes one row from the legacy read-only coverage provider and separates
structural coverage from execution observation and material verdicts. It never
creates a PASS verdict.
"""
from __future__ import annotations

from typing import Any, Mapping

INPUT_FIELDS = frozenset({
    "operation_code",
    "lifecycle_state_code",
    "assurance_obligation",
    "required_binding_count",
    "executable_suite_count",
    "active_case_count",
    "observed_run_count",
    "coverage_state",
    "coverage_reason",
})
LEGACY_STATES = frozenset({"DISCOVERED", "EVIDENCE_UNMAPPED", "NOT_COVERED", "BLOCK", "COVERED"})
STRUCTURAL_STATE_MAP = {
    "DISCOVERED": "DISCOVERED",
    "EVIDENCE_UNMAPPED": "EVIDENCE_UNMAPPED",
    "NOT_COVERED": "NOT_COVERED",
    "BLOCK": "STRUCTURAL_BLOCKED",
    "COVERED": "STRUCTURALLY_COVERED",
}


class CoverageProjectionError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CoverageProjectionError(code)
    return value.strip()


def _count(value: Any, code: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise CoverageProjectionError(code)
    return value


def project_operation_test_coverage(row: Mapping[str, Any]) -> dict[str, Any]:
    try:
        if not isinstance(row, Mapping):
            raise CoverageProjectionError("BLOCKED_COVERAGE_ROW_SHAPE")
        if set(row) != INPUT_FIELDS:
            raise CoverageProjectionError(
                "BLOCKED_COVERAGE_ROW_FIELDS",
                ",".join(sorted(set(row) ^ INPUT_FIELDS)),
            )

        operation_code = _text(row["operation_code"], "BLOCKED_OPERATION_CODE")
        lifecycle_state = _text(row["lifecycle_state_code"], "BLOCKED_LIFECYCLE_STATE")
        obligation = _text(row["assurance_obligation"], "BLOCKED_ASSURANCE_OBLIGATION")
        coverage_state = _text(row["coverage_state"], "BLOCKED_LEGACY_COVERAGE_STATE")
        coverage_reason = _text(row["coverage_reason"], "BLOCKED_COVERAGE_REASON")
        if coverage_state not in LEGACY_STATES:
            raise CoverageProjectionError("BLOCKED_UNKNOWN_LEGACY_COVERAGE_STATE", coverage_state)

        required_binding_count = _count(row["required_binding_count"], "BLOCKED_REQUIRED_BINDING_COUNT")
        executable_suite_count = _count(row["executable_suite_count"], "BLOCKED_EXECUTABLE_SUITE_COUNT")
        active_case_count = _count(row["active_case_count"], "BLOCKED_ACTIVE_CASE_COUNT")
        observed_run_count = _count(row["observed_run_count"], "BLOCKED_OBSERVED_RUN_COUNT")

        # Preserve structural semantics but never infer execution result or PASS.
        return {
            "schema_version": "lf-operation-test-coverage-projection/v1",
            "projection_status": "PROJECTED",
            "operation_code": operation_code,
            "lifecycle_state_code": lifecycle_state,
            "coverage_obligation": obligation,
            "structural_coverage_state": STRUCTURAL_STATE_MAP[coverage_state],
            "execution_observation_state": (
                "EXECUTION_OBSERVED" if observed_run_count > 0 else "NO_EXECUTION_OBSERVED"
            ),
            "quality_verdict_state": "NOT_EVALUATED",
            "assurance_verdict_state": "NOT_EVALUATED",
            "qualification_verdict_state": "NOT_EVALUATED",
            "material_pass_claimed": False,
            "source": {
                "provider": "public.lf_s36_operation_assurance_coverage_v1",
                "legacy_coverage_state": coverage_state,
                "legacy_coverage_reason": coverage_reason,
            },
            "counts": {
                "required_binding_count": required_binding_count,
                "executable_suite_count": executable_suite_count,
                "active_case_count": active_case_count,
                "observed_run_count": observed_run_count,
            },
        }
    except CoverageProjectionError as exc:
        return {
            "schema_version": "lf-operation-test-coverage-projection/v1",
            "projection_status": "BLOCKED",
            "reason_code": exc.code,
            "detail": exc.detail,
            "material_pass_claimed": False,
            "quality_verdict_state": "NOT_EVALUATED",
            "assurance_verdict_state": "NOT_EVALUATED",
            "qualification_verdict_state": "NOT_EVALUATED",
        }
