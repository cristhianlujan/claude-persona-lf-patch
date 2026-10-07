#!/usr/bin/env python3
import copy
import json
import sys

TEST_CODE = "ENG_M5_4_NEGATIVE_NO_CLASSIFY"
EXPECTED_NAMES = {
    "fn_input_governance_curator_materialize_v1",
    "fn_input_governance_curator_rebind_v1",
    "fn_input_governance_bootstrap_materialize_v2",
    "fn_input_governance_recurate_source_stale_v1",
    "fn_input_governance_recurate_v2",
}


def find_violations(payload):
    rows = payload.get("functions")
    allowed = set(payload.get("allowed_semantic_resolvers") or [])
    violations = []
    if not isinstance(rows, list):
        return [{"reason": "FUNCTION_ROWS_INVALID"}]

    for row in rows:
        fn = row.get("f")
        if row.get("direct_classify_bypass"):
            violations.append({"fn": fn, "reason": "DIRECT_CLASSIFY_BYPASS"})
        if row.get("parallel_router_hit"):
            violations.append({"fn": fn, "reason": "PARALLEL_ROUTER_REFERENCE"})
        for resolver in row.get("resolver_refs") or []:
            if resolver not in allowed:
                violations.append({"fn": fn, "resolver": resolver, "reason": "RESOLVER_NOT_IN_REGISTRY"})
            elif not row.get("semantic_plan_boundary"):
                violations.append({"fn": fn, "resolver": resolver, "reason": "RESOLVER_OUTSIDE_SEMANTIC_PLAN_BOUNDARY"})

    if payload.get("semantic_plan_authority_bound") is not True:
        violations.append({"reason": "SEMANTIC_PLAN_AUTHORITY_NOT_BOUND"})
    return violations


def emit(status, observed):
    print(json.dumps({"status": status, "test_code": TEST_CODE, "observed": observed}, sort_keys=True))
    raise SystemExit(0 if status == "PASS" else 1)


if len(sys.argv) != 2:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": False,
        "adversarial_case_executed": False,
        "reason": "LIVE_ARCHITECTURE_BUNDLE_REQUIRED",
    })

try:
    payload = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": False,
        "adversarial_case_executed": False,
        "reason": "LIVE_ARCHITECTURE_BUNDLE_INVALID",
        "detail": str(exc),
    })

if not isinstance(payload, dict) or not isinstance(payload.get("functions"), list):
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": False,
        "adversarial_case_executed": False,
        "reason": "LIVE_ARCHITECTURE_BUNDLE_SHAPE_INVALID",
    })

seen = {row.get("proname") for row in payload["functions"] if isinstance(row, dict)}
missing = sorted(EXPECTED_NAMES - seen)
if missing:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": bool(payload.get("semantic_plan_authority_bound")),
        "adversarial_case_executed": False,
        "reason": "DECLARED_FUNCTIONS_MISSING",
        "missing": missing,
    })

# Sensitivity proof: a direct classifier bypass must be rejected.
mutated = copy.deepcopy(payload)
mutated["functions"][0]["direct_classify_bypass"] = True
if not find_violations(mutated):
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": bool(payload.get("semantic_plan_authority_bound")),
        "adversarial_case_executed": True,
        "reason": "ADVERSARIAL_CLASSIFY_BYPASS_NOT_DETECTED",
    })

# Sensitivity proof: a resolver outside the governed semantic-plan boundary must be rejected.
mutated = copy.deepcopy(payload)
allowed = mutated.get("allowed_semantic_resolvers") or []
if allowed:
    mutated["functions"][0]["resolver_refs"] = [allowed[0]]
    mutated["functions"][0]["semantic_plan_boundary"] = False
    reasons = {x.get("reason") for x in find_violations(mutated)}
    if "RESOLVER_OUTSIDE_SEMANTIC_PLAN_BOUNDARY" not in reasons:
        emit("FAIL", {
            "test_passed": False,
            "test_exit_code": 1,
            "semantic_authority_bound": bool(payload.get("semantic_plan_authority_bound")),
            "adversarial_case_executed": True,
            "reason": "ADVERSARIAL_RESOLVER_BOUNDARY_NOT_DETECTED",
        })

bad = find_violations(payload)
if bad:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": bool(payload.get("semantic_plan_authority_bound")),
        "adversarial_case_executed": True,
        "canonical_exit_criterion": "No direct classify bypass; semantic resolvers only from registry and inside semantic-plan boundary; no parallel router",
        "violations": bad,
    })

emit("PASS", {
    "test_passed": True,
    "test_exit_code": 0,
    "semantic_authority_bound": True,
    "adversarial_case_executed": True,
    "canonical_exit_criterion": "No direct classify bypass; semantic resolvers only from registry and inside semantic-plan boundary; no parallel router",
    "declared_function_count": len(EXPECTED_NAMES),
    "direct_classify_bypass_count": 0,
    "resolver_boundary_violation_count": 0,
    "parallel_router_count": 0,
})
