#!/usr/bin/env python3
"""Mechanical validator for ZERO_COST independent-review evidence.

The review is transported outside the candidate Git tree (normally a PR comment).
This module validates shape, exact material binding, and session separation. It does
not call a model, GitHub, Supabase, or execute candidate code.
"""
from __future__ import annotations

import re
from typing import Any, Mapping

SCHEMA = "lf-pase-control-independent-review/v1"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
REVIEW_QS = ("Q05", "Q06", "Q09", "Q10")
STATUSES = {"PASS", "FAIL", "BLOCKED", "NA"}
VERDICTS = {"REVIEW_PASS", "REVIEW_FAIL", "REVIEW_BLOCK"}


class ReviewError(ValueError):
    pass


def _need_text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReviewError(code)
    return value.strip()


def validate_review(
    review: Mapping[str, Any],
    *,
    repository: str,
    pr_number: int,
    candidate_id: str,
    candidate_material_sha256: str,
    builder_session_id: str,
    builder_session_ref: str,
    qualification_type: str,
) -> dict[str, Any]:
    if not isinstance(review, Mapping) or review.get("schema_version") != SCHEMA:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_SCHEMA")
    if review.get("repository") != repository or review.get("pr_number") != pr_number:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_PR_IDENTITY")
    if review.get("candidate_id") != candidate_id:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_CANDIDATE_IDENTITY")
    if not HEX64.fullmatch(str(review.get("candidate_material_sha256", ""))):
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_MATERIAL_HASH")
    if review["candidate_material_sha256"] != candidate_material_sha256:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_STALE")

    observed_builder_id = _need_text(review.get("builder_session_id"), "BLOCK_QUALIFICATION_REVIEW_BUILDER_ID")
    observed_builder_ref = _need_text(review.get("builder_session_ref"), "BLOCK_QUALIFICATION_REVIEW_BUILDER_REF")
    if observed_builder_id != builder_session_id or observed_builder_ref != builder_session_ref:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_BUILDER_DRIFT")

    reviewer_id = _need_text(review.get("reviewer_session_id"), "BLOCK_QUALIFICATION_REVIEW_REVIEWER_ID")
    reviewer_ref = _need_text(review.get("reviewer_session_ref"), "BLOCK_QUALIFICATION_REVIEW_REVIEWER_REF")
    if reviewer_id == builder_session_id or reviewer_ref == builder_session_ref:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_NOT_INDEPENDENT")
    if review.get("blind_review") is not True:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_NOT_BLIND")

    rows = review.get("checks")
    if not isinstance(rows, list) or [row.get("id") for row in rows if isinstance(row, Mapping)] != list(REVIEW_QS):
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_CHECK_SET")

    normalized: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, Mapping) or set(row) != {"id", "status", "evidence", "rationale"}:
            raise ReviewError("BLOCK_QUALIFICATION_REVIEW_CHECK_SHAPE")
        qid = row["id"]
        status = row["status"]
        if status not in STATUSES:
            raise ReviewError(f"BLOCK_QUALIFICATION_REVIEW_STATUS:{qid}")
        evidence = row.get("evidence")
        if not isinstance(evidence, list) or any(not isinstance(x, str) or not x.strip() for x in evidence):
            raise ReviewError(f"BLOCK_QUALIFICATION_REVIEW_EVIDENCE:{qid}")
        rationale = _need_text(row.get("rationale"), f"BLOCK_QUALIFICATION_REVIEW_RATIONALE:{qid}")
        if status in {"PASS", "FAIL", "BLOCKED"} and not evidence:
            raise ReviewError(f"BLOCK_QUALIFICATION_REVIEW_EVIDENCE_MISSING:{qid}")
        if qid != "Q09" and status == "NA":
            raise ReviewError(f"BLOCK_QUALIFICATION_REVIEW_NA_FORBIDDEN:{qid}")
        if qid == "Q09":
            if qualification_type == "CONTROL_REPLACEMENT" and status != "PASS":
                raise ReviewError("BLOCK_QUALIFICATION_REVIEW_Q09_REPLAY_REQUIRED")
            if qualification_type != "CONTROL_REPLACEMENT" and status not in {"PASS", "NA"}:
                # FAIL/BLOCKED remain meaningful and must not be silently ignored.
                pass
        normalized[qid] = {
            "id": qid,
            "status": status,
            "evidence": list(evidence),
            "rationale": rationale,
        }

    verdict = review.get("verdict")
    if verdict not in VERDICTS:
        raise ReviewError("BLOCK_QUALIFICATION_REVIEW_VERDICT")
    statuses = {row["status"] for row in normalized.values()}
    expected = "REVIEW_FAIL" if "FAIL" in statuses else ("REVIEW_BLOCK" if "BLOCKED" in statuses else "REVIEW_PASS")
    if verdict != expected:
        raise ReviewError(f"BLOCK_QUALIFICATION_REVIEW_VERDICT_DRIFT:expected={expected}:observed={verdict}")

    return {
        "reviewer_session_id": reviewer_id,
        "reviewer_session_ref": reviewer_ref,
        "builder_session_id": builder_session_id,
        "builder_session_ref": builder_session_ref,
        "candidate_material_sha256": candidate_material_sha256,
        "checks": normalized,
        "verdict": verdict,
    }
