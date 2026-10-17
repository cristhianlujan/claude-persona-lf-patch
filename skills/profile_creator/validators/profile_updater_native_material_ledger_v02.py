"""Read the canonical generic INDEPENDENT_ASSURANCE six-step review, fail closed.

The verified reviewer receipt is bound to a verified raw SOURCE_SNAPSHOT.
No alternate receipt writer, self-review, runtime permission or version activation.
The caller supplies an authenticated read-only Supabase `read_one` function.
"""
from __future__ import annotations

import re
import uuid
from typing import Any, Callable

_SHA64 = re.compile(r"^[0-9a-f]{64}$")
_SHA40 = re.compile(r"^[0-9a-f]{40}$")
_PLAN = "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1"
_SUBJECT = "PROFILE_NATIVE_CHAT_MATERIAL_REVIEW"

_SQL = """
SELECT l.receipt_id::text receipt_id, l.execution_id reviewer_execution_id,
 l.capability_code, l.receipt_kind, l.subject_type, l.subject_ref,
 l.subject_sha256, l.source_head_sha, l.verification_state,
 l.receipt_payload, l.verification_payload, l.verified_at,
 l.provider, l.verification_method, r.active resolver_active,
 r.trust_level, r.provider resolver_provider, r.verification_method resolver_method,
 op.operation_code, op.status reviewer_operation_status, op.manifest reviewer_manifest,
 source.receipt_id::text source_receipt_id, source.execution_id producer_execution_id,
 source.receipt_kind source_receipt_kind, source.capability_code source_capability_code,
 source.subject_type source_subject_type, source.subject_ref source_subject_ref,
 source.subject_sha256 source_subject_sha256, source.source_head_sha source_head,
 source.receipt_payload source_payload, source.verification_payload source_verification,
 source.verification_state source_verification_state, source.provider source_provider,
 source.verification_method source_verification_method,
 sr.active source_resolver_active, sr.trust_level source_trust_level,
 sr.provider source_resolver_provider, sr.verification_method source_resolver_method,
 (SELECT count(DISTINCT st.step_id) FROM public.lf_operation_execution_steps st
  WHERE st.execution_id=l.execution_id AND st.status='STEP_PASS_WITH_EVIDENCE'
  AND st.step_id IN('route_bind','target_currentness','semantic_review',
                    'judge_record','reviewer_readback','report_output')) clean_review_steps,
 (SELECT es.evidence_payload FROM public.lf_operation_execution_steps es
  WHERE es.execution_id=l.execution_id AND es.step_id='semantic_review'
  AND es.status='STEP_PASS_WITH_EVIDENCE' LIMIT 1) semantic_payload
FROM private.lf_evidence_ledger_v1 l
JOIN private.lf_evidence_resolver_registry_v1 r ON r.resolver_id=l.resolver_id
JOIN public.lf_operation_execution op ON op.execution_id=l.execution_id
JOIN private.lf_evidence_ledger_v1 source
 ON source.receipt_id::text=op.manifest->>'subject_receipt_id'
JOIN private.lf_evidence_resolver_registry_v1 sr ON sr.resolver_id=source.resolver_id
WHERE l.receipt_id=%s::uuid
LIMIT 1
"""


