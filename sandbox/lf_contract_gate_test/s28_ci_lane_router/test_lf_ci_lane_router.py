#!/usr/bin/env python3
from lf_ci_lane_router import classify


def check(name, paths, *, migration, input_gov, selftest, p0_external, deep_shared, mode=None):
    got = classify(paths)
    expected = (migration, input_gov, selftest, p0_external, deep_shared)
    actual = (got.migration_parity_required, got.input_governance_parity_required, got.ci_router_selftest_required, got.p0_exact_head_external_required, got.deep_shared)
    assert actual == expected, (name, actual, expected, got)
    if mode is not None:
        assert got.mode == mode, (name, got.mode, mode)


def main():
    s30 = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml"
    s30_self = "sandbox/lf_contract_gate_test/s30_self_governance/s30_a_prewrite_receipt.json"
    s30_self_receipt = "sandbox/lf_contract_gate_test/receipts/s30_a_self_governance_gate_v2.json"
    s30_data = "sandbox/lf_contract_gate_test/s30_data_access_candidate/data_access_registry_v2.json"
    s30_data_receipt = "sandbox/lf_contract_gate_test/receipts/s30_b_data_access_safety_v3.json"
    migration = "supabase/migrations/20260909010101_lf_example.sql"
    migration_transport_test = "sandbox/lf_contract_gate_test/test_lf_migration_source_parity_transport.py"
    s30d_c05 = "sandbox/lf_contract_gate_test/s30_d_final_r09/c05_source_persistence_closeout_v2.json"
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
    check("s30_data_access_only", [s30_data], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_DATA_ACCESS_ISOLATED")
    check("s30_data_access_receipt_only", [s30_data_receipt], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_DATA_ACCESS_ISOLATED")
    check("migration_only", [migration], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False)
    check("input_governance_migration", [input_migration], migration=True, input_gov=True, selftest=False, p0_external=False, deep_shared=False)
    check("migration_validator", ["sandbox/lf_contract_gate_test/lf_migration_source_parity.py"], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False)
    check("migration_transport_test", [migration_transport_test], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="SPECIALIZED_REQUIRED")
    check("c05_source_parity_bundle_no_p0", [s30d_c05, migration_transport_test, migration], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="SPECIALIZED_REQUIRED")
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
    real_s30a_delta = [validate_workflow, "gobernanza/contratos/s30_self_governance_gate_v1.json", "gobernanza/judges/validate_s30_self_governance_gate.py", s30_self_receipt, s30_self]
    check("s30a_real_delta_isolated", real_s30a_delta, migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    real_s30b_delta = [validate_workflow, s30_data_receipt, s30_data, "sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access.py", "sandbox/lf_contract_gate_test/s30_data_access_candidate/test_s30_data_access_v2.py"]
    check("s30b_real_delta_isolated", real_s30b_delta, migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    check("unknown_contract_gate_sandbox_fail_closed", ["sandbox/lf_contract_gate_test/new_unbound_validator.py"], migration=True, input_gov=True, selftest=False, p0_external=True, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("unknown_s30_receipt_sibling_fail_closed", ["sandbox/lf_contract_gate_test/receipts/s30_b_unbound.json"], migration=True, input_gov=True, selftest=False, p0_external=True, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("s30b_plus_unknown_fail_closed", [s30_data, "sandbox/lf_contract_gate_test/s30_data_access_other/unbound.py"], migration=True, input_gov=True, selftest=False, p0_external=True, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("unknown_fail_closed", ["mystery/new_surface.xyz"], migration=True, input_gov=True, selftest=False, p0_external=True, deep_shared=True, mode="DEEP_SHARED_UNKNOWN")
    check("empty_fail_closed", [], migration=True, input_gov=True, selftest=True, p0_external=True, deep_shared=True, mode="DEEP_SHARED_EMPTY_FAIL_CLOSED")
    print("CI_LANE_ROUTER_REGRESSIONS_PASS=32/32")


import copy
import json
from pathlib import Path

REGISTRY_PATH = Path(__file__).with_name("s30_lane_ownership_registry_v1.json")


def defensive(decision, name):
    actual = (
        decision.migration_parity_required,
        decision.input_governance_parity_required,
        decision.p0_exact_head_external_required,
        decision.deep_shared,
    )
    assert actual == (True, True, True, True), (name, actual, decision)


def fresh_registry():
    return json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))


def future_entry(*, lane_id="S30-E", ownership="S30_FUTURE", mode="S30_FUTURE_ISOLATED", value="sandbox/lf_contract_gate_test/s30_e_future/", kind="prefix", known=True):
    return {
        "lane_id": lane_id,
        "namespace": "S30",
        "ownership_class": ownership,
        "mode": mode,
        "matchers": [{"kind": kind, "value": value}],
        "migration_parity_required": False if known else True,
        "input_governance_parity_required": False if known else True,
        "p0_exact_head_external_required": False if known else True,
        "ci_router_selftest_required": False,
        "deep_shared": False if known else True,
        "known": known,
    }


def extended_main():
    positives = 0
    negatives = 0
    c = "sandbox/lf_contract_gate_test/s30_c_reliability_harness/freeze_contract.json"
    d = "sandbox/lf_contract_gate_test/s30_d_final_r09/r09_manifest_v1.json"
    p0 = "supabase/functions/lf-p0-exact-head-evidence-broker-v2/index.ts"
    migration = "supabase/migrations/20260910010101_router_guard.sql"

    check("s30_c_declarative", [c], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_C_RELIABILITY_ISOLATED")
    positives += 1
    check("s30_d_declarative", [d], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_D_FINAL_R09_ISOLATED")
    positives += 1
    check("s30_c_plus_d", [c, d], migration=False, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="S30_MULTI_LANE_KNOWN")
    positives += 1
    check("p0_owner_still_p0", [p0], migration=False, input_gov=False, selftest=False, p0_external=True, deep_shared=False, mode="SPECIALIZED_REQUIRED")
    positives += 1
    check("migration_owner_still_migration", [migration], migration=True, input_gov=False, selftest=False, p0_external=False, deep_shared=False, mode="SPECIALIZED_REQUIRED")
    positives += 1
    check("registry_self_change_runs_selftest", ["sandbox/lf_contract_gate_test/s28_ci_lane_router/s30_lane_ownership_registry_v1.json"], migration=False, input_gov=False, selftest=True, p0_external=False, deep_shared=False, mode="CI_ROUTER_SELFTEST_ONLY")
    positives += 1

    reg = fresh_registry()
    reg["lanes"].append(future_entry())
    got = classify(["sandbox/lf_contract_gate_test/s30_e_future/a.json"], registry_data=reg)
    assert got.mode == "S30_FUTURE_ISOLATED" and not any((got.migration_parity_required, got.input_governance_parity_required, got.p0_exact_head_external_required, got.deep_shared))
    positives += 1

    reg_exact = fresh_registry()
    reg_exact["lanes"].append(future_entry(lane_id="S30-F", ownership="S30_FUTURE_EXACT", mode="S30_FUTURE_EXACT_ISOLATED", value="sandbox/lf_contract_gate_test/s30_f_future/only.json", kind="exact"))
    got = classify(["sandbox/lf_contract_gate_test/s30_f_future/only.json"], registry_data=reg_exact)
    assert got.mode == "S30_FUTURE_EXACT_ISOLATED" and not got.deep_shared
    positives += 1

    got = classify(["sandbox/lf_contract_gate_test/s30_c_reliability_harnes/freeze.json"])
    defensive(got, "typo")
    assert got.mode == "DEEP_SHARED_UNKNOWN"
    negatives += 1
    got = classify(["sandbox/lf_contract_gate_test/s30_z_unregistered/a.json"])
    defensive(got, "unregistered")
    assert got.mode == "DEEP_SHARED_UNKNOWN"
    negatives += 1

    reg = fresh_registry()
    reg["lanes"].append(copy.deepcopy(reg["lanes"][3]))
    got = classify([c], registry_data=reg)
    defensive(got, "duplicate_lane")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"].append(future_entry(value="sandbox/lf_contract_gate_test/s30_c_reliability_harness/"))
    got = classify([c], registry_data=reg)
    defensive(got, "duplicate_matcher")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"].append(future_entry(value="sandbox/lf_contract_gate_test/s30_c_reliability_harness/sub/"))
    got = classify([c], registry_data=reg)
    defensive(got, "overlap")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    del reg["lanes"][3]["known"]
    got = classify([c], registry_data=reg)
    defensive(got, "incomplete")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"][3]["p0_exact_head_external_required"] = "false"
    got = classify([c], registry_data=reg)
    defensive(got, "bad_bool")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"].append(future_entry(value="sandbox/lf_contract_gate_test/s30_e_future/../p0/"))
    got = classify([c], registry_data=reg)
    defensive(got, "traversal")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"].append(future_entry(value="sandbox/lf_contract_gate_test/s30_"))
    got = classify([c], registry_data=reg)
    defensive(got, "too_broad")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    got = classify([c, "sandbox/lf_contract_gate_test/unbound_future_validator.py"])
    defensive(got, "mixed_known_unknown")
    assert got.mode == "DEEP_SHARED_UNKNOWN"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"][3]["matchers"] = [{"kind": "prefix", "value": "supabase/functions/lf-p0-exact-head-evidence-broker-v2/"}]
    got = classify([c], registry_data=reg)
    defensive(got, "p0_capture")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    bad = future_entry(known=False)
    bad["p0_exact_head_external_required"] = False
    reg["lanes"].append(bad)
    got = classify([c], registry_data=reg)
    defensive(got, "unknown_permissive")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"].append(future_entry(value="sandbox/lf_contract_gate_test/s30_e_*/"))
    got = classify([c], registry_data=reg)
    defensive(got, "wildcard")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"].append(future_entry(lane_id="S30-F", ownership="S30_FUTURE_EXACT", mode="S30_FUTURE_EXACT_ISOLATED", value="sandbox/lf_contract_gate_test/s30_c_reliability_harness/freeze_contract.json", kind="exact"))
    got = classify([c], registry_data=reg)
    defensive(got, "exact_prefix_overlap")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    reg = fresh_registry()
    reg["lanes"][3]["unexpected"] = True
    got = classify([c], registry_data=reg)
    defensive(got, "extra_field")
    assert got.mode == "DEEP_SHARED_REGISTRY_INVALID"
    negatives += 1
    got = classify(["mystery/unknown.xyz"])
    defensive(got, "outside_unknown")
    assert got.mode == "DEEP_SHARED_UNKNOWN"
    negatives += 1

    print(f"S30_DECLARATIVE_POSITIVE_PASS={positives}/{positives}")
    print(f"S30_DECLARATIVE_ADVERSARIAL_PASS={negatives}/{negatives}")


if __name__ == "__main__":
    main()
    extended_main()
