"""Evidence-bound hypothesis falsification (revised candidate transversal capability).

Determines which explicit hypothesis predictions are contradicted by independently
verified observations. Does not infer causality, authority, or fitness for deployment.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Callable


def canonical_sha(obj: Any) -> str:
    return hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def evaluate_hypotheses(
    task: dict[str, Any],
    *,
    evidence_verify: Callable[[dict[str, Any]], bool] | None,
) -> dict[str, Any]:
    base = {"schema": "CAUSAL_HYPOTHESIS_FALSIFICATION_V2", "status": "BLOCKED",
            "hypotheses": [], "rejected_evidence": [], "causal_proof": False,
            "execution_permission": False, "candidate_only": True}
    if not isinstance(task, dict) or not callable(evidence_verify):
        return {**base, "reason": "REQUEST_OR_EVIDENCE_VERIFIER_MISSING"}
    hypotheses = task.get("hypotheses")
    observations = task.get("observations")
    if not isinstance(hypotheses, list) or not 2 <= len(hypotheses) <= 8 or not isinstance(observations, list):
        return {**base, "reason": "HYPOTHESIS_OR_OBSERVATION_SET_INVALID"}
    if not isinstance(task.get("case_id"), str) or not task["case_id"]:
        return {**base, "reason": "CASE_ID_MISSING"}
    predictions = {}
    for h in hypotheses:
        if not isinstance(h, dict) or not isinstance(h.get("id"), str) or not isinstance(h.get("predictions"), dict) or not h["predictions"]:
            return {**base, "reason": "HYPOTHESIS_CONTRACT_INVALID"}
        if h["id"] in predictions:
            return {**base, "reason": "DUPLICATE_HYPOTHESIS"}
        if any(not isinstance(k, str) or type(v) is not bool for k, v in h["predictions"].items()):
            return {**base, "reason": "PREDICTION_CONTRACT_INVALID"}
        predictions[h["id"]] = h["predictions"]
    verified_obs, rejected, seen = {}, [], set()
    for e in observations:
        if not isinstance(e, dict) or not isinstance(e.get("probe_id"), str) or type(e.get("observed")) is not bool or not isinstance(e.get("evidence_ref"), str) or not e["evidence_ref"]:
            return {**base, "reason": "OBSERVATION_CONTRACT_INVALID"}
        if e["probe_id"] in seen:
            return {**base, "reason": "DUPLICATE_OBSERVATION_PROBE"}
        seen.add(e["probe_id"])
        try:
            check = evidence_verify(e) is True
        except Exception:
            check = False
        if check:
            verified_obs[e["probe_id"]] = e
        else:
            rejected.append(e["probe_id"])
    if not verified_obs:
        return {**base, "reason": "NO_INDEPENDENTLY_VERIFIED_OBSERVATIONS",
                "rejected_evidence": sorted(rejected)}
    rows = []
    for id, predicted in predictions.items():
        counter = [p for p,v in predicted.items()
                   if p in verified_obs and verified_obs[p]["observed"] != v]
        compatible = [p for p,v in predicted.items()
                      if p in verified_obs and verified_obs[p]["observed"] == v]
        missing = [p for p in predicted if p not in verified_obs]
        rows.append({"hypothesis_id": id, "state": "FALSIFIED" if counter else
                     "NOT_FALSIFIED" if compatible else "UNTESTED",
                     "falsified_by": sorted(counter),
                     "consistent_with": sorted(compatible),
                     "unverified_prediction_probes": sorted(missing)})
    return {**base, "status": "EVALUATED",
            "hypotheses": rows, "rejected_evidence": sorted(rejected),
            "verified_probe_count": len(verified_obs),
            "causal_proof": False,
            "next_action": "COLLECT_MORE_EVIDENCE" if (
                sum(x["state"] != "FALSIFIED" for x in rows) != 1
                or any(x["unverified_prediction_probes"] for x in rows if x["state"] != "FALSIFIED")
            ) else "EVALUATE_ALTERNATIVE_CAUSES_AND_STOP_GATES"}
