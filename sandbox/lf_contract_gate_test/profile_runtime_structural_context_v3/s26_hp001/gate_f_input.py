from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = Path(__file__).resolve().parents[4]
E_OUTPUT = HERE / "gate_e_output.json"
F_INPUT = HERE / "gate_f_input.json"
F_RECEIPT = HERE / "manual_profile_execution_receipt.json"
QDP_CONTRACT = HERE / "quality_depth_performance_contract.json"


class GateFInputBlocked(RuntimeError):
    pass


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _git_blob_sha(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("utf-8") + raw).hexdigest()


def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise GateFInputBlocked(f"GATE_F_INPUT_NOT_OBJECT:{path.name}")
    return value


def _validate_payload(payload: dict[str, Any], gate_e: dict[str, Any], receipt: dict[str, Any]) -> None:
    if payload.get("schema") != "S26_HP001_GATE_F_INPUT_V1":
        raise GateFInputBlocked("GATE_F_INPUT_SCHEMA_INVALID")
    if payload.get("gate") != "F_PROFILE_EXECUTION_INPUT":
        raise GateFInputBlocked("GATE_F_INPUT_GATE_INVALID")
    if payload.get("project_id") != "S26" or payload.get("run_id") != gate_e.get("run_id"):
        raise GateFInputBlocked("GATE_F_INPUT_IDENTITY_INVALID")
    if gate_e.get("status") != "PASS" or gate_e.get("next_gate") != "F_PROFILE_EXECUTION":
        raise GateFInputBlocked("GATE_E_DID_NOT_AUTHORIZE_F")

    e_raw = E_OUTPUT.read_bytes()
    e_sha = _sha256(e_raw)
    upstream = payload.get("upstream") or {}
    binding = upstream.get("committed_readback_binding") or {}
    if upstream.get("source_gate") != "E_ADAPTER_TYPED_CONTEXT":
        raise GateFInputBlocked("GATE_F_INPUT_SOURCE_GATE_INVALID")
    if upstream.get("source_output_sha256") != e_sha or binding.get("source_sha256") != e_sha:
        raise GateFInputBlocked("GATE_F_INPUT_E_SHA_MISMATCH")
    if binding.get("source_ref") != "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_e_output.json":
        raise GateFInputBlocked("GATE_F_INPUT_E_REF_INVALID")
    if binding.get("source_commit_sha") != "5cb6ab761f1aa5dea546f8923f184295d0fdb807":
        raise GateFInputBlocked("GATE_F_INPUT_E_COMMIT_INVALID")
    if binding.get("source_git_blob_sha") != _git_blob_sha(e_raw):
        raise GateFInputBlocked("GATE_F_INPUT_E_BLOB_INVALID")
    if binding.get("same_commit_source_and_binding_forbidden") is not True:
        raise GateFInputBlocked("GATE_F_INPUT_SAME_COMMIT_GUARD_MISSING")
    if upstream.get("input_sha256") != gate_e.get("typed_context", {}).get("input_literal_sha256"):
        raise GateFInputBlocked("GATE_F_INPUT_LITERAL_SHA_MISMATCH")

    boot = payload.get("bootstrap_context") or {}
    e_boot = gate_e.get("bootstrap_context") or {}
    for key in ("bootstrap_context_sha256", "operation_code", "execution_mode", "distribution_mode", "policy_snapshot_sha256"):
        e_key = key if key != "bootstrap_context_sha256" else "source_sha256"
        if boot.get(key) != e_boot.get(e_key):
            raise GateFInputBlocked(f"GATE_F_INPUT_BOOTSTRAP_DRIFT:{key}")

    p = payload.get("profile_input") or {}
    typed = gate_e.get("typed_context") or {}
    fields = typed.get("input_fields") or {}
    expected = {
        "profile_slug": fields.get("profile_slug"),
        "task_mode": fields.get("task_mode"),
        "output_contract_version": fields.get("output_contract_version"),
        "domain_scope": fields.get("domain_scope"),
        "input_literal_sha256": typed.get("input_literal_sha256"),
        "typed_context_sha256": gate_e.get("typed_context_sha256"),
        "card_resolution": (typed.get("card_resolution") or {}).get("mode"),
        "adapter_binding_count": len(typed.get("adapter_binding") or []),
        "authority_count": len(typed.get("authority_resolution") or []),
    }
    if p != expected:
        raise GateFInputBlocked("GATE_F_INPUT_PROFILE_CONTEXT_DIVERGENCE")

    acceptance = payload.get("acceptance_requirements") or {}
    qdp_raw = QDP_CONTRACT.read_bytes()
    if acceptance.get("quality_depth_performance_contract_ref") != "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/quality_depth_performance_contract.json":
        raise GateFInputBlocked("GATE_F_INPUT_QDP_REF_INVALID")
    if acceptance.get("quality_depth_performance_contract_sha256") != _sha256(qdp_raw):
        raise GateFInputBlocked("GATE_F_INPUT_QDP_SHA_MISMATCH")
    expected_acceptance = {
        "quality_depth_performance_contract_ref": "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/quality_depth_performance_contract.json",
        "quality_depth_performance_contract_sha256": _sha256(qdp_raw),
        "quality_required": True,
        "depth_required": True,
        "deterministic_performance_required": True,
        "model_generation_latency_required_at_gate_f": True,
        "independent_semantic_review_still_required": True,
    }
    if acceptance != expected_acceptance:
        raise GateFInputBlocked("GATE_F_INPUT_QDP_REQUIREMENTS_DIVERGENCE")

    compat = payload.get("current_f_compatibility") or {}
    if compat.get("receipt_ref") != "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/manual_profile_execution_receipt.json":
        raise GateFInputBlocked("GATE_F_INPUT_RECEIPT_REF_INVALID")
    if compat.get("compatibility_only") is not True:
        raise GateFInputBlocked("GATE_F_INPUT_COMPATIBILITY_ONLY_REQUIRED")
    if compat.get("historical_execution_consumed_this_boundary") is not False:
        raise GateFInputBlocked("GATE_F_INPUT_FALSE_HISTORICAL_CONSUMPTION_CLAIM")
    if compat.get("actual_consumption_must_be_proven_in_gate_f") is not True:
        raise GateFInputBlocked("GATE_F_INPUT_F_AUDIT_REQUIREMENT_MISSING")

    if receipt.get("test_id") != payload.get("run_id"):
        raise GateFInputBlocked("GATE_F_INPUT_RECEIPT_RUN_MISMATCH")
    if receipt.get("profile_slug") != p.get("profile_slug"):
        raise GateFInputBlocked("GATE_F_INPUT_RECEIPT_PROFILE_MISMATCH")
    if receipt.get("input_sha256") != p.get("input_literal_sha256"):
        raise GateFInputBlocked("GATE_F_INPUT_RECEIPT_INPUT_MISMATCH")
    if receipt.get("output_contract_version") != p.get("output_contract_version"):
        raise GateFInputBlocked("GATE_F_INPUT_RECEIPT_CONTRACT_MISMATCH")
    if receipt.get("card_resolution") != p.get("card_resolution"):
        raise GateFInputBlocked("GATE_F_INPUT_RECEIPT_CARD_MISMATCH")
    if receipt.get("execution_mode") != compat.get("receipt_execution_mode"):
        raise GateFInputBlocked("GATE_F_INPUT_RECEIPT_MODE_MISMATCH")

    decision = payload.get("decision") or {}
    if decision != {
        "input_contract_ready": True,
        "f_can_consume_without_schema_invention": True,
        "historical_consumption_claimed": False,
        "next_gate_authorized": True,
    }:
        raise GateFInputBlocked("GATE_F_INPUT_DECISION_INVALID")
    if payload.get("status") != "PASS" or payload.get("next_gate") != "F_PROFILE_EXECUTION":
        raise GateFInputBlocked("GATE_F_INPUT_TRANSITION_INVALID")


def evaluate_f_input() -> dict[str, Any]:
    gate_e = _load(E_OUTPUT)
    payload = _load(F_INPUT)
    receipt = _load(F_RECEIPT)
    _validate_payload(payload, gate_e, receipt)
    return {
        "output": payload,
        "output_sha256": _sha256(F_INPUT.read_bytes()),
        "source_e_sha256": _sha256(E_OUTPUT.read_bytes()),
        "typed_context_sha256": payload["profile_input"]["typed_context_sha256"],
        "bootstrap_context_sha256": payload["bootstrap_context"]["bootstrap_context_sha256"],
        "policy_snapshot_sha256": payload["bootstrap_context"]["policy_snapshot_sha256"],
        "quality_depth_performance_contract_sha256": payload["acceptance_requirements"]["quality_depth_performance_contract_sha256"],
        "f_compatibility_proven": True,
        "historical_f_consumption_proven": False,
    }
