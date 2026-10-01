#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = HERE / "owner_runner_carrier_authority_contract_v1.json"
IMPACT_PATH = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
INVENTORY_PATH = ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json"


class ResolutionError(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_json(path: Path) -> tuple[dict[str, Any], str]:
    raw = path.read_bytes()
    try:
        data = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ResolutionError(f"BLOCK_INVALID_JSON:{path.name}") from exc
    if not isinstance(data, dict):
        raise ResolutionError(f"BLOCK_INVALID_OBJECT:{path.name}")
    return data, sha256_bytes(raw)


def validate_contract(contract: dict[str, Any]) -> None:
    if contract.get("schema_version") != "lf-owner-runner-carrier-authority/v1":
        raise ResolutionError("BLOCK_CONTRACT_SCHEMA")
    if contract.get("capability_code") != "OWNER_RUNNER_CARRIER_AUTHORITY":
        raise ResolutionError("BLOCK_CAPABILITY_IDENTITY")
    if contract.get("administrative_super_admin") != "LF_GOVERNANCE":
        raise ResolutionError("BLOCK_SUPER_ADMIN_IDENTITY")
    entry = contract.get("entry_contract")
    if not isinstance(entry, dict) or entry.get("required") is not True:
        raise ResolutionError("BLOCK_ENTRY_CONTRACT")
    if entry.get("guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        raise ResolutionError("BLOCK_ENTRY_GUARD_CODE")
    invariants = contract.get("invariants")
    if not isinstance(invariants, dict):
        raise ResolutionError("BLOCK_INVARIANTS")
    required_true = (
        "single_administrative_owner",
        "carrier_is_not_owner",
        "classification_inventory_is_evidence_only",
        "persistent_binding_catalog_forbidden",
        "impact_registry_remains_carrier_authority",
        "candidate_runner_execution_forbidden",
        "registered_not_cutover_execution_forbidden",
        "unknown_control_fail_closed",
        "unknown_owner_fail_closed",
        "carrier_drift_fail_closed",
        "duplicate_control_fail_closed",
        "missing_or_invalid_orchestrator_receipt_fail_closed",
        "read_model_is_not_activation",
        "read_model_is_not_new_authority",
    )
    for key in required_true:
        if invariants.get(key) is not True:
            raise ResolutionError(f"BLOCK_INVARIANT:{key}")


def validate_entry_readback(readback: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(readback, dict) or readback.get("ready") is not True:
        raise ResolutionError("BLOCK_ORCHESTRATOR_BINDING_NOT_READY")
    guard = readback.get("entry_guard")
    binding = readback.get("binding")
    if not isinstance(guard, dict) or guard.get("ready") is not True:
        raise ResolutionError("BLOCK_ORCHESTRATOR_ENTRY_GUARD")
    if guard.get("decision") != "ORCHESTRATOR_ENTRY_ACCEPTED":
        raise ResolutionError("BLOCK_ORCHESTRATOR_ENTRY_DECISION")
    if guard.get("guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        raise ResolutionError("BLOCK_ORCHESTRATOR_ENTRY_GUARD_CODE")
    if not isinstance(guard.get("orchestrator_execution_id"), str) or not guard["orchestrator_execution_id"].strip():
        raise ResolutionError("BLOCK_ORCHESTRATOR_EXECUTION_ID")
    if not isinstance(guard.get("receipt_id"), str) or not guard["receipt_id"].strip():
        raise ResolutionError("BLOCK_ORCHESTRATOR_RECEIPT_ID")
    if not isinstance(binding, dict) or binding.get("ready") is not True:
        raise ResolutionError("BLOCK_CAPABILITY_BINDING_NOT_READY")
    return guard


def plan_carriers(plan: dict[str, Any]) -> dict[str, str]:
    if plan.get("schema_version") != "lf-ci-execution-plan/v2":
        raise ResolutionError("BLOCK_PLAN_SCHEMA")
    admin = plan.get("governance_admin")
    if not isinstance(admin, dict) or admin.get("super_admin") != "LF_GOVERNANCE":
        raise ResolutionError("BLOCK_PLAN_SUPER_ADMIN")
    if not isinstance(admin.get("source_revision"), str) or not admin["source_revision"].strip():
        raise ResolutionError("BLOCK_PLAN_SUPER_ADMIN_SOURCE_REVISION")
    required = plan.get("required_controls")
    carriers = plan.get("carrier_controls")
    if not isinstance(required, list) or not isinstance(carriers, dict):
        raise ResolutionError("BLOCK_PLAN_CONTROL_SHAPE")
    required_set = set(required)
    if len(required_set) != len(required):
        raise ResolutionError("BLOCK_DUPLICATE_REQUIRED_CONTROL")
    reverse: dict[str, str] = {}
    for carrier, controls in carriers.items():
        if not isinstance(carrier, str) or not carrier or not isinstance(controls, list):
            raise ResolutionError("BLOCK_PLAN_CARRIER_SHAPE")
        for control_id in controls:
            if control_id in reverse:
                raise ResolutionError(f"BLOCK_DUPLICATE_CONTROL_CARRIER:{control_id}")
            reverse[control_id] = carrier
    if set(reverse) != required_set:
        raise ResolutionError("BLOCK_PLAN_CARRIER_COVERAGE")
    return reverse


def index_unique(rows: Any, key: str, error: str) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        raise ResolutionError(error)
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get(key), str) or not row[key]:
            raise ResolutionError(error)
        value = row[key]
        if value in out:
            raise ResolutionError(f"BLOCK_DUPLICATE_SOURCE_ROW:{value}")
        out[value] = row
    return out


def row_state(classification: str, runner_state: str, asset_state: str) -> str:
    if classification == "INTERNAL_CI_CHECK":
        return "RESOLVED_CARRIER_INTERNAL"
    if runner_state == "CANONICAL_EXECUTABLE_PRESENT":
        if asset_state == "REGISTERED_NOT_CUTOVER":
            return "BLOCK_NOT_CUTOVER"
        if asset_state in {"ACTIVE_SHARED_ENFORCEMENT", "ACTIVE"}:
            return "RESOLVED_CURRENT_CARRIER"
        return "BLOCK_CANONICAL_STATE_NOT_EXECUTABLE"
    if runner_state in {"CANDIDATE_UNMERGED_DIVERGED", "CANDIDATE_READ_ONLY"}:
        return "BLOCK_CANDIDATE_RUNNER"
    if runner_state == "OWNER_BOUNDARY_ONLY":
        return "BLOCK_OWNER_RUNNER_NOT_MATERIALIZED"
    return "BLOCK_OWNER_RUNNER_NOT_RESOLVED"


def resolve(plan: dict[str, Any], entry_readback: dict[str, Any]) -> dict[str, Any]:
    contract, contract_sha = load_json(CONTRACT_PATH)
    impact, impact_sha = load_json(IMPACT_PATH)
    inventory, inventory_sha = load_json(INVENTORY_PATH)
    validate_contract(contract)
    guard = validate_entry_readback(entry_readback)
    carrier_by_control = plan_carriers(plan)

    if impact.get("schema_version") != "lf-ci-control-impact-registry/v2":
        raise ResolutionError("BLOCK_IMPACT_REGISTRY_SCHEMA")
    if inventory.get("schema_version") != "lf-pase-control-binding-inventory/v1":
        raise ResolutionError("BLOCK_BINDING_INVENTORY_SCHEMA")
    authority = inventory.get("authority_model")
    if not isinstance(authority, dict) or authority.get("administrative_super_admin") != "LF_GOVERNANCE":
        raise ResolutionError("BLOCK_INVENTORY_SUPER_ADMIN")
    if authority.get("inventory_is_evidence_only") is not True:
        raise ResolutionError("BLOCK_INVENTORY_AUTHORITY_COLLAPSE")

    impact_rows = index_unique(impact.get("controls"), "control_id", "BLOCK_IMPACT_ROWS")
    inventory_rows = index_unique(inventory.get("controls"), "control_id", "BLOCK_INVENTORY_ROWS")
    resolved: list[dict[str, Any]] = []

    for control_id in sorted(carrier_by_control):
        canonical_carrier = carrier_by_control[control_id]
        impact_row = impact_rows.get(control_id)
        evidence_row = inventory_rows.get(control_id)
        if impact_row is None or evidence_row is None:
            raise ResolutionError(f"BLOCK_UNKNOWN_CONTROL:{control_id}")
        if impact_row.get("carrier") != canonical_carrier or evidence_row.get("carrier") != canonical_carrier:
            raise ResolutionError(f"BLOCK_CARRIER_DRIFT:{control_id}")

        classification = evidence_row.get("classification")
        runner_ref = evidence_row.get("runner_ref")
        runner_state = evidence_row.get("runner_state")
        asset_state = evidence_row.get("canonical_asset_state")
        if not isinstance(classification, str) or not isinstance(runner_ref, str) or not runner_ref:
            raise ResolutionError(f"BLOCK_OWNER_RUNNER_EVIDENCE:{control_id}")
        if not isinstance(runner_state, str) or not isinstance(asset_state, str):
            raise ResolutionError(f"BLOCK_OWNER_RUNNER_STATE:{control_id}")

        capability_id = evidence_row.get("canonical_asset_code") or evidence_row.get("target_parent_capability")
        if classification == "INTERNAL_CI_CHECK":
            capability_id = None
            effective_runner_state = "CARRIER_INTERNAL"
        else:
            effective_runner_state = runner_state
            if not isinstance(capability_id, str) or not capability_id:
                capability_id = None

        state = row_state(classification, runner_state, asset_state)
        source_revision = evidence_row.get("source_revision")
        if not isinstance(source_revision, str) or not source_revision:
            source_revision = sha256_bytes(canonical(evidence_row).encode("utf-8"))
        resolved.append({
            "control_id": control_id,
            "super_admin": "LF_GOVERNANCE",
            "classification": classification,
            "capability_id": capability_id,
            "runner_ref": runner_ref,
            "runner_state": effective_runner_state,
            "carrier": canonical_carrier,
            "state": state,
            "source_revision": source_revision,
        })

    ready = all(row["state"].startswith("RESOLVED_") for row in resolved)
    payload = {
        "schema_version": "lf-owner-runner-carrier-read-model/v1",
        "capability_code": "OWNER_RUNNER_CARRIER_AUTHORITY",
        "ready": ready,
        "decision": "OWNER_RUNNER_CARRIER_RESOLVED" if ready else "BLOCK_OWNER_RUNNER_CARRIER_UNRESOLVED",
        "orchestrator_execution_id": guard["orchestrator_execution_id"],
        "dispatch_receipt_id": guard["receipt_id"],
        "plan_sha256": plan.get("plan_sha256"),
        "source_digests": {
            "contract": contract_sha,
            "impact_registry": impact_sha,
            "classification_inventory": inventory_sha,
        },
        "rows": resolved,
    }
    payload["read_model_revision"] = sha256_bytes(canonical(payload).encode("utf-8"))
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--entry-readback", required=True, type=Path)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    readback = json.loads(args.entry_readback.read_text(encoding="utf-8"))
    try:
        result = resolve(plan, readback)
    except ResolutionError as exc:
        print(json.dumps({"ready": False, "decision": str(exc)}, sort_keys=True))
        raise SystemExit(2) from exc
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0 if result["ready"] else 3)


if __name__ == "__main__":
    main()
