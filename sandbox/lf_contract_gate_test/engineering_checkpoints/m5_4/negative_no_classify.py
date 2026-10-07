#!/usr/bin/env python3
import copy
import json
import sys

TEST_CODE = "ENG_M5_4_NEGATIVE_NO_CLASSIFY"
EXPECTED_WRITERS = {
    "fn_input_governance_bootstrap_materialize_v2",
    "fn_input_governance_curator_rebind_v1",
    "fn_input_governance_recurate_source_stale_v1",
    "fn_input_governance_recurate_v2",
}


def find_violations(payload):
    violations = []
    central = payload.get("central") or {}
    writers = payload.get("writers")
    allowed = set(payload.get("allowed_semantic_resolvers") or [])

    if central.get("core_normalization_present") is not True:
        violations.append({"reason": "CORE_NORMALIZATION_MISSING"})
    if central.get("normalizes_all_materialized_assessments") is not True:
        violations.append({"reason": "CORE_NORMALIZATION_NOT_APPLIED_TO_ALL_MATERIALIZED_ASSESSMENTS"})
    if central.get("semantic_plan_authority_bound") is not True:
        violations.append({"reason": "SEMANTIC_PLAN_AUTHORITY_NOT_BOUND"})
    if central.get("parallel_router_hit"):
        violations.append({"fn": central.get("f"), "reason": "PARALLEL_ROUTER_REFERENCE"})

    if not isinstance(writers, list):
        violations.append({"reason": "STRATEGY_WRITER_ROWS_INVALID"})
        return violations

    for row in writers:
        fn = row.get("f")
        if row.get("external_runtime_execute"):
            violations.append({"fn": fn, "reason": "STRATEGY_WRITER_RUNTIME_EXPOSED"})
        unauthorized = row.get("unauthorized_runtime_callers") or []
        if unauthorized:
            violations.append({"fn": fn, "callers": unauthorized, "reason": "STRATEGY_WRITER_UNAUTHORIZED_RUNTIME_CALLER"})
        if row.get("parallel_router_hit"):
            violations.append({"fn": fn, "reason": "PARALLEL_ROUTER_REFERENCE"})
        for resolver in row.get("resolver_refs") or []:
            if resolver not in allowed:
                violations.append({"fn": fn, "resolver": resolver, "reason": "RESOLVER_NOT_IN_REGISTRY"})
            else:
                violations.append({"fn": fn, "resolver": resolver, "reason": "SEMANTIC_RESOLVER_BYPASSES_CENTRAL_PLAN"})

    return violations


def emit(status, observed):
    print(json.dumps({"status": status, "test_code": TEST_CODE, "observed": observed}, sort_keys=True))
    raise SystemExit(0 if status == "PASS" else 1)


if len(sys.argv) != 2:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": False, "adversarial_case_executed": False,
        "reason": "LIVE_ARCHITECTURE_BUNDLE_REQUIRED",
    })

try:
    payload = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": False, "adversarial_case_executed": False,
        "reason": "LIVE_ARCHITECTURE_BUNDLE_INVALID", "detail": str(exc),
    })

if not isinstance(payload, dict) or not isinstance(payload.get("writers"), list):
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": False, "adversarial_case_executed": False,
        "reason": "LIVE_ARCHITECTURE_BUNDLE_SHAPE_INVALID",
    })

seen = {row.get("proname") for row in payload["writers"] if isinstance(row, dict)}
missing = sorted(EXPECTED_WRITERS - seen)
if missing:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": bool((payload.get("central") or {}).get("semantic_plan_authority_bound")),
        "adversarial_case_executed": False,
        "reason": "DECLARED_STRATEGY_WRITERS_MISSING", "missing": missing,
    })

# Adversarial sensitivity: exposing an internal writer to runtime must fail.
mutated = copy.deepcopy(payload)
mutated["writers"][0]["external_runtime_execute"] = True
if "STRATEGY_WRITER_RUNTIME_EXPOSED" not in {x.get("reason") for x in find_violations(mutated)}:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": True,
        "reason": "ADVERSARIAL_RUNTIME_EXPOSURE_NOT_DETECTED",
    })

# Adversarial sensitivity: removing Core normalization must fail.
mutated = copy.deepcopy(payload)
mutated.setdefault("central", {})["core_normalization_present"] = False
if "CORE_NORMALIZATION_MISSING" not in {x.get("reason") for x in find_violations(mutated)}:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": True,
        "reason": "ADVERSARIAL_CORE_BYPASS_NOT_DETECTED",
    })

bad = find_violations(payload)
if bad:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": bool((payload.get("central") or {}).get("semantic_plan_authority_bound")),
        "adversarial_case_executed": True,
        "canonical_exit_criterion": "No legacy authority escape: internal writers are runtime-inaccessible, every materialized assessment is normalized by deterministic_assess, semantic resolvers stay centralized/governed, and no parallel router exists",
        "violations": bad,
    })

legacy_seed_count = sum(1 for row in payload["writers"] if row.get("legacy_classify_seed"))
emit("PASS", {
    "test_passed": True,
    "test_exit_code": 0,
    "semantic_authority_bound": True,
    "adversarial_case_executed": True,
    "canonical_exit_criterion": "No legacy authority escape: internal writers are runtime-inaccessible, every materialized assessment is normalized by deterministic_assess, semantic resolvers stay centralized/governed, and no parallel router exists",
    "strategy_writer_count": len(EXPECTED_WRITERS),
    "contained_legacy_seed_count": legacy_seed_count,
    "runtime_exposed_writer_count": 0,
    "unauthorized_runtime_caller_count": 0,
    "parallel_router_count": 0,
})
