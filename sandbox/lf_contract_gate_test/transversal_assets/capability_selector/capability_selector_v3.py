from __future__ import annotations

from copy import deepcopy
from typing import Any

from capability_selector_v2 import build_selection_signals, _select_capabilities_multilabel

REPLAN_TRIGGERS={
    "NEW_EVIDENCE","METHOD_FAILED","QUALITY_PLATEAU","VERIFIER_REJECTED",
    "RISK_CHANGED","BUDGET_CHANGED","STOP_CONDITION_MET"
}

def _method_matches(method: dict[str,Any], signals: list[dict[str,Any]]) -> bool:
    for rule in method.get("signals",[]) if isinstance(method.get("signals"),list) else []:
        if not isinstance(rule,dict):
            continue
        t=rule.get("type"); accepted=rule.get("accepted_values",[])
        if any(s.get("type")==t and s.get("value") in accepted and s.get("status","OK")=="OK" for s in signals):
            return True
    return False

def _precondition_result(rule: dict[str,Any], state: dict[str,Any]) -> dict[str,Any]:
    key=rule.get("key")
    item=state.get(key) if isinstance(state,dict) else None
    if not isinstance(item,dict):
        return {"key":key,"status":"UNKNOWN","reason":"PRECONDITION_EVIDENCE_MISSING"}
    if rule.get("verification_required") is True:
        if item.get("verification_state")!="VERIFIED" or not isinstance(item.get("evidence_refs"),list) or not item.get("evidence_refs"):
            return {"key":key,"status":"UNKNOWN","reason":"PRECONDITION_NOT_VERIFIED"}
    actual=item.get("value")
    op=rule.get("operator","EQ"); expected=rule.get("expected")
    ok=(actual==expected) if op=="EQ" else (actual!=expected if op=="NE" else False)
    return {"key":key,"status":"PASS" if ok else "FAIL","actual":actual,"expected":expected,"operator":op,"evidence_refs":item.get("evidence_refs",[])}

def verify_method_preconditions(method: dict[str,Any], state: dict[str,Any]) -> dict[str,Any]:
    results=[_precondition_result(r,state) for r in method.get("precondition_contract",[]) if isinstance(r,dict)]
    status="PASS" if all(x["status"]=="PASS" for x in results) else ("FAIL" if any(x["status"]=="FAIL" for x in results) else "UNKNOWN")
    return {"method_id":method.get("method_id"),"status":status,"checks":results}

def _method_cost(method: dict[str,Any], context: dict[str,Any]) -> tuple[float,str]:
    obs=context.get("method_cost_observations",{})
    item=obs.get(method.get("method_id")) if isinstance(obs,dict) else None
    if isinstance(item,dict) and item.get("verification_state")=="VERIFIED" and isinstance(item.get("cost_points_equivalent"),(int,float)) and not isinstance(item.get("cost_points_equivalent"),bool):
        return float(item["cost_points_equivalent"]),"OBSERVED"
    cost=method.get("cost_points",0)
    return float(cost) if isinstance(cost,(int,float)) and not isinstance(cost,bool) else 0.0,"ESTIMATE_ONLY"

