#!/usr/bin/env python3
from __future__ import annotations

from s30_interim_dependency_impact import classify_paths, load_policy, verify_observed_delta

OBSERVED_DELTA = [
    ".github/workflows/lf-github-reconcile-v3.yml",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_pooler_fallback.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_s26_reconcile_workflow_ownership.py",
    "services/profile_runtime_api/profile_runtime_api/engine.py",
    "services/profile_runtime_api/profile_runtime_api/ui_semantic_quality.py",
    "services/profile_runtime_api/tests/test_s26_w2_repairs.py",
    "services/profile_runtime_api/tests/test_ui_production_semantic_repair.py",
    "supabase/migrations/20260913050553_lf_card_update_i5_carrier_adapter_intent_v1.sql",
    "supabase/migrations/20260913083223_lf_s26_ci_402_pooler_fallback_governance_repin_v1.sql",
    "supabase/migrations/20260913133413_lf_s26_ci_402_source_workflow_governance_repin_v1.sql",
    "supabase/migrations/20260913134145_lf_s26_ci_402_source_workflow_sha_corrective_repin_v1.sql",
    "supabase/migrations/20260913140430_lf_s26_ci_402_contract_validator_governance_repin_v1.sql",
    "supabase/migrations/20260913150751_lf_regla_router_governance_v1.sql",
    "supabase/migrations/20260913175344_lf_mode_normalization_v1.sql",
]


def main() -> None:
    policy = load_policy()

    observed = verify_observed_delta(policy, OBSERVED_DELTA)
    assert observed["result"] == "NO_S30_REVALIDATION_REQUIRED", observed
    assert observed["buckets"]["s30_owned"] == [], observed
    assert observed["buckets"]["declared_consumed_contract"] == [], observed
    assert observed["buckets"]["unknown"] == [], observed

    head_only = classify_paths(policy, [])
    assert head_only["result"] == "NO_S30_REVALIDATION_REQUIRED", head_only
    assert head_only["main_sha_drift_alone_invalidates_s30"] is False, head_only

    owned = classify_paths(
        policy,
        ["sandbox/lf_contract_gate_test/s30_d_final_r09/strategy_orchestrator_bootstrap_contract_v1.json"],
    )
    assert owned["result"] == "FULL_S30_REVALIDATION_REQUIRED", owned
    assert owned["reason"] == "S30_OWNED_SURFACE_CHANGED", owned

    consumed = classify_paths(policy, [".github/workflows/validate-lf-packs.yml"])
    assert consumed["result"] == "TARGETED_IMPACT_REVIEW_REQUIRED", consumed
    assert consumed["reason"] == "DECLARED_CONSUMED_CONTRACT_CHANGED", consumed

    unrelated_s26 = classify_paths(policy, ["services/profile_runtime_api/profile_runtime_api/engine.py"])
    assert unrelated_s26["result"] == "NO_S30_REVALIDATION_REQUIRED", unrelated_s26

    transport = classify_paths(policy, [".github/workflows/lf-github-reconcile-v3.yml"])
    assert transport["result"] == "NO_S30_REVALIDATION_REQUIRED", transport

    unknown = classify_paths(policy, ["gobernanza/contratos/future_shared_contract_v9.json"])
    assert unknown["result"] == "TARGETED_IMPACT_REVIEW_REQUIRED", unknown
    assert unknown["reason"] == "UNKNOWN_OR_MIXED_DEPENDENCY_CHANGE", unknown

    mixed = classify_paths(
        policy,
        [
            ".github/workflows/lf-github-reconcile-v3.yml",
            "gobernanza/contratos/future_shared_contract_v9.json",
        ],
    )
    assert mixed["result"] == "TARGETED_IMPACT_REVIEW_REQUIRED", mixed

    safety = policy["safety_ceiling"]
    assert not any(safety.values()), safety

    print("PASS_S30_INTERIM_DEPENDENCY_IMPACT=18/18")


if __name__ == "__main__":
    main()
