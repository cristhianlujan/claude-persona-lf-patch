#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[3]
INVENTORY = HERE / "pase_control_binding_inventory_v1.json"
IMPACT = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"


def main() -> None:
    inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
    impact = json.loads(IMPACT.read_text(encoding="utf-8"))
    checks = 0

    assert inv["schema_version"] == "lf-pase-control-binding-inventory/v1"
    authority = inv["authority_model"]
    assert authority["inventory_is_evidence_only"] is True
    assert authority["supabase_mutation_performed"] is False
    assert authority["cutover_authorized"] is False
    assert authority["rebind_authorized"] is False
    assert authority["activation_authorized"] is False
    assert authority["carrier_is_not_owner"] is True
    assert authority["current_execution_host_is_not_owner"] is True
    checks += 1

    rows = inv["controls"]
    assert len(rows) == 25
    assert len({row["control_id"] for row in rows}) == len(rows)
    by_id = {row["control_id"]: row for row in rows}
    impact_rows = {row["control_id"]: row for row in impact["controls"]}
    assert set(by_id) == set(impact_rows)
    checks += 1

    for control_id, row in by_id.items():
        assert row["carrier"] == impact_rows[control_id]["carrier"], control_id
        assert row["current_execution_host"] == row["carrier"], control_id
        assert row["classification"] in inv["classification_vocabulary"], control_id
        assert row["runner_state"] in inv["runner_state_vocabulary"], control_id
        assert row["target_parent_status"] in inv["target_parent_status_vocabulary"], control_id
        assert isinstance(row["target_parent_candidates"], list), control_id
        assert row["binding_eligible"] is False, control_id
        assert isinstance(row["reason"], str) and row["reason"].strip(), control_id
    checks += 1

    class_counts = Counter(row["classification"] for row in rows)
    expected_classes = {
        "CANONICAL_CAPABILITY": 2,
        "EXPLICIT_CAPABILITY_ALIAS": 1,
        "CANONICAL_ASSET_CANDIDATE": 1,
        "CONTROL_OWNER_BOUNDARY_ONLY": 1,
        "SEMANTIC_MAPPING_CANDIDATE": 1,
        "OWNER_RUNNER_CANDIDATE_NO_CANONICAL_BINDING": 3,
        "INTERNAL_CI_CHECK": 16,
    }
    assert dict(class_counts) == expected_classes
    assert class_counts["UNRESOLVED"] == 0
    checks += 1

    parent_counts = Counter(row["target_parent_status"] for row in rows)
    assert dict(parent_counts) == {
        "MATCH_CLEAR": 3,
        "CANDIDATE_ONLY": 13,
        "OWNER_BOUNDARY_ONLY": 1,
        "UNRESOLVED": 8,
    }
    checks += 1

    summary = inv["summary"]
    assert summary["control_count"] == 25
    assert summary["binding_eligible_count"] == 0
    assert summary["known_internal_ci_check_count"] == 16
    assert summary["unresolved_identity_count"] == 0
    assert summary["target_parent_match_clear_count"] == 3
    assert summary["target_parent_candidate_only_count"] == 13
    assert summary["target_parent_owner_boundary_only_count"] == 1
    assert summary["target_parent_unresolved_count"] == 8
    assert summary["pack_validation_grouped_control_count"] == 3
    checks += 1

    internal_ids = {cid for cid, row in by_id.items() if row["classification"] == "INTERNAL_CI_CHECK"}
    expected_internal = {
        "CI_ROUTER_SELFTEST",
        "DB_CANDIDATE_APPLY_ROLLBACK",
        "DECLARED_GOVERNANCE_PATHS",
        "E16_ACTIONS_INVENTORY",
        "E16_GOVERNANCE",
        "INPUT_GOVERNANCE_MIGRATION_PARITY",
        "LEARNING_ENGINE_PACK",
        "LF_VALIDATION_ENGINE",
        "NO_BYPASS_PROFILE_CARD_SKILL",
        "P0_FAST_DOCS",
        "PASS_EVIDENCE",
        "POLICY_RESOLVER_REGRESSION",
        "R8_USER_STORY_AUDIT",
        "SKILL_PACK",
        "SUPABASE_CONTROL_PLANE_READBACK",
        "V7_RUNTIME_REGRESSION",
    }
    assert internal_ids == expected_internal
    for cid in internal_ids:
        assert by_id[cid].get("canonical_owner") is None, cid
    checks += 1

    pack_controls = {"PROFILE_PACK", "SKILL_PACK", "LEARNING_ENGINE_PACK"}
    for cid in pack_controls:
        row = by_id[cid]
        assert row["target_parent_capability"] == "PACK_VALIDATION", cid
        assert row["target_parent_status"] == "CANDIDATE_ONLY", cid
        assert row.get("canonical_owner") is None, cid
    assert by_id["PROFILE_PACK"]["canonical_asset_code"] is None
    assert "PACK_VALIDATION_HARNESS" in by_id["PROFILE_PACK"]["related_assets"]
    checks += 1

    migration = by_id["MIGRATION_SOURCE_PARITY"]
    assert migration["canonical_asset_code"] == "MIGRATION_SOURCE_PARITY"
    assert migration["canonical_owner"] == "LF_GOVERNANCE_S30_DB"
    assert migration["target_parent_capability"] == "MIGRATION_SOURCE_PARITY"
    assert migration["target_parent_status"] == "MATCH_CLEAR"
    checks += 1

    visual = by_id["P0_VISUAL_RUNTIME"]
    assert visual["canonical_asset_code"] == "VISUAL_EVIDENCE_GATE"
    assert visual["target_parent_capability"] == "VISUAL_EVIDENCE_GATE"
    assert visual["target_parent_status"] == "MATCH_CLEAR"
    assert visual["canonical_asset_state"] == "REGISTERED_NOT_CUTOVER"
    checks += 1

    gco = by_id["GATE_CHECK_OBSERVABILITY"]
    assert gco["canonical_asset_code"] == "GATE_CHECK_OBSERVABILITY"
    assert gco["target_parent_status"] == "MATCH_CLEAR"
    assert gco["runner_state"] == "CANDIDATE_UNMERGED_DIVERGED"
    checks += 1

    db_internal = {"DB_CANDIDATE_APPLY_ROLLBACK", "POLICY_RESOLVER_REGRESSION", "V7_RUNTIME_REGRESSION"}
    for cid in db_internal:
        row = by_id[cid]
        assert row["classification"] == "INTERNAL_CI_CHECK"
        assert row["canonical_asset_code"] is None
        assert row["target_parent_capability"] is None
        assert row["target_parent_status"] == "UNRESOLVED"
        assert row["declaration_source_capability"] == "CI_FAST_DEEP_LANE_ROUTER"
    checks += 1

    contract = by_id["LF_CONTRACT_CORE"]
    assert contract["canonical_owner"] == "CONTRACT_CHECK"
    assert contract["secondary_owner_boundary"] == "CONTRACT_RESOLUTION"
    assert contract["target_parent_status"] == "OWNER_BOUNDARY_ONLY"
    checks += 1

    pass_evidence = by_id["PASS_EVIDENCE"]
    assert pass_evidence["target_parent_capability"] is None
    assert set(pass_evidence["target_parent_candidates"]) == {
        "TYPED_EVIDENCE_REGISTRY",
        "EVIDENCE_ANTIREPLAY",
        "EVIDENCE_LEDGER",
    }
    assert pass_evidence["target_parent_status"] == "CANDIDATE_ONLY"
    checks += 1

    unresolved_parent_ids = {cid for cid, row in by_id.items() if row["target_parent_status"] == "UNRESOLVED"}
    assert unresolved_parent_ids == {
        "DB_CANDIDATE_APPLY_ROLLBACK",
        "E16_ACTIONS_INVENTORY",
        "E16_GOVERNANCE",
        "INPUT_GOVERNANCE_MIGRATION_PARITY",
        "NO_BYPASS_PROFILE_CARD_SKILL",
        "POLICY_RESOLVER_REGRESSION",
        "SUPABASE_CONTROL_PLANE_READBACK",
        "V7_RUNTIME_REGRESSION",
    }
    checks += 1

    candidate_prs = {row["candidate_pr"] for row in rows if "candidate_pr" in row}
    assert candidate_prs == {1168, 1169, 1171, 1172}
    checks += 1

    print(
        "PASS_PASE_CONTROL_BINDING_INVENTORY_V1 "
        f"checks={checks} controls={len(rows)} "
        f"identity_unresolved={class_counts['UNRESOLVED']} "
        f"parent_unresolved={parent_counts['UNRESOLVED']}"
    )


if __name__ == "__main__":
    main()
