"""Non-authority reconciliation of model answer against independently verified method plan."""
from __future__ import annotations
from typing import Any,Callable


def reconcile_profile_answer(
    method_plan: dict[str,Any],model_answer:dict[str,Any],*,
    verify_plan:Callable[[dict[str,Any]],bool]|None,
) -> dict[str,Any]:
    out={"schema":"PROFILE_METHOD_DECISION_GATE_V1","status":"BLOCKED",
         "publication_authorized":False,"production_authorized":False,
         "cutover_eligible":False}
    if not isinstance(method_plan,dict) or not isinstance(model_answer,dict) or not callable(verify_plan):
        return {**out,"reason":"METHOD_PLAN_OR_MODEL_ANSWER_INVALID"}
    try: ok=verify_plan(method_plan) is True
    except Exception:ok=False
    if not ok or method_plan.get("status")!="TEST_ONLY_RECONCILED" or method_plan.get("causality_proven") is not False:
        return {**out,"reason":"METHOD_PLAN_NOT_VERIFIED"}
    required={"decision","falsified","causality_proven"}
    if not required.issubset(model_answer):
        return {**out,"reason":"MODEL_ANSWER_MISSING_FIELDS"}
    reasons=[]
    if model_answer["decision"]!=method_plan.get("recommended_action"):
        reasons.append("ACTION_CONTRADICTION")
    if not isinstance(model_answer["falsified"],list) or sorted(model_answer["falsified"])!=method_plan.get("falsified_hypotheses"):
        reasons.append("FALSIFICATION_CONTRADICTION")
    if model_answer["causality_proven"] is not False:
        reasons.append("CAUSALITY_OVERCLAIM")
    if reasons:
        return {**out,"reason":"MODEL_CONTRADICTS_VERIFIED_METHOD",
                "blocking_codes":reasons,
                "verified_method_action":method_plan["recommended_action"],
                "next_step":"REGENERATE_EXPLANATION_FROM_TYPED_METHOD_RESULT",
                "model_output_admitted":False}
    return {**out,"status":"TEST_ONLY_RECONCILED",
        "reason":"MODEL_MATCHES_VERIFIED_METHOD",
        "verified_method_action":method_plan["recommended_action"],
        "admitted_test_only_explanation":model_answer.get("reason"),
        "model_output_admitted":True,
        "publication_authorized":False}
