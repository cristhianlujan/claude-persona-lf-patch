#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "owner_runner_carrier_authority_v1.py"
CONTRACT_PATH = HERE / "owner_runner_carrier_authority_contract_v1.json"
PLAN_DIGEST = "a" * 64
RECEIPT_ID = "11111111-1111-4111-8111-111111111111"


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
            "orchestrator_execution_id": "EXEC-ORCH-AUTHORITY-001",
            "receipt_id": RECEIPT_ID,
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
            "source_revision": "b" * 64,
        },
        "required_controls": control_ids,
        "carrier_controls": {carrier: control_ids},
        "plan_sha256": PLAN_DIGEST,
    }


def migration_live(**overrides) -> dict:
    row = {
        "control_id": "MIGRATION_SOURCE_PARITY",
        "capability_code": "MIGRATION_SOURCE_PARITY",
        "registry_status": "ACTIVE",
        "entry_guard_required": True,
        "entry_guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "current_version": "1.0.0",
        "current_manifest_sha256": "39bb96aa3668c9e82af061f80be658c093545c918ee8a18cc24c21c423df257e",
        "version_release_state": "RELEASED",
        "source_ref": "github://cristhianlujan/claude-persona-lf-patch@e1c98f25a3fec60bf50c3ca73b52e44fa34afa17/sandbox/lf_contract_gate_test/migration_source_parity/migration_source_parity_core.py",
        "source_revision": "e1c98f25a3fec60bf50c3ca73b52e44fa34afa17",
        "runner_ref": "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py",
        "orchestrator_execution_id": "EXEC-ORCH-PARITY-001",
        "consumer_execution_id": "EXEC-PARITY-001",
        "dispatch_receipt_id": "22222222-2222-4222-8222-222222222222",
        "dispatch_receipt_sha256": "c" * 64,
        "dispatch_plan_digest": PLAN_DIGEST,
        "dispatch_capability_code": "MIGRATION_SOURCE_PARITY",
        "dispatch_guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "dispatch_consumer_execution_id": "EXEC-PARITY-001",
        "dispatch_orchestrator_execution_id": "EXEC-ORCH-PARITY-001",
        "matching_current_binding_count": 1,
        "historical_bound_count": 8,
        "binding_execution_id": "EXEC-PARITY-001",
        "binding_capability_code": "MIGRATION_SOURCE_PARITY",
        "bound_version": "1.0.0",
        "bound_manifest_sha256": "39bb96aa3668c9e82af061f80be658c093545c918ee8a18cc24c21c423df257e",
        "operation_execution_id": "EXEC-PARITY-001",
        "operation_status": "COMPLETED",
        "operation_manifest_plan_digest": PLAN_DIGEST,
        "operation_manifest_capability_code": "MIGRATION_SOURCE_PARITY",
        "operation_manifest_orchestrator_execution_id": "EXEC-ORCH-PARITY-001",
    }
    row.update(overrides)
    return {
        "schema_version": "lf-owner-runner-live-binding-readback/v1",
        "authority": "CANONICAL_LIVE_AUTHORITIES_READBACK_ONLY",
        "plan_digest": PLAN_DIGEST,
        "classification_inventory_is_authority": False,
        "rows": [row],
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
    inv = contract["invariants"]
    assert inv["classification_inventory_is_evidence_only"] is True
    assert inv["classification_evidence_cannot_authorize_execution"] is True
    assert inv["live_current_binding_required_for_resolved_capability"] is True
    assert inv["exact_consumer_binding_unique"] is True
    assert inv["historical_bindings_do_not_count_as_current_multiplicity"] is True
    assert contract["materialization"]["cutover_authorized"] is False
    checks += 1

    # Canonical capability cannot resolve from classification inventory alone.
    p = plan(["MIGRATION_SOURCE_PARITY"], carrier="MIGRATION_SOURCE_PARITY")
    expect_block(R, lambda: R.resolve(p, accepted_entry()), "BLOCK_LIVE_BINDING_READBACK_MISSING")
    checks += 1

    # Exact live current binding + dispatch + operation proof resolves the runner.
    parity = R.resolve(p, accepted_entry(), migration_live())
    assert parity["ready"] is True
    assert parity["decision"] == "OWNER_RUNNER_CARRIER_RESOLVED"
    assert parity["live_binding_readback_consumed"] is True
    assert parity["live_binding_control_count"] == 1
    row = parity["rows"][0]
    assert row["control_id"] == "MIGRATION_SOURCE_PARITY"
    assert row["capability_id"] == "MIGRATION_SOURCE_PARITY"
    assert row["state"] == "RESOLVED_CURRENT_CARRIER"
    assert row["current_version"] == "1.0.0"
    assert row["binding_execution_id"] == "EXEC-PARITY-001"
    assert row["consumer_execution_id"] == "EXEC-PARITY-001"
    assert row["operation_status"] == "COMPLETED"
    assert row["binding_selection"] == "EXACT_CONSUMER_EXECUTION_PLUS_CURRENT_VERSION_AND_MANIFEST"
    assert parity["historical_binding_rows_are_not_current_multiplicity"] is True
    checks += 1

    # Historical rows do not cause ambiguity; exact current consumer cardinality does.
    live = migration_live(matching_current_binding_count=0)
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_BINDING_CARDINALITY")
    live = migration_live(matching_current_binding_count=2)
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_BINDING_CARDINALITY")
    checks += 1

    live = migration_live(bound_version="0.9.0")
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_BINDING_CURRENTNESS")
    live = migration_live(bound_manifest_sha256="d" * 64)
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_BINDING_CURRENTNESS")
    checks += 1

    live = migration_live(dispatch_plan_digest="e" * 64)
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_DISPATCH_PLAN")
    live = migration_live(dispatch_capability_code="OTHER")
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_DISPATCH_CAPABILITY")
    checks += 1

    live = migration_live(binding_execution_id="EXEC-OTHER")
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_BINDING_EXECUTION")
    live = migration_live(dispatch_consumer_execution_id="EXEC-OTHER")
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_DISPATCH_EXECUTION")
    checks += 1

    live = migration_live(operation_manifest_plan_digest="f" * 64)
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_OPERATION_PLAN")
    live = migration_live(operation_manifest_orchestrator_execution_id="EXEC-ORCH-OTHER")
    expect_block(R, lambda: R.resolve(p, accepted_entry(), live), "BLOCK_LIVE_OPERATION_ORCHESTRATOR")
    checks += 1

    # Internal CI checks remain carrier-internal; no fake standalone binding is required.
    internal = R.resolve(plan(["CI_ROUTER_SELFTEST"]), accepted_entry())
    irow = internal["rows"][0]
    assert internal["ready"] is True
    assert internal["live_binding_readback_consumed"] is False
    assert irow["classification"] == "INTERNAL_CI_CHECK"
    assert irow["capability_id"] is None
    assert irow["runner_state"] == "CARRIER_INTERNAL"
    assert irow["state"] == "RESOLVED_CARRIER_INTERNAL"
    checks += 1

    # Registered-not-cutover and candidate runners remain blocked without live execution.
    not_cutover = R.resolve(plan(["P0_VISUAL_RUNTIME"]), accepted_entry())
    assert not_cutover["ready"] is False
    assert not_cutover["rows"][0]["state"] == "BLOCK_NOT_CUTOVER"
    checks += 1

    candidate = R.resolve(plan(["GATE_CHECK_OBSERVABILITY"], carrier="VALIDATE_LF_PACKS"), accepted_entry())
    assert candidate["ready"] is False
    assert candidate["rows"][0]["state"] == "BLOCK_CANDIDATE_RUNNER"
    checks += 1

    bad_guard = accepted_entry()
    bad_guard["entry_guard"]["decision"] = "OTHER"
    expect_block(R, lambda: R.resolve(p, bad_guard, migration_live()), "BLOCK_ORCHESTRATOR_ENTRY_DECISION")
    checks += 1

    wrong_admin = p.copy()
    wrong_admin["governance_admin"] = dict(p["governance_admin"])
    wrong_admin["governance_admin"]["super_admin"] = "OTHER"
    expect_block(R, lambda: R.resolve(wrong_admin, accepted_entry(), migration_live()), "BLOCK_PLAN_SUPER_ADMIN")
    checks += 1

    drift = plan(["MIGRATION_SOURCE_PARITY"], carrier="VALIDATE_LF_PACKS")
    expect_block(R, lambda: R.resolve(drift, accepted_entry(), migration_live()), "BLOCK_CARRIER_DRIFT:MIGRATION_SOURCE_PARITY")
    checks += 1

    unknown = plan(["UNKNOWN_CONTROL"])
    expect_block(R, lambda: R.resolve(unknown, accepted_entry()), "BLOCK_UNKNOWN_CONTROL:UNKNOWN_CONTROL")
    checks += 1

    duplicate = plan(["MIGRATION_SOURCE_PARITY", "MIGRATION_SOURCE_PARITY"], carrier="MIGRATION_SOURCE_PARITY")
    expect_block(R, lambda: R.resolve(duplicate, accepted_entry(), migration_live()), "BLOCK_DUPLICATE_REQUIRED_CONTROL")
    checks += 1

    bad_readback = migration_live()
    bad_readback["classification_inventory_is_authority"] = True
    expect_block(R, lambda: R.resolve(p, accepted_entry(), bad_readback), "BLOCK_CLASSIFICATION_AUTHORITY_COLLAPSE")
    checks += 1

    extra = migration_live()
    extra["rows"].append(copy.deepcopy(extra["rows"][0]))
    extra["rows"][1]["control_id"] = "UNPLANNED"
    expect_block(R, lambda: R.resolve(p, accepted_entry(), extra), "BLOCK_LIVE_BINDING_COVERAGE")
    checks += 1

    source = MODULE_PATH.read_text(encoding="utf-8")
    for forbidden in ("execute_sql", "apply_migration", "requests", "urllib", "subprocess", "POST_PASE_ORCHESTRATOR"):
        assert forbidden not in source, forbidden
    checks += 1

    print(f"PASS_OWNER_RUNNER_CARRIER_AUTHORITY_LIVE_BINDING_V1 checks={checks}")


if __name__ == "__main__":
    main()
