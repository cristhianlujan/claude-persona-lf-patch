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
    """Compose advisory methods using v1 signal selection, not execution authority.

    A method may enter composition only when its preconditions and evidence
    have caller-supplied references. Such refs are *not* source attestations.
    An upstream authority resolver must independently verify them.
    """
    signals = build_selection_signals(context)
    base = _select_capabilities_multilabel(signals, catalog, policy)

    def fail(code: str) -> dict[str, Any]:
        return {
            "schema": "CAPABILITY_SELECTOR_COMPOSITION_V2",
            "selected_capabilities": [], "method_requirements": [],
            "composition_order": [], "reason": [{"code": code}],
            "estimated_cost": {"method_cost_points": 0, "budget_limit": None},
            "escalation_conditions": [], "fallback_state": "CAPABILITY_FAILURE",
            "execution_authorized": False, "admission_required": True,
            "selection_evidence_authority": "CALLER_DECLARED_UNVERIFIED",
        }

    if (not isinstance(method_registry, dict)
        or method_registry.get("schema_version") != "METHOD_PACK_REGISTRY_V1"
        or method_registry.get("execution_permission") is not False
        or not isinstance(method_registry.get("methods"), list)):
        return fail("METHOD_REGISTRY_INVALID_OR_UNAUTHORIZED")
    methods = method_registry["methods"]
    seen: set[str] = set()
    for method in methods:
        if not isinstance(method, dict):
            return fail("METHOD_RECORD_INVALID")
        mid = method.get("method_id")
        if not isinstance(mid, str) or not mid or mid in seen:
            return fail("METHOD_ID_MISSING_OR_DUPLICATE")
        seen.add(mid)
        if (not isinstance(method.get("signals"), list)
            or not isinstance(method.get("preconditions"), list)
            or not isinstance(method.get("evidence_required"), list)
            or not isinstance(method.get("compatible_capabilities"), list)
            or not isinstance(method.get("stop_conditions"), list)
            or not isinstance(method.get("escalation"), list)):
            return fail("METHOD_CONTRACT_INVALID")

    budget = context.get("budget", {})
    if not isinstance(budget, dict):
        return fail("METHOD_BUDGET_INVALID")
    max_cost = budget.get("max_method_cost_points")
    if max_cost is not None and (type(max_cost) not in (int, float) or max_cost < 0):
        return fail("METHOD_BUDGET_INVALID")
    verified_preconditions = context.get("precondition_evidence", {})
    verified_evidence = context.get("method_evidence", {})
    if not isinstance(verified_preconditions, dict) or not isinstance(verified_evidence, dict):
        return fail("METHOD_EVIDENCE_BINDING_INVALID")
    valid_ref = lambda value: isinstance(value, str) and bool(value.strip())

    # Contradictory/failed capability evidence must not enable optional methods.
    if base["fallback_state"] in {"CONTRADICTORY", "CAPABILITY_FAILURE"}:
        return {
            **fail("BASE_" + base["fallback_state"]),
            "selected_capabilities": base["selected_capabilities"],
            "reason": base["reasons"],
            "fallback_state": base["fallback_state"],
        }

    total_cost = 0
    selected_methods: list[dict[str, Any]] = []
    composition = list(base["selected_capabilities"])
    known_capabilities = {
        item["capability_code"] for item in catalog
        if isinstance(item, dict) and isinstance(item.get("capability_code"), str)
        and item.get("state", "AVAILABLE") == "AVAILABLE"
    }
    escalations = []
    for method in methods:
        if not _method_matches(method, signals):
            continue
        cost = method.get("cost_points")
        if type(cost) not in (int, float) or cost < 0:
            return fail("METHOD_COST_INVALID")
        preconditions = method["preconditions"]
        evidence_required = method["evidence_required"]
        if any(not isinstance(x, str) or not x for x in preconditions + evidence_required):
            return fail("METHOD_EVIDENCE_CONTRACT_INVALID")
        missing_preconditions = [p for p in preconditions if not valid_ref(verified_preconditions.get(p))]
        missing_evidence = [e for e in evidence_required if not valid_ref(verified_evidence.get(e))]
        eligible = not missing_preconditions and not missing_evidence
        within_budget = eligible and (max_cost is None or total_cost + cost <= max_cost)
        selected_methods.append({
            "method_id": method["method_id"], "cost_points": cost,
            "within_budget": within_budget,
            "preconditions": preconditions,
            "stop_conditions": method["stop_conditions"],
            "validation_method": method.get("validation_method"),
            "missing_preconditions": missing_preconditions,
            "missing_evidence": missing_evidence,
            "eligible_for_composition": eligible and within_budget,
        })
        if not eligible:
            continue
        if not within_budget:
            escalations.append({"method_id": method["method_id"], "condition": "BUDGET_INSUFFICIENT"})
            continue
        total_cost += cost
        for cap in method["compatible_capabilities"]:
            if isinstance(cap, str) and cap in known_capabilities and cap not in composition:
                composition.append(cap)
        for target in method["escalation"]:
            if isinstance(target, str) and target:
                escalations.append({"from": method["method_id"], "to": target,
                                    "condition": "STOP_CONDITION_UNMET_OR_EVIDENCE_REQUIRES_ESCALATION"})

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
        "selection_evidence_authority": "CALLER_DECLARED_UNVERIFIED",
    }
