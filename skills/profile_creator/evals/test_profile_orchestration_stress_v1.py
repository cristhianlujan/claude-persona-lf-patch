#!/usr/bin/env python3
"""PE-ORCH-STRESS-V1: deterministic selector stress and explicit liveness audit.

Read-only. Synthetic preconditions are fixtures, not evidence of live execution.
Exit 3 with --require-live if method execution is unbound.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "sandbox/lf_contract_gate_test/transversal_assets"
sys.path.insert(0, str(BASE / "capability_selector"))
from capability_selector_v3 import compose_capabilities_v3, replan_composition

REGISTRY_PATH = BASE / "method_pack_registry/method_pack_registry_v2.json"
REGISTRY = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
CATALOG = [
    {"capability_code": "PACK_VALIDATION_HARNESS", "signal_type": "complexity",
     "accepted_values": ["HIGH"], "rank": 10, "state": "AVAILABLE"},
    {"capability_code": "INDEPENDENT_ASSURANCE", "signal_type": "risk",
     "accepted_values": ["HIGH", "CRITICAL"], "rank": 20, "state": "AVAILABLE"},
    {"capability_code": "TARGETED_EVIDENCE_ACQUISITION", "signal_type": "novelty",
     "accepted_values": ["HIGH"], "rank": 30, "state": "AVAILABLE"},
]
POLICY = {"fallback_capabilities": ["PACK_VALIDATION_HARNESS"]}


def verified(value):
    return {"value": value, "verification_state": "VERIFIED",
            "evidence_refs": ["fixture://synthetic-not-runtime-proof"]}


def run_case(name, context, conditions, expected, rejected=None):
    result = compose_capabilities_v3(
        {"budget": {"max_method_cost_points": 100}, **context},
        CATALOG, POLICY, REGISTRY,
        {key: verified(value) for key, value in conditions.items()},
    )
    found = {x["method_id"] for x in result["selected_methods"]}
    denied = {x["method_id"]: x["reason"] for x in result["rejected_methods"]}
    missing = set(expected) - found
    surprising = found - set(expected)
    rejection_errors = {
        k: (reason, denied.get(k)) for k, reason in (rejected or {}).items()
        if denied.get(k) != reason
    }
    assert not missing and not surprising and not rejection_errors, (
        name, sorted(found), sorted(expected), rejection_errors
    )
    assert result["execution_authorized"] is False
    return {"case": name, "selection": "PASS", "selected": sorted(found),
            "rejected": denied, "method_execution_observed": False,
            "fallback_state": result["fallback_state"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-live", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()
    cases = [
        run_case(
            "causal_and_adversarial",
            {"causal_requirement": "HIGH", "risk": "HIGH"},
            {"evidence_sufficiency": "SUFFICIENT", "candidate_exists": True},
            ["CAUSAL_ANALYSIS", "HOSTILE_CHALLENGE"]),
        run_case(
            "contradictory_authority_research",
            {"novelty": "HIGH", "uncertainty": "HIGH"},
            {"candidate_exists": True, "decision_can_change_with_external_evidence": True},
            ["DEEP_RESEARCH", "HOSTILE_CHALLENGE"]),
        run_case(
            "parallel_evidence_isolation",
            {"evidence_paths": "MULTIPLE_INDEPENDENT"},
            {"no_shared_mutable_state": True},
            ["PARALLEL_EVIDENCE_SEARCH"]),
        run_case(
            "complex_verify_and_refine",
            {"complexity": "HIGH"},
            {"candidate_exists": True, "grader_available": True,
             "deterministic_verifier_exists": True},
            ["SELF_REFINE", "VERIFIER_GUIDED_SEARCH"],
            {"REASONING_COMPOSITION_SEARCH": "EXPERIMENTAL_NOT_ADMITTED",
             "WORKFLOW_SEARCH": "EXPERIMENTAL_NOT_ADMITTED"}),
        run_case(
            "optimizer_matched_benchmark",
            {"optimization_need": "REQUIRED"},
            {"benchmark_exists": True, "uplift_target_defined": True},
            ["EVALUATOR_OPTIMIZER"],
            {"TEXTUAL_FEEDBACK_OPTIMIZATION": "EXPERIMENTAL_NOT_ADMITTED"}),
        run_case(
            "advanced_prompt_optimization",
            {"optimization_need": "ADVANCED"},
            {"benchmark_exists": True, "holdout_exists": True,
             "search_budget_approved": True},
            ["PROMPT_OPTIMIZATION"],
            {"TEXTUAL_FEEDBACK_OPTIMIZATION": "EXPERIMENTAL_NOT_ADMITTED"}),
        run_case(
            "unverified_precondition_fails_closed",
            {"causal_requirement": "HIGH"},
            {},
            [],
            {"CAUSAL_ANALYSIS": "PRECONDITION_UNKNOWN"}),
        run_case(
            "contradictory_precondition_fails_closed",
            {"causal_requirement": "HIGH"},
            {"evidence_sufficiency": "NONE"},
            [],
            {"CAUSAL_ANALYSIS": "PRECONDITION_FAIL"}),
        run_case(
            "method_cost_budget_gate",
            {"causal_requirement": "HIGH", "risk": "HIGH",
             "budget": {"max_method_cost_points": 2}},
            {"evidence_sufficiency": "SUFFICIENT", "candidate_exists": True},
            ["CAUSAL_ANALYSIS"],
            {"HOSTILE_CHALLENGE": "BUDGET_INSUFFICIENT"}),
        run_case(
            "semantic_text_without_typed_signals",
            {"task_description": "Conflicting sources: risk high; evidence uncertain"},
            {"candidate_exists": True}, [], {}),
        run_case("no_method_required", {"risk": "LOW"}, {}, []),
    ]
    prev = {"complexity": "HIGH", "selection_cycle": 0}
    pre = {"candidate_exists": verified(True), "grader_available": verified(True),
           "deterministic_verifier_exists": verified(True)}
    after = replan_composition(
        prev, {"trigger": "METHOD_FAILED", "method_id": "SELF_REFINE",
               "evidence_refs": ["fixture://failed-method"]},
        CATALOG, POLICY, REGISTRY, pre)
    assert after["status"] == "REPLANNED"
    assert after["new_cycle"] == 1
    assert after["blocked_methods_for_current_run"] == ["SELF_REFINE"]
    assert "VERIFIER_GUIDED_SEARCH" in {
        x["method_id"] for x in after["new_composition"]["selected_methods"]}
    assert "SELF_REFINE" not in {
        x["method_id"] for x in after["new_composition"]["selected_methods"]}
    cases.append({"case": "replanning_after_failed_method",
                  "selection": "PASS", "method_execution_observed": False})
    records = []
    for method in REGISTRY["methods"]:
        method_id = method["method_id"]
        runtime_fields = [name for name in
                          ("executor_entrypoint", "handler_ref", "execution_adapter_ref",
                           "execution_contract_ref") if method.get(name)]
        records.append({
            "method_id": method_id,
            "availability": method["availability_state"],
            "selectable": bool(method["auto_select"]),
            "selector_contract": "DEFINED",
            "runtime_binding": "DECLARED" if runtime_fields else "MISSING",
            "invocation_receipt": "NOT_OBSERVED",
        })
    result = {
        "schema": "PE_ORCHESTRATION_STRESS_V1",
        "scope": "SYNTHETIC_SELECTOR_TEST_NOT_END_TO_END_EXPERT_BENCHMARK",
        "selection_cases": len(cases),
        "selection_passed": len(cases),
        "methods_registered": len(records),
        "method_runtime_bindings_declared": sum(
            x["runtime_binding"] == "DECLARED" for x in records),
        "execution_permission": REGISTRY.get("execution_permission"),
        "real_method_invocations": 0,
        "selector_status": "PASS",
        "e2e_status": "BLOCKED_METHOD_EXECUTION_NOT_WIRED",
        "cutover_eligible": False,
        "cases": cases,
        "methods": records,
    }
    if args.output:
        Path(args.output).write_text(
            json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        key: value for key, value in result.items()
        if key not in {"cases", "methods"}}, sort_keys=True))
    if args.require_live and result["e2e_status"] != "PASS":
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
