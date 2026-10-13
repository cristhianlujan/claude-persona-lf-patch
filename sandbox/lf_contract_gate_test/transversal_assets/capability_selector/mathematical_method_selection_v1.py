"""Optional mathematical method prioritization inside CAPABILITY_SELECTOR V3.

This is not an independent selector, engine, method runner, or authority. The
caller passes its existing typed signals, precondition verifier and cost model.
Mathematical methods remain SHADOW_ONLY until separate governed admission.
"""
from __future__ import annotations

from math import isfinite
from typing import Any, Callable


def _observed_uplift(method_id: str, context: dict[str, Any]) -> dict[str, Any]:
    history = context.get("method_effectiveness_observations")
    item = history.get(method_id) if isinstance(history, dict) else None
    if not isinstance(item, dict):
        return {"state": "UNPROVEN"}
    if item.get("verification_state") != "VERIFIED":
        return {"state": "UNPROVEN"}
    refs = item.get("evidence_refs")
    if (not isinstance(refs, list) or not refs
            or any(not isinstance(r, str) or not r.strip() for r in refs)):
        return {"state": "UNPROVEN"}
    gain = item.get("paired_quality_delta")
    critical = item.get("critical_regressions")
    if (isinstance(gain, bool) or not isinstance(gain, (int, float)) or not isfinite(gain)
            or isinstance(critical, bool) or not isinstance(critical, int) or critical < 0):
        return {"state": "UNPROVEN"}
    if critical > 0:
        return {"state": "REGRESSION", "critical_regressions": critical, "evidence_refs": refs}
    if gain <= 0:
        return {"state": "NO_POSITIVE_UPLIFT", "paired_quality_delta": float(gain),
                "evidence_refs": refs}
    if item.get("independent_holdout_verified") is not True:
        return {"state": "UNPROVEN"}
    return {"state": "OBSERVED_POSITIVE_NOT_ADMITTED", "paired_quality_delta": float(gain),
            "evidence_refs": refs}


