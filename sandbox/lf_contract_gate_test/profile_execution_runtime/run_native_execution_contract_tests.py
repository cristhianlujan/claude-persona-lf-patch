#!/usr/bin/env python3
from copy import deepcopy

from profile_execution_contract import (
    build_control_receipt,
    build_execution_contract,
    canonical_json_sha256,
    validate_control_receipt,
    validate_execution_contract,
)

CONTEXT_SHA = "a" * 64
CARD_SHA = "b" * 64


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

    print(f"PROFILE_EXECUTION_CONTRACT_TESTS_PASS {passed}/11")


if __name__ == "__main__":
    main()