def make_native_review_ledger_reader(
    read_one: Callable[[str, tuple[str]], dict[str, Any] | None],
    *, plan_code: str = _PLAN, checkpoint_code: str = "PE10_C5",
) -> Callable[[str], dict[str, Any] | None]:
    """Normalize an actual v3 independent terminal receipt, never author one."""
    if not callable(read_one):
        raise ValueError("TRUSTED_LEDGER_READ_ONE_MISSING")
    if plan_code != _PLAN or checkpoint_code != "PE10_C5":
        raise ValueError("NATIVE_ASSURANCE_SUBJECT_SCOPE_INVALID")

    def resolve(receipt_id: str) -> dict[str, Any] | None:
        try:
            canonical_id = str(uuid.UUID(receipt_id))
        except (ValueError, TypeError, AttributeError):
            return None
        row = read_one(_SQL, (canonical_id,))
        if not isinstance(row, dict):
            return None
        review = row.get("receipt_payload")
        verify = row.get("verification_payload")
        raw = row.get("source_payload")
        sv = row.get("source_verification")
        manifest = row.get("reviewer_manifest")
        semantic = row.get("semantic_payload")
        if not all(isinstance(v, dict) for v in (review, verify, raw, sv, manifest, semantic)):
            return None
        sha = row.get("subject_sha256")
        source_head = row.get("source_head_sha")
        if not (
            row.get("receipt_id") == canonical_id
            and row.get("capability_code") == "INDEPENDENT_ASSURANCE"
            and row.get("receipt_kind") == "INDEPENDENT_REVIEW_RECEIPT"
            and row.get("subject_type") == _SUBJECT
            and row.get("subject_ref") == f"{plan_code}/{checkpoint_code}"
            and isinstance(sha, str) and _SHA64.fullmatch(sha)
            and isinstance(source_head, str) and _SHA40.fullmatch(source_head)
            and row.get("verification_state") == "VERIFIED"
            and row.get("verified_at") is not None
            and row.get("resolver_active") is True
            and row.get("trust_level") == "TRUSTED_PROVIDER_BOUND"
            and row.get("provider") == row.get("resolver_provider")
            and row.get("verification_method") == row.get("resolver_method")
            and row.get("source_resolver_active") is True
            and row.get("source_trust_level") == "TRUSTED_PROVIDER_BOUND"
            and row.get("source_provider") == row.get("source_resolver_provider")
            and row.get("source_verification_method") == row.get("source_resolver_method")
            and row.get("source_capability_code") == "EVIDENCE_LEDGER"
            and row.get("source_receipt_kind") == "SOURCE_SNAPSHOT"
            and row.get("source_verification_state") == "VERIFIED"
            and row.get("source_subject_type") == row.get("subject_type")
            and row.get("source_subject_ref") == row.get("subject_ref")
            and row.get("source_subject_sha256") == sha
            and row.get("source_head") == source_head
            and sv.get("provider_readback_verified") is True
            and sv.get("digest_recomputed") is True
            and review.get("verdict") == "PASS"
            and isinstance(review.get("evidence_refs"), list)
            and bool(review["evidence_refs"])
            and verify.get("reviewer_execution_id") == row.get("reviewer_execution_id")
            and verify.get("producer_execution_id") == row.get("producer_execution_id")
            and isinstance(row.get("reviewer_execution_id"), str)
            and row["reviewer_execution_id"] != row.get("producer_execution_id")
            and row.get("operation_code") == "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"
            and row.get("reviewer_operation_status") == "COMPLETED"
            and manifest.get("review_scope") == "NATIVE_MATERIAL_CONTENT_ONLY"
            and manifest.get("subject_sha256") == sha
            and manifest.get("producer_execution_id") == row.get("producer_execution_id")
            and manifest.get("subject_receipt_id") == row.get("source_receipt_id")
            and row.get("clean_review_steps") == 6
            and semantic.get("verdict") == "PASS"
            and semantic.get("review_context") == "INDEPENDENT_OPERATION_CONTEXT"
            and isinstance(semantic.get("independence_measure"), dict)
            and semantic["independence_measure"].get("state") == "INDEPENDENT"
            and semantic.get("positive_controls_passed") is True
            and semantic.get("negative_controls_passed") is True
            and isinstance(raw.get("handoff_sha256"), str)
            and _SHA64.fullmatch(raw["handoff_sha256"])
            and isinstance(raw.get("capture_sha256"), str)
            and _SHA64.fullmatch(raw["capture_sha256"])
            and isinstance(raw.get("source_manifest_sha256"), str)
            and _SHA64.fullmatch(raw["source_manifest_sha256"])
            and isinstance(raw.get("profile_slug"), str) and bool(raw["profile_slug"])
            and isinstance(raw.get("run_id"), str) and bool(raw["run_id"])
            and raw.get("native_conversation_scope") == "EXISTING_CONVERSATION_ONLY"
            and raw.get("api_invocation") is False
            and raw.get("session_creation") is False
            and raw.get("cutover_eligible") is False
            and raw.get("method_execution_certified") is False
        ):
            return None
        return {
            "receipt_id": canonical_id, "verification_state": "VERIFIED",
            "verdict": "PASS", "subject_raw_sha256": sha,
            "handoff_sha256": raw["handoff_sha256"],
            "capture_sha256": raw["capture_sha256"],
            "source_manifest_sha256": raw["source_manifest_sha256"],
            "profile_slug": raw["profile_slug"], "run_id": raw["run_id"],
            "reviewer_execution_id": row["reviewer_execution_id"],
            "positive_controls_passed": True, "negative_controls_passed": True,
        }

    return resolve
