#!/usr/bin/env python3
from copy import deepcopy
from pathlib import Path
import subprocess
import sys

from contract_bound_profile_runtime import execute_contract_bound_profile_runtime
from profile_execution_contract import build_execution_contract
from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked
from validate_profile_execution import canonical_json_sha256, sha256_text, validate_receipt

PROFILE_SOURCES = [
    {"ref": "profiles/ui_architect/SKILL.md", "content": "# UI Architect\nUse governed contract."},
]
INPUT = "Evalua la pantalla B2B-CARGA-001 bajo el contrato Golden."
CONTEXT_SHA = "a" * 64
CARD_SHA = "b" * 64


def make_contract(mode="GPT_NATIVE"):
    return build_execution_contract(
        run_id="EXEC-S26-N03-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_version="v1",
        objective="Evaluate the frozen Golden screen.",
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
        executor_mode=mode,
    )


class NativeAdapter:
    adapter_id = "native-test-adapter"
    is_test_double = True

    def execute(self, request):
        assert request["execution_contract"]["contract_sha256"] == request["execution_contract_sha256"]
        assert request["executor_mode"] in {"GPT_NATIVE", "CLAUDE_NATIVE"}
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": {
                "worker": "ui_architect",
                "output_type": "PRODUCTION_UI_SPEC",
                "deliverable_created": {"screen_definition": {"task_mode": "REMEDIATE_EXISTING"}},
            },
            "runtime_attestation": {
                "provider": "native-test-provider",
                "model_id": "native-model-test",
                "run_id": "native-run-001",
                "attested_at": "2026-09-08T18:00:00+00:00",
                "adapter_id": self.adapter_id,
                "request_sha256": request["request_sha256"],
                "profile_source_sha256": request["profile_source_sha256"],
                "input_sha256": request["input_sha256"],
                "operation_code": request["operation_code"],
                "profile_code": request["profile_code"],
                "profile_slug": request["profile_slug"],
            },
        }


class NativeVerifier:
    verifier_id = "native-test-verifier"
    is_test_double = True

    def verify(self, *, request, response, adapter):
        response_sha = canonical_json_sha256(response)
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": sha256_text(f"{request['request_sha256']}:{response_sha}"),
        }


def run(mode):
    contract = make_contract(mode)
    return contract, execute_contract_bound_profile_runtime(
        execution_contract=contract,
        execution_id=contract["run_id"],
        profile_code=contract["profile_code"],
        profile_slug="ui_architect",
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
        adapter=NativeAdapter(),
        attestation_verifier=NativeVerifier(),
        allow_test_doubles=True,
    )


def main():
    passed = 0

    gpt_contract, gpt = run("GPT_NATIVE")
    assert gpt["executor_mode"] == "GPT_NATIVE"
    assert gpt["request"]["execution_contract_sha256"] == gpt_contract["contract_sha256"]
    assert gpt["receipt"]["execution_contract_sha256"] == gpt_contract["contract_sha256"]
    assert validate_receipt(
        gpt["receipt"],
        expected_profile_code="PERFIL-UI-ARCHITECT",
        expected_input_literal=INPUT,
        expected_raw_output=gpt["raw_output"],
    ) == []
    passed += 1

    claude_contract, claude = run("CLAUDE_NATIVE")
    assert claude["executor_mode"] == "CLAUDE_NATIVE"
    assert claude["request"]["execution_contract"]["schema"] == "LF_PROFILE_EXECUTION_CONTRACT_V1"
    passed += 1

    assert gpt["request"]["request_sha256"] != claude["request"]["request_sha256"]
    assert gpt_contract["contract_sha256"] != claude_contract["contract_sha256"]
    passed += 1

    wrong_run = make_contract()
    try:
        execute_contract_bound_profile_runtime(
            execution_contract=wrong_run,
            execution_id="OTHER-RUN",
            profile_code="PERFIL-UI-ARCHITECT",
            profile_slug="ui_architect",
            profile_sources=PROFILE_SOURCES,
            input_literal=INPUT,
            adapter=NativeAdapter(),
            attestation_verifier=NativeVerifier(),
            allow_test_doubles=True,
        )
    except RuntimeExecutionBlocked as exc:
        assert exc.code == "EXECUTION_CONTRACT_RUN_ID_MISMATCH"
    else:
        raise AssertionError("run mismatch must block")
    passed += 1

    tampered = deepcopy(make_contract())
    tampered["objective"] = "tampered"
    try:
        execute_contract_bound_profile_runtime(
            execution_contract=tampered,
            execution_id=tampered["run_id"],
            profile_code="PERFIL-UI-ARCHITECT",
            profile_slug="ui_architect",
            profile_sources=PROFILE_SOURCES,
            input_literal=INPUT,
            adapter=NativeAdapter(),
            attestation_verifier=NativeVerifier(),
            allow_test_doubles=True,
        )
    except RuntimeExecutionBlocked as exc:
        assert exc.code == "EXECUTION_CONTRACT_INVALID"
    else:
        raise AssertionError("tampered contract must block")
    passed += 1

    print(f"CONTRACT_BOUND_PROFILE_RUNTIME_TESTS_PASS {passed}/5")

    source_first_test = Path(__file__).with_name("run_s26_source_first_runtime_tests.py")
    subprocess.run([sys.executable, str(source_first_test)], check=True)

    source_first_prebind_test = Path(__file__).with_name("run_s26_source_first_prebind_tests.py")
    subprocess.run([sys.executable, str(source_first_prebind_test)], check=True)


if __name__ == "__main__":
    main()