def prioritize_mathematical_methods(
    context: dict[str, Any],
    signals: list[dict[str, Any]],
    methods: list[dict[str, Any]],
    precondition_state: dict[str, Any],
    verify_preconditions: Callable,
    method_cost: Callable,
) -> dict[str, Any]:
    """Build non-executable shadow recommendations; no unverified uplift claim."""
    budget = context.get("budget", {})
    if not isinstance(budget, dict):
        budget = {}
    max_cost = budget.get("max_shadow_method_cost_points")
    max_trials = budget.get("max_shadow_method_trials")
    if (max_cost is not None and
            (isinstance(max_cost, bool) or not isinstance(max_cost, (int, float))
             or not isfinite(max_cost) or max_cost < 0)):
        return {"status": "BLOCK", "reason": "SHADOW_COST_BUDGET_INVALID",
                "recommended_trials": [], "rejected": [], "execution_authorized": False}
    if (max_trials is not None and
            (type(max_trials) is not int or max_trials < 0)):
        return {"status": "BLOCK", "reason": "SHADOW_TRIAL_LIMIT_INVALID",
                "recommended_trials": [], "rejected": [], "execution_authorized": False}
    allowed_trials = max_trials if max_trials is not None else len(methods)
    blocked = context.get("blocked_methods")
    blocked = set(blocked) if isinstance(blocked, list) and all(isinstance(x, str) for x in blocked) else set()
    candidates = []
    rejected = []
    evidence_required = False
    matched_count = 0
    for method in methods:
        if (not isinstance(method, dict)
                or method.get("selection_lane") != "SHADOW_ONLY"
                or method.get("method_family") != "MATHEMATICAL"):
            continue
        mid = method.get("method_id")
        if not isinstance(mid, str) or not mid:
            continue
        matching = []
        for rule in method.get("signals", []):
            if not isinstance(rule, dict) or not isinstance(rule.get("accepted_values"), list):
                continue
            if any(s.get("type") == rule.get("type") and
                   s.get("value") in rule["accepted_values"] and s.get("status") == "OK"
                   for s in signals):
                matching.append(rule.get("type"))
        if not matching:
            continue
        matched_count += 1
        if mid in blocked:
            rejected.append({"method_id": mid, "reason": "BLOCKED_FOR_CURRENT_RUN"})
            continue
        if (method.get("availability_state") != "EXPERIMENTAL_NOT_ADMITTED"
                or method.get("auto_select") is not False):
            rejected.append({"method_id": mid, "reason": "SHADOW_CANDIDATE_POLICY_INVALID"})
            continue
        pre = verify_preconditions(method, precondition_state)
        if pre.get("status") != "PASS":
            evidence_required = True
            rejected.append({"method_id": mid, "reason": "PRECONDITION_" + str(pre.get("status")),
                             "missing_or_failed": [c.get("key") for c in pre.get("checks", [])
                                                   if c.get("status") != "PASS"]})
            continue
        measured = _observed_uplift(mid, context)
        if measured["state"] in ("REGRESSION", "NO_POSITIVE_UPLIFT"):
            rejected.append({"method_id": mid, "reason": measured["state"],
                             "history_evidence_refs": measured.get("evidence_refs", [])})
            continue
        cost, cost_state = method_cost(method, context)
        if not isinstance(cost, (int, float)) or not isfinite(cost) or cost < 0:
            rejected.append({"method_id": mid, "reason": "METHOD_COST_INVALID"})
            continue
        candidates.append({
            "method_id": mid,
            "selection_state": "SHADOW_TRIAL_ONLY",
            "matched_signal_types": sorted(set(matching)),
            "verified_precondition_refs": sorted({ref for check in pre["checks"]
                                                  for ref in check.get("evidence_refs", [])
                                                  if isinstance(ref, str)}),
            "effectiveness": measured,
            "cost_points": cost,
            "cost_state": cost_state,
            "compatible_capabilities": method.get("compatible_capabilities", []),
            "hypothesis": method.get("evaluation_hypothesis"),
            "availability_state": method["availability_state"],
            "execution_authorized": False,
        })
    # Empirical replicated gains take priority; absent those, evidence fit wins.
    # Cost breaks ties only; estimated cost is NOT presented as a measured benefit.
    candidates.sort(key=lambda m: (
        -(m["effectiveness"]["state"] == "OBSERVED_POSITIVE_NOT_ADMITTED"),
        -float(m["effectiveness"].get("paired_quality_delta", 0)),
        -len(m["matched_signal_types"]),
        m["cost_points"],
        m["method_id"],
    ))
    selected, spent = [], 0.0
    for m in candidates:
        if len(selected) >= allowed_trials:
            rejected.append({"method_id": m["method_id"], "reason": "SHADOW_TRIAL_LIMIT_REACHED"})
        elif max_cost is not None and spent + m["cost_points"] > max_cost:
            rejected.append({"method_id": m["method_id"], "reason": "SHADOW_BUDGET_INSUFFICIENT"})
        else:
            selected.append(m)
            spent += m["cost_points"]
    if selected:
        state = "SHADOW_RECOMMENDATIONS_READY"
    elif evidence_required:
        state = "EVIDENCE_REQUIRED"
    elif matched_count:
        state = "NO_ELIGIBLE_MATHEMATICAL_METHOD"
    else:
        state = "NO_MATHEMATICAL_METHOD_NEEDED"
    return {
        "schema": "CAPABILITY_SELECTOR_MATH_SHADOW_V1",
        "status": state,
        "recommended_trials": selected,
        "rejected": rejected,
        "matched_methods": matched_count,
        "planned_cost_points": spent,
        "cost_budget_limit": max_cost,
        "execution_authorized": False,
        "method_admission_authorized": False,
        "source_authority_mutation": False,
        "external_evidence_authenticity_required": True,
    }
