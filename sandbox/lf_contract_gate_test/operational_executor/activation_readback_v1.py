#!/usr/bin/env python3
"""Read-only activation gate for the operation executor (no DDL, no DML).

The snapshot is independently collected from the canonical Router/catalogue,
not authored by the caller. In offline CI, fixtures are explicitly synthetic.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

OPERATION = "EJECUCION_OPERATIVA_LF"
ASSET = "OPERATIONAL_DB"
ACTION = "OPERATION_EXECUTE"
MIGRATION_OPERATION = "ACTUALIZACION_DB_LF"


def evaluate(snapshot: dict) -> dict:
    failures = []
    original = snapshot.get("migration_route") or {}
    if (original.get("operation_code") != MIGRATION_OPERATION
            or original.get("status") != "READY_TO_EXECUTE"):
        failures.append("BLOCK_MIGRATION_ROUTE_NOT_PRESERVED")
    route = snapshot.get("operational_route") or {}
    if (route.get("status") != "READY_TO_EXECUTE"
            or route.get("operation_code") != OPERATION
            or route.get("asset_type") != ASSET
            or route.get("action_code") != ACTION
            or route.get("downstream_execution_allowed") is not True):
        failures.append("BLOCK_OPERATIONAL_ROUTE_NOT_ADMITTED")
    if snapshot.get("operation_registry_count") != 1:
        failures.append("BLOCK_OPERATION_REGISTRY_UNVERIFIED")
    if snapshot.get("router_action_count") != 1:
        failures.append("BLOCK_ROUTER_ACTION_UNVERIFIED")
    if snapshot.get("router_authority_consumer") is not True:
        failures.append("BLOCK_ROUTER_AUTHORITY_CONSUMER_NOT_REGISTERED")
    if snapshot.get("governed_execution_admission_proven") is not True:
        failures.append("BLOCK_OPERATIONAL_EXECUTION_ADMISSION_NOT_PROVEN")
    if snapshot.get("durable_human_decision_authority_current_proven") is not True:
        failures.append("BLOCK_DURABLE_HUMAN_DECISION_AUTHORITY_NOT_CURRENT")
    if snapshot.get("private_decision_function_execute_proven") is not True:
        failures.append("BLOCK_PRIVATE_DECISION_FUNCTION_EXECUTE_NOT_PROVEN")
    if snapshot.get("active_contract_count", 0) < 1:
        failures.append("BLOCK_OPERATION_CONTRACT_NOT_ACTIVE")
    if snapshot.get("active_required_step_count", 0) < 1:
        failures.append("BLOCK_OPERATION_STEPS_NOT_ACTIVE")
    if snapshot.get("active_judge_binding_count", 0) < snapshot.get("active_required_step_count", 0):
        failures.append("BLOCK_OPERATION_JUDGE_BINDINGS_INCOMPLETE")
    if snapshot.get("governed_closeout_function") is not True:
        failures.append("BLOCK_OPERATION_CLOSEOUT_NOT_INSTALLED")
    if snapshot.get("read_only_connection_unchanged") is not True:
        failures.append("BLOCK_READ_ONLY_BOUNDARY_NOT_VERIFIED")
    if snapshot.get("runtime_role_grant_audit_passed") is not True:
        failures.append("BLOCK_RUNTIME_PRIVILEGE_AUDIT_REQUIRED")
    if snapshot.get("public_security_definer_exposure_reviewed") is not True:
        failures.append("BLOCK_PUBLIC_DEFINER_EXPOSURE_UNREVIEWED")
    return {
        "schema_version": "LF_OPERATION_EXECUTOR_ACTIVATION_READBACK_V1",
        "status": "PASS" if not failures else "BLOCKED",
        "blocking_codes": failures,
        "migration_train_exclusive": original.get("operation_code") == MIGRATION_OPERATION,
        "operational_route": ASSET + "/" + ACTION,
        "operation_code": OPERATION,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", required=True)
    args = parser.parse_args()
    snapshot = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
    report = evaluate(snapshot)
    print(json.dumps(report, sort_keys=True))
    raise SystemExit(0 if report["status"] == "PASS" else 2)


if __name__ == "__main__":
    main()
