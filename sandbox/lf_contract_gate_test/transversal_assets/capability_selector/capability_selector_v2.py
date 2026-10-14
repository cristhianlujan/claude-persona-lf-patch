from __future__ import annotations

from typing import Any

from capability_selector_v1 import select_capabilities


_CONTEXT_FIELDS = (
    "task_family",
    "complexity",
    "novelty",
    "uncertainty",
    "causal_requirement",
    "risk",
    "repeated_pattern",
    "evidence_sufficiency",
    "optimization_need",
    "evidence_paths",
)


def build_selection_signals(context: dict[str, Any]) -> list[dict[str, Any]]:
    if not isinstance(context, dict):
        raise ValueError("SELECTION_CONTEXT_INVALID")
    out: list[dict[str, Any]] = []
    for gap in context.get("profile_gaps", []):
        if isinstance(gap, str) and gap:
            out.append({"type": "profile_gap", "value": gap, "status": "OK"})
        elif isinstance(gap, dict) and isinstance(gap.get("gap"), str):
            out.append({"type": "profile_gap", "value": gap["gap"], "status": "OK"})
    for key in _CONTEXT_FIELDS:
        if key in context and context[key] is not None:
            out.append({"type": key, "value": context[key], "status": "OK"})
    return out


def _select_capabilities_multilabel(
    signals: list[dict[str, Any]],
    catalog: list[dict[str, Any]],
    policy: dict[str, Any],
) -> dict[str, Any]:
    """Preserve v1 contradiction semantics while treating profile_gap as multi-label in v2."""
    non_gap = [s for s in signals if s.get("type") != "profile_gap"]
    gaps = [s for s in signals if s.get("type") == "profile_gap"]
    empty_policy = dict(policy)
    empty_policy["fallback_capabilities"] = []

    base = select_capabilities(non_gap, catalog, empty_policy)
    if base["fallback_state"] in {"CONTRADICTORY", "CAPABILITY_FAILURE"}:
        return select_capabilities(non_gap, catalog, policy)

    selected = list(base["selected_capabilities"])
    reasons = list(base["reasons"])
    for gap in gaps:
        part = select_capabilities([gap], catalog, empty_policy)
        if part["fallback_state"] == "CAPABILITY_FAILURE":
            return select_capabilities([gap], catalog, policy)
        for code in part["selected_capabilities"]:
            if code not in selected:
                selected.append(code)
        reasons.extend(part["reasons"])

    if not selected:
        return select_capabilities([], catalog, policy)

    rank_by_code: dict[str, float] = {}
    for entry in catalog:
        if isinstance(entry, dict) and isinstance(entry.get("capability_code"), str):
            rank = entry.get("rank", 0)
            if isinstance(rank, (int, float)) and not isinstance(rank, bool):
                rank_by_code[entry["capability_code"]] = max(rank_by_code.get(entry["capability_code"], float("-inf")), float(rank))
    selected.sort(key=lambda code: (-rank_by_code.get(code, 0), code))
    seen: set[tuple[Any, ...]] = set()
    deduped_reasons = []
    for reason in reasons:
        key = (reason.get("code"), reason.get("signal_type"), reason.get("capability_code"), reason.get("rank"))
        if key not in seen:
            seen.add(key)
            deduped_reasons.append(reason)
    return {
        "selected_capabilities": selected,
        "reasons": deduped_reasons,
        "fallback_state": "CLEAR" if len(selected) == 1 else "MULTI",
    }


def _method_matches(method: dict[str, Any], signals: list[dict[str, Any]]) -> bool:
    rules = method.get("signals", [])
    if not isinstance(rules, list):
        return False
    for rule in rules:
        if not isinstance(rule, dict):
            continue
        t = rule.get("type")
        accepted = rule.get("accepted_values", [])
        if any(s.get("type") == t and s.get("value") in accepted and s.get("status", "OK") == "OK" for s in signals):
            return True
    return False


def compose_capabilities(
    context: dict[str, Any],
    catalog: list[dict[str, Any]],
    policy: dict[str, Any],
    method_registry: dict[str, Any],
) -> dict[str, Any]:
    """Compose capabilities + method requirements. Selection is not admission."""
    signals = build_selection_signals(context)
    base = _select_capabilities_multilabel(signals, catalog, policy)
    methods = method_registry.get("methods", []) if isinstance(method_registry, dict) else []
    budget = context.get("budget", {}) if isinstance(context.get("budget", {}), dict) else {}
    max_cost = budget.get("max_method_cost_points")
    selected_methods: list[dict[str, Any]] = []
    total_cost = 0

    for method in methods if isinstance(methods, list) else []:
        if not isinstance(method, dict) or not _method_matches(method, signals):
            continue
        cost = method.get("cost_points", 0)
        if not isinstance(cost, (int, float)) or isinstance(cost, bool) or cost < 0:
            continue
        within_budget = max_cost is None or total_cost + cost <= max_cost
        selected_methods.append({
            "method_id": method.get("method_id"),
            "cost_points": cost,
            "within_budget": within_budget,
            "preconditions": method.get("preconditions", []),
            "stop_conditions": method.get("stop_conditions", []),
            "validation_method": method.get("validation_method"),
        })
        if within_budget:
            total_cost += cost

    composition = list(base["selected_capabilities"])
    for m in selected_methods:
        if not m["within_budget"]:
            continue
        method = next((x for x in methods if x.get("method_id") == m["method_id"]), {})
        for cap in method.get("compatible_capabilities", []):
            if isinstance(cap, str) and cap not in composition:
                composition.append(cap)

    escalations = []
    for m in selected_methods:
        if not m["within_budget"]:
            escalations.append({"method_id": m["method_id"], "condition": "BUDGET_INSUFFICIENT"})
            continue
        method = next((x for x in methods if x.get("method_id") == m["method_id"]), {})
        for target in method.get("escalation", []):
            escalations.append({"from": m["method_id"], "to": target, "condition": "STOP_CONDITION_UNMET_OR_EVIDENCE_REQUIRES_ESCALATION"})

    return {
        "schema": "CAPABILITY_SELECTOR_COMPOSITION_V2",
        "selected_capabilities": base["selected_capabilities"],
        "method_requirements": selected_methods,
        "composition_order": composition,
        "reason": base["reasons"],
        "estimated_cost": {"method_cost_points": total_cost, "budget_limit": max_cost},
        "escalation_conditions": escalations,
        "fallback_state": base["fallback_state"],
        "execution_authorized": False,
        "admission_required": True,
    }
