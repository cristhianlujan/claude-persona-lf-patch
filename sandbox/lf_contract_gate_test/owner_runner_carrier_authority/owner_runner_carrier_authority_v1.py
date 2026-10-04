#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = HERE / "owner_runner_carrier_authority_contract_v1.json"
IMPACT_PATH = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
INVENTORY_PATH = ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)
LIVE_READBACK_SCHEMA = "lf-owner-runner-live-binding-readback/v1"


class ResolutionError(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha256(value: Any) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def _uuid(value: Any) -> bool:
    return isinstance(value, str) and UUID_RE.fullmatch(value) is not None


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
    authority = contract.get("source_authorities")
    if not isinstance(authority, dict) or authority.get("live_binding_readback_schema") != LIVE_READBACK_SCHEMA:
        raise ResolutionError("BLOCK_LIVE_BINDING_AUTHORITY")
    invariants = contract.get("invariants")
    if not isinstance(invariants, dict):
        raise ResolutionError("BLOCK_INVARIANTS")
    required_true = (
        "single_administrative_owner",
        "carrier_is_not_owner",
        "classification_inventory_is_evidence_only",
        "classification_evidence_cannot_authorize_execution",
        "persistent_binding_catalog_forbidden",
        "impact_registry_remains_carrier_authority",
        "live_current_binding_required_for_resolved_capability",
        "exact_consumer_binding_unique",
        "historical_bindings_do_not_count_as_current_multiplicity",
        "dispatch_execution_crossbind_required",
        "current_version_manifest_crossbind_required",
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
    if not _nonempty(guard.get("orchestrator_execution_id")):
        raise ResolutionError("BLOCK_ORCHESTRATOR_EXECUTION_ID")
    if not _uuid(guard.get("receipt_id")):
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
    if not _nonempty(admin.get("source_revision")):
        raise ResolutionError("BLOCK_PLAN_SUPER_ADMIN_SOURCE_REVISION")
    if not _sha256(plan.get("plan_sha256")):
        raise ResolutionError("BLOCK_PLAN_DIGEST")
    required = plan.get("required_controls")
    carriers = plan.get("carrier_controls")
    if not isinstance(required, list) or not isinstance(carriers, dict):
        raise ResolutionError("BLOCK_PLAN_CONTROL_SHAPE")
    required_set = set(required)
    if len(required_set) != len(required):
        raise ResolutionError("BLOCK_DUPLICATE_REQUIRED_CONTROL")
    reverse: dict[str, str] = {}
    for carrier, controls in carriers.items():
        if not _nonempty(carrier) or not isinstance(controls, list):
            raise ResolutionError("BLOCK_PLAN_CARRIER_SHAPE")
        for control_id in controls:
            if not _nonempty(control_id):
                raise ResolutionError("BLOCK_PLAN_CONTROL_ID")
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
        if not isinstance(row, dict) or not _nonempty(row.get(key)):
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


def _validate_live_row(*, control_id: str, capability_id: str, plan_digest: str, row: dict[str, Any]) -> dict[str, Any]:
    if row.get("control_id") != control_id:
        raise ResolutionError(f"BLOCK_LIVE_CONTROL_CROSSBIND:{control_id}")
    if row.get("capability_code") != capability_id:
        raise ResolutionError(f"BLOCK_LIVE_CAPABILITY_CROSSBIND:{control_id}")
    if row.get("registry_status") != "ACTIVE":
        raise ResolutionError(f"BLOCK_LIVE_CAPABILITY_NOT_ACTIVE:{control_id}")
    if row.get("entry_guard_required") is not True or row.get("entry_guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        raise ResolutionError(f"BLOCK_LIVE_ENTRY_GUARD:{control_id}")
    current_version = row.get("current_version")
    current_manifest = row.get("current_manifest_sha256")
    if not _nonempty(current_version) or not _sha256(current_manifest):
        raise ResolutionError(f"BLOCK_LIVE_CURRENT_IDENTITY:{control_id}")
    if row.get("version_release_state") != "RELEASED":
        raise ResolutionError(f"BLOCK_LIVE_VERSION_NOT_RELEASED:{control_id}")
    if not _nonempty(row.get("source_ref")) or not _nonempty(row.get("source_revision")) or not _nonempty(row.get("runner_ref")):
        raise ResolutionError(f"BLOCK_LIVE_SOURCE_IDENTITY:{control_id}")
    if row.get("dispatch_plan_digest") != plan_digest:
        raise ResolutionError(f"BLOCK_LIVE_DISPATCH_PLAN:{control_id}")
    if row.get("dispatch_capability_code") != capability_id:
        raise ResolutionError(f"BLOCK_LIVE_DISPATCH_CAPABILITY:{control_id}")
    if row.get("dispatch_guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        raise ResolutionError(f"BLOCK_LIVE_DISPATCH_GUARD:{control_id}")
    if not _uuid(row.get("dispatch_receipt_id")) or not _sha256(row.get("dispatch_receipt_sha256")):
        raise ResolutionError(f"BLOCK_LIVE_DISPATCH_RECEIPT:{control_id}")
    orchestrator_execution_id = row.get("orchestrator_execution_id")
    consumer_execution_id = row.get("consumer_execution_id")
    if not _nonempty(orchestrator_execution_id) or not _nonempty(consumer_execution_id):
        raise ResolutionError(f"BLOCK_LIVE_EXECUTION_IDENTITY:{control_id}")
    if row.get("matching_current_binding_count") != 1:
        raise ResolutionError(f"BLOCK_LIVE_BINDING_CARDINALITY:{control_id}")
    if row.get("binding_execution_id") != consumer_execution_id or row.get("binding_capability_code") != capability_id:
        raise ResolutionError(f"BLOCK_LIVE_BINDING_EXECUTION:{control_id}")
    if row.get("bound_version") != current_version or row.get("bound_manifest_sha256") != current_manifest:
        raise ResolutionError(f"BLOCK_LIVE_BINDING_CURRENTNESS:{control_id}")
    if row.get("operation_execution_id") != consumer_execution_id:
        raise ResolutionError(f"BLOCK_LIVE_OPERATION_EXECUTION:{control_id}")
    if row.get("operation_status") not in {"IN_PROGRESS", "COMPLETED"}:
        raise ResolutionError(f"BLOCK_LIVE_OPERATION_STATUS:{control_id}")
    if row.get("operation_manifest_plan_digest") != plan_digest:
        raise ResolutionError(f"BLOCK_LIVE_OPERATION_PLAN:{control_id}")
    if row.get("operation_manifest_capability_code") != capability_id:
        raise ResolutionError(f"BLOCK_LIVE_OPERATION_CAPABILITY:{control_id}")
    if row.get("operation_manifest_orchestrator_execution_id") != orchestrator_execution_id:
        raise ResolutionError(f"BLOCK_LIVE_OPERATION_ORCHESTRATOR:{control_id}")
    if row.get("dispatch_consumer_execution_id") != consumer_execution_id or row.get("dispatch_orchestrator_execution_id") != orchestrator_execution_id:
        raise ResolutionError(f"BLOCK_LIVE_DISPATCH_EXECUTION:{control_id}")
    return row


def validate_live_binding_readback(plan: dict[str, Any], readback: Any, required_controls: set[str]) -> dict[str, dict[str, Any]]:
    if not isinstance(readback, dict) or readback.get("schema_version") != LIVE_READBACK_SCHEMA:
        raise ResolutionError("BLOCK_LIVE_BINDING_READBACK_SCHEMA")
    if readback.get("authority") != "CANONICAL_LIVE_AUTHORITIES_READBACK_ONLY":
        raise ResolutionError("BLOCK_LIVE_BINDING_READBACK_AUTHORITY")
    if readback.get("plan_digest") != plan.get("plan_sha256"):
        raise ResolutionError("BLOCK_LIVE_BINDING_READBACK_PLAN")
    if readback.get("classification_inventory_is_authority") is not False:
        raise ResolutionError("BLOCK_CLASSIFICATION_AUTHORITY_COLLAPSE")
    rows = index_unique(readback.get("rows"), "control_id", "BLOCK_LIVE_BINDING_ROWS")
    extra = sorted(set(rows) - required_controls)
    missing = sorted(required_controls - set(rows))
    if extra or missing:
        raise ResolutionError(f"BLOCK_LIVE_BINDING_COVERAGE:missing={','.join(missing) or '-'}:extra={','.join(extra) or '-'}")
    return rows


def resolve(plan: dict[str, Any], entry_readback: dict[str, Any], live_binding_readback: dict[str, Any] | None = None) -> dict[str, Any]:
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

    prepared: list[dict[str, Any]] = []
    live_required: set[str] = set()
    for control_id in sorted(carrier_by_control):
        canonical_carrier = carrier_by_control[control_id]
        impact_row = impact_rows.get(control_id)
        evidence_row = inventory_rows.get(control_id)
        if impact_row is None or evidence_row is None:
            raise ResolutionError(f"BLOCK_UNKNOWN_CONTROL:{control_id}")
        if impact_row.get("carrier") != canonical_carrier or evidence_row.get("carrier") != canonical_carrier:
            raise ResolutionError(f"BLOCK_CARRIER_DRIFT:{control_id}")
        classification = evidence_row.get("classification")
        runner_state = evidence_row.get("runner_state")
        asset_state = evidence_row.get("canonical_asset_state")
        runner_ref = evidence_row.get("runner_ref")
        if not _nonempty(classification) or not _nonempty(runner_ref) or not _nonempty(runner_state) or not _nonempty(asset_state):
            raise ResolutionError(f"BLOCK_OWNER_RUNNER_EVIDENCE:{control_id}")
        capability_id = evidence_row.get("canonical_asset_code") or evidence_row.get("target_parent_capability")
        if classification == "INTERNAL_CI_CHECK":
            capability_id = None
            effective_runner_state = "CARRIER_INTERNAL"
        else:
            effective_runner_state = runner_state
            if not _nonempty(capability_id):
                capability_id = None
        state = row_state(classification, runner_state, asset_state)
        if state == "RESOLVED_CURRENT_CARRIER":
            if capability_id is None:
                raise ResolutionError(f"BLOCK_LIVE_CAPABILITY_ID_MISSING:{control_id}")
            live_required.add(control_id)
        prepared.append({
            "control_id": control_id,
            "canonical_carrier": canonical_carrier,
            "classification": classification,
            "capability_id": capability_id,
            "inventory_runner_ref": runner_ref,
            "runner_state": effective_runner_state,
            "state": state,
            "evidence_row": evidence_row,
        })

    if live_required:
        if live_binding_readback is None:
            raise ResolutionError("BLOCK_LIVE_BINDING_READBACK_MISSING")
        live_rows = validate_live_binding_readback(plan, live_binding_readback, live_required)
    else:
        if live_binding_readback is not None:
            validate_live_binding_readback(plan, live_binding_readback, set())
        live_rows = {}

    resolved: list[dict[str, Any]] = []
    for item in prepared:
        control_id = item["control_id"]
        evidence_row = item["evidence_row"]
        state = item["state"]
        source_revision = evidence_row.get("source_revision")
        runner_ref = item["inventory_runner_ref"]
        row: dict[str, Any] = {
            "control_id": control_id,
            "super_admin": "LF_GOVERNANCE",
            "classification": item["classification"],
            "capability_id": item["capability_id"],
            "runner_ref": runner_ref,
            "runner_state": item["runner_state"],
            "carrier": item["canonical_carrier"],
            "state": state,
            "source_revision": source_revision if _nonempty(source_revision) else sha256_bytes(canonical(evidence_row).encode("utf-8")),
            "current_version": None,
            "current_manifest_sha256": None,
            "consumer_execution_id": None,
            "orchestrator_execution_id": None,
            "dispatch_receipt_id": None,
            "binding_execution_id": None,
            "operation_status": None,
        }
        if state == "RESOLVED_CURRENT_CARRIER":
            live = _validate_live_row(
                control_id=control_id,
                capability_id=item["capability_id"],
                plan_digest=plan["plan_sha256"],
                row=live_rows[control_id],
            )
            row.update({
                "runner_ref": live["runner_ref"],
                "source_revision": live["source_revision"],
                "current_version": live["current_version"],
                "current_manifest_sha256": live["current_manifest_sha256"],
                "consumer_execution_id": live["consumer_execution_id"],
                "orchestrator_execution_id": live["orchestrator_execution_id"],
                "dispatch_receipt_id": live["dispatch_receipt_id"],
                "binding_execution_id": live["binding_execution_id"],
                "operation_status": live["operation_status"],
                "binding_selection": "EXACT_CONSUMER_EXECUTION_PLUS_CURRENT_VERSION_AND_MANIFEST",
            })
        resolved.append(row)

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
        "live_binding_readback_consumed": bool(live_required),
        "live_binding_control_count": len(live_required),
        "historical_binding_rows_are_not_current_multiplicity": True,
        "rows": resolved,
    }
    payload["read_model_revision"] = sha256_bytes(canonical(payload).encode("utf-8"))
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--entry-readback", required=True, type=Path)
    parser.add_argument("--live-binding-readback", type=Path)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    readback = json.loads(args.entry_readback.read_text(encoding="utf-8"))
    live = json.loads(args.live_binding_readback.read_text(encoding="utf-8")) if args.live_binding_readback else None
    try:
        result = resolve(plan, readback, live)
    except ResolutionError as exc:
        print(json.dumps({"ready": False, "decision": str(exc)}, sort_keys=True))
        raise SystemExit(2) from exc
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0 if result["ready"] else 3)


if __name__ == "__main__":
    main()
