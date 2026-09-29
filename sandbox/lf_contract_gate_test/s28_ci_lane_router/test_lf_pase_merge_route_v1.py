#!/usr/bin/env python3
from __future__ import annotations

import copy

from lf_pase_merge_route_v1 import (
    PaseMergeRouteError,
    _sha256,
    build_merge_route,
    classify_route,
    load_registry,
    validate_registry,
)

checks = 0


def ok(condition: bool, label: str) -> None:
    global checks
    if not condition:
        raise AssertionError(label)
    checks += 1


def fails(fn, code: str) -> None:
    global checks
    try:
        fn()
    except PaseMergeRouteError as exc:
        if not str(exc).startswith(code):
            raise AssertionError(f"expected {code}, got {exc}") from exc
        checks += 1
        return
    raise AssertionError(f"expected failure {code}")


registry = load_registry()
validate_registry(registry)
checks += 1

plan = {
    "schema_version": "lf-ci-execution-plan/v2",
    "coverage_complete": True,
    "required_controls": ["LF_CONTRACT_CORE", "MIGRATION_SOURCE_PARITY"],
    "plan_sha256": "a" * 64,
}
enforcement = {
    "schema_version": "lf-pase-control-enforcement/v1",
    "authority": "CHANGESET_GOVERNANCE_LF_V1",
    "policy_id": "PASE_CONTROL_REPAIR_QUARANTINE_V1",
    "source_plan_sha256": plan["plan_sha256"],
    "required_controls": plan["required_controls"],
    "blocking_controls": ["LF_CONTRACT_CORE"],
    "observe_only_controls": ["MIGRATION_SOURCE_PARITY"],
    "repair_window_active": True,
    "manual_diagnostic_execution_allowed": True,
    "observe_only_results_cannot_block_merge": True,
    "no_applicability_reclassification": True,
    "structural_governance_fail_closed": True,
    "silent_reactivation_forbidden": True,
}
enforcement["result_sha256"] = _sha256(enforcement)
head = "b" * 40

# Normal product/docs change stays on the execution-plan route.
route = build_merge_route(
    plan=plan,
    enforcement=enforcement,
    head_sha=head,
    changed_paths=["docs/example.md"],
    registry=registry,
)
ok(route["mode"] == "EXECUTION_PLAN", "normal route mode")
ok(route["candidate_id"] is None, "normal route candidate absent")
ok(route["required_control_ids"] == ["LF_CONTRACT_CORE"], "route equals blocking subset")
ok(route["authority"] == "CHANGESET_GOVERNANCE_LF_V1", "route authority")
ok(len(route["source_revision"]) == 64, "route source revision")

# Known control-system surfaces are explicitly routed to independent qualification.
mode, candidate = classify_route(
    ["sandbox/lf_contract_gate_test/pase_merge_gate/pase_merge_gate_v1.py"],
    registry,
)
ok(mode == "CONTROL_SYSTEM_QUALIFICATION" and candidate == "PASE_MERGE_GATE_V1", "merge gate candidate")

mode, candidate = classify_route(
    [".github/workflows/lf-contract-check.yml"],
    registry,
)
ok(mode == "CONTROL_SYSTEM_QUALIFICATION" and candidate == "PASE_GITHUB_ENTRYPOINT_V1", "workflow candidate")

# The merge-route solution itself must beat the broader s28 Changeset Governance matcher.
mode, candidate = classify_route(
    ["sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_pase_merge_route_v1.py"],
    registry,
)
ok(mode == "CONTROL_SYSTEM_QUALIFICATION" and candidate == "PASE_MERGE_ROUTE_V1", "longest specific match")

# Other s28 mutations remain control-system changes owned by Changeset Governance.
mode, candidate = classify_route(
    ["sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"],
    registry,
)
ok(mode == "CONTROL_SYSTEM_QUALIFICATION" and candidate == "CHANGESET_GOVERNANCE_LF_V1", "s28 authority change")

# One PR cannot silently combine two independent control-system candidates.
fails(
    lambda: classify_route(
        [
            "sandbox/lf_contract_gate_test/pase_merge_gate/pase_merge_gate_v1.py",
            ".github/workflows/lf-contract-check.yml",
        ],
        registry,
    ),
    "FAIL_PASE_ROUTE_MULTIPLE_CONTROL_SYSTEM_CANDIDATES",
)

# Exact-head and trusted enforcement are mandatory.
fails(
    lambda: build_merge_route(
        plan=plan,
        enforcement=enforcement,
        head_sha="bad",
        changed_paths=["docs/example.md"],
        registry=registry,
    ),
    "FAIL_PASE_ROUTE_HEAD",
)

bad = copy.deepcopy(enforcement)
bad["source_plan_sha256"] = "c" * 64
bad_without_digest = dict(bad)
bad_without_digest.pop("result_sha256", None)
bad["result_sha256"] = _sha256(bad_without_digest)
fails(
    lambda: build_merge_route(
        plan=plan,
        enforcement=bad,
        head_sha=head,
        changed_paths=["docs/example.md"],
        registry=registry,
    ),
    "FAIL_PASE_ROUTE_ENFORCEMENT_PLAN_DRIFT",
)

bad = copy.deepcopy(enforcement)
bad["blocking_controls"] = ["MIGRATION_SOURCE_PARITY"]
bad["observe_only_controls"] = ["LF_CONTRACT_CORE"]
# Preserve a valid digest so the test targets policy partition semantics, not hashing.
bad_without_digest = dict(bad)
bad_without_digest.pop("result_sha256", None)
bad["result_sha256"] = _sha256(bad_without_digest)
route = build_merge_route(
    plan=plan,
    enforcement=bad,
    head_sha=head,
    changed_paths=["docs/example.md"],
    registry=registry,
)
ok(route["required_control_ids"] == ["MIGRATION_SOURCE_PARITY"], "route follows enforcement not applicability reclassification")

bad_registry = copy.deepcopy(registry)
bad_registry["authority"] = "OTHER"
fails(lambda: validate_registry(bad_registry), "FAIL_PASE_ROUTE_REGISTRY_AUTHORITY")

fails(lambda: classify_route([], registry), "FAIL_PASE_ROUTE_CHANGED_PATHS_EMPTY")
fails(lambda: classify_route(["../escape"], registry), "FAIL_PASE_ROUTE_CHANGED_PATH_INVALID")

print(f"PASS_PASE_MERGE_ROUTE_V1 checks={checks}")
