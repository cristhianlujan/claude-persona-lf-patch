from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[3]
CONTRACT = ROOT / "lf_governance_super_admin_contract_v1.json"
REGISTRY = REPO_ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    c = load_json(CONTRACT)
    registry = load_json(REGISTRY)

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

    catalog = c["binding_catalog"]
    assert catalog["schema_version"] == "lf-governance-control-binding-catalog/v1"
    assert catalog["catalog_materialized"] is True
    assert catalog["owner_runner_migration_complete"] is False
    assert catalog["carrier_authority"] == {
        "schema_version": "lf-ci-control-impact-registry/v2",
        "path": "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json",
    }

    allowed_states = {
        "LEGACY_CARRIER",
        "OWNER_RUNNER_ACTIVE_LEGACY_CARRIER",
        "REGISTERED_NOT_CUTOVER",
        "CANDIDATE_NOT_CANONICAL",
    }
    assert set(catalog["allowed_states"]) == allowed_states

    rows = catalog["controls"]
    assert isinstance(rows, list) and rows
    ids = [row["control_id"] for row in rows]
    assert len(ids) == len(set(ids))

    registry_rows = registry["controls"]
    registry_ids = [row["control_id"] for row in registry_rows]
    assert len(registry_ids) == len(set(registry_ids))
    assert sorted(ids) == sorted(registry_ids)
    assert len(ids) == 25

    for row in rows:
        assert set(row) == {
            "control_id",
            "capability_id",
            "runner_ref",
            "state",
            "source_revision",
            "evidence_ref",
        }
        assert isinstance(row["control_id"], str) and re.fullmatch(r"[A-Z][A-Z0-9_]*", row["control_id"])
        assert row["state"] in allowed_states
        assert isinstance(row["source_revision"], str) and re.fullmatch(r"[0-9a-f]{40}", row["source_revision"])
        assert isinstance(row["evidence_ref"], str) and row["evidence_ref"].strip()
        assert "carrier" not in row
        assert "super_admin" not in row

        capability = row["capability_id"]
        runner = row["runner_ref"]
        if capability is not None:
            assert isinstance(capability, str) and capability.strip()
        if row["state"] == "LEGACY_CARRIER":
            assert runner is None
        else:
            assert isinstance(capability, str) and capability.strip()
            assert isinstance(runner, str) and runner.strip()

        if row["state"] == "CANDIDATE_NOT_CANONICAL":
            assert row["evidence_ref"].startswith("PR#")

    counts = Counter(row["state"] for row in rows)
    assert counts == Counter({
        "LEGACY_CARRIER": 19,
        "CANDIDATE_NOT_CANONICAL": 4,
        "OWNER_RUNNER_ACTIVE_LEGACY_CARRIER": 1,
        "REGISTERED_NOT_CUTOVER": 1,
    })

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
    assert inv["legacy_carrier_state_is_explicit_no_runner_exception"] is True
    assert inv["carrier_drift_fail_closed"] is True
    assert inv["candidate_runner_never_executable"] is True
    assert inv["registered_not_cutover_never_executable"] is True
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

    # Catalog exists, but end-to-end binding is intentionally not active yet.
    assert c["binding_materialized"] is False
    assert c["supabase_registered"] is False
    assert c["cutover_authorized"] is False
    assert c["production_authorized"] is False

    print(
        "PASS_LF_GOVERNANCE_SUPER_ADMIN_CONTRACT_V1 "
        "catalog=25 legacy=19 active=1 registered_not_cutover=1 candidate=4"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
