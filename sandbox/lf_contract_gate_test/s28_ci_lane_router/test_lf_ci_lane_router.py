#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
from lf_ci_lane_router import classify


def expect(name, paths, expected):
    result = classify(paths)
    assert result["status"] == "ROUTED", (name, result)
    for lane, value in expected.items():
        assert result["lanes"][lane] is value, (name, lane, result)
    print("PASS", name)


def main():
    expect("s30_contract_only", ["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml"], {
        "S30_POLICY": True, "MIGRATION_PARITY": False, "INPUT_GOVERNANCE_MIGRATION_PARITY": False, "DEEP_SHARED": False,
    })
    expect("s30_runtime_only", ["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/router_ready_rollback_canary_v2.sql"], {
        "S30_POLICY": True, "MIGRATION_PARITY": False, "INPUT_GOVERNANCE_MIGRATION_PARITY": False,
    })
    expect("general_migration", ["supabase/migrations/20260909120000_lf_example.sql"], {
        "MIGRATION_PARITY": True, "S30_POLICY": False,
    })
    expect("input_governance_migration", ["supabase/migrations/20260909120001_input_governance_example.sql"], {
        "MIGRATION_PARITY": True, "INPUT_GOVERNANCE_MIGRATION_PARITY": True,
    })
    expect("migration_validator", ["sandbox/lf_contract_gate_test/lf_migration_source_parity.py"], {
        "MIGRATION_PARITY": True,
    })
    expect("input_validator", ["sandbox/lf_contract_gate_test/input_governance_migration_parity_compact.py"], {
        "INPUT_GOVERNANCE_MIGRATION_PARITY": True,
    })
    expect("ci_router_change", [".github/workflows/lf-contract-check.yml", "scripts/lf_ci_lane_router.py"], {
        "CI_ROUTER_SELF_TEST": True, "MIGRATION_PARITY": False, "DEEP_SHARED": False,
    })
    expect("mixed_s30_and_migration", ["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/x.sql", "supabase/migrations/20260909120002_lf_x.sql"], {
        "S30_POLICY": True, "MIGRATION_PARITY": True,
    })
    expect("unknown_fail_deep", ["some/new/unknown_surface.txt"], {
        "DEEP_SHARED": True, "MIGRATION_PARITY": False,
    })
    blocked = classify([])
    assert blocked["status"] == "BLOCKED" and blocked["blocking_code"] == "BLOCK_CI_LANE_ROUTER_EMPTY_CHANGESET"
    try:
        classify(["../escape.sql"])
    except ValueError as exc:
        assert str(exc).startswith("INVALID_CHANGED_PATH:")
    else:
        raise AssertionError("invalid path was not blocked")
    print("PASS empty_and_invalid_fail_closed")
    print("S28_CI_LANE_ROUTER_REGRESSIONS_PASS=11/11")


if __name__ == "__main__":
    main()
