#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "owner_runner_carrier_authority_v1.py"
CONTRACT_PATH = HERE / "owner_runner_carrier_authority_contract_v1.json"


def load_module():
    spec = importlib.util.spec_from_file_location("owner_runner_carrier_authority_v1_tested", MODULE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def accepted_entry() -> dict:
    return {
        "ready": True,
        "entry_guard": {
            "ready": True,
            "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
            "orchestrator_execution_id": "EXEC-ORCH-TEST-001",
            "receipt_id": "00000000-0000-0000-0000-000000000001",
            "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
        },
        "binding": {"ready": True},
    }


def plan(control_ids: list[str], carrier: str = "LF_CONTRACT_CHECK") -> dict:
    return {
        "schema_version": "lf-ci-execution-plan/v2",
        "governance_admin": {
            "schema_version": "lf-ci-governance-admin-identity/v1",
            "super_admin": "LF_GOVERNANCE",
            "source_revision": "test-source-revision",
        },
        "required_controls": control_ids,
        "carrier_controls": {carrier: control_ids},
        "plan_sha256": "test-plan-sha",
    }


def expect_block(R, fn, marker: str) -> None:
    try:
        fn()
    except R.ResolutionError as exc:
        assert marker in str(exc), (marker, str(exc))
    else:
        raise AssertionError(f"expected block: {marker}")


def main() -> None:
    R = load_module()
    checks = 0

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    R.validate_contract(contract)
    assert contract["invariants"]["persistent_binding_catalog_forbidden"] is True
    assert contract["invariants"]["local_guard_readback_is_not_authority"] is True
    assert contract["invariants"]["invocation_authenticity_belongs_to_l1_009"] is True
    assert contract["entry_contract"]["local_shape_validation_is_authority"] is False
    assert contract["entry_contract"]["invocation_wiring_work_code"] == "SADM-PP-L1-009"
    assert contract["source_authorities"]["classification_evidence"].endswith("pase_control_binding_inventory_v1.json")
    checks += 1

    parity = R.resolve(
        plan(["MIGRATION_SOURCE_PARITY"], carrier="MIGRATION_SOURCE_PARITY"),
        accepted_entry(),
    )
    assert parity["ready"] is True
    assert parity["decision"] == "OWNER_RUNNER_CARRIER_RESOLVED"
    assert len(parity["rows"]) == 1
    row = parity["rows"][0]
    assert row["control_id"] == "MIGRATION_SOURCE_PARITY"
    assert row["super_admin"] == "LF_GOVERNANCE"
    assert row["capability_id"] == "MIGRATION_SOURCE_PARITY"
    assert row["carrier"] == "MIGRATION_SOURCE_PARITY"
    assert row["state"] == "RESOLVED_CURRENT_CARRIER"
    checks += 1

    internal = R.resolve(plan(["CI_ROUTER_SELFTEST"]), accepted_entry())
    irow = internal["rows"][0]
    assert internal["ready"] is True
    assert irow["classification"] == "INTERNAL_CI_CHECK"
    assert irow["capability_id"] is None
    assert irow["runner_state"] == "CARRIER_INTERNAL"
    assert irow["state"] == "RESOLVED_CARRIER_INTERNAL"
    checks += 1

    not_cutover = R.resolve(plan(["P0_VISUAL_RUNTIME"]), accepted_entry())
    assert not_cutover["ready"] is False
    assert not_cutover["rows"][0]["state"] == "BLOCK_NOT_CUTOVER"
    assert not_cutover["rows"][0]["capability_id"] == "VISUAL_EVIDENCE_GATE"
    checks += 1

    bad_guard = accepted_entry()
    bad_guard["entry_guard"]["decision"] = "OTHER"
    expect_block(R, lambda: R.resolve(plan(["MIGRATION_SOURCE_PARITY"], carrier="MIGRATION_SOURCE_PARITY"), bad_guard), "BLOCK_ORCHESTRATOR_ENTRY_DECISION")
    checks += 1

    missing_binding = accepted_entry()
    missing_binding["binding"]["ready"] = False
    expect_block(R, lambda: R.resolve(plan(["MIGRATION_SOURCE_PARITY"], carrier="MIGRATION_SOURCE_PARITY"), missing_binding), "BLOCK_CAPABILITY_BINDING_NOT_READY")
    checks += 1

    wrong_admin = plan(["MIGRATION_SOURCE_PARITY"], carrier="MIGRATION_SOURCE_PARITY")
    wrong_admin["governance_admin"]["super_admin"] = "OTHER"
    expect_block(R, lambda: R.resolve(wrong_admin, accepted_entry()), "BLOCK_PLAN_SUPER_ADMIN")
    checks += 1

    drift = plan(["MIGRATION_SOURCE_PARITY"], carrier="VALIDATE_LF_PACKS")
    expect_block(R, lambda: R.resolve(drift, accepted_entry()), "BLOCK_CARRIER_DRIFT:MIGRATION_SOURCE_PARITY")
    checks += 1

    unknown = plan(["UNKNOWN_CONTROL"])
    expect_block(R, lambda: R.resolve(unknown, accepted_entry()), "BLOCK_UNKNOWN_CONTROL:UNKNOWN_CONTROL")
    checks += 1

    duplicate = plan(["MIGRATION_SOURCE_PARITY", "MIGRATION_SOURCE_PARITY"], carrier="MIGRATION_SOURCE_PARITY")
    expect_block(R, lambda: R.resolve(duplicate, accepted_entry()), "BLOCK_DUPLICATE_REQUIRED_CONTROL")
    checks += 1

    assert parity["read_model_revision"]
    assert set(parity["source_digests"]) == {"contract", "impact_registry", "classification_inventory"}
    checks += 1

    print(f"PASS_OWNER_RUNNER_CARRIER_AUTHORITY_V1 checks={checks}")


if __name__ == "__main__":
    main()
