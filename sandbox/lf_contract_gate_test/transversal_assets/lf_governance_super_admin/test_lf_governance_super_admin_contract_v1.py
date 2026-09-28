from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[3]
CONTRACT = ROOT / "lf_governance_super_admin_contract_v1.json"
INVENTORY = REPO_ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    c = load_json(CONTRACT)
    inventory = load_json(INVENTORY)

    assert c["schema_version"] == "lf-governance-super-admin/v1"
    assert c["super_admin"] == "LF_GOVERNANCE"
    assert c["role"] == "SUPER_ADMIN_GOVERNANCE"
    assert c["status"] == "CANDIDATE_READ_ONLY"
    assert c["applicability_authority"] == "CHANGESET_GOVERNANCE_LF_V1"
    assert c["orchestrator_consumer"] == "PASE_ORCHESTRATOR_V1"
    assert "binding_catalog" not in c

    policy = c["ownership_policy"]
    assert policy == {
        "schema_version": "lf-governance-control-ownership-policy/v1",
        "model": "SINGLE_ADMIN_ROOT",
        "super_admin": "LF_GOVERNANCE",
        "unknown_owner_detection": "PLAN_GOVERNANCE_ADMIN",
        "ci_control_is_not_automatically_capability": True,
        "standalone_capability_requires_canonical_authority": True,
        "owner_runner_required_only_for_standalone_capability": True,
        "internal_ci_check_execution": "CARRIER_INTERNAL",
        "internal_ci_check_requires_owner_runner": False,
        "internal_ci_check_must_not_spawn_capability": True,
        "carrier_is_not_owner": True,
        "candidate_runner_execution": "FORBIDDEN",
        "registered_not_cutover_execution": "FORBIDDEN",
        "unbound_or_noncutover_execution": "CURRENT_CARRIER_ONLY",
        "binding_inventory_is_evidence_only": True,
        "binding_inventory_path": "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json",
    }

    controls = inventory["controls"]
    assert len(controls) == 25
    assert len({row["control_id"] for row in controls}) == 25
    assert inventory["summary"]["unresolved_count"] == 0
    assert inventory["summary"]["binding_eligible_count"] == 0
    counts = Counter(row["classification"] for row in controls)
    assert counts["INTERNAL_CI_CHECK"] == 16
    assert counts["CANONICAL_CAPABILITY"] == 2
    assert counts["EXPLICIT_CAPABILITY_ALIAS"] == 1
    assert counts["CANONICAL_ASSET_CANDIDATE"] == 1
    assert counts["SEMANTIC_MAPPING_CANDIDATE"] == 1
    assert counts["OWNER_RUNNER_CANDIDATE_NO_CANONICAL_BINDING"] == 3
    assert counts["CONTROL_OWNER_BOUNDARY_ONLY"] == 1
    assert counts["UNRESOLVED"] == 0

    required = {
        "control_id",
        "super_admin",
        "capability_id",
        "runner_ref",
        "carrier",
        "state",
        "source_revision",
    }
    assert set(c["required_binding_fields"]) == required

    inv = c["invariants"]
    assert inv["single_super_admin"] is True
    assert inv["super_admin_equals"] == "LF_GOVERNANCE"
    assert inv["super_admin_is_not_carrier"] is True
    assert inv["super_admin_is_not_runner"] is True
    assert inv["subscope_aliases_are_not_parallel_authorities"] is True
    assert inv["act_0001_role"] == "ROUTER_RESOLUTION_ONLY"
    assert inv["unknown_control_fail_closed"] is True
    assert inv["missing_or_wrong_super_admin_fail_closed"] is True
    assert inv["missing_runner_fail_closed"] is True
    assert inv["runner_requirement_is_classification_aware"] is True
    assert inv["internal_ci_check_missing_owner_runner_is_not_owner_error"] is True
    assert inv["standalone_capability_missing_required_runner_fail_closed"] is True
    assert inv["carrier_drift_fail_closed"] is True
    assert inv["qualification_not_activation"] is True

    forbidden = {
        "DECIDE_APPLICABILITY",
        "GENERATE_EXECUTION_PLAN",
        "EXECUTE_DOMAIN_CONTROL",
        "CREATE_CAPABILITY_FROM_CI_CONTROL_BY_INFERENCE",
        "CREATE_OWNER_RUNNER_FOR_INTERNAL_CI_CHECK",
        "REPLACE_CAPABILITY_CONTRACT",
        "REPLACE_RUNNER",
        "ACT_AS_CARRIER",
        "CUTOVER",
        "REBIND",
        "DEPLOY",
        "RUNTIME_ACTIVATION",
        "PRODUCTION_ACTIVATION",
        "SUPABASE_WRITE",
    }
    assert set(c["prohibitions"]) == forbidden

    assert c["binding_materialized"] is False
    assert c["supabase_registered"] is False
    assert c["cutover_authorized"] is False
    assert c["production_authorized"] is False

    print(
        "PASS_LF_GOVERNANCE_OWNERSHIP_POLICY_V1 "
        "controls=25 internal=16 capabilities=2 unresolved=0 binding_eligible=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
