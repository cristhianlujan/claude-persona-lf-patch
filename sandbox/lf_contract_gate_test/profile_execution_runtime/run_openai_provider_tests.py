#!/usr/bin/env python3
"""Offline contract tests for the OpenAI Responses profile runtime adapter."""

from __future__ import annotations

from copy import deepcopy

from openai_responses_runtime import (
    ADAPTER_ID,
    DEFAULT_MODEL,
    OpenAIResponsesAdapter,
    OpenAIResponsesReadbackVerifier,
)
from profile_runtime_runner import (
    RuntimeExecutionBlocked,
    build_runtime_request,
    execute_profile_runtime,
)
from validate_profile_execution import authorize_downstream

INPUT = "Evalúa esta pantalla y devuelve las decisiones ejecutables."
PROFILE_SOURCES = [
    {
        "ref": "profiles/ui_architect/SKILL.md",
        "content": "# UI Architect\nEvaluate visible hierarchy and return executable UI decisions.",
    },
    {
        "ref": "profiles/ui_architect/contracts/existing_screen_review.md",
        "content": "# Existing screen review\nPreserve source facts and forbid invented values.",
    },
]
OUTPUT = [
    {
        "id": "msg_test_001",
        "type": "message",
        "status": "completed",
        "role": "assistant",
        "content": [
            {
                "type": "output_text",
                "text": "Eliminar la franja duplicada y mantener Resumen como fuente única.",
                "annotations": [],
            }
        ],
    }
]


def request_fixture():
    return build_runtime_request(
        execution_id="EXEC-OPENAI-PROFILE-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
    )


def provider_response(request):
    return {
        "id": "resp_test_001",
        "object": "response",
        "created_at": 1787821200,
        "status": "completed",
        "error": None,
        "model": DEFAULT_MODEL,
        "output": deepcopy(OUTPUT),
        "metadata": {
            "execution_id": request["execution_id"],
            "operation_code": request["operation_code"],
            "profile_code": request["profile_code"],
            "profile_slug": request["profile_slug"],
            "profile_source_sha256": request["profile_source_sha256"],
            "input_sha256": request["input_sha256"],
            "request_sha256": request["request_sha256"],
        },
        "store": True,
    }


def expect_block(name, expected_code, fn):
    try:
        fn()
    except RuntimeExecutionBlocked as exc:
        if exc.code != expected_code:
            raise AssertionError(f"{name}: expected {expected_code}, got {exc.code}") from exc
        print(f"PASS {name}: {exc.code}")
        return
    raise AssertionError(f"{name}: expected {expected_code}")


class FakeOpenAIAdapter(OpenAIResponsesAdapter):
    is_test_double = True

    def __init__(self, response, **kwargs):
        super().__init__(api_key="test-key", **kwargs)
        self.provider_response = deepcopy(response)
        self.last_payload = None

    def _create_response(self, payload):
        self.last_payload = deepcopy(payload)
        return deepcopy(self.provider_response)


class FakeOpenAIVerifier(OpenAIResponsesReadbackVerifier):
    is_test_double = True

    def __init__(self, readback):
        super().__init__(api_key="verify-test-key")
        self.readback = deepcopy(readback)

    def _retrieve_response(self, response_id):
        return deepcopy(self.readback)


