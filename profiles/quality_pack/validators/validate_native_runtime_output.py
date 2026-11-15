#!/usr/bin/env python3
"""Fail-closed native Step50 validator for Quality Pack.

This is a profile-local deterministic *candidate* check, not an independent
semantic judge, trusted-ref resolver, GOV-037 approval, or promotion authority.
"""
import json
import sys

from validate_routing import validate_routing

SCORE_FIELDS = (
    "contract_schema_compliance",
    "evidence_integrity",
    "lf_safety_governance",
    "handoff_readiness",
    "leakage_scope_control",
)
VERDICTS = {
    "PASS_TO_COMPOSER",
    "PASS_WITH_RESTRICTIONS",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR",
    "BLOCK_PIPELINE",
}
PASS_VERDICTS = {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"}


def validate(payload):
    errors = []
    if not isinstance(payload, dict):
        return {"valid": False, "errors": ["QUALITY_OUTPUT_OBJECT_REQUIRED"]}
    required = (
        "review_id", "reviewed_artifact", "verdict", "score_breakdown",
        "evidence_map", "blocking_codes", "repair_actions",
        "remaining_risks", "next_gate", "routing",
    )
    for key in required:
        if key not in payload:
            errors.append("QUALITY_FIELD_MISSING:" + key)
    verdict = payload.get("verdict")
    if verdict not in VERDICTS:
        errors.append("QUALITY_VERDICT_INVALID")

    scores = payload.get("score_breakdown")
    if not isinstance(scores, dict):
        errors.append("QUALITY_SCORE_BREAKDOWN_REQUIRED")
    else:
        vals = [scores.get(k) for k in SCORE_FIELDS]
        if any(type(v) is not int or not 0 <= v <= 5 for v in vals):
            errors.append("QUALITY_SCORE_COMPONENT_INVALID")
        elif type(scores.get("total")) is not int or scores["total"] != sum(vals):
            errors.append("QUALITY_SCORE_TOTAL_MISMATCH")

    if not isinstance(payload.get("review_id"), str) or not payload["review_id"].strip():
        errors.append("QUALITY_REVIEW_ID_REQUIRED")
    if not isinstance(payload.get("reviewed_artifact"), str) or not payload["reviewed_artifact"].strip():
        errors.append("QUALITY_REVIEWED_ARTIFACT_REQUIRED")
    if not isinstance(payload.get("next_gate"), str) or not payload["next_gate"].strip():
        errors.append("QUALITY_NEXT_GATE_REQUIRED")
    evidence = payload.get("evidence_map")
    if not isinstance(evidence, list) or not evidence:
        errors.append("QUALITY_EVIDENCE_MAP_REQUIRED")
    else:
        for item in evidence:
            if not isinstance(item, dict) or not isinstance(item.get("source_ref"), str) or not item["source_ref"].strip():
                errors.append("QUALITY_EVIDENCE_REF_REQUIRED")
                break

    for key in ("blocking_codes", "repair_actions", "remaining_risks"):
        if not isinstance(payload.get(key), list):
            errors.append("QUALITY_LIST_REQUIRED:" + key)
    blockers = payload.get("blocking_codes")
    if verdict not in PASS_VERDICTS and (
        not isinstance(blockers, list)
        or not blockers
        or any(not isinstance(x, str) or not x.strip() for x in blockers)
    ):
        errors.append("QUALITY_NONPASS_BLOCKING_CODE_REQUIRED")
    if isinstance(verdict, str):
        errors.extend("QUALITY_" + code for code in validate_routing(verdict, payload.get("routing")))

    # This minimal binding restores non-PASS candidate transport only.
    # GOV-037 source readback + a genuinely independent semantic receipt
    # are not implemented by this validator. Never transform candidate
    # declarations, offline tests, or producer Step70 into a Quality PASS.
    if verdict in PASS_VERDICTS:
        errors.append("QUALITY_PASS_INDEPENDENT_GOV037_GATE_REQUIRED")
    if payload.get("production_authorized") is True:
        errors.append("QUALITY_PRODUCTION_AUTHORITY_FORBIDDEN")
    if payload.get("promotion_authorized") is True:
        errors.append("QUALITY_PROMOTION_AUTHORITY_FORBIDDEN")
    if payload.get("judge_independence_status") == "PROVEN":
        errors.append("QUALITY_JUDGE_INDEPENDENCE_UNVERIFIED")

    return {"valid": not errors, "errors": sorted(set(errors))}


def main():
    try:
        payload = json.load(sys.stdin)
        result = validate(payload)
    except (ValueError, UnicodeError):
        result = {"valid": False, "errors": ["QUALITY_INPUT_JSON_INVALID"]}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
