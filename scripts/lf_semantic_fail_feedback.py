"""Read-only semantic FAIL feedback for the existing LF native profile bridge.

Informational only: never records steps, invokes a model or grants authority.
"""
import json
import re
from pathlib import Path

CHECKS = (
    "context_resolution_valid", "evidence_supported", "decision_resolves_objective",
    "authority_resolution_valid", "constraints_preserved", "claims_authorized",
    "materiality_handled_correctly", "tradeoff_defensible",
    "acceptance_detects_wrong_implementation", "handoff_implementation_ready",
    "router_direct_consistency", "counterfactual_trajectory",
)
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def normalize_checks(raw):
    """Accept canonical checks object or observed list without duplicate IDs."""
    if isinstance(raw, list):
        if any(not isinstance(item, dict) or not isinstance(item.get("check"), str) for item in raw):
            raise ValueError("SEMANTIC_REVIEW_CHECKS_MISMATCH")
        names = [item["check"] for item in raw]
        if len(set(names)) != len(names):
            raise ValueError("SEMANTIC_REVIEW_CHECKS_MISMATCH")
        checks = {item["check"]: item for item in raw}
    elif isinstance(raw, dict):
        checks = raw
    else:
        raise ValueError("SEMANTIC_REVIEW_CHECKS_MISMATCH")
    if set(checks) != set(CHECKS):
        raise ValueError("SEMANTIC_REVIEW_CHECKS_MISMATCH")
    return checks


def digest_from_review(review, canonical, observed):
    """Validate digest and optional prefixed alias; require equality if both."""
    full, alias = review.get(canonical), review.get(observed)
    if full is None and alias is None:
        raise ValueError("SEMANTIC_REVIEW_DIGESTS_INVALID")
    if full is not None and (not isinstance(full, str) or not SHA256.fullmatch(full)):
        raise ValueError("SEMANTIC_REVIEW_DIGESTS_INVALID")
    if alias is not None and (not isinstance(alias, str) or not alias.startswith("sha256:") or not SHA256.fullmatch(alias[7:])):
        raise ValueError("SEMANTIC_REVIEW_DIGESTS_INVALID")
    if full is not None and alias is not None and full != alias[7:]:
        raise ValueError("SEMANTIC_REVIEW_DIGESTS_INVALID")
    return full if full is not None else alias[7:]


def classify_failure(review: dict, execution_id: str, profile_code: str) -> dict:
    """Transform a V3 semantic FAIL into typed producer feedback, without effects."""
    if not isinstance(review, dict):
        raise ValueError("SEMANTIC_REVIEW_NOT_OBJECT")
    verdict = review.get("verdict")
    if not isinstance(verdict, str) or not (verdict.startswith("FAIL_") or verdict.startswith("BLOCKED_")):
        raise ValueError("SEMANTIC_REVIEW_FAILURE_VERDICT_REQUIRED")
    checks = normalize_checks(review.get("decision_checks"))
    failures = []
    for name in CHECKS:
        check = checks[name]
        if not isinstance(check, dict) or check.get("result") not in (True, False, "true", "false", "blocked"):
            raise ValueError("SEMANTIC_REVIEW_CHECK_RESULT_INVALID")
        if not isinstance(check.get("reason"), str) or not check["reason"].strip():
            raise ValueError("SEMANTIC_REVIEW_CHECK_REASON_MISSING")
        if not isinstance(check.get("source_refs"), list):
            raise ValueError("SEMANTIC_REVIEW_CHECK_REFS_MISSING")
        if check["result"] in (False, "false", "blocked"):
            failures.append({
                "check": name, "result": check["result"],
                "reason": check["reason"], "source_refs": check["source_refs"],
            })
    if not failures:
        raise ValueError("SEMANTIC_FAIL_WITHOUT_FAILED_CHECKS")
    candidate_digest = digest_from_review(review, "candidate_sha256", "candidate_sha")
    scope_digest = digest_from_review(review, "scope_packet_sha256", "scope_sha")
    if not isinstance(review.get("source_refs"), list) or not review["source_refs"]:
        raise ValueError("SEMANTIC_REVIEW_SOURCES_REQUIRED")
    if not isinstance(review.get("resolved_context_refs"), list) or not review["resolved_context_refs"]:
        raise ValueError("SEMANTIC_REVIEW_CONTEXT_REQUIRED")
    if not execution_id or not profile_code:
        raise ValueError("SEMANTIC_REVIEW_TARGET_MISSING")
    return {
        "phase": "PRODUCER_REPAIR_REQUIRED",
        "outcome": "RETURN_TO_WORKER",
        "verdict": verdict,
        "execution_id": execution_id,
        "profile_code": profile_code,
        "candidate_sha256": candidate_digest,
        "scope_packet_sha256": scope_digest,
        "failed_checks": failures,
        "blocking_codes": review.get("blocking_codes", []),
        "source_refs": review["source_refs"],
        "resolved_context_refs": review["resolved_context_refs"],
        "next_action": "REQUEST_NEW_RAW_USING_EXISTING_ACT_0001_ROUTE",
        "source_execution_immutable": True,
        "step_70_recorded": False,
        "step_80_recorded": False,
        "producer_executed_by_bridge": False,
        "profile_evolution_automatically_requested": False,
        "governed_semantic_pass": False,
    }


def persist_feedback(review, execution_id, profile_code, out: Path) -> dict:
    feedback = classify_failure(review, execution_id, profile_code)
    out.write_text(
        json.dumps({"independent_review": review, "producer_feedback": feedback},
                   ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    return feedback
