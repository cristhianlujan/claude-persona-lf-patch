from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONTRACT = ROOT / "lf_governance_super_admin_contract_v1.json"


def load_contract() -> dict:
    return json.loads(CONTRACT.read_text(encoding="utf-8"))


def main() -> int:
    c = load_contract()

    assert c["schema_version"] == "lf-governance-super-admin/v1"
    assert c["super_admin"] == "LF_GOVERNANCE"
    assert c["role"] == "SUPER_ADMIN_GOVERNANCE"
    assert c["status"] == "CANDIDATE_READ_ONLY"
    assert c["applicability_authority"] == "CHANGESET_GOVERNANCE_LF_V1"
    assert c["orchestrator_consumer"] == "PASE_ORCHESTRATOR_V1"

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
    assert inv["carrier_drift_fail_closed"] is True
    assert inv["qualification_not_activation"] is True

    forbidden = {
        "DECIDE_APPLICABILITY",
        "GENERATE_EXECUTION_PLAN",
        "EXECUTE_DOMAIN_CONTROL",
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

    print("PASS_LF_GOVERNANCE_SUPER_ADMIN_CONTRACT_V1 checks=26")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