def compose_capabilities_v3(
    context: dict[str,Any],
    catalog: list[dict[str,Any]],
    policy: dict[str,Any],
    method_registry: dict[str,Any],
    precondition_state: dict[str,Any],
) -> dict[str,Any]:
    signals=build_selection_signals(context)
    base=_select_capabilities_multilabel(signals,catalog,policy)
    methods=method_registry.get("methods",[]) if isinstance(method_registry,dict) else []
    budget=context.get("budget",{}) if isinstance(context.get("budget"),dict) else {}
    max_cost=budget.get("max_method_cost_points")
    allow_experimental=bool(context.get("allow_experimental_methods",False))
    blocked=set(context.get("blocked_methods",[])) if isinstance(context.get("blocked_methods"),list) else set()

    selected=[]; rejected=[]; total=0.0
    for method in methods if isinstance(methods,list) else []:
        if not isinstance(method,dict) or not _method_matches(method,signals):
            continue
        mid=method.get("method_id")
        if mid in blocked:
            rejected.append({"method_id":mid,"reason":"BLOCKED_FOR_CURRENT_RUN"})
            continue
        if method.get("availability_state")=="EXPERIMENTAL_NOT_ADMITTED" and not allow_experimental:
            rejected.append({"method_id":mid,"reason":"EXPERIMENTAL_NOT_ADMITTED"})
            continue
        if method.get("auto_select") is False and not allow_experimental:
            rejected.append({"method_id":mid,"reason":"AUTO_SELECT_DISABLED"})
            continue
        pre=verify_method_preconditions(method,precondition_state)
        if pre["status"]!="PASS":
            rejected.append({"method_id":mid,"reason":"PRECONDITION_"+pre["status"],"preconditions":pre})
            continue
        cost,cost_status=_method_cost(method,context)
        if max_cost is not None and total+cost>float(max_cost):
            rejected.append({"method_id":mid,"reason":"BUDGET_INSUFFICIENT","cost":cost,"cost_status":cost_status})
            continue
        selected.append({
            "method_id":mid,"cost_points":cost,"cost_status":cost_status,
            "precondition_receipt":pre,
            "stop_conditions":method.get("stop_conditions",[]),
            "validation_method":method.get("validation_method"),
            "availability_state":method.get("availability_state")
        })
        total+=cost

    composition=list(base["selected_capabilities"])
    by_id={m.get("method_id"):m for m in methods if isinstance(m,dict)}
    for sm in selected:
        for cap in by_id.get(sm["method_id"],{}).get("compatible_capabilities",[]):
            if isinstance(cap,str) and cap not in composition:
                composition.append(cap)

    return {
        "schema":"CAPABILITY_SELECTOR_COMPOSITION_V3",
        "selection_cycle":int(context.get("selection_cycle",0)),
        "selected_capabilities":base["selected_capabilities"],
        "selected_methods":selected,
        "rejected_methods":rejected,
        "composition_order":composition,
        "reason":base["reasons"],
        "estimated_or_observed_cost":{"method_cost_points":total,"budget_limit":max_cost},
        "fallback_state":base["fallback_state"],
        "execution_authorized":False,
        "admission_required":True,
        "replan_allowed":True,
    }

def replan_composition(
    previous_context: dict[str,Any],
    observation: dict[str,Any],
    catalog: list[dict[str,Any]],
    policy: dict[str,Any],
    method_registry: dict[str,Any],
    precondition_state: dict[str,Any],
) -> dict[str,Any]:
    if not isinstance(observation,dict) or observation.get("trigger") not in REPLAN_TRIGGERS:
        return {"schema":"CAPABILITY_SELECTOR_REPLAN_V1","status":"BLOCKED","blocking_codes":["REPLAN_TRIGGER_INVALID"]}
    refs=observation.get("evidence_refs")
    if not isinstance(refs,list) or not refs:
        return {"schema":"CAPABILITY_SELECTOR_REPLAN_V1","status":"BLOCKED","blocking_codes":["REPLAN_EVIDENCE_REQUIRED"]}

    context=deepcopy(previous_context)
    updates=observation.get("signal_updates",{})
    if isinstance(updates,dict):
        context.update(updates)
    context["selection_cycle"]=int(previous_context.get("selection_cycle",0))+1
    blocked=set(context.get("blocked_methods",[])) if isinstance(context.get("blocked_methods"),list) else set()
    method_id=observation.get("method_id")
    if observation.get("trigger") in {"METHOD_FAILED","QUALITY_PLATEAU","VERIFIER_REJECTED","STOP_CONDITION_MET"} and isinstance(method_id,str) and method_id:
        blocked.add(method_id)
    context["blocked_methods"]=sorted(blocked)

    result=compose_capabilities_v3(context,catalog,policy,method_registry,precondition_state)
    return {
        "schema":"CAPABILITY_SELECTOR_REPLAN_V1",
        "status":"REPLANNED",
        "trigger":observation["trigger"],
        "evidence_refs":refs,
        "previous_cycle":int(previous_context.get("selection_cycle",0)),
        "new_cycle":context["selection_cycle"],
        "blocked_methods_for_current_run":sorted(blocked),
        "new_composition":result,
        "persistent_learning_authorized":False,
    }
