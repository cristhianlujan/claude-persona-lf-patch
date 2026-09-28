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
    assert inv["authority_model"]["inventory_is_evidence_only"] is True
    assert inv["authority_model"]["supabase_mutation_performed"] is False
    assert inv["authority_model"]["cutover_authorized"] is False
    assert inv["authority_model"]["rebind_authorized"] is False
    assert inv["authority_model"]["activation_authorized"] is False
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
        assert row["classification"] in inv["classification_vocabulary"], control_id
        assert row["runner_state"] in inv["runner_state_vocabulary"], control_id
        assert row["binding_eligible"] is False, control_id
        assert isinstance(row["reason"], str) and row["reason"].strip(), control_id
    checks += 1

    counts = Counter(row["classification"] for row in rows)
    expected = {
        "CANONICAL_CAPABILITY": 2,
        "EXPLICIT_CAPABILITY_ALIAS": 1,
        "CANONICAL_ASSET_CANDIDATE": 1,
        "CONTROL_OWNER_BOUNDARY_ONLY": 1,
        "SEMANTIC_MAPPING_CANDIDATE": 1,
        "OWNER_RUNNER_CANDIDATE_NO_CANONICAL_BINDING": 3,
        "INTERNAL_CI_CHECK": 16,
    }
    assert dict(counts) == expected
    assert counts["UNRESOLVED"] == 0
    summary = inv["summary"]
    assert summary["control_count"] == 25
    assert summary["binding_eligible_count"] == 0
    assert summary["exact_canonical_capability_count"] == 2
    assert summary["explicit_capability_alias_count"] == 1
    assert summary["canonical_asset_candidate_count"] == 1
    assert summary["semantic_mapping_candidate_count"] == 1
    assert summary["owner_runner_candidate_without_canonical_binding_count"] == 3
    assert summary["control_owner_boundary_only_count"] == 1
    assert summary["known_internal_ci_check_count"] == 16
    assert summary["unresolved_count"] == 0
    checks += 1

    migration = by_id["MIGRATION_SOURCE_PARITY"]
    assert migration["canonical_asset_code"] == "MIGRATION_SOURCE_PARITY"
    assert migration["canonical_owner"] == "LF_GOVERNANCE_S30_DB"
    assert migration["canonical_asset_state"] == "ACTIVE_SHARED_ENFORCEMENT"
    checks += 1

    visual = by_id["P0_VISUAL_RUNTIME"]
    assert visual["classification"] == "EXPLICIT_CAPABILITY_ALIAS"
    assert visual["canonical_asset_code"] == "VISUAL_EVIDENCE_GATE"
    assert visual["canonical_asset_state"] == "REGISTERED_NOT_CUTOVER"
    checks += 1

    internal_required = {
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
    assert {cid for cid, row in by_id.items() if row["classification"] == "INTERNAL_CI_CHECK"} == internal_required
    checks += 1

    db_internal = {"DB_CANDIDATE_APPLY_ROLLBACK", "POLICY_RESOLVER_REGRESSION", "V7_RUNTIME_REGRESSION"}
    for control_id in db_internal:
        assert by_id[control_id]["classification"] == "INTERNAL_CI_CHECK"
        assert by_id[control_id]["canonical_asset_code"] == "CI_FAST_DEEP_LANE_ROUTER"
    checks += 1

    gco = by_id["GATE_CHECK_OBSERVABILITY"]
    assert gco["canonical_asset_code"] == "GATE_CHECK_OBSERVABILITY"
    assert gco["canonical_owner"] is None
    assert gco["runner_state"] == "CANDIDATE_UNMERGED_DIVERGED"
    checks += 1

    contract = by_id["LF_CONTRACT_CORE"]
    assert contract["canonical_owner"] == "CONTRACT_CHECK"
    assert contract["secondary_owner_boundary"] == "CONTRACT_RESOLUTION"
    assert contract["binding_eligible"] is False
    checks += 1

    candidate_prs = {row["candidate_pr"] for row in rows if "candidate_pr" in row}
    assert candidate_prs == {1168, 1169, 1171, 1172}
    checks += 1

    print(f"PASS_PASE_CONTROL_BINDING_INVENTORY_V1 checks={checks} controls={len(rows)} unresolved={counts['UNRESOLVED']}")


if __name__ == "__main__":
    main()
