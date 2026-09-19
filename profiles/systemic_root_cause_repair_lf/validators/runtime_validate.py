#!/usr/bin/env python3
"""Deterministic runtime validator for Systemic Root Cause Repair LF.

This validates profile-local invariants only. It is not the canonical semantic judge.
"""

ALLOWED_STATUS = {
    "SYSTEMIC_REPAIR_SPEC",
    "NEEDS_MORE_EVIDENCE",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "BLOCK_PIPELINE",
}
REQUIRED_FALSIFICATION_CASES = {
    "bypass",
    "retry",
    "concurrency",
    "partial_failure",
    "stale_state",
    "interrupted_execution",
    "replay_or_duplicate",
    "undeclared_or_unversioned_caller",
}


def _error(code, path="$", message=""):
    return {"code": code, "path": path, "message": message}


def validate(payload):
    errors = []
    if not isinstance(payload, dict):
        return {"valid": False, "status": "FAIL", "errors": [_error("NOT_OBJECT")], "blocking_codes": ["NOT_OBJECT"]}

    status = payload.get("status")
    if status not in ALLOWED_STATUS:
        errors.append(_error("STATUS_INVALID", "$.status"))
    if payload.get("profile_pack_id") != "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2":
        errors.append(_error("PROFILE_PACK_ID_MISMATCH", "$.profile_pack_id"))


    if status == "SYSTEMIC_REPAIR_SPEC":
        contradictions = payload.get("authority_contradictions")
        if not isinstance(contradictions, list):
            errors.append(_error("AUTHORITY_CONTRADICTIONS_INVALID", "$.authority_contradictions"))
        elif contradictions:
            errors.append(_error("UNRESOLVED_AUTHORITY_CONTRADICTION", "$.authority_contradictions"))

        blockers = payload.get("blocking_codes")
        if not isinstance(blockers, list):
            errors.append(_error("BLOCKING_CODES_INVALID", "$.blocking_codes"))
        elif blockers:
            errors.append(_error("SYSTEMIC_SPEC_WITH_BLOCKERS", "$.blocking_codes"))

        existence = payload.get("should_exist_assessment")
        if not isinstance(existence, dict):
            errors.append(_error("SHOULD_EXIST_ASSESSMENT_MISSING", "$.should_exist_assessment"))
        elif existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
            errors.append(_error("SHOULD_EXIST_ASSESSMENT_UNRESOLVED", "$.should_exist_assessment.verdict"))

        alternatives = payload.get("alternatives")
        if not isinstance(alternatives, list) or len(alternatives) < 3:
            errors.append(_error("ALTERNATIVES_INSUFFICIENT", "$.alternatives"))

        rejected = payload.get("rejected_alternatives")
        if not isinstance(rejected, list) or len(rejected) < 2:
            errors.append(_error("REJECTED_ALTERNATIVES_INSUFFICIENT", "$.rejected_alternatives"))

        falsifications = payload.get("falsification_results")
        if not isinstance(falsifications, list):
            errors.append(_error("FALSIFICATION_RESULTS_INVALID", "$.falsification_results"))
        else:
            cases = {str(item.get("case")) for item in falsifications if isinstance(item, dict)}
            missing = sorted(REQUIRED_FALSIFICATION_CASES - cases)
            if missing:
                errors.append(_error("FALSIFICATION_FAMILIES_MISSING", "$.falsification_results", ",".join(missing)))

        guard = payload.get("hard_guard")
        if not isinstance(guard, dict) or not all(isinstance(guard.get(k), str) and guard.get(k).strip() for k in ("control","fail_closed_condition","observable_result")):
            errors.append(_error("HARD_GUARD_NOT_TESTABLE", "$.hard_guard"))

        if not isinstance(payload.get("evidence_map"), list) or not payload.get("evidence_map"):
            errors.append(_error("EVIDENCE_MAP_EMPTY", "$.evidence_map"))

    codes = sorted({e["code"] for e in errors})
    return {"valid": not errors, "status": "PASS" if not errors else "FAIL", "errors": errors, "blocking_codes": codes}


if __name__ == "__main__":
    import json, sys
    try:
        value = json.load(sys.stdin)
    except Exception:
        value = None
    print(json.dumps(validate(value), ensure_ascii=False, indent=2))
