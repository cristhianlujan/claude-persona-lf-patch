#!/usr/bin/env python3
"""RW1-02_C2 executable architecture-design benchmark validator.

Scope is deliberately architecture-contract evidence, not ACT-0001 runtime,
production behavior, latency, cost, or GOLDEN status.
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

SCHEMA = "RW102_ARCHITECTURE_COMPETITION_V1"
RESULT_SCHEMA = "RW102_ARCHITECTURE_COMPETITION_RESULT_V1"
EXPECTED_CANDIDATES = {
    "A_MIN_ROUTER_SEMANTIC_SPECIALIST",
    "B_MIN_CLASSIFIER_COMPOSITE_DERIVATION",
    "C_BOUNDED_SEMANTIC_ROUTER",
    "D_CURRENT_HYBRID_BASELINE",
}
ELIGIBLE = [
    "A_MIN_ROUTER_SEMANTIC_SPECIALIST",
    "B_MIN_CLASSIFIER_COMPOSITE_DERIVATION",
    "C_BOUNDED_SEMANTIC_ROUTER",
]
BASELINE = "D_CURRENT_HYBRID_BASELINE"
EXPECTED_NEEDS = {f"N{i:02d}" for i in range(1, 13)}
CAPABILITIES = {
    "preserve_literal",
    "discover_registered_responsibility",
    "semantic_normalization",
    "preserve_negation",
    "multi_goal_composition",
    "context_resolution",
    "material_clarification_only",
    "future_capability_gap",
    "role_separation",
    "no_effect_authority",
    "safe_readonly_continuity",
    "deterministic_authority",
    "simulation_no_effect",
    "typed_hint_non_authority",
    "train_technical_route_separation",
    "stale_currentness_fail_closed",
}
NOT_MEASURED = "NOT_MEASURED_NO_EQUIVALENT_IMPLEMENTATIONS"


def load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def evaluate_candidate(cand: dict, cases: list[dict]) -> dict:
    failures: list[dict] = []
    hops = 0.0
    continuity = 0
    extensibility = 0
    for case in cases:
        required = case["required_capabilities"]
        missing = [cap for cap in required if cand["capabilities"].get(cap) is not True]
        if missing:
            failures.append({"case_id": case["id"], "missing_capabilities": missing})
        passed = not missing
        if passed and "safe_readonly_continuity" in required:
            continuity += 1
        if passed and case["extensibility_case"] is True:
            extensibility += 1
        metrics = cand["structural_metrics"]
        hops += metrics["base_control_hops"]
        if case["semantic_complex"] is True:
            hops += metrics["semantic_extra_hops"]
    return {
        "cases_total": len(cases),
        "cases_passed": len(cases) - len(failures),
        "hard_failures": len(failures),
        "failed_cases": [row["case_id"] for row in failures],
        "missing_capabilities": sorted(
            {cap for row in failures for cap in row["missing_capabilities"]}
        ),
        "continuity_cases_passed": continuity,
        "extensibility_cases_passed": extensibility,
        "avg_control_hops": round(hops / len(cases), 3),
    }


def rank_key(name: str, doc: dict, scoreboard: dict) -> tuple:
    metrics = doc["candidates"][name]["structural_metrics"]
    return (
        scoreboard[name]["hard_failures"],
        metrics["core_router_semantic_rule_change_touches"],
        metrics["router_authority_decision_responsibilities"],
        metrics["new_shared_runtime_components"],
        scoreboard[name]["avg_control_hops"],
        name,
    )


def compute_result(doc: dict) -> dict:
    cases = doc["cases"]
    scoreboard = {
        name: evaluate_candidate(cand, cases)
        for name, cand in doc["candidates"].items()
    }
    hard_pass = [
        name
        for name in doc["selection_policy"]["eligible_candidates"]
        if scoreboard[name]["hard_failures"] == 0
    ]
    hard_pass = sorted(hard_pass, key=lambda n: rank_key(n, doc, scoreboard))
    return {
        "schema_version": RESULT_SCHEMA,
        "checkpoint_code": "RW1-02_C2",
        "scope": "EXECUTABLE_DESIGN_CONTRACT_BENCHMARK_NOT_ROUTER_RUNTIME",
        "corpus_cases": len(cases),
        "requirements_covered": sorted(
            {need for case in cases for need in case["needs"]}
        ),
        "candidate_count": len(doc["candidates"]),
        "eligible_candidate_count": len(
            doc["selection_policy"]["eligible_candidates"]
        ),
        "hard_pass_candidates": hard_pass,
        "scoreboard": scoreboard,
        "provisional_selection": hard_pass[0] if hard_pass else None,
        "selection_status": "PROVISIONAL_PENDING_INDEPENDENT_C3",
        "selection_reason": (
            "Zero hard failures first; among hard-pass eligible candidates, "
            "minimize core Router semantic-change blast radius, then Router "
            "authority-decision responsibilities, then new runtime components, "
            "then control-hop proxy. No latency/cost was invented."
        ),
        "actual_latency": NOT_MEASURED,
        "actual_cost": NOT_MEASURED,
        "no_router_runtime_claim": True,
        "no_production_mutation": True,
        "baseline_not_eligible": True,
    }


def validate_corpus(doc: dict) -> list[str]:
    errors: list[str] = []
    if doc.get("schema_version") != SCHEMA:
        errors.append("WRONG_SCHEMA")
    if doc.get("plan_code") != "LF_ROUTER_ARCHITECTURE_WAVE_V1":
        errors.append("WRONG_PLAN")
    if doc.get("unit_code") != "RW1-02" or doc.get("checkpoint_code") != "RW1-02_C2":
        errors.append("WRONG_CHECKPOINT")
    if doc.get("scope") != "EXECUTABLE_DESIGN_CONTRACT_BENCHMARK_NOT_ROUTER_RUNTIME":
        errors.append("WRONG_SCOPE")
    if doc.get("source_c1_blob") != "470979c9b9a0dd9a728601b6ec5f577d7445f8b5":
        errors.append("C1_SOURCE_BLOB_DRIFT")

    cases = doc.get("cases")
    if not isinstance(cases, list) or len(cases) != 36:
        errors.append("CASE_COUNT_NOT_36")
        cases = cases if isinstance(cases, list) else []
    ids = [c.get("id") for c in cases if isinstance(c, dict)]
    if len(ids) != len(set(ids)):
        errors.append("DUPLICATE_CASE_ID")
    if set(doc.get("requirements_expected", [])) != EXPECTED_NEEDS:
        errors.append("EXPECTED_NEEDS_NOT_N01_N12")
    covered = {
        need
        for case in cases
        if isinstance(case, dict)
        for need in case.get("needs", [])
    }
    if covered != EXPECTED_NEEDS:
        errors.append("ACTUAL_NEED_COVERAGE_NOT_N01_N12")

    candidates = doc.get("candidates")
    if not isinstance(candidates, dict) or set(candidates) != EXPECTED_CANDIDATES:
        errors.append("CANDIDATE_SET_WRONG")
        candidates = candidates if isinstance(candidates, dict) else {}

    policy = doc.get("selection_policy", {})
    if policy.get("eligible_candidates") != ELIGIBLE:
        errors.append("ELIGIBLE_CANDIDATES_DRIFT")
    if policy.get("baseline_eligible") is not False:
        errors.append("BASELINE_MUST_BE_INELIGIBLE")
    if policy.get("weights_forbidden") is not True or "weights" in policy:
        errors.append("WEIGHTS_FORBIDDEN")
    if policy.get("actual_latency") != NOT_MEASURED:
        errors.append("LATENCY_MUST_BE_NOT_MEASURED")
    if policy.get("actual_cost") != NOT_MEASURED:
        errors.append("COST_MUST_BE_NOT_MEASURED")
    expected_tiebreak = [
        "hard_failures_asc",
        "core_router_semantic_rule_change_touches_asc",
        "router_authority_decision_responsibilities_asc",
        "new_shared_runtime_components_asc",
        "avg_control_hops_asc",
    ]
    if policy.get("lexicographic_tiebreak") != expected_tiebreak:
        errors.append("TIEBREAK_DRIFT")

    inv = doc.get("hard_invariants", {})
    required_inv = [
        "router_owns_discovery_and_derivation",
        "semantic_specialist_is_not_router",
        "semantic_specialist_cannot_discover_workers",
        "semantic_specialist_cannot_route",
        "semantic_specialist_cannot_authorize_effect",
        "effect_authority_outside_router",
        "current_baseline_not_oracle",
        "no_production_mutation",
    ]
    if any(inv.get(k) is not True for k in required_inv):
        errors.append("HARD_INVARIANT_FALSE")

    for name, cand in candidates.items():
        if not isinstance(cand, dict):
            errors.append(f"{name}:CANDIDATE_NOT_OBJECT")
            continue
        if cand.get("eligible") is not (name != BASELINE):
            errors.append(f"{name}:ELIGIBILITY_WRONG")
        ccaps = cand.get("capabilities")
        if not isinstance(ccaps, dict) or set(ccaps) != CAPABILITIES:
            errors.append(f"{name}:CAPABILITY_SET_WRONG")
        elif any(type(v) is not bool for v in ccaps.values()):
            errors.append(f"{name}:CAPABILITY_NOT_BOOLEAN")
        m = cand.get("structural_metrics")
        if not isinstance(m, dict):
            errors.append(f"{name}:METRICS_NOT_OBJECT")
            continue
        for key in (
            "core_router_semantic_rule_change_touches",
            "router_authority_decision_responsibilities",
            "new_shared_runtime_components",
            "base_control_hops",
            "semantic_extra_hops",
        ):
            if type(m.get(key)) is not int or m[key] < 0:
                errors.append(f"{name}:BAD_METRIC:{key}")
        if name == "A_MIN_ROUTER_SEMANTIC_SPECIALIST":
            if m.get("router_internal_semantic_engine") is not False:
                errors.append("A:SEMANTIC_ENGINE_MUST_NOT_BE_IN_ROUTER")
            if m.get("specialist_can_discover_workers") is not False:
                errors.append("A:SPECIALIST_MUST_NOT_DISCOVER")
            if m.get("specialist_can_route") is not False:
                errors.append("A:SPECIALIST_MUST_NOT_ROUTE")
            if m.get("specialist_can_authorize_effect") is not False:
                errors.append("A:SPECIALIST_MUST_NOT_AUTHORIZE_EFFECT")

    for case in cases:
        if not isinstance(case, dict):
            errors.append("CASE_NOT_OBJECT")
            continue
        if not isinstance(case.get("literal_request"), str) or not case["literal_request"].strip():
            errors.append(f"{case.get('id')}:EMPTY_LITERAL")
        req = case.get("required_capabilities")
        if not isinstance(req, list) or not req or len(req) != len(set(req)):
            errors.append(f"{case.get('id')}:BAD_REQUIRED_CAPABILITIES")
        elif any(cap not in CAPABILITIES for cap in req):
            errors.append(f"{case.get('id')}:UNKNOWN_CAPABILITY")
        needs = case.get("needs")
        if not isinstance(needs, list) or not needs or any(n not in EXPECTED_NEEDS for n in needs):
            errors.append(f"{case.get('id')}:BAD_NEEDS")
        if type(case.get("semantic_complex")) is not bool:
            errors.append(f"{case.get('id')}:SEMANTIC_COMPLEX_NOT_BOOL")
        if type(case.get("extensibility_case")) is not bool:
            errors.append(f"{case.get('id')}:EXTENSIBILITY_NOT_BOOL")

    return errors


def validate_package(doc: dict, result: dict) -> tuple[list[str], dict]:
    errors = validate_corpus(doc)
    if errors:
        return errors, {}
    computed = compute_result(doc)
    if result != computed:
        errors.append("RESULT_NOT_EXACT_RECOMPUTATION")
    if computed.get("provisional_selection") != "A_MIN_ROUTER_SEMANTIC_SPECIALIST":
        errors.append("PROVISIONAL_SELECTION_NOT_A")
    if computed.get("hard_pass_candidates") != [
        "A_MIN_ROUTER_SEMANTIC_SPECIALIST",
        "C_BOUNDED_SEMANTIC_ROUTER",
    ]:
        errors.append("HARD_PASS_SET_DRIFT")
    if computed["scoreboard"][BASELINE]["hard_failures"] <= 0:
        errors.append("BASELINE_FALSE_HARD_PASS")
    return errors, computed


def self_test(doc: dict, result: dict) -> int:
    probes = []

    def add(name, mutate_doc=None, mutate_result=None):
        d = copy.deepcopy(doc)
        r = copy.deepcopy(result)
        if mutate_doc:
            mutate_doc(d)
        if mutate_result:
            mutate_result(r)
        errs, _ = validate_package(d, r)
        probes.append((name, bool(errs), errs[:3]))

    add("A_specialist_authorizes", lambda d: d["candidates"]["A_MIN_ROUTER_SEMANTIC_SPECIALIST"]["structural_metrics"].__setitem__("specialist_can_authorize_effect", True))
    add("A_specialist_discovers", lambda d: d["candidates"]["A_MIN_ROUTER_SEMANTIC_SPECIALIST"]["structural_metrics"].__setitem__("specialist_can_discover_workers", True))
    add("A_specialist_routes", lambda d: d["candidates"]["A_MIN_ROUTER_SEMANTIC_SPECIALIST"]["structural_metrics"].__setitem__("specialist_can_route", True))
    add("baseline_eligible", lambda d: d["selection_policy"].__setitem__("baseline_eligible", True))
    add("weights_allowed", lambda d: d["selection_policy"].__setitem__("weights_forbidden", False))
    add("invent_latency", lambda d: d["selection_policy"].__setitem__("actual_latency", 12.5))
    add("invent_cost", lambda d: d["selection_policy"].__setitem__("actual_cost", 0.04))
    add("duplicate_case", lambda d: d["cases"].append(copy.deepcopy(d["cases"][0])))
    add("drop_need_n12", lambda d: [c.__setitem__("needs", [n for n in c["needs"] if n != "N12"]) for c in d["cases"]])
    add("drop_capability_schema", lambda d: d["candidates"]["A_MIN_ROUTER_SEMANTIC_SPECIALIST"]["capabilities"].pop("preserve_negation"))
    add("A_loses_no_effect", lambda d: d["candidates"]["A_MIN_ROUTER_SEMANTIC_SPECIALIST"]["capabilities"].__setitem__("no_effect_authority", False))
    add("result_wrong_winner", mutate_result=lambda r: r.__setitem__("provisional_selection", "C_BOUNDED_SEMANTIC_ROUTER"))
    add("result_runtime_claim", mutate_result=lambda r: r.__setitem__("no_router_runtime_claim", False))
    add("result_latency_fabricated", mutate_result=lambda r: r.__setitem__("actual_latency", 10))
    add("tiebreak_reordered", lambda d: d["selection_policy"]["lexicographic_tiebreak"].reverse())
    add("hard_invariant_off", lambda d: d["hard_invariants"].__setitem__("effect_authority_outside_router", False))

    failed = [p for p in probes if not p[1]]
    if failed:
        print(json.dumps({"status": "SELF_TEST_FAILED", "failed": failed}, ensure_ascii=False))
        return 2
    print(json.dumps({
        "status": "RW102_C2_SELF_TEST_PASS",
        "negative_probes": len(probes),
        "all_rejected": True,
        "scope": "DESIGN_CONTRACT_ONLY_NOT_ROUTER_RUNTIME",
    }, ensure_ascii=False))
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: validate_rw102_architecture_competition_v1.py CORPUS RESULT [--self-test]", file=sys.stderr)
        return 2
    doc = load(sys.argv[1])
    result = load(sys.argv[2])
    errors, computed = validate_package(doc, result)
    if errors:
        print(json.dumps({"status": "FAIL", "errors": errors}, ensure_ascii=False))
        return 1
    if "--self-test" in sys.argv[3:]:
        return self_test(doc, result)
    print(json.dumps({
        "status": "RW102_C2_COMPETITION_PASS",
        "test_passed": True,
        "test_exit_code": 0,
        "corpus_cases": computed["corpus_cases"],
        "requirements_covered": len(computed["requirements_covered"]),
        "candidate_count": computed["candidate_count"],
        "eligible_candidate_count": computed["eligible_candidate_count"],
        "hard_pass_candidates": len(computed["hard_pass_candidates"]),
        "provisional_selection": computed["provisional_selection"],
        "baseline_not_eligible": computed["baseline_not_eligible"],
        "actual_latency_measured": False,
        "actual_cost_measured": False,
        "no_router_runtime_claim": computed["no_router_runtime_claim"],
        "no_production_mutation": computed["no_production_mutation"],
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
