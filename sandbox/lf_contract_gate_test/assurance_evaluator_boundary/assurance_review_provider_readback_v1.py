#!/usr/bin/env python3
"""Validate LF_SUPABASE_READBACK_V1 snapshots for Assurance review evidence.

This is not a Supabase client and does not query the database. The canonical
owner-runner must obtain the packet through the existing trusted resolver. This
module cross-binds that provider result to the exact judge, review type and
subject revision before the semantic core may treat Independent Review as
provenance-bearing evidence.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping

INPUT_SCHEMA = "lf-assurance-review-provider-readback/v1"
OUTPUT_SCHEMA = "lf-assurance-review-provider-decision/v1"
RESOLVER_ID = "LF_SUPABASE_READBACK_V1"
PROVIDER = "SUPABASE"
VERIFICATION_METHOD = "SUPABASE_SQL_READBACK_PLUS_DB_DIGEST"
SOURCE_PREFIX = "supabase://public/lf_test_judge_results/"
NEW_REVIEW_TYPES = frozenset({"INDEPENDENT_REVIEW", "INDEPENDENT_HOLDOUT"})
LEGACY_REVIEW_TYPE = "S36_ASSURANCE"
MODES = frozenset({"NEW_REVIEW_REFERENCE", "HISTORICAL_LEGACY_READBACK"})
VERDICTS = frozenset({"PASS", "FAIL"})


class ProviderReadbackError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ProviderReadbackError(code)
    return value.strip()


def _mapping(value: Any, code: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ProviderReadbackError(code)
    return value


def _canonical_sha256(value: Mapping[str, Any]) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def validate_provider_readback(
    packet: Mapping[str, Any],
    *,
    expected_judge_result_id: str,
    expected_review_type: str,
    expected_subject_revision: str,
    mode: str,
) -> dict[str, Any]:
    try:
        if not isinstance(packet, Mapping):
            raise ProviderReadbackError("BLOCKED_PROVIDER_READBACK_SHAPE")
        expected_fields = {
            "schema_version",
            "resolver_id",
            "provider",
            "verification_method",
            "verification_state",
            "source_ref",
            "row_digest_sha256",
            "row",
        }
        if set(packet) != expected_fields:
            raise ProviderReadbackError(
                "BLOCKED_PROVIDER_READBACK_FIELDS",
                ",".join(sorted(set(packet) ^ expected_fields)),
            )
        if packet["schema_version"] != INPUT_SCHEMA:
            raise ProviderReadbackError("BLOCKED_PROVIDER_READBACK_SCHEMA")
        if packet["resolver_id"] != RESOLVER_ID:
            raise ProviderReadbackError("BLOCKED_PROVIDER_RESOLVER_ID")
        if packet["provider"] != PROVIDER:
            raise ProviderReadbackError("BLOCKED_PROVIDER_IDENTITY")
        if packet["verification_method"] != VERIFICATION_METHOD:
            raise ProviderReadbackError("BLOCKED_PROVIDER_VERIFICATION_METHOD")
        if packet["verification_state"] != "VERIFIED":
            raise ProviderReadbackError("BLOCKED_PROVIDER_VERIFICATION_STATE")

        expected_judge_result_id = _text(
            expected_judge_result_id, "BLOCKED_EXPECTED_JUDGE_RESULT_ID"
        )
        expected_review_type = _text(
            expected_review_type, "BLOCKED_EXPECTED_REVIEW_TYPE"
        )
        expected_subject_revision = _text(
            expected_subject_revision, "BLOCKED_EXPECTED_SUBJECT_REVISION"
        )
        mode = _text(mode, "BLOCKED_PROVIDER_READBACK_MODE")
        if mode not in MODES:
            raise ProviderReadbackError("BLOCKED_PROVIDER_READBACK_MODE", mode)

        source_ref = _text(packet["source_ref"], "BLOCKED_PROVIDER_SOURCE_REF")
        if source_ref != SOURCE_PREFIX + expected_judge_result_id:
            raise ProviderReadbackError("BLOCKED_PROVIDER_SOURCE_CROSSBIND")

        row = _mapping(packet["row"], "BLOCKED_PROVIDER_ROW_SHAPE")
        required_row_fields = {
            "judge_result_id",
            "test_run_id",
            "judge_code",
            "judge_type",
            "verdict",
            "evidence_payload",
            "metadata",
            "created_by_execution_id",
        }
        missing = sorted(required_row_fields - set(row))
        if missing:
            raise ProviderReadbackError("BLOCKED_PROVIDER_ROW_FIELDS", ",".join(missing))

        judge_id = _text(row["judge_result_id"], "BLOCKED_PROVIDER_JUDGE_ID")
        if judge_id != expected_judge_result_id:
            raise ProviderReadbackError("BLOCKED_PROVIDER_JUDGE_CROSSBIND")
        judge_type = _text(row["judge_type"], "BLOCKED_PROVIDER_JUDGE_TYPE")
        if judge_type != expected_review_type:
            raise ProviderReadbackError("BLOCKED_PROVIDER_REVIEW_TYPE_CROSSBIND")

        if mode == "NEW_REVIEW_REFERENCE":
            if judge_type not in NEW_REVIEW_TYPES:
                raise ProviderReadbackError("BLOCKED_PROVIDER_NEW_REVIEW_TYPE", judge_type)
        elif judge_type != LEGACY_REVIEW_TYPE:
            raise ProviderReadbackError("BLOCKED_PROVIDER_HISTORICAL_REVIEW_TYPE", judge_type)

        verdict = _text(row["verdict"], "BLOCKED_PROVIDER_JUDGE_VERDICT")
        if verdict not in VERDICTS:
            raise ProviderReadbackError("BLOCKED_PROVIDER_JUDGE_VERDICT", verdict)

        evidence_payload = _mapping(
            row["evidence_payload"], "BLOCKED_PROVIDER_EVIDENCE_PAYLOAD"
        )
        metadata = _mapping(row["metadata"], "BLOCKED_PROVIDER_METADATA")
        revision = (
            evidence_payload.get("revision_sha256")
            or evidence_payload.get("subject_revision_sha256")
        )
        revision = _text(revision, "BLOCKED_PROVIDER_SUBJECT_REVISION_MISSING")
        if revision != expected_subject_revision:
            raise ProviderReadbackError("BLOCKED_PROVIDER_SUBJECT_REVISION_MISMATCH")

        reviewer_execution_id = metadata.get("reviewer_execution_id") or evidence_payload.get(
            "reviewer_execution_id"
        )
        producer_execution_id = metadata.get(
            "test_producer_execution_id"
        ) or evidence_payload.get("producer_execution_id")
        reviewer_execution_id = _text(
            reviewer_execution_id, "BLOCKED_PROVIDER_REVIEWER_EXECUTION_ID"
        )
        producer_execution_id = _text(
            producer_execution_id, "BLOCKED_PROVIDER_PRODUCER_EXECUTION_ID"
        )
        if reviewer_execution_id == producer_execution_id:
            raise ProviderReadbackError("BLOCKED_PROVIDER_SELF_ASSESSMENT")

        digest = _text(packet["row_digest_sha256"], "BLOCKED_PROVIDER_ROW_DIGEST")
        if len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
            raise ProviderReadbackError("BLOCKED_PROVIDER_ROW_DIGEST_FORMAT")
        observed_digest = _canonical_sha256(row)
        if digest != observed_digest:
            raise ProviderReadbackError("BLOCKED_PROVIDER_ROW_DIGEST_MISMATCH")

        return {
            "schema_version": OUTPUT_SCHEMA,
            "status": "VERIFIED",
            "provider_bound_readback_verified": True,
            "resolver_id": RESOLVER_ID,
            "provider": PROVIDER,
            "verification_method": VERIFICATION_METHOD,
            "judge_result_id": judge_id,
            "review_type": judge_type,
            "judge_verdict": verdict,
            "subject_revision": revision,
            "reviewer_execution_id": reviewer_execution_id,
            "producer_execution_id": producer_execution_id,
            "row_digest_sha256": observed_digest,
            "source_ref": source_ref,
        }
    except ProviderReadbackError as exc:
        return {
            "schema_version": OUTPUT_SCHEMA,
            "status": "BLOCKED",
            "provider_bound_readback_verified": False,
            "reason_code": exc.code,
            "detail": exc.detail,
        }
