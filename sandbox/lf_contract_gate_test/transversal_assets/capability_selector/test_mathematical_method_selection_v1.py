"""Contract tests: mathematical selection must improve V3 choices, never execute drafts."""
import json
from pathlib import Path

from capability_selector_v3 import compose_capabilities_v3, replan_composition

REG = json.loads((Path(__file__).resolve().parent.parent /
                  "method_pack_registry" / "method_pack_registry_v2.json").read_text())
MATH = set(REG["math_extension"]["method_ids"])


def verified(value):
    return {"value": value, "verification_state": "VERIFIED",
            "evidence_refs": ["evidence://bounded-observation"]}


def preconditions():
    evidence = {p["key"]: verified(p["expected"]) for m in REG["methods"]
                if m["method_id"] in MATH for p in m["precondition_contract"]}
    evidence.update({key: verified(True) for key in (
        "candidate_exists", "grader_available", "benchmark_exists",
        "uplift_target_defined", "deterministic_verifier_exists")})
    return evidence


def evaluate(context, pre=None):
    catalog = [{
        "capability_code": "CURRENTNESS_AUTHORITY", "signal_type": "risk",
        "accepted_values": ["LOW"], "rank": 1, "state": "AVAILABLE"
    }]
    return compose_capabilities_v3(context, catalog,
                                   {"fallback_capabilities": ["CURRENTNESS_AUTHORITY"]},
                                   REG, preconditions() if pre is None else pre)


def math_plan(result):
    return result["mathematical_method_selection"]


