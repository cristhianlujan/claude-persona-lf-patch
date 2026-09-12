from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from .gate_a_admission import admit_input

HERE = Path(__file__).resolve().parent
OUTPUT_PATH = HERE / "gate_b_output.json"
CONTRACT_PATH = HERE / "preexecution_contract.json"


class GateBGovernanceBlocked(RuntimeError):
    pass


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise GateBGovernanceBlocked(f"GATE_B_NOT_OBJECT:{path.name}")
    return payload


def evaluate_governance(gate_a: dict[str, Any] | None = None) -> dict[str, Any]:
    gate_a = gate_a or admit_input()
    a = gate_a["output"]
    payload = _load_json(OUTPUT_PATH)
    contract = _load_json(CONTRACT_PATH)
    expected = contract.get("stage_b_ekb") or {}

    if payload.get("schema") != "S26_HP001_GATE_B_OUTPUT_V1":
        raise GateBGovernanceBlocked("GATE_B_SCHEMA_INVALID")
    if payload.get("gate") != "B_EKB_GOVERNANCE":
        raise GateBGovernanceBlocked("GATE_B_NAME_INVALID")
    if payload.get("project_id") != "S26" or payload.get("run_id") != a.get("run_id"):
        raise GateBGovernanceBlocked("GATE_B_IDENTITY_INVALID")
    if a.get("next_gate") != "B_EKB_GOVERNANCE":
        raise GateBGovernanceBlocked("GATE_A_DID_NOT_AUTHORIZE_B")

    upstream = payload.get("upstream") or {}
    if upstream.get("source_gate") != "A_INPUT_ADMISSION":
        raise GateBGovernanceBlocked("GATE_B_UPSTREAM_GATE_INVALID")
    if upstream.get("source_output_sha256") != gate_a.get("output_sha256"):
        raise GateBGovernanceBlocked("GATE_B_UPSTREAM_OUTPUT_SHA_MISMATCH")
    a_input = a.get("input") or {}
    if upstream.get("input_sha256") != a_input.get("sha256"):
        raise GateBGovernanceBlocked("GATE_B_UPSTREAM_INPUT_SHA_MISMATCH")

    inherited = payload.get("input") or {}
    if inherited.get("source_type") != "USER_TEXT":
        raise GateBGovernanceBlocked("GATE_B_INPUT_TYPE_INVALID")
    if inherited.get("content") != a_input.get("content"):
        raise GateBGovernanceBlocked("GATE_B_INPUT_CONTENT_MUTATED")
    if inherited.get("sha256") != a_input.get("sha256"):
        raise GateBGovernanceBlocked("GATE_B_INPUT_SHA_MUTATED")
    if inherited.get("content_mutated") is not False:
        raise GateBGovernanceBlocked("GATE_B_MUTATION_FLAG_INVALID")

    gov = payload.get("governance") or {}
    if gov.get("source") != "SUPABASE_CONTROL_PLANE":
        raise GateBGovernanceBlocked("GATE_B_SOURCE_INVALID")
    if gov.get("project_ref") != expected.get("project_id") or gov.get("table") != expected.get("table"):
        raise GateBGovernanceBlocked("GATE_B_SOURCE_REF_INVALID")
    if gov.get("read_mode") != "LIVE_CONTROL_PLANE_READBACK_MATERIALIZED":
        raise GateBGovernanceBlocked("GATE_B_LIVE_READBACK_NOT_MATERIALIZED")
    if gov.get("schema_first_verified") is not True:
        raise GateBGovernanceBlocked("GATE_B_SCHEMA_FIRST_NOT_PROVEN")
    if gov.get("snapshot_scope") != a.get("run_id") + "_ONLY":
        raise GateBGovernanceBlocked("GATE_B_SNAPSHOT_SCOPE_INVALID")
    if gov.get("reusable_for_new_run") is not False:
        raise GateBGovernanceBlocked("GATE_B_SNAPSHOT_REUSE_ALLOWED")
    if not isinstance(gov.get("broad_high_critical_active_count"), int) or gov["broad_high_critical_active_count"] < 1:
        raise GateBGovernanceBlocked("GATE_B_BROAD_SNAPSHOT_EMPTY")
    broad_sha = gov.get("broad_snapshot_sha256")
    if not isinstance(broad_sha, str) or len(broad_sha) != 64:
        raise GateBGovernanceBlocked("GATE_B_BROAD_SNAPSHOT_SHA_INVALID")

    controls = gov.get("applicable_controls")
    if not isinstance(controls, list) or not controls:
        raise GateBGovernanceBlocked("GATE_B_APPLICABLE_CONTROLS_EMPTY")
    codes = [item.get("codigo") for item in controls if isinstance(item, dict)]
    if len(codes) != len(controls) or len(codes) != len(set(codes)):
        raise GateBGovernanceBlocked("GATE_B_CONTROL_CODES_INVALID")
    required_minimum = set(expected.get("minimum_applicable_codes") or [])
    if not required_minimum.issubset(set(codes)):
        missing = sorted(required_minimum.difference(codes))
        raise GateBGovernanceBlocked("GATE_B_REQUIRED_CONTROL_MISSING:" + ",".join(missing))
    for item in controls:
        if not item.get("severidad") or not item.get("rationale") or not item.get("source_ref"):
            raise GateBGovernanceBlocked("GATE_B_CONTROL_EVIDENCE_INCOMPLETE")

    basis = gov.get("selection_basis") or {}
    if basis.get("selection_mode") != "TASK_SIGNATURE_TARGETED_FROM_BROAD_ACTIVE_SNAPSHOT":
        raise GateBGovernanceBlocked("GATE_B_SELECTION_MODE_INVALID")
    if basis.get("project") != "S26" or basis.get("scope") != "HP001_GATE_PIPELINE":
        raise GateBGovernanceBlocked("GATE_B_TASK_SIGNATURE_INVALID")

    decision = payload.get("decision") or {}
    if decision.get("governance_context_ready") is not True:
        raise GateBGovernanceBlocked("GATE_B_CONTEXT_NOT_READY")
    if decision.get("blocking_controls_missing") is not False:
        raise GateBGovernanceBlocked("GATE_B_BLOCKING_CONTROL_GAP")
    if decision.get("input_mutation_allowed") is not False:
        raise GateBGovernanceBlocked("GATE_B_INPUT_MUTATION_ALLOWED")
    if decision.get("next_gate_authorized") is not True:
        raise GateBGovernanceBlocked("GATE_B_NEXT_GATE_NOT_AUTHORIZED")
    if payload.get("status") != "PASS" or payload.get("next_gate") != "C_CARD_SELECTION":
        raise GateBGovernanceBlocked("GATE_B_TRANSITION_INVALID")

    return {
        "output": payload,
        "output_sha256": _sha256(OUTPUT_PATH.read_bytes()),
        "input_sha256": inherited["sha256"],
        "applicable_control_count": len(controls),
        "broad_snapshot_count": gov["broad_high_critical_active_count"],
    }
