#!/usr/bin/env python3
from copy import deepcopy

from profile_execution_contract import (
    ExecutionContractError,
    build_control_receipt,
    build_execution_contract,
    canonical_json_sha256,
    validate_control_receipt,
    validate_execution_contract,
    build_source_fidelity_contract,
    validate_downstream_semantics,
)

CONTEXT_SHA = "a" * 64
CARD_SHA = "b" * 64
CORE_SHA = "c" * 64
VISUAL_SHA = "ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287"


def make_contract(executor_mode: str = "GPT_NATIVE"):
    return build_execution_contract(
        run_id="EXEC-S26-NATIVE-CONTRACT-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_version="v1",
        objective="Evaluate a governed UI screen without bypassing deterministic gates.",
        authorized_scope=["screen:B2B-CARGA-001"],
        current_gate="GPT_NATIVE_GOLDEN",
        allowed_actions=["READ_INPUT", "EVALUATE_UI", "EMIT_FINDINGS"],
        forbidden_actions=["MODIFY_PRODUCTION", "MERGE_MAIN", "ACQUIRE_MODEL_WEIGHTS"],
        required_checks=["ROUTER", "INPUT_GOVERNANCE", "PROFILE_CONTRACT", "SEMANTIC_UTILITY"],
        required_evidence=["router", "input_governance", "profile_execution", "semantic"],
        closure_conditions=["NO_P0_OPEN", "EVIDENCE_PERSISTED", "READBACK_PASS"],
        input_governance_ref="programacion.input_readiness_runs/221",
        card_refs_and_hashes=[{"ref": "decision_product_experience", "sha256": CARD_SHA}],
        adapter_ref="ADAPTER-LF-SHELL-PROFILE-20260827",
        context_fingerprint=CONTEXT_SHA,
        tool_permissions=["READ_GITHUB", "READ_SUPABASE"],
        executor_mode=executor_mode,
    )


def make_generic_safe_contract(*, critical_authority_missing: bool = False):
    return build_execution_contract(
        run_id="EXEC-S26-GENERIC-SAFE-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_version="v1",
        objective="Resolve a governed UI task safely when no exact or compatible Card exists.",
        authorized_scope=["screen:GENERIC-001"],
        current_gate="GPT_NATIVE_GOLDEN",
        allowed_actions=["READ_INPUT", "EVALUATE_UI", "EMIT_FINDINGS"],
        forbidden_actions=["MODIFY_PRODUCTION", "MERGE_MAIN", "ACQUIRE_MODEL_WEIGHTS"],
        required_checks=["ROUTER", "INPUT_GOVERNANCE", "PROFILE_CONTRACT", "SEMANTIC_UTILITY"],
        required_evidence=["router", "input_governance", "profile_execution", "semantic"],
        closure_conditions=["NO_P0_OPEN", "EVIDENCE_PERSISTED", "READBACK_PASS"],
        input_governance_ref="programacion.input_readiness_runs/generic-safe",
        card_refs_and_hashes=[],
        adapter_ref="ADAPTER-LF-SHELL-PROFILE-20260827",
        context_fingerprint=CONTEXT_SHA,
        tool_permissions=["READ_GITHUB", "READ_SUPABASE"],
        executor_mode="GPT_NATIVE",
        card_resolution={
            "mode": "GENERIC_SAFE",
            "core_policy_ref": "profiles/ui_architect/SKILL.md",
            "core_policy_sha256": CORE_SHA,
            "critical_authority_missing": critical_authority_missing,
            "fallback_reason": "No exact or compatible Card is available; governed Core is sufficient.",
            "unresolved_capabilities": ["SPECIALIZED_PATTERN"],
        },
    )


def rehash_contract(contract):
    contract["contract_sha256"] = canonical_json_sha256({k: v for k, v in contract.items() if k != "contract_sha256"})
    return contract


def rehash_receipt(receipt):
    receipt["receipt_sha256"] = canonical_json_sha256({k: v for k, v in receipt.items() if k != "receipt_sha256"})
    return receipt


