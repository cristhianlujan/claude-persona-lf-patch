"""Fail-closed publication receipt checker for PG-00 C3; static independent evidence only."""
import hashlib
import json

class PublicationBlocked(ValueError):
    pass

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def sha256(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()

STAGES=("DRAFT_NOT_RELEASED","REVIEWED_CANDIDATE","PASE_QUALIFIED","TRAIN_APPLIED","ACTIVE_READBACK_VERIFIED")

def check_release(candidate, evidence):
    if not isinstance(candidate,dict) or not isinstance(evidence,dict):
        raise PublicationBlocked("INVALID_INPUT")
    if candidate.get("state")!="ACTIVE_READBACK_VERIFIED":
        raise PublicationBlocked("NOT_ACTIVE")
    if candidate.get("closed_static_front_catalog_forbidden") is not True or candidate.get("front_kind_policy")!="EVIDENCE_DERIVED_OPEN_CATALOG":
        raise PublicationBlocked("A7_OPEN_POLICY_MISSING")
    if evidence.get("transition_history")!=list(STAGES):
        raise PublicationBlocked("INVALID_TRANSITION_HISTORY")
    if not isinstance(evidence.get("owner_approval_ref"),str) or not evidence["owner_approval_ref"]:
        raise PublicationBlocked("OWNER_APPROVAL_MISSING")
    if not isinstance(evidence.get("independent_review_ref"),str) or not evidence["independent_review_ref"]:
        raise PublicationBlocked("INDEPENDENT_REVIEW_MISSING")
    if evidence["owner_approval_ref"]==evidence["independent_review_ref"]:
        raise PublicationBlocked("SELF_REVIEW")
    if evidence.get("pase_status")!="PASS" or not evidence.get("pase_receipt"):
        raise PublicationBlocked("PASE_MISSING")
    if evidence.get("train_status")!="APPLIED" or not evidence.get("train_receipt"):
        raise PublicationBlocked("TRAIN_RECEIPT_MISSING")
    if not evidence.get("head_sha") or evidence.get("head_sha")!=evidence.get("reviewed_head_sha"):
        raise PublicationBlocked("HEAD_DRIFT")
    actual=sha256(candidate)
    if evidence.get("repo_digest")!=actual or evidence.get("transversal_digest")!=actual:
        raise PublicationBlocked("READBACK_DRIFT")
    if not evidence.get("catalog_std_full") or not evidence.get("machine_format_ref") or not evidence.get("llm_format_ref"):
        raise PublicationBlocked("STD_CATALOG_INCOMPLETE")
    if not evidence.get("aud02_decision_ref"):
        raise PublicationBlocked("AUD02_UNRESOLVED")
    # All of the above must be verified against authoritative systems; this pure checker
    # is NEVER sufficient proof of authenticity (caller-supplied strings can be spoofed).
    return {"state":"EVIDENCE_SHAPE_VALID_ONLY_NOT_AUTHORIZED","sha256":actual}
