#!/usr/bin/env python3
from lf_ci_lane_router import classify


def check(name, paths, *, migration, input_gov, selftest, p0_external, deep_shared, mode=None):
    got = classify(paths)
    expected = (migration, input_gov, selftest, p0_external, deep_shared)
    actual = (
        got.migration_parity_required,
        got.input_governance_parity_required,
        got.ci_router_selftest_required,
        got.p0_exact_head_external_required,
        got.deep_shared,
    )
    assert actual == expected, (name, actual, expected, got)
    if mode is not None:
        assert got.mode == mode, (name, got.mode, mode)
    print(
        f"PASS {name}: mode={got.mode} migration={actual[0]} input_gov={actual[1]} "
        f"selftest={actual[2]} p0_external={actual[3]} deep_shared={actual[4]}"
    )


def main():
    s30 = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml"
    s30_self = "sandbox/lf_contract_gate_test/s30_self_governance/s30_a_prewrite_receipt.json"
    s30_self_receipt = "sandbox/lf_contract_gate_test/receipts/s30_a_self_governance_gate_v2.json"
    migration = "supabase/migrations/20260909010101_lf_example.sql"
    input_migration = "supabase/migrations/20260909010102_input_governance_example.sql"
    workflow = ".github/workflows/lf-contract-check.yml"
    validate_workflow = ".github/workflows/validate-lf-packs.yml"
    router = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    router_test = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py"
    entrypoint = "sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT.py"
    p0_helper = "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v2.py"
    p0_config = "sandbox/lf_contract_gate_test/p0_exact_head_real_source_v2.json"
    p0_broker = "supabase/functions/lf-p0-exact-head-evidence-broker-v2/index.ts"

    check("s30_only", [s30], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_POLICY_ISOLATED")
    check("s30_self_governance_only", [s30_self], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_SELF_GOVERNANCE_ISOLATED")
    check("s30_self_governance_receipt_only", [s30_self_receipt], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_SELF_GOVERNANCE_ISOLATED")
    check("migration_only", [migration], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False)
    check("input_governance_migration", [input_migration], migration=True, input_gov=True, selftest=False, p0_external=False, deep_shared=False)
    check("migration_validator", ["sandbox/lf_contract_gate_test/lf_migration_source_parity.py"], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False)
    check("input_governance_validator", ["sandbox/lf_contract_gate_test/input_governance_migration_parity_compact.py"], migration=False, input_gov=True, selftest=False, p0_external=False, deep_shared=False)
    check("workflow_self_change", [workflow], migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    check("validate_lf_packs_workflow_self_change", [validate_workflow], migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    check("router_self_change", [router, router_test], migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    check("entrypoint_control_change", [entrypoint], migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    check("p0_helper_requires_external", [p0_helper], migration=False, input_gov=False, selftest=False, p0_external=True, deep_shared=False, mode="SPECIALIZED_REQUIRED")
    check("p0_config_requires_external", [p0_config], migration=False, input_gov=False, selftest=False, p0_external=True, deep_shared=False, mode="SPECIALIZED_REQUIRED")
    check("p0_broker_requires_external", [p0_broker], migration=False, input_gov=False, selftest=False, p0_external=True, deep_shared=False, mode="SPECIALIZED_REQUIRED")
    check("supabase_config_requires_external", ["supabase/config.toml"], migration=False, input_gov=False, selftest=False, p0_external=True, deep_shared=False, mode="SPECIALIZED_REQUIRED")
    check("s30_plus_workflow", [s30, workflow], migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False)
    check("s30_plus_p0", [s30, p0_broker], migration=False, input_gov=False, selftest=False, p0_external=True, deep_shared=False)
    check("s30_plus_migration", [s30, migration], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False)
    check("workflow_plus_migration", [workflow, migration], migration=True, input_gov=False, selftest=True, p0_external=False, deep_shared=False)
    check("workflow_plus_input_migration", [workflow, input_migration], migration=True, input_gov=True, selftest=True, p0_external=False, deep_shared=False)
    check("known_shared_non_specialized", ["skills/learning_engine/validators/validate_pack.py"], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="DEEP_SHARED_KNOWN")

    real_s30a_delta = [
        validate_workflow,
        "gobernanza/contratos/s30_self_governance_gate_v1.json",
        "gobernanza/judges/validate_s30_self_governance_gate.py",
        s30_self_receipt,
        s30_self,
    ]
    check("s30a_real_delta_isolated", real_s30a_delta, migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")

    check("unknown_contract_gate_sandbox_fail_closed", ["sandbox/lf_contract_gate_test/new_unbound_validator.py"], migration=True, input_gov=True, selftest=False, p0_external=True, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("unknown_s30_receipt_sibling_fail_closed", ["sandbox/lf_contract_gate_test/receipts/s30_b_unbound.json"], migration=True, input_gov=True, selftest=False, p0_external=True, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("unknown_fail_closed", ["mystery/new_surface.xyz"], migration=True, input_gov=True, selftest=False, p0_external=True, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("empty_fail_closed", [], migration=True, input_gov=True, selftest=True, p0_external=True, deep_shared=True, mode="DEEP_SHARED_EMPTY_FAIL_CLOSED")
    print("CI_LANE_ROUTER_REGRESSIONS_PASS=26/26")


if __name__ == "__main__":
    main()