def main():
    passed = 0
    contract = make_contract()
    assert validate_execution_contract(contract) == []
    passed += 1

    assert validate_execution_contract(make_contract("CLAUDE_NATIVE"), expected_executor_mode="CLAUDE_NATIVE") == []
    passed += 1

    tampered = deepcopy(contract)
    tampered["objective"] = "changed after hash"
    assert "CONTRACT_SHA256_MISMATCH" in validate_execution_contract(tampered)
    passed += 1

    overlap = deepcopy(contract)
    overlap["allowed_actions"].append("MERGE_MAIN")
    rehash_contract(overlap)
    assert any(x.startswith("ACTION_POLICY_OVERLAP:") for x in validate_execution_contract(overlap))
    passed += 1

    receipt = build_control_receipt(
        contract,
        executed_checks=["ROUTER", "INPUT_GOVERNANCE", "PROFILE_CONTRACT", "SEMANTIC_UTILITY"],
        evidence_refs={
            "router": "ACT-0001:v0.3",
            "input_governance": "programacion.input_readiness_runs/221",
            "profile_execution": "PROFILE_EXECUTION_RECEIPT_V1:test",
            "semantic": "SEMANTIC_JUDGE_RECEIPT_V2:test",
        },
        closure_conditions_met=["NO_P0_OPEN", "EVIDENCE_PERSISTED", "READBACK_PASS"],
        action_log=["READ_INPUT", "EVALUATE_UI", "EMIT_FINDINGS"],
    )
    assert validate_control_receipt(contract, receipt) == []
    passed += 1

    missing_check = deepcopy(receipt)
    missing_check["executed_checks"] = ["ROUTER"]
    rehash_receipt(missing_check)
    assert any(x.startswith("REQUIRED_CHECKS_MISSING:") for x in validate_control_receipt(contract, missing_check))
    passed += 1

    missing_evidence = deepcopy(receipt)
    missing_evidence["evidence_refs"].pop("semantic")
    rehash_receipt(missing_evidence)
    assert "REQUIRED_EVIDENCE_MISSING:semantic" in validate_control_receipt(contract, missing_evidence)
    passed += 1

    forbidden = deepcopy(receipt)
    forbidden["action_log"].append("MERGE_MAIN")
    rehash_receipt(forbidden)
    errors = validate_control_receipt(contract, forbidden)
    assert "ACTION_OUTSIDE_ALLOWLIST:MERGE_MAIN" in errors
    assert "FORBIDDEN_ACTION_EXECUTED:MERGE_MAIN" in errors
    passed += 1

    scope = deepcopy(receipt)
    scope["scope_violations"] = ["screen:OTHER"]
    rehash_receipt(scope)
    assert "SCOPE_VIOLATION_PRESENT" in validate_control_receipt(contract, scope)
    passed += 1

    self_auth = deepcopy(receipt)
    self_auth["downstream_authorized"] = True
    rehash_receipt(self_auth)
    assert "CONTROL_SELF_AUTHORIZATION_FORBIDDEN" in validate_control_receipt(contract, self_auth)
    passed += 1

    wrong_executor = deepcopy(receipt)
    wrong_executor["executor_mode"] = "CLAUDE_NATIVE"
    rehash_receipt(wrong_executor)
    assert "CONTROL_EXECUTOR_MODE_MISMATCH" in validate_control_receipt(contract, wrong_executor)
    passed += 1

    generic = make_generic_safe_contract()
    assert validate_execution_contract(generic) == []
    passed += 1

    no_card_no_resolution = deepcopy(generic)
    no_card_no_resolution.pop("card_resolution")
    rehash_contract(no_card_no_resolution)
    assert "CARD_RESOLUTION_REQUIRED_WHEN_NO_CARD" in validate_execution_contract(no_card_no_resolution)
    passed += 1

    try:
        make_generic_safe_contract(critical_authority_missing=True)
        raise AssertionError("critical authority gap must block")
    except ExecutionContractError as exc:
        assert "CRITICAL_AUTHORITY_MISSING" in str(exc)
    passed += 1

    missing_fidelity_bind = deepcopy(contract)
    missing_fidelity_bind["source_fidelity_contract_ref"] = "evidence/source_fidelity_contract.json"
    missing_fidelity_bind["source_fidelity_contract_sha256"] = "d" * 64
    rehash_contract(missing_fidelity_bind)
    fidelity_errors = validate_execution_contract(missing_fidelity_bind)
    assert "SOURCE_FIDELITY_REQUIRED_CHECK_MISSING" in fidelity_errors
    assert "SOURCE_FIDELITY_REQUIRED_EVIDENCE_MISSING" in fidelity_errors
    passed += 1

    source_headers = [
        ("lote", "Lote"), ("nombre", "Nombre"), ("archivo", "Archivo"), ("tipo", "Tipo"),
        ("cargado_por", "Cargado por"), ("fecha", "Fecha"), ("total", "Total"),
        ("validos", "Válidos"), ("estado", "Estado"), ("acciones", "Acciones"),
    ]
    source_entities = [
        {"entity_id": f"history_table.column.{key}", "kind": "TABLE_COLUMN", "semantic_signature": {"label": label}}
        for key, label in source_headers
    ]
    source_fidelity = build_source_fidelity_contract(
        source_ref="source_visual.png",
        source_sha256=VISUAL_SHA,
        authority_kind="VISUAL_ONLY",
        extraction_confidence=0.97,
        critical_ambiguity=False,
        immutable_entities=source_entities,
        mutable_dimensions=["LAYOUT", "SPACING", "RESPONSIVE", "OVERFLOW_STRATEGY"],
    )
    assert validate_downstream_semantics(source_fidelity, list(reversed(source_entities))) == []
    passed += 1

    bad_headers = [
        ("fecha_carga", "Fecha de carga"), ("archivo", "Archivo"), ("tipo", "Tipo"),
        ("registros", "Registros"), ("validos", "Válidos"), ("con_error", "Con error"),
        ("estado", "Estado"), ("usuario", "Usuario"), ("fecha_proceso", "Fecha de proceso"),
        ("acciones", "Acciones"),
    ]
    bad_entities = [
        {"entity_id": f"history_table.column.{key}", "kind": "TABLE_COLUMN", "semantic_signature": {"label": label}}
        for key, label in bad_headers
    ]
    bad_errors = validate_downstream_semantics(source_fidelity, bad_entities)
    assert len([x for x in bad_errors if x.startswith("SEMANTIC_ENTITY_MISSING:")]) == 5, bad_errors
    assert len([x for x in bad_errors if x.startswith("SEMANTIC_ENTITY_INVENTED:")]) == 5, bad_errors
    passed += 1

    mutated = deepcopy(source_entities)
    mutated[0]["semantic_signature"]["label"] = "Batch"
    assert "SEMANTIC_ENTITY_MUTATED:history_table.column.lote" in validate_downstream_semantics(source_fidelity, mutated)
    passed += 1

    print(f"PROFILE_EXECUTION_CONTRACT_TESTS_PASS {passed}/18")


if __name__ == "__main__":
    main()
