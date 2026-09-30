#!/usr/bin/env python3
"""Fail-closed review-reference guard for a future Assurance evaluator.

This guard never records judge rows and never executes a review. It only accepts
persisted review evidence. New evaluation references may use the current
canonical review types; S36_ASSURANCE is accepted only as an explicitly tagged
historical readback of an already persisted judge row.
"""
from __future__ import annotations

from typing import Any, Mapping

INPUT_SCHEMA = "lf-assurance-evaluator-review-reference/v1"
JUDGE_SOURCE = "public.lf_test_judge_results"
NEW_REVIEW_TYPES = frozenset({"INDEPENDENT_REVIEW", "INDEPENDENT_HOLDOUT"})
LEGACY_REVIEW_TYPE = "S36_ASSURANCE"
MODES = frozenset({"NEW_REVIEW_REFERENCE", "HISTORICAL_LEGACY_READBACK"})


class LegacyReviewGuardError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise LegacyReviewGuardError(code)
    return value.strip()


def validate_review_reference(packet: Mapping[str, Any]) -> dict[str, Any]:
    try:
        if not isinstance(packet, Mapping):
            raise LegacyReviewGuardError("BLOCKED_REVIEW_REFERENCE_SHAPE")

        expected = {
            "schema_version",
            "mode",
            "review_type",
            "judge_source",
            "judge_result_id",
            "judge_write_requested",
        }
        if set(packet) != expected:
            raise LegacyReviewGuardError(
                "BLOCKED_REVIEW_REFERENCE_FIELDS",
                ",".join(sorted(set(packet) ^ expected)),
            )

        if packet["schema_version"] != INPUT_SCHEMA:
            raise LegacyReviewGuardError("BLOCKED_REVIEW_REFERENCE_SCHEMA")

        mode = _text(packet["mode"], "BLOCKED_REVIEW_REFERENCE_MODE")
        if mode not in MODES:
            raise LegacyReviewGuardError("BLOCKED_REVIEW_REFERENCE_MODE", mode)

        review_type = _text(packet["review_type"], "BLOCKED_REVIEW_TYPE")
        judge_source = _text(packet["judge_source"], "BLOCKED_JUDGE_SOURCE")
        judge_result_id = _text(packet["judge_result_id"], "BLOCKED_JUDGE_RESULT_ID")

        if judge_source != JUDGE_SOURCE:
            raise LegacyReviewGuardError("BLOCKED_NON_CANONICAL_JUDGE_SOURCE", judge_source)
        if packet["judge_write_requested"] is not False:
            raise LegacyReviewGuardError("BLOCKED_EVALUATOR_JUDGE_WRITE_ATTEMPT")

        if mode == "NEW_REVIEW_REFERENCE":
            if review_type == LEGACY_REVIEW_TYPE:
                raise LegacyReviewGuardError("BLOCKED_LEGACY_S36_NEW_WRITE_SEMANTICS")
            if review_type not in NEW_REVIEW_TYPES:
                raise LegacyReviewGuardError("BLOCKED_NEW_REVIEW_TYPE", review_type)
            return {
                "schema_version": "lf-assurance-evaluator-review-decision/v1",
                "status": "ACCEPTED_NEW_REVIEW_REFERENCE",
                "review_type": review_type,
                "judge_source": judge_source,
                "judge_result_id": judge_result_id,
                "legacy_readback_only": False,
                "judge_write_allowed": False,
            }

        if review_type != LEGACY_REVIEW_TYPE:
            raise LegacyReviewGuardError(
                "BLOCKED_HISTORICAL_READBACK_TYPE",
                review_type,
            )
        return {
            "schema_version": "lf-assurance-evaluator-review-decision/v1",
            "status": "ACCEPTED_HISTORICAL_LEGACY_READBACK",
            "review_type": review_type,
            "judge_source": judge_source,
            "judge_result_id": judge_result_id,
            "legacy_readback_only": True,
            "judge_write_allowed": False,
        }
    except LegacyReviewGuardError as exc:
        return {
            "schema_version": "lf-assurance-evaluator-review-decision/v1",
            "status": "BLOCKED",
            "reason_code": exc.code,
            "detail": exc.detail,
            "judge_write_allowed": False,
        }
