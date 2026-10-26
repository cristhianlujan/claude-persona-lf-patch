"""Pure A9 -> INDEPENDENT_ASSURANCE@2.0.1 parameter adapter.

No network, database, model invocation, evidence write, or authorization effect.
The PostgreSQL JSONB text digest cannot be reconstructed safely using Python
json.dumps; use the verified context_sha256 supplied by the as-of readback.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Mapping

SUBJECT_TYPE = "PROGRAMMING_ANALYSIS_PACKAGE"
CAPABILITY = "INDEPENDENT_ASSURANCE"
OPERATION = "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"
CAPABILITY_MANIFEST = "f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35"
ENTRY_DIGEST = "d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8"
SUBJECT_ANCHOR_CAPABILITY = "EVIDENCE_LEDGER"
SUBJECT_ANCHOR_RECEIPT_KIND = "SOURCE_SNAPSHOT"
SUBJECT_ANCHOR_GATE = "A9_PROGRAMMING_ANALYSIS_SOURCE"  # proposal; confirm with the owner
SUBJECT_ANCHOR_RESOLVER = "LF_SUPABASE_READBACK_V1"
SUBJECT_ANCHOR_PROVIDER = "SUPABASE"
SUBJECT_ANCHOR_METHOD = "SUPABASE_SQL_READBACK_PLUS_DB_DIGEST"
CHAT_LEVEL = "OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT"
RUNTIME_LEVEL = "GOVERNED_RUNTIME"
FORBIDDEN = frozenset({"governed_execution_id", "router_dispatch_receipt_id", "provider_response_id_attested_by_transport", "evidence_ledger_verified_ref"})
SHA = re.compile(r"[a-f0-9]{64}\Z")
UUID = re.compile(r"[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\Z")


class A9ContractError(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def _require(cond: bool, code: str) -> None:
    if not cond:
        raise A9ContractError(code)


def _sha(value: Any, code: str = "SUBJECT_HASH_INVALID") -> str:
    _require(isinstance(value, str) and SHA.fullmatch(value) is not None, code)
    return value


def _nonempty(value: Any, code: str) -> str:
    _require(isinstance(value, str) and bool(value.strip()), code)
    return value


def _canonical(obj: Any) -> bytes:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def _digest(obj: Any) -> str:
    return hashlib.sha256(_canonical(obj)).hexdigest()


def _snapshot_parts(snapshot_row: Mapping[str, Any], required: list[str]) -> tuple[str, str, dict[str, Any]]:
    _require(isinstance(snapshot_row, Mapping), "A9_REVIEW_SUBJECT_INCOMPLETE")
    context_id = snapshot_row.get("context_id")
    context_sha = snapshot_row.get("context_sha256")
    payload = snapshot_row.get("context_payload")
    _require(isinstance(context_id, str) and UUID.fullmatch(context_id) is not None, "A9_REVIEW_SUBJECT_INCOMPLETE")
    _sha(context_sha)
    _require(isinstance(payload, dict), "A9_REVIEW_SUBJECT_INCOMPLETE")
    snap = payload.get("extensions", {}).get("programming_context_snapshot") if isinstance(payload.get("extensions"), dict) else None
    _require(isinstance(snap, dict) and all(field in snap and snap[field] is not None for field in required), "A9_REVIEW_SUBJECT_INCOMPLETE")
    return context_id, context_sha, payload


def _dimensions(contract: Mapping[str, Any]) -> list[dict[str, Any]]:
    dims = contract.get("required_dimensions")
    _require(isinstance(dims, list) and 6 <= len(dims) <= 8, "A9_REVIEW_CONTRACT_INVALID")
    codes = [d.get("code") for d in dims if isinstance(d, dict)]
    _require(len(codes) == len(dims) and len(set(codes)) == len(codes) and all(isinstance(c, str) and re.fullmatch(r"[A-Z][A-Z0-9_]*", c) for c in codes), "A9_REVIEW_CONTRACT_INVALID")
    return dims


def build_subject_anchor_params(snapshot_row: Mapping[str, Any], source_head_sha: str, producer_execution_id: str, actor_execution_id: str, *, subject_contract: Mapping[str, Any]) -> dict[str, Any]:
    """Prepare fn_lf_evidence_ledger_anchor_v1 arguments for the SUBJECT; never anchor.

    The subject is a SOURCE_SNAPSHOT of the as-of row, not a review receipt
    (pattern of the real subject receipt 731e93ae…, 21-oct). Resolver,
    provider and verification method are the existing ledger catalog values
    for Supabase readbacks (LF_SUPABASE_READBACK_V1 / SUPABASE /
    SUPABASE_SQL_READBACK_PLUS_DB_DIGEST). verification_state stays None:
    only the governed operation may set VERIFIED after its own DB readback.
    The payload references the as-of row; it never copies context_payload.
    """
    cid, sha, _payload = _snapshot_parts(snapshot_row, subject_contract["required_snapshot_fields"])
    _nonempty(producer_execution_id, "SUBJECT_OR_PRODUCER_IDENTITY_MISSING")
    _nonempty(actor_execution_id, "A9_REVIEW_ACTOR_MISSING")
    _nonempty(source_head_sha, "A9_REVIEW_SOURCE_HEAD_MISSING")
    authority_ref = f"supabase://private/lf_decision_context_asof_v1/{cid}"
    return {
        "p_execution_id": producer_execution_id,
        "p_capability_code": SUBJECT_ANCHOR_CAPABILITY,
        "p_gate_code": SUBJECT_ANCHOR_GATE,
        "p_receipt_kind": SUBJECT_ANCHOR_RECEIPT_KIND,
        "p_subject_type": SUBJECT_TYPE,
        "p_subject_ref": f"{SUBJECT_TYPE}/{cid}",
        "p_subject_sha256": sha,
        "p_source_head_sha": source_head_sha,
        "p_authority_ref": authority_ref,
        "p_resolver_id": SUBJECT_ANCHOR_RESOLVER,
        "p_provider": SUBJECT_ANCHOR_PROVIDER,
        "p_provider_ref": authority_ref,
        "p_verification_method": SUBJECT_ANCHOR_METHOD,
        "p_verification_state": None,
        "p_verification_payload": {"provider_attested": False, "context_id": cid, "context_sha256": sha, "requires_governed_verification": True, "digest_rule": "SHA256(UTF8(context_payload::text)) recomputed by PostgreSQL"},
        "p_receipt_payload": {"schema_version": "A9_PROGRAMMING_SUBJECT_ANCHOR_PROPOSAL_V1", "subject_ref": f"{SUBJECT_TYPE}/{cid}", "subject_sha256": sha, "source_table": "private.lf_decision_context_asof_v1", "context_id": cid, "context_sha256": sha},
        "p_actor_execution_id": actor_execution_id,
    }


def build_begin_params(subject: Mapping[str, Any], subject_receipt_id: str, reviewer_execution_id: str, producer_execution_id: str, plan: Mapping[str, Any], dispatch_receipt_id: str, actor_execution_id: str, *, subject_contract: Mapping[str, Any]) -> dict[str, Any]:
    """Prepare begin_v3 parameters; plan supplies only verified external refs.

    Required plan keys: expected_capability_manifest_sha256, plan_digest,
    request_sha256, idempotency_key, review_scope; optional manifest.
    The runtime must bind and verify all foreign receipts before beginning.
    """
    _nonempty(reviewer_execution_id, "SUBJECT_OR_PRODUCER_IDENTITY_MISSING")
    _nonempty(producer_execution_id, "SUBJECT_OR_PRODUCER_IDENTITY_MISSING")
    _require(reviewer_execution_id != producer_execution_id, "BUILDER_REVIEWER_NOT_INDEPENDENT")
    _require(subject.get("subject_type") == SUBJECT_TYPE, "SUBJECT_TYPE_MISSING")
    _nonempty(subject.get("subject_ref"), "SUBJECT_OR_PRODUCER_IDENTITY_MISSING")
    subject_sha = _sha(subject.get("subject_sha256"))
    _require(isinstance(plan, Mapping), "A9_REVIEW_PLAN_INVALID")
    _require(plan.get("expected_capability_manifest_sha256") == CAPABILITY_MANIFEST, "BLOCK_CURRENTNESS_MISMATCH")
    _sha(plan.get("request_sha256"), "A9_REVIEW_PLAN_INVALID")
    _nonempty(plan.get("plan_digest"), "A9_REVIEW_PLAN_INVALID")
    _nonempty(plan.get("idempotency_key"), "A9_REVIEW_PLAN_INVALID")
    _nonempty(plan.get("review_scope"), "A9_REVIEW_PLAN_INVALID")
    _nonempty(subject.get("source_head_sha"), "A9_REVIEW_SOURCE_HEAD_MISSING")
    _nonempty(subject_receipt_id, "A9_REVIEW_RECEIPT_ID_MISSING")
    _nonempty(dispatch_receipt_id, "A9_REVIEW_DISPATCH_ID_MISSING")
    _nonempty(actor_execution_id, "A9_REVIEW_ACTOR_MISSING")
    dims = _dimensions(subject_contract)
    evidence_level = plan.get("evidence_level", CHAT_LEVEL)
    _require(evidence_level in (CHAT_LEVEL, RUNTIME_LEVEL), "A9_REVIEW_EVIDENCE_LEVEL_INVALID")
    manifest = plan.get("manifest", {})
    _require(isinstance(manifest, dict), "A9_REVIEW_PLAN_INVALID")
    _require(not any(k in manifest for k in FORBIDDEN), "FORGED_GOVERNED_FIELD")
    return {
        "p_execution_id": reviewer_execution_id,
        "p_subject_type": SUBJECT_TYPE,
        "p_subject_ref": subject["subject_ref"],
        "p_subject_sha256": subject_sha,
        "p_source_head_sha": subject["source_head_sha"],
        "p_subject_receipt_id": subject_receipt_id,
        "p_producer_execution_id": producer_execution_id,
        "p_expected_capability_manifest_sha256": CAPABILITY_MANIFEST,
        "p_plan_digest": plan["plan_digest"],
        "p_dispatch_receipt_id": dispatch_receipt_id,
        "p_request_sha256": plan["request_sha256"],
        "p_idempotency_key": plan["idempotency_key"],
        "p_actor_execution_id": actor_execution_id,
        "p_manifest": {**manifest, "required_dimensions": [d["code"] for d in dims], "review_scope": plan["review_scope"], "evidence_level": evidence_level, "provider_attested": False if evidence_level == CHAT_LEVEL else None, "runtime_activation": False, "production_activation": False, "business_effect_allowed": False},
    }


def build_blind_review_packet(snapshot_payload: Mapping[str, Any], subject_contract: Mapping[str, Any]) -> dict[str, Any]:
    """Return packet and digest; scrub producer traces recursively, fail on forbidden governed fields."""
    _require(isinstance(snapshot_payload, Mapping), "A9_REVIEW_SUBJECT_INCOMPLETE")
    dims = _dimensions(subject_contract)
    banned = {"stage_trace", "producer_verdict", "producer_execution_id", "review_verdict", "producer_conversation", "producer_chat_transcript", "producer_name", "producer_id"}
    def scrub(value: Any) -> Any:
        if isinstance(value, dict):
            _require(not (set(value) & FORBIDDEN), "FORGED_GOVERNED_FIELD")
            return {k: scrub(v) for k, v in value.items() if k not in banned}
        if isinstance(value, list):
            return [scrub(v) for v in value]
        return value
    clean = scrub(dict(snapshot_payload))
    _require(isinstance(clean.get("extensions"), dict) and isinstance(clean["extensions"].get("programming_context_snapshot"), dict), "A9_REVIEW_SUBJECT_INCOMPLETE")
    packet = {"schema_version": "A9_BLIND_REVIEW_PACKET_V1", "subject_type": SUBJECT_TYPE, "snapshot_payload": clean, "required_dimensions": dims, "response_format": {"packet_sha256": "<copy supplied packet_sha256>", "dimensions": [{"code": d["code"], "verdict": "PASS|FAIL|UNKNOWN", "evidence": ["exact packet references"], "reason": "explanation"} for d in dims]}}
    digest = _digest(packet)
    return {"packet": packet, "packet_sha256": digest}


def parse_review_verdict(raw_text: str, packet_sha256: str, subject_contract: Mapping[str, Any]) -> dict[str, Any]:
    """Parse a raw JSON-only GPT Native review. Never interpret as provider attestation."""
    try:
        value = json.loads(raw_text)
    except (TypeError, ValueError) as exc:
        raise A9ContractError("A9_REVIEW_VERDICT_INVALID") from exc
    _require(isinstance(value, dict), "A9_REVIEW_VERDICT_INVALID")
    def forbid(obj: Any) -> None:
        if isinstance(obj, dict):
            _require(not (set(obj) & FORBIDDEN), "FORGED_GOVERNED_FIELD")
            for v in obj.values(): forbid(v)
        elif isinstance(obj, list):
            for v in obj: forbid(v)
    forbid(value)
    _sha(packet_sha256, "A9_REVIEW_PACKET_HASH_MISMATCH")
    _require(value.get("packet_sha256") == packet_sha256, "A9_REVIEW_PACKET_HASH_MISMATCH")
    dims = _dimensions(subject_contract)
    expected = {d["code"] for d in dims}
    actual = value.get("dimensions")
    _require(isinstance(actual, list) and all(isinstance(d, dict) for d in actual), "A9_REVIEW_DIMENSIONS_INVALID")
    codes = [d.get("code") for d in actual]
    _require(len(codes) == len(expected) and len(set(codes)) == len(codes) and set(codes) == expected, "A9_REVIEW_DIMENSIONS_INVALID")
    for d in actual:
        _require(set(d) == {"code", "verdict", "evidence", "reason"}, "A9_REVIEW_VERDICT_INVALID")
        _require(d["verdict"] in ("PASS", "FAIL", "UNKNOWN"), "A9_REVIEW_VERDICT_INVALID")
        _require(isinstance(d["reason"], str) and d["reason"].strip(), "A9_REVIEW_VERDICT_INVALID")
        _require(isinstance(d["evidence"], list) and all(isinstance(x, str) and x.strip() for x in d["evidence"]), "A9_REVIEW_VERDICT_INVALID")
        _require(d["verdict"] != "PASS" or bool(d["evidence"]), "A9_REVIEW_PASS_WITHOUT_EVIDENCE")
    _require(set(value) == {"packet_sha256", "dimensions"}, "A9_REVIEW_VERDICT_INVALID")
    statuses = {d["verdict"] for d in actual}
    global_verdict = "BLOCKED" if "UNKNOWN" in statuses else "RETURN_TO_WORKER" if "FAIL" in statuses else "PASS"
    return {"packet_sha256": packet_sha256, "dimensions": actual, "global_verdict": global_verdict, "evidence_level": CHAT_LEVEL, "provider_attested": False}


def build_a9q_c3_evidence(*, subject: Mapping[str, Any], review: Mapping[str, Any], reviewer_execution_id: str | None = None, review_dispatch_receipt_id: str | None = None, review_verdict_ref: str | None = None, exact_stage_assertion_results: Any = None, no_critical_regressions: bool | None = None, evidence_level: str = CHAT_LEVEL) -> dict[str, Any]:
    """Build an A9Q_C3 proposal, not an evidence-ledger verified receipt.

    Identifiers/receipts emitted solely by the governed runtime remain None.
    Caller-provided reviewer/dispatch identifiers are proposals, not attestations.
    """
    _require(evidence_level == CHAT_LEVEL, "A9_REVIEW_GOVERNED_RUNTIME_REQUIRED")
    _sha(subject.get("subject_sha256"))
    return {"frozen_subject_sha256": subject["subject_sha256"], "producer_execution_id": subject.get("producer_execution_id"), "reviewer_execution_id": reviewer_execution_id, "review_dispatch_receipt_id": review_dispatch_receipt_id, "review_verdict_ref": review_verdict_ref, "evidence_ledger_verified_ref": None, "exact_stage_assertion_results": exact_stage_assertion_results, "no_critical_regressions": no_critical_regressions, "provider_attested": False, "evidence_level": evidence_level, "governed_execution_id": None, "router_dispatch_receipt_id": None, "provider_response_id_attested_by_transport": None, "global_verdict": review.get("global_verdict")}


def build_v2_envelope_review_fragment(*, subject: Mapping[str, Any], review: Mapping[str, Any], reviewer_execution_id: str | None, review_verdict_ref: str | None, evidence_level: str = CHAT_LEVEL) -> dict[str, Any]:
    """Provisional review fragment only: PROGRAMMING_ENTRY_CONTRACT_V2 IS NOT RELEASED.

    Never use this fragment to grant admission; it is not an envelope V2.
    """
    _require(evidence_level == CHAT_LEVEL, "A9_REVIEW_GOVERNED_RUNTIME_REQUIRED")
    cid = subject.get("context_id")
    _require(isinstance(cid, str) and UUID.fullmatch(cid) is not None, "A9_REVIEW_SUBJECT_INCOMPLETE")
    sha = _sha(subject.get("context_sha256"))
    _require(sha == subject.get("subject_sha256"), "A9_REVIEW_SUBJECT_HASH_MISMATCH")
    return {"schema_version": "A9_V2_REVIEW_FRAGMENT_PROPOSAL_V1", "review_verdict_ref": review_verdict_ref, "reviewer_execution_id": reviewer_execution_id, "frozen_subject_sha256": sha, "context_id": cid, "context_sha256": sha, "dimensions": review.get("dimensions"), "global_verdict": review.get("global_verdict"), "evidence_level": evidence_level, "provider_attested": False, "admissible": False}
