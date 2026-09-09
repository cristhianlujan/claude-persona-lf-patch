#!/usr/bin/env python3
from lf_ci_lane_router import classify


def check(name, paths, *, migration, input_gov, selftest, deep_shared, mode=None):
    got = classify(paths)
    expected = (migration, input_gov, selftest, deep_shared)
    actual = (
        got.migration_parity_required,
        got.input_governance_parity_required,
        got.ci_router_selftest_required,
        got.deep_shared,
    )
    assert actual == expected, (name, actual, expected, got)
    if mode is not None:
        assert got.mode == mode, (name, got.mode, mode)
    print(f"PASS {name}: mode={got.mode} migration={actual[0]} input_gov={actual[1]} selftest={actual[2]} deep_shared={actual[3]}")


def main():
    s30 = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml"
    migration = "supabase/migrations/20260909010101_lf_example.sql"
    input_migration = "supabase/migrations/20260909010102_input_governance_example.sql"
    workflow = ".github/workflows/lf-contract-check.yml"
    router = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    router_test = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py"

    check("s30_only", [s30], migration=False, input_gov=False, selftest=False, deep_shared=False, mode="S30_POLICY_ISOLATED")
    check("migration_only", [migration], migration=True, input_gov=False, selftest=False, deep_shared=False)
    check("input_governance_migration", [input_migration], migration=True, input_gov=True, selftest=False, deep_shared=False)
    check("migration_validator", ["sandbox/lf_contract_gate_test/lf_migration_source_parity.py"], migration=True, input_gov=False, selftest=False, deep_shared=False)
    check("input_governance_validator", ["sandbox/lf_contract_gate_test/input_governance_migration_parity_compact.py"], migration=False, input_gov=True, selftest=False, deep_shared=False)
    check("workflow_self_change", [workflow], migration=False, input_gov=False, selftest=True, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    check("router_self_change", [router, router_test], migration=False, input_gov=False, selftest=True, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    check("s30_plus_workflow", [s30, workflow], migration=False, input_gov=False, selftest=True, deep_shared=False)
    check("s30_plus_migration", [s30, migration], migration=True, input_gov=False, selftest=False, deep_shared=False)
    check("workflow_plus_migration", [workflow, migration], migration=True, input_gov=False, selftest=True, deep_shared=False)
    check("workflow_plus_input_migration", [workflow, input_migration], migration=True, input_gov=True, selftest=True, deep_shared=False)
    check("known_shared_non_specialized", ["sandbox/lf_contract_gate_test/pass_evidence_gate.py"], migration=False, input_gov=False, selftest=False, deep_shared=False, mode="DEEP_SHARED_KNOWN")
    check("unknown_fail_closed", ["mystery/new_surface.xyz"], migration=True, input_gov=True, selftest=False, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("empty_fail_closed", [], migration=True, input_gov=True, selftest=True, deep_shared=True, mode="DEEP_SHARED_EMPTY_FAIL_CLOSED")
    print("CI_LANE_ROUTER_REGRESSIONS_PASS=14/14")


if __name__ == "__main__":
    main()
