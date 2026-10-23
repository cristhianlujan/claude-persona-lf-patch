"""Read-only Ochiai failure-spectrum ranking; hypotheses, never causal proof.

Input contains frozen case-level binary failure observations and execution/evaluator
references. This module never selects a method, executes a model or admits a profile.
"""
from __future__ import annotations
from math import sqrt


def rank_ochiai(cases: list[dict], suspects: list[str]) -> dict:
    blocked = lambda reason: {"status": "BLOCK", "reason": reason, "cutover_eligible": False}
    if not isinstance(cases, list) or not isinstance(suspects, list) or not cases:
        return blocked("OBSERVED_CASES_REQUIRED")
    if not suspects or any(not isinstance(s, str) or not s for s in suspects) or len(set(suspects)) != len(suspects):
        return blocked("SUSPECT_IDENTITY_INVALID")
    ids = set()
    snapshot = set()
    fails = passes = 0
    for c in cases:
        if not isinstance(c, dict) or not isinstance(c.get("case_id"), str) or not c["case_id"] or c["case_id"] in ids:
            return blocked("CASE_IDENTITY_INVALID")
        ids.add(c["case_id"])
        if type(c.get("failed")) is not bool or c.get("frozen") is not True:
            return blocked("BINARY_FROZEN_FAILURE_REQUIRED")
        if any(not isinstance(c.get(k), str) or not c[k].strip() for k in ("subject_sha256", "execution_receipt_ref", "evaluator_receipt_ref")):
            return blocked("BOUND_EVIDENCE_REQUIRED")
        if c.get("independent_evaluator") is not True:
            return blocked("INDEPENDENT_EVALUATOR_REQUIRED")
        snapshot.add(c["subject_sha256"])
        covered = c.get("covered")
        if not isinstance(covered, list) or any(not isinstance(s, str) or s not in suspects for s in covered) or len(set(covered)) != len(covered):
            return blocked("COVERAGE_INVALID")
        fails += int(c["failed"])
        passes += int(not c["failed"])
    if len(snapshot) != 1:
        return blocked("FROZEN_SUBJECT_MISMATCH")
    if not fails or not passes:
        return {"status": "NOT_OBSERVED", "reason": "FAILING_AND_PASSING_CONTROLS_REQUIRED", "cutover_eligible": False}
    results = []
    for suspect in suspects:
        ef = sum(c["failed"] and suspect in c["covered"] for c in cases)
        ep = sum(not c["failed"] and suspect in c["covered"] for c in cases)
        nf = fails - ef
        denom = sqrt((ef + nf) * (ef + ep))
        score = ef / denom if denom else 0.0
        results.append({"suspect": suspect, "ef": ef, "ep": ep, "nf": nf, "score": round(score, 10)})
    results.sort(key=lambda r: (-r["score"], r["suspect"]))
    return {"status": "RANKED_CANDIDATES_NOT_CAUSAL_PROOF", "failed_cases": fails,
            "passed_cases": passes, "ranking": results, "external_receipt_readback_required": True,
            "expertise_certified": False, "cutover_eligible": False}
