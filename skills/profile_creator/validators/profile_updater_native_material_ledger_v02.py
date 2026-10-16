"""Read an independently VERIFIED same-chat content-review receipt from LF ledger.

Uses only the existing EVIDENCE_LEDGER/INDEPENDENT_ASSURANCE authority and
provider-bound resolver registry. No insert, promotion or profile mutation.
The host's read_one(sql, parameters) is an authenticated read-only DB client,
never an LLM function, a fixture, or user-supplied SQL result.
"""
from __future__ import annotations

import re
import uuid
from typing import Any, Callable

_REVIEW_TYPE = "PROFILE_NATIVE_CHAT_MATERIAL_REVIEW"
_REVIEW_KIND = "INDEPENDENT_REVIEW_RECEIPT"
_REVIEW_CAPABILITY = "INDEPENDENT_ASSURANCE"
_SHA64 = re.compile(r"^[0-9a-f]{64}$")
_SQL = """
SELECT l.receipt_id::text AS receipt_id,
       l.execution_id AS reviewer_execution_id,
       l.capability_code,
       l.receipt_kind,
       l.subject_type,
       l.subject_ref,
       l.subject_sha256,
       l.verification_state,
       l.receipt_payload,
       l.verification_payload,
       l.verified_at,
       l.provider,
       l.verification_method,
       r.active AS resolver_active,
       r.trust_level,
       r.provider AS resolver_provider,
       r.verification_method AS resolver_method
FROM private.lf_evidence_ledger_v1 l
JOIN private.lf_evidence_resolver_registry_v1 r
  ON r.resolver_id=l.resolver_id
WHERE l.receipt_id = %s::uuid
LIMIT 1
"""


def make_native_review_ledger_reader(
    read_one: Callable[[str, tuple[str]], dict[str, Any] | None],
    *, plan_code: str = "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1",
    checkpoint_code: str = "PE10_C5",
) -> Callable[[str], dict[str, Any] | None]:
    """Resolve a REVIEWED raw capture without assigning runtime permission.

    Reviewer receipt subject is bound to (plan/checkpoint, run_id, profile)
    via its immutable receipt_payload. A positive review here is NOT the
    independent full behavioral PE10_C3 cutover PASS.
    """
    if not callable(read_one):
        raise ValueError("TRUSTED_LEDGER_READ_ONE_MISSING")
    if not plan_code or not checkpoint_code:
        raise ValueError("REVIEW_SCOPE_MISSING")

    def resolve(receipt_id: str) -> dict[str, Any] | None:
        try:
            canonical_id = str(uuid.UUID(receipt_id))
        except (ValueError, TypeError, AttributeError):
            return None
        row = read_one(_SQL, (canonical_id,))
        if not isinstance(row, dict):
            return None
        payload = row.get("receipt_payload")
        if not isinstance(payload, dict):
            return None
        if not (
            row.get("receipt_id") == canonical_id
            and row.get("capability_code") == _REVIEW_CAPABILITY
            and row.get("receipt_kind") == _REVIEW_KIND
            and row.get("subject_type") == _REVIEW_TYPE
            and row.get("subject_ref") == f"{plan_code}/{checkpoint_code}"
            and row.get("verification_state") == "VERIFIED"
            and row.get("verified_at") is not None
            and row.get("resolver_active") is True
            and row.get("trust_level") == "TRUSTED_PROVIDER_BOUND"
            and row.get("provider") == row.get("resolver_provider")
            and row.get("verification_method") == row.get("resolver_method")
            and payload.get("semantic_verdict") == "PASS"
            and payload.get("plan_code") == plan_code
            and payload.get("checkpoint_code") == checkpoint_code
            and payload.get("review_scope") == "NATIVE_MATERIAL_CONTENT_ONLY"
            and payload.get("positive_controls_passed") is True
            and payload.get("negative_controls_passed") is True
            and payload.get("method_qualification_claimed") is False
            and payload.get("cutover_eligible") is False
            and isinstance(row.get("subject_sha256"), str)
            and _SHA64.fullmatch(row["subject_sha256"])
            and isinstance(payload.get("handoff_sha256"), str)
            and _SHA64.fullmatch(payload["handoff_sha256"])
            and isinstance(payload.get("profile_slug"), str)
            and bool(payload["profile_slug"])
            and isinstance(payload.get("run_id"), str)
            and bool(payload["run_id"])
            and isinstance(row.get("reviewer_execution_id"), str)
            and bool(row["reviewer_execution_id"])
            and row["reviewer_execution_id"] != payload["run_id"]
        ):
            return None
        return {
            "receipt_id": canonical_id,
            "verification_state": "VERIFIED",
            "verdict": "PASS",
            "subject_raw_sha256": row["subject_sha256"],
            "handoff_sha256": payload["handoff_sha256"],
            "profile_slug": payload["profile_slug"],
            "reviewer_execution_id": row["reviewer_execution_id"],
            "positive_controls_passed": True,
            "negative_controls_passed": True,
        }
    return resolve
