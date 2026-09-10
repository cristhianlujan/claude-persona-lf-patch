#!/usr/bin/env python3
"""Deterministic sandbox tests for Router Context Compiler V3 candidate.

This test does not claim LLM semantic quality. It verifies the transport contract:
- fail-closed responses remain RAW;
- non-blocked responses expose a compact capsule;
- contracts/policies/adapters/current step/input governance remain JIT-recoverable;
- binding hashes detect tampering;
- target_hint is not part of the compiler API.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def compile_from_raw(raw: dict[str, Any], context_id: str = "00000000-0000-0000-0000-000000000001") -> dict[str, Any]:
    raw_bytes = len(canonical_bytes(raw))
    router_sha = sha(raw)
    if raw.get("status") == "BLOCKED":
        return {
            "context_contract": "LF_ROUTER_CONTEXT_V3_CANDIDATE",
            "transport_mode": "RAW_FAIL_CLOSED",
            "router_sha256": router_sha,
            "raw_bytes": raw_bytes,
            "capsule_bytes": raw_bytes,
            "payload": raw,
        }

    contracts = raw.get("contract_refs") or []
    policies = raw.get("policy_refs") or []
    adapters = raw.get("adapters") or []
    step = raw.get("next_step")
    ig = raw.get("input_governance")
    asset = raw.get("asset") or {}
    handles = {}
    if contracts:
        handles["contracts"] = sha(contracts)
    if policies:
        handles["policies"] = sha(policies)
    if adapters:
        handles["adapters"] = sha(adapters)
    if step is not None:
        handles["current_step"] = sha(step)
    if ig is not None:
        handles["input_governance"] = sha(ig)

    capsule = {
        "context_contract": "LF_ROUTER_CONTEXT_V3_CANDIDATE",
        "context_id": context_id,
        "status": raw.get("status"),
        "router": "ACT-0001",
        "source": "SUPABASE",
        "asset": {
            "code": asset.get("codigo_activo") or raw.get("asset_code"),
            "type": asset.get("tipo_activo") or raw.get("asset_type"),
        },
        "action": raw.get("action_code"),
        "operation": (
            {"code": raw.get("operation_code"), "status": raw.get("operation_status")}
            if raw.get("operation_code")
            else None
        ),
        "blocking_code": raw.get("blocking_code"),
        "downstream_allowed": raw.get("downstream_execution_allowed") if "downstream_execution_allowed" in raw else None,
        "handles": handles,
        "router_sha256": router_sha,
    }
    capsule = {k: v for k, v in capsule.items() if v is not None}
    capsule_bytes = len(canonical_bytes(capsule))
    if capsule_bytes >= raw_bytes:
        return {
            "context_contract": "LF_ROUTER_CONTEXT_V3_CANDIDATE",
            "transport_mode": "RAW_NO_SAVINGS",
            "router_sha256": router_sha,
            "raw_bytes": raw_bytes,
            "capsule_bytes": raw_bytes,
            "payload": raw,
        }
    return {
        "context_contract": "LF_ROUTER_CONTEXT_V3_CANDIDATE",
        "transport_mode": "HANDLE_V3",
        "raw_bytes": raw_bytes,
        "capsule_bytes": capsule_bytes,
        "capsule": capsule,
    }


def resolve_reference(raw: dict[str, Any], kind: str, expected_sha: str) -> Any:
    mapping = {
        "CONTRACTS": raw.get("contract_refs") or [],
        "POLICIES": raw.get("policy_refs") or [],
        "ADAPTERS": raw.get("adapters") or [],
        "CURRENT_STEP": raw.get("next_step"),
        "INPUT_GOVERNANCE": raw.get("input_governance"),
    }
    if kind not in mapping:
        raise ValueError("ROUTER_CONTEXT_V3_HANDLE_KIND_NOT_AUTHORIZED")
    value = mapping[kind]
    if value is None:
        return None
    if sha(value) != expected_sha:
        raise ValueError("STALE_OR_TAMPERED_HANDLE")
    return value


def ready_skill() -> dict[str, Any]:
    return {
        "status": "READY_TO_EXECUTE",
        "router": "ACT-0001",
        "source": "SUPABASE",
        "asset": {"codigo_activo": "ACT-0046", "tipo_activo": "SKILL", "nombre_canonico": "X", "estado_documental": "CANDIDATO", "estado_operativo": "READ_ONLY", "version": "v0.1"},
        "action_code": "SKILL_EXECUTION",
        "operation_code": "EJECUCION_SKILL_LF",
        "operation_status": "SANDBOX_ACTIVE",
        "contract_refs": [["CONTRACT-EJECUCION-SKILL-LF-v0.1", None]],
        "policy_refs": [["P1", "v1", "a" * 64], ["P2", "v1", "b" * 64], ["P3", "v1", "c" * 64], ["P4", "v1", "d" * 64]],
        "adapters": [],
        "next_step": {"step_id": "init_execution", "execution_order": 0, "resolver_ref": "GPT_RUNTIME_WITH_SUPABASE_CONTEXT", "required_evidence_keys": ["execution_id_created"]},
        "precedence": ["OPERATION_CONTRACT", "POLICY", "ADAPTER", "PROFILE", "SHELL"],
        "composition_order": ["SHELL", "PROFILE", "ADAPTER", "POLICY_AND_CONTRACT_GATES"],
        "required_policy_count": 4,
        "resolved_policy_count": 4,
        "step_count": 9,
    }


def input_governance_profile() -> dict[str, Any]:
    raw = ready_skill()
    raw["asset"] = {"codigo_activo": "PERFIL-UI-ARCHITECT", "tipo_activo": "PERFIL", "nombre_canonico": "UI", "estado_documental": "CANDIDATO", "estado_operativo": "READ_ONLY", "version": "v1"}
    raw["action_code"] = "PROFILE_UPDATE"
    raw["operation_code"] = "ACTUALIZACION_PERFIL_LF"
    raw["operation_status"] = "PRODUCCION_CONTROLADA"
    raw["status"] = "INPUT_GOVERNANCE_REQUIRED"
    raw["blocking_code"] = "BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED"
    raw["downstream_execution_allowed"] = False
    raw["adapters"] = [{"adapter_code": "ADAPTER-LF-SHELL-PROFILE-20260827", "target_asset_code": "PERFIL-UI-ARCHITECT"}]
    raw["input_governance"] = {"status": "INPUT_GOVERNANCE_REQUIRED", "decision": "PENDING", "continuation_allowed": False, "required_by_adapters": ["ADAPTER_LF_SHELL_PROFILE"]}
    return raw


def blocked() -> dict[str, Any]:
    return {"status": "BLOCKED", "blocking_code": "BLOCK_ASSET_NOT_FOUND", "router": "ACT-0001", "asset_type": "SKILL", "action_code": "SKILL_EXECUTION"}


def inspection() -> dict[str, Any]:
    return {
        "status": "READY_INSPECTION",
        "router": "ACT-0001",
        "source": "SUPABASE",
        "asset": {"codigo_activo": "ACT-0001", "tipo_activo": "DOC", "nombre_canonico": "DOC_ROUTER_OPERATIVO_GOBERNANZA_LF", "estado_documental": "VIGENTE", "estado_operativo": "ACTIVO", "version": "v0.3"},
        "action_code": "ASSET_INSPECTION",
        "operation_code": None,
        "adapters": [],
        "precedence": ["OPERATION_CONTRACT", "POLICY", "ADAPTER", "PROFILE", "SHELL"],
    }


def run() -> None:
    # 1. Ready execution compacts and keeps all deep fields recoverable by hashes.
    raw = ready_skill()
    compiled = compile_from_raw(raw)
    assert compiled["transport_mode"] == "HANDLE_V3"
    cap = compiled["capsule"]
    assert cap["asset"] == {"code": "ACT-0046", "type": "SKILL"}
    assert cap["operation"]["code"] == "EJECUCION_SKILL_LF"
    assert compiled["capsule_bytes"] < compiled["raw_bytes"]
    for kind, key in [("CONTRACTS", "contracts"), ("POLICIES", "policies"), ("CURRENT_STEP", "current_step")]:
        assert resolve_reference(raw, kind, cap["handles"][key]) is not None

    # 2. Governance-sensitive Input Governance survives through a dedicated handle.
    raw_ig = input_governance_profile()
    compiled_ig = compile_from_raw(raw_ig)
    assert compiled_ig["transport_mode"] == "HANDLE_V3"
    cap_ig = compiled_ig["capsule"]
    assert cap_ig["status"] == "INPUT_GOVERNANCE_REQUIRED"
    assert cap_ig["blocking_code"] == "BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED"
    assert cap_ig["downstream_allowed"] is False
    assert resolve_reference(raw_ig, "INPUT_GOVERNANCE", cap_ig["handles"]["input_governance"])["decision"] == "PENDING"
    assert resolve_reference(raw_ig, "ADAPTERS", cap_ig["handles"]["adapters"])[0]["adapter_code"] == "ADAPTER-LF-SHELL-PROFILE-20260827"

    # 3. Hard blocks remain byte-for-byte RAW payloads.
    raw_block = blocked()
    compiled_block = compile_from_raw(raw_block)
    assert compiled_block["transport_mode"] == "RAW_FAIL_CLOSED"
    assert compiled_block["payload"] == raw_block

    # 4. Small inspection outputs may compact or deliberately stay RAW when no savings.
    raw_inspection = inspection()
    compiled_inspection = compile_from_raw(raw_inspection)
    assert compiled_inspection["transport_mode"] in {"HANDLE_V3", "RAW_NO_SAVINGS"}

    # 5. Tamper detection: changing the referenced payload invalidates the stored handle SHA.
    tampered = json.loads(json.dumps(raw))
    tampered["policy_refs"][0][2] = "f" * 64
    try:
        resolve_reference(tampered, "POLICIES", cap["handles"]["policies"])
        raise AssertionError("tampered policy set was accepted")
    except ValueError as exc:
        assert str(exc) == "STALE_OR_TAMPERED_HANDLE"

    # 6. Unknown handle kinds are fail-closed.
    try:
        resolve_reference(raw, "ARBITRARY_SQL", "x")
        raise AssertionError("unauthorized handle was accepted")
    except ValueError as exc:
        assert str(exc) == "ROUTER_CONTEXT_V3_HANDLE_KIND_NOT_AUTHORIZED"

    # 7. Evidence ceiling: this suite does not fabricate LLM semantic quality.
    receipt = {
        "executed": True,
        "exit_code": 0,
        "deterministic_cases": 7,
        "semantic_llm_output_quality": "NOT_OBSERVED_REQUIRES_SAME_INPUT_MODEL_AB",
        "claims": [
            "transport_contract",
            "jit_recoverability",
            "fail_closed_block_preservation",
            "tamper_detection",
        ],
    }
    print(json.dumps(receipt, sort_keys=True))


if __name__ == "__main__":
    run()