def main():
    tests = 0
    request = request_fixture()
    response_body = provider_response(request)

    adapter = FakeOpenAIAdapter(response_body)
    wrapped = adapter.execute(request)
    assert wrapped["runtime_attestation"]["provider"] == "openai"
    assert wrapped["runtime_attestation"]["run_id"] == response_body["id"]
    assert wrapped["raw_output"] == OUTPUT
    assert adapter.last_payload["store"] is True
    assert adapter.last_payload["model"] == DEFAULT_MODEL
    assert adapter.last_payload["input"] == INPUT
    assert adapter.last_payload["metadata"]["request_sha256"] == request["request_sha256"]
    assert "profiles/ui_architect/SKILL.md" in adapter.last_payload["instructions"]
    print("PASS openai_adapter_request_binding")
    tests += 1

    verifier = FakeOpenAIVerifier(response_body)
    verification = verifier.verify(request=request, response=wrapped, adapter=adapter)
    assert verification["verified"] is True
    assert verification["provider_response_id"] == response_body["id"]
    assert len(verification["evidence_sha256"]) == 64
    print("PASS openai_readback_verification")
    tests += 1

    expect_block(
        "openai_missing_api_key_blocks",
        "OPENAI_API_KEY_MISSING",
        lambda: OpenAIResponsesAdapter(api_key="").execute(request),
    )
    tests += 1

    incomplete = provider_response(request)
    incomplete["status"] = "incomplete"
    expect_block(
        "openai_incomplete_response_blocks",
        "OPENAI_RESPONSE_NOT_COMPLETED",
        lambda: FakeOpenAIAdapter(incomplete).execute(request),
    )
    tests += 1

    wrong_metadata = provider_response(request)
    wrong_metadata["metadata"]["input_sha256"] = "0" * 64
    expect_block(
        "openai_readback_metadata_mismatch_blocks",
        "OPENAI_READBACK_METADATA_MISMATCH",
        lambda: FakeOpenAIVerifier(wrong_metadata).verify(
            request=request, response=wrapped, adapter=adapter
        ),
    )
    tests += 1

    wrong_output = provider_response(request)
    wrong_output["output"][0]["content"][0]["text"] = "tampered"
    expect_block(
        "openai_readback_output_mismatch_blocks",
        "OPENAI_READBACK_OUTPUT_MISMATCH",
        lambda: FakeOpenAIVerifier(wrong_output).verify(
            request=request, response=wrapped, adapter=adapter
        ),
    )
    tests += 1

    wrong_id = provider_response(request)
    wrong_id["id"] = "resp_other"
    expect_block(
        "openai_readback_id_mismatch_blocks",
        "OPENAI_READBACK_ID_MISMATCH",
        lambda: FakeOpenAIVerifier(wrong_id).verify(
            request=request, response=wrapped, adapter=adapter
        ),
    )
    tests += 1

    wrong_model = provider_response(request)
    wrong_model["model"] = "gpt-5.6-luna"
    expect_block(
        "openai_readback_model_mismatch_blocks",
        "OPENAI_READBACK_MODEL_MISMATCH",
        lambda: FakeOpenAIVerifier(wrong_model).verify(
            request=request, response=wrapped, adapter=adapter
        ),
    )
    tests += 1

    expect_block(
        "openai_invalid_reasoning_effort_blocks",
        "OPENAI_REASONING_EFFORT_INVALID",
        lambda: OpenAIResponsesAdapter(api_key="test-key", reasoning_effort="ultra"),
    )
    tests += 1

    adapter2 = FakeOpenAIAdapter(response_body)
    verifier2 = FakeOpenAIVerifier(response_body)
    package = execute_profile_runtime(
        execution_id=request["execution_id"],
        profile_code=request["profile_code"],
        profile_slug=request["profile_slug"],
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
        adapter=adapter2,
        attestation_verifier=verifier2,
        allow_test_doubles=True,
    )
    receipt = package["receipt"]
    result = authorize_downstream(
        profile_execution_required=True,
        recipient="IMAGE_GENERATOR",
        receipt=receipt,
        expected_profile_code=request["profile_code"],
        expected_input_literal=INPUT,
        expected_raw_output=OUTPUT,
        expected_profile_source_sha256=package["request"]["profile_source_sha256"],
    )
    assert result["status"] == "PASS_PROFILE_EXECUTION_PROVENANCE"
    assert receipt["runtime_attestation"]["attestation_verifier"] == verifier2.verifier_id
    assert receipt["runtime_attestation"]["adapter_id"] == ADAPTER_ID
    print("PASS openai_runner_receipt_end_to_end")
    tests += 1

    print(f"OPENAI_PROFILE_RUNTIME_TESTS_PASS {tests}/{tests}")


if __name__ == "__main__":
    main()
