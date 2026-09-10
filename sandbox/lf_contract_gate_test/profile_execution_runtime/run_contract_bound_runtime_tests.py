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
    is_test_double = True

    def __init__(self, mode="GPT_NATIVE", *, provider=None, attested_mode=None, model_id=None):
        ids = {
            "GPT_NATIVE": "chatgpt-native-current-context-v1",
            "CLAUDE_NATIVE": "claude-native-current-context-v1",
            "REMOTE_API": "cloudflare-workers-ai-v1",
        }
        default_providers = {
            "GPT_NATIVE": "OPENAI_CHATGPT_NATIVE",
            "CLAUDE_NATIVE": "ANTHROPIC_CLAUDE_NATIVE",
            "REMOTE_API": "CLOUDFLARE_WORKERS_AI",
        }
        default_models = {
            "GPT_NATIVE": "gpt-native-test",
            "CLAUDE_NATIVE": "claude-native-test",
            "REMOTE_API": "@cf/test/model",
        }
        self.adapter_id = ids[mode]
        self.provider = provider or default_providers[mode]
        self.attested_mode = mode if attested_mode is None else attested_mode
        self.model_id = model_id or default_models[mode]

    def execute(self, request):
        assert request["execution_contract"]["contract_sha256"] == request["execution_contract_sha256"]
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": {
                "worker": "ui_architect",
                "output_type": "PRODUCTION_UI_SPEC",
                "deliverable_created": {"screen_definition": {"task_mode": "REMEDIATE_EXISTING"}},
            },
            "runtime_attestation": {
                "provider": self.provider,
                "model_id": self.model_id,
                "run_id": "native-run-001",
                "attested_at": "2026-09-08T18:00:00+00:00",
                "adapter_id": self.adapter_id,
                "executor_mode": self.attested_mode,
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
        adapter=NativeAdapter(mode),
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

    remote_contract, remote = run("REMOTE_API")
    assert remote["executor_mode"] == "REMOTE_API"
    passed += 1

    assert gpt["request"]["request_sha256"] != claude["request"]["request_sha256"]
    assert gpt_contract["contract_sha256"] != claude_contract["contract_sha256"]
    assert remote_contract["contract_sha256"] not in {gpt_contract["contract_sha256"], claude_contract["contract_sha256"]}
    passed += 1

    # Cross-mode mismatch must fail before the adapter is invoked.
    mismatch_contract = make_contract("GPT_NATIVE")
    try:
        execute_contract_bound_profile_runtime(
            execution_contract=mismatch_contract,
            execution_id=mismatch_contract["run_id"],
            profile_code=mismatch_contract["profile_code"],
            profile_slug="ui_architect",
            profile_sources=PROFILE_SOURCES,
            input_literal=INPUT,
            adapter=NativeAdapter("REMOTE_API"),
            attestation_verifier=NativeVerifier(),
            allow_test_doubles=True,
        )
    except RuntimeExecutionBlocked as exc:
        assert exc.code == "EXECUTOR_MODE_ADAPTER_MISMATCH"
    else:
        raise AssertionError("GPT_NATIVE with REMOTE_API adapter must block")
    passed += 1

    provider_contract = make_contract("GPT_NATIVE")
    try:
        execute_contract_bound_profile_runtime(
            execution_contract=provider_contract,
            execution_id=provider_contract["run_id"],
            profile_code=provider_contract["profile_code"],
            profile_slug="ui_architect",
            profile_sources=PROFILE_SOURCES,
            input_literal=INPUT,
            adapter=NativeAdapter("GPT_NATIVE", provider="CLOUDFLARE_WORKERS_AI"),
            attestation_verifier=NativeVerifier(),
            allow_test_doubles=True,
        )
    except RuntimeExecutionBlocked as exc:
        assert exc.code == "EXECUTOR_MODE_PROVIDER_MISMATCH"
    else:
        raise AssertionError("GPT_NATIVE with remote provider must block")
    passed += 1

    for contract_mode, adapter_mode in (
        ("CLAUDE_NATIVE", "GPT_NATIVE"),
        ("REMOTE_API", "GPT_NATIVE"),
    ):
        cross_contract = make_contract(contract_mode)
        try:
            execute_contract_bound_profile_runtime(
                execution_contract=cross_contract,
                execution_id=cross_contract["run_id"],
                profile_code=cross_contract["profile_code"],
                profile_slug="ui_architect",
                profile_sources=PROFILE_SOURCES,
                input_literal=INPUT,
                adapter=NativeAdapter(adapter_mode),
                attestation_verifier=NativeVerifier(),
                allow_test_doubles=True,
            )
        except RuntimeExecutionBlocked as exc:
            assert exc.code == "EXECUTOR_MODE_ADAPTER_MISMATCH"
        else:
            raise AssertionError(f"{contract_mode} with {adapter_mode} adapter must block")
        passed += 1

    model_contract = make_contract("CLAUDE_NATIVE")
    try:
        execute_contract_bound_profile_runtime(
            execution_contract=model_contract,
            execution_id=model_contract["run_id"],
            profile_code=model_contract["profile_code"],
            profile_slug="ui_architect",
            profile_sources=PROFILE_SOURCES,
            input_literal=INPUT,
            adapter=NativeAdapter("CLAUDE_NATIVE", model_id="mistral-test"),
            attestation_verifier=NativeVerifier(),
            allow_test_doubles=True,
        )
    except RuntimeExecutionBlocked as exc:
        assert exc.code == "EXECUTOR_MODE_MODEL_ID_MISMATCH"
    else:
        raise AssertionError("CLAUDE_NATIVE with non-Claude model must block")
    passed += 1

    attestation_contract = make_contract("CLAUDE_NATIVE")
    try:
        execute_contract_bound_profile_runtime(
            execution_contract=attestation_contract,
            execution_id=attestation_contract["run_id"],
            profile_code=attestation_contract["profile_code"],
            profile_slug="ui_architect",
            profile_sources=PROFILE_SOURCES,
            input_literal=INPUT,
            adapter=NativeAdapter("CLAUDE_NATIVE", attested_mode="GPT_NATIVE"),
            attestation_verifier=NativeVerifier(),
            allow_test_doubles=True,
        )
    except RuntimeExecutionBlocked as exc:
        assert exc.code == "EXECUTOR_MODE_ATTESTATION_MISMATCH"
    else:
        raise AssertionError("attested executor mode mismatch must block")
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

    print(f"CONTRACT_BOUND_PROFILE_RUNTIME_TESTS_PASS {passed}/12")

    source_first_test = Path(__file__).with_name("run_s26_source_first_runtime_tests.py")
    subprocess.run([sys.executable, str(source_first_test)], check=True)

    source_first_prebind_test = Path(__file__).with_name("run_s26_source_first_prebind_tests.py")
    subprocess.run([sys.executable, str(source_first_prebind_test)], check=True)


if __name__ == "__main__":
    main()