def run():
    assert len(MATH) == 5

    # Simple request must not lead to speculative mathematical composition.
    no = evaluate({"risk": "LOW", "complexity": "LOW"})
    assert math_plan(no)["status"] == "NO_MATHEMATICAL_METHOD_NEEDED"
    assert math_plan(no)["recommended_trials"] == []
    assert not any(m["method_id"] in MATH for m in no["selected_methods"])

    # Typed causal signal with sufficient independent evidence -> causal graph trial.
    causal = {"causal_requirement": "HIGH", "risk": "LOW"}
    yes = evaluate(causal)
    assert [x["method_id"] for x in math_plan(yes)["recommended_trials"]] == ["CAUSAL_GRAPH_ANALYSIS"]
    assert math_plan(yes)["recommended_trials"][0]["selection_state"] == "SHADOW_TRIAL_ONLY"
    assert "CAUSAL_EFFECT_LINEAGE" not in yes["composition_order"]
    assert not math_plan(yes)["execution_authorized"]

    # A causal signal without verified graph evidence must not be recommended.
    unverified = preconditions()
    unverified["material_graph_bound"] = {
        "value": True, "verification_state": "UNKNOWN", "evidence_refs": []}
    blocked = math_plan(evaluate(causal, unverified))
    assert blocked["status"] == "EVIDENCE_REQUIRED"
    assert any(x["method_id"] == "CAUSAL_GRAPH_ANALYSIS" and
               x["reason"] == "PRECONDITION_UNKNOWN" for x in blocked["rejected"])

    # Normal-method selection cannot depend on the catalog declaration order.
    # A shared budget must be allocated by typed relevance, not first match.
    normal_ctx = {"complexity": "HIGH", "optimization_need": "REQUIRED",
                  "budget": {"max_method_cost_points": 7}}
    base_r = evaluate(normal_ctx)
    reversed_registry = {**REG, "methods": list(reversed(REG["methods"]))}
    reversed_r = compose_capabilities_v3(
        normal_ctx, [], {"fallback_capabilities": ["CURRENTNESS_AUTHORITY"]},
        reversed_registry, preconditions())
    assert [x["method_id"] for x in base_r["selected_methods"]] == [
        x["method_id"] for x in reversed_r["selected_methods"]]
    assert len(base_r["selected_methods"]) >= 2, base_r
    assert all("matched_signal_types" in x for x in base_r["selected_methods"])

    # Five separate task shapes cause five different math trial recommendations.
    cases = [
        ({"causal_requirement": "REQUIRED"}, "CAUSAL_GRAPH_ANALYSIS"),
        ({"repeated_pattern": True}, "OCHIAI_SUSPICIOUSNESS"),
        ({"evidence_paths": "MULTIPLE_INDEPENDENT"}, "RECIPROCAL_RANK_FUSION"),
        ({"profile_gaps": ["MINIMIZE_REPRODUCIBLE_FAILURE"]}, "DELTA_DEBUGGING"),
        ({"optimization_need": "REQUIRED"}, "MCNEMAR_AND_CONFIDENCE_INTERVALS"),
    ]
    for ctx, method in cases:
        result = math_plan(evaluate(ctx))
        assert [m["method_id"] for m in result["recommended_trials"]] == [method], (ctx, result)
        assert not result["execution_authorized"]

    # Stronger matched evidence wins without magic domain-name routing.
    mix = {"complexity": "HIGH", "optimization_need": "REQUIRED",
           "repeated_pattern": True, "evidence_paths": "MULTIPLE_INDEPENDENT",
           "causal_requirement": "HIGH",
           "profile_gaps": ["MINIMIZE_REPRODUCIBLE_FAILURE"],
           "allow_experimental_methods": True,
           "budget": {"max_method_cost_points": 10}}
    selected = evaluate(mix)
    shadow = math_plan(selected)
    assert [m["method_id"] for m in shadow["recommended_trials"]] == ["DELTA_DEBUGGING"], shadow
    assert not any(m["method_id"] in MATH for m in selected["selected_methods"])
    assert all(m["method_id"] not in MATH or m.get("selection_state") == "SHADOW_TRIAL_ONLY"
               for m in shadow["recommended_trials"])

    # Surgical C19/C20 decision closure. Exercise all relevant normal methods
    # with verified fixture fields (not provider-attested task outcomes).
    full_pre = preconditions()
    for method in REG["methods"]:
        if method["availability_state"] == "EXPERIMENTAL_NOT_ADMITTED":
            continue
        for rule in method.get("precondition_contract", []):
            if rule["key"] not in full_pre:
                value = rule["expected"] if rule["operator"] == "EQ" else "SUFFICIENT"
                full_pre[rule["key"]] = verified(value)
    c19 = dict(mix, allow_experimental_methods=False,
               budget={"max_method_cost_points": 15})
    r19 = evaluate(c19, full_pre)
    expected_normal = [
        "CAUSAL_ANALYSIS", "SELF_REFINE",
        "PARALLEL_EVIDENCE_SEARCH", "EVALUATOR_OPTIMIZER",
    ]
    assert [m["method_id"] for m in r19["selected_methods"]] == expected_normal, r19
    deferred = [m for m in r19["rejected_methods"]
                if m["reason"] == "DEFERRED_NO_MARGINAL_TASK_SIGNAL"]
    assert len(deferred) == 1 and deferred[0]["method_id"] == "VERIFIER_GUIDED_SEARCH"
    assert deferred[0]["already_covered_by"] == ["SELF_REFINE"]
    assert r19["estimated_or_observed_cost"]["method_cost_points"] == 12
    assert [m["method_id"] for m in math_plan(r19)["recommended_trials"]] == ["DELTA_DEBUGGING"]
    assert not r19["execution_authorized"] and not math_plan(r19)["execution_authorized"]

    c20 = dict(c19, method_effectiveness_observations={
        "MCNEMAR_AND_CONFIDENCE_INTERVALS": {
            "verification_state": "VERIFIED", "evidence_refs": ["fixture://self-report"],
            "paired_quality_delta": .99, "critical_regressions": 0,
            "independent_holdout_verified": True,
        }
    })
    r20 = evaluate(c20, full_pre)
    assert [m["method_id"] for m in r20["selected_methods"]] == expected_normal
    assert [m["method_id"] for m in math_plan(r20)["recommended_trials"]] == ["DELTA_DEBUGGING"]
    assert len([m for m in r20["rejected_methods"]
                if m["reason"] == "DEFERRED_NO_MARGINAL_TASK_SIGNAL"]) == 1
    assert r20["estimated_or_observed_cost"]["method_cost_points"] == 12

    # Explicit budget can allow several independent trials but cannot authorize them.
    budgeted = dict(mix, budget={
        "max_method_cost_points": 10, "max_shadow_method_trials": 2,
        "max_shadow_method_cost_points": 3})
    two = math_plan(evaluate(budgeted))
    assert len(two["recommended_trials"]) == 2, two
    assert two["planned_cost_points"] <= 3
    assert not two["execution_authorized"]

    # Verified repeated critical regression removes a previously attractive method.
    history = {
        "DELTA_DEBUGGING": {
            "verification_state": "VERIFIED",
            "evidence_refs": ["judge://critical"],
            "paired_quality_delta": 0.5,
            "critical_regressions": 1,
            "independent_holdout_verified": True
        }
    }
    reg = math_plan(evaluate(dict(mix, method_effectiveness_observations=history)))
    assert not any(m["method_id"] == "DELTA_DEBUGGING" for m in reg["recommended_trials"])
    assert any(x["reason"] == "REGRESSION" for x in reg["rejected"])

    # Replanning with method failure blocks that method for the current run.
    replanned = replan_composition(
        causal,
        {"trigger": "METHOD_FAILED", "method_id": "CAUSAL_GRAPH_ANALYSIS",
         "evidence_refs": ["judge://rejected"]},
        [], {"fallback_capabilities": ["CURRENTNESS_AUTHORITY"]}, REG, preconditions())
    assert replanned["status"] == "REPLANNED"
    assert "CAUSAL_GRAPH_ANALYSIS" in replanned["blocked_methods_for_current_run"]
    assert not math_plan(replanned["new_composition"])["recommended_trials"]

    # Unauthenticated reported positive uplift cannot outrank stronger signal fit.
    claimed = dict(mix, method_effectiveness_observations={
        "MCNEMAR_AND_CONFIDENCE_INTERVALS": {
            "verification_state": "VERIFIED",
            "evidence_refs": ["self-reported://not-authenticated"],
            "paired_quality_delta": 0.99,
            "critical_regressions": 0,
            "independent_holdout_verified": True
        }
    })
    claim_result = math_plan(evaluate(claimed))
    assert claim_result["recommended_trials"][0]["method_id"] == "DELTA_DEBUGGING"
    assert any(x["effectiveness"]["state"] == "REPORTED_POSITIVE_UNATTESTED"
               for x in claim_result["recommended_trials"]) is False

    # Invalid base capability catalog is an authoritative failure, not a
    # reason to recommend mathematical experiments.
    failed_base = compose_capabilities_v3(causal,
        [{"capability_code": None, "signal_type": "risk",
          "accepted_values": ["LOW"], "state": "AVAILABLE"}],
        {"fallback_capabilities": []}, REG, preconditions())
    assert failed_base["fallback_state"] == "CAPABILITY_FAILURE"
    assert failed_base["selected_methods"] == []
    assert math_plan(failed_base)["status"] == "BLOCK"

    # The unknown outcome of an unavailable method must not be counted as PASS.
    unproven = dict(mix, method_effectiveness_observations={
        "DELTA_DEBUGGING": {"verification_state": "UNKNOWN",
            "evidence_refs": ["unknown://report"], "paired_quality_delta": 0.9,
            "critical_regressions": 0, "independent_holdout_verified": True}
    })
    assert math_plan(evaluate(unproven))["recommended_trials"][0]["effectiveness"]["state"] == "UNPROVEN"

    invalid = math_plan(evaluate(dict(causal, budget={"max_shadow_method_cost_points": -1})))
    assert invalid["status"] == "BLOCK" and not invalid["execution_authorized"]
    assert math_plan(evaluate(dict(causal, budget={"max_shadow_method_trials": True})))["status"] == "BLOCK"
    invalid_exclusion = math_plan(evaluate(dict(causal, blocked_methods=[7])))
    assert invalid_exclusion["status"] == "BLOCK"
    assert invalid_exclusion["recommended_trials"] == []


    print("PASS_CAPABILITY_SELECTOR_MATH_V3 five_task_types=5 "
          "simple_no_math=1 verified_preconditions=1 cost_budget=1 "
          "history_regression=1 replan=1 no_auto_experiment=1")


if __name__ == "__main__":
    run()
