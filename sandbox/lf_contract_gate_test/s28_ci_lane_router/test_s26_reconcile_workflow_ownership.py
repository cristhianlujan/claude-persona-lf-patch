#!/usr/bin/env python3
from lf_ci_lane_router import classify


def main() -> None:
    workflow = ".github/workflows/lf-github-reconcile-v3.yml"
    helper = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_pooler_fallback.py"
    helper_test = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py"
    migration = "supabase/migrations/20260913083223_lf_s26_ci_402_pooler_fallback_governance_repin_v1.sql"

    workflow_only = classify([workflow])
    assert workflow_only.mode == "CI_ROUTER_SELFTEST_ONLY", workflow_only
    assert workflow_only.ci_router_selftest_required is True, workflow_only
    assert workflow_only.p0_exact_head_external_required is False, workflow_only
    assert workflow_only.deep_shared is False, workflow_only

    repaired_delta = classify([workflow, helper, helper_test, migration])
    assert repaired_delta.mode == "SPECIALIZED_REQUIRED", repaired_delta
    assert repaired_delta.migration_parity_required is True, repaired_delta
    assert repaired_delta.input_governance_parity_required is False, repaired_delta
    assert repaired_delta.ci_router_selftest_required is True, repaired_delta
    assert repaired_delta.p0_exact_head_external_required is False, repaired_delta
    assert repaired_delta.deep_shared is False, repaired_delta

    lookalike = classify([workflow + ".bak"])
    assert lookalike.mode == "CLASSIFICATION_REQUIRED", lookalike
    assert lookalike.p0_exact_head_external_required is False, lookalike
    assert lookalike.deep_shared is True, lookalike

    print("PASS_S26_RECONCILE_WORKFLOW_OWNERSHIP=11/11")


if __name__ == "__main__":
    main()
