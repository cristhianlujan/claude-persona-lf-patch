#!/usr/bin/env python3
from copy import deepcopy

from profile_runtime_runner import (
    RESPONSE_TYPE,
    RuntimeExecutionBlocked,
    execute_profile_runtime,
)
from validate_profile_execution import (
    authorize_downstream,
    build_receipt,
    canonical_json_sha256,
    sha256_text,
)

INPUT = "Modifica esta pantalla aplicando todas las decisiones del ui_architect."
RAW = {
    "worker": "ui_architect",
    "output_type": "PRODUCTION_UI_SPEC",
    "deliverable_created": {"screen_definition": {"task_mode": "REMEDIATE_EXISTING"}},
}
SOURCE_SHA = "a" * 64
PROFILE_SOURCES = [
    {"ref": "profiles/ui_architect/SKILL.md", "content": "# UI Architect\nApply the profile contract."},
    {
        "ref": "profiles/ui_architect/contracts/existing_screen_review.md",
        "content": "# Existing screen review\nReturn executable remediation decisions.",
    },
]


def verified_attestation():
    return {
        "provider": "test-model-runtime",
        "model_id": "model-test",
        "run_id": "run-test-001",
        "attested_at": "2026-08-27T07:00:00Z",
        "attestation_verifier": "test-attestation-verifier",
        "attestation_evidence_sha256": "b" * 64,
        "verified_request_sha256": "c" * 64,
        "verified_response_sha256": "d" * 64,
    }


def make_receipt():
    return build_receipt(
        execution_id="EXEC-PROFILE-RUNTIME-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_source_refs=[
            "profiles/ui_architect/SKILL.md",
            "profiles/ui_architect/contracts/existing_screen_review.md",
        ],
        profile_source_sha256=SOURCE_SHA,
        input_literal=INPUT,
        raw_output=RAW,
        runtime_attestation=verified_attestation(),
    )


def rehash(receipt):
    receipt["receipt_sha256"] = canonical_json_sha256(
        {key: value for key, value in receipt.items() if key != "receipt_sha256"}
    )
    return receipt


def assert_status(name, result, expected):
    if result["status"] != expected:
        raise AssertionError(f"{name}: expected {expected}, got {result}")
    print(f"PASS {name}: {result['status']}")


def expect_block(name, expected_code, fn):
    try:
        fn()
    except RuntimeExecutionBlocked as exc:
        if exc.code != expected_code:
            raise AssertionError(f"{name}: expected {expected_code}, got {exc.code}") from exc
        print(f"PASS {name}: {exc.code}")
        return
    raise AssertionError(f"{name}: expected RuntimeExecutionBlocked({expected_code})")


class TestAdapter:
    adapter_id = "test-runtime-adapter"
    is_test_double = True

    def __init__(self, *, tamper_request_hash=False, raw_output=RAW, raise_error=False):
        self.tamper_request_hash = tamper_request_hash
        self.raw_output = raw_output
        self.raise_error = raise_error

    def execute(self, request):
        if self.raise_error:
            raise ValueError("synthetic adapter failure")
        request_sha = request["request_sha256"]
        if self.tamper_request_hash:
            request_sha = "0" * 64
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": self.raw_output,
            "runtime_attestation": {
                "provider": "synthetic-provider",
                "model_id": "synthetic-model",
                "run_id": "synthetic-run-001",
                "attested_at": "2026-08-27T08:00:00Z",
                "adapter_id": self.adapter_id,
                "request_sha256": request_sha,
                "profile_source_sha256": request["profile_source_sha256"],
                "input_sha256": request["input_sha256"],
                "operation_code": request["operation_code"],
                "profile_code": request["profile_code"],
                "profile_slug": request["profile_slug"],
            },
        }


class OperationalFlagAdapter(TestAdapter):
    is_test_double = False


class TestVerifier:
    verifier_id = "test-attestation-verifier"
    is_test_double = True

    def __init__(self, *, tamper_response_hash=False, verified=True):
        self.tamper_response_hash = tamper_response_hash
        self.verified = verified

    def verify(self, *, request, response, adapter):
        response_sha = canonical_json_sha256(response)
        if self.tamper_response_hash:
            response_sha = "f" * 64
        return {
            "verified": self.verified,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": sha256_text(
                f"{self.verifier_id}:{request['request_sha256']}:{response_sha}"
            ),
        }


class OperationalFlagVerifier(TestVerifier):
    is_test_double = False


def runner_call(*, adapter=None, verifier=None, allow_test_doubles=True, sources=None):
    return execute_profile_runtime(
        execution_id="EXEC-PROFILE-RUNNER-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_sources=PROFILE_SOURCES if sources is None else sources,
        input_literal=INPUT,
        adapter=TestAdapter() if adapter is None else adapter,
        attestation_verifier=TestVerifier() if verifier is None else verifier,
        allow_test_doubles=allow_test_doubles,
    )


def main():
    tests = 0

    receipt = make_receipt()
    assert_status(
        "valid_runtime_receipt",
        authorize_downstream(
            profile_execution_required=True,
            recipient="IMAGE_GENERATOR",
            receipt=receipt,
            expected_profile_code="PERFIL-UI-ARCHITECT",
            expected_input_literal=INPUT,
            expected_raw_output=RAW,
            expected_profile_source_sha256=SOURCE_SHA,
        ),
        "PASS_PROFILE_EXECUTION_PROVENANCE",
    )
    tests += 1

    assert_status(
        "missing_receipt_blocks",
        authorize_downstream(
            profile_execution_required=True,
            recipient="IMAGE_GENERATOR",
            receipt=None,
        ),
        "BLOCK_PIPELINE",
    )
    tests += 1

    static_fixture = deepcopy(receipt)
    static_fixture["execution_origin"] = "STATIC_FIXTURE"
    rehash(static_fixture)
    result = authorize_downstream(
        profile_execution_required=True,
        recipient="IMAGE_GENERATOR",
        receipt=static_fixture,
    )
    assert_status("static_fixture_blocks", result, "BLOCK_PIPELINE")
    assert "EXECUTION_ORIGIN_NOT_MODEL_RUNTIME" in result["blocking_codes"]
    tests += 1

    missing_raw = deepcopy(receipt)
    missing_raw["raw_output_captured"] = False
    rehash(missing_raw)
    result = authorize_downstream(
        profile_execution_required=True,
        recipient="IMAGE_GENERATOR",
        receipt=missing_raw,
    )
    assert_status("missing_raw_blocks", result, "BLOCK_PIPELINE")
    assert "RAW_OUTPUT_NOT_CAPTURED" in result["blocking_codes"]
    tests += 1

    wrong_input = authorize_downstream(
        profile_execution_required=True,
        recipient="IMAGE_GENERATOR",
        receipt=receipt,
        expected_input_literal=INPUT + " CAMBIO",
    )
    assert_status("input_hash_mismatch_blocks", wrong_input, "BLOCK_PIPELINE")
    assert "INPUT_SHA256_MISMATCH" in wrong_input["blocking_codes"]
    tests += 1

    self_authorized = deepcopy(receipt)
    self_authorized["downstream_authorized"] = True
    rehash(self_authorized)
    result = authorize_downstream(
        profile_execution_required=True,
        recipient="IMAGE_GENERATOR",
        receipt=self_authorized,
    )
    assert_status("self_authorization_blocks", result, "BLOCK_PIPELINE")
    assert "SELF_AUTHORIZATION_FORBIDDEN" in result["blocking_codes"]
    tests += 1

    missing_verifier = deepcopy(receipt)
    del missing_verifier["runtime_attestation"]["attestation_verifier"]
    rehash(missing_verifier)
    result = authorize_downstream(
        profile_execution_required=True,
        recipient="IMAGE_GENERATOR",
        receipt=missing_verifier,
    )
    assert_status("missing_attestation_verifier_blocks", result, "BLOCK_PIPELINE")
    assert "RUNTIME_ATTESTATION_ATTESTATION_VERIFIER_MISSING" in result["blocking_codes"]
    tests += 1

    assert_status(
        "no_profile_needed",
        authorize_downstream(
            profile_execution_required=False,
            recipient="FINAL_USER",
            receipt=None,
        ),
        "PASS_NO_PROFILE_REQUIRED",
    )
    tests += 1

    package = runner_call()
    runner_receipt = package["receipt"]
    assert package["result_type"] == "PROFILE_RUNTIME_RESULT_V1"
    assert package["raw_output"] == RAW
    assert runner_receipt["runtime_attestation"]["attestation_verifier"] == "test-attestation-verifier"
    result = authorize_downstream(
        profile_execution_required=True,
        recipient="IMAGE_GENERATOR",
        receipt=runner_receipt,
        expected_profile_code="PERFIL-UI-ARCHITECT",
        expected_input_literal=INPUT,
        expected_raw_output=RAW,
        expected_profile_source_sha256=package["request"]["profile_source_sha256"],
    )
    assert_status("runner_test_mode_success", result, "PASS_PROFILE_EXECUTION_PROVENANCE")
    tests += 1

    expect_block(
        "operational_mode_blocks_test_adapter",
        "TEST_RUNTIME_ADAPTER_FORBIDDEN",
        lambda: runner_call(allow_test_doubles=False),
    )
    tests += 1

    expect_block(
        "operational_mode_blocks_test_verifier",
        "TEST_ATTESTATION_VERIFIER_FORBIDDEN",
        lambda: runner_call(
            adapter=OperationalFlagAdapter(),
            verifier=TestVerifier(),
            allow_test_doubles=False,
        ),
    )
    tests += 1

    expect_block(
        "attestation_request_hash_mismatch_blocks",
        "RUNTIME_ATTESTATION_REQUEST_SHA256_MISMATCH",
        lambda: runner_call(adapter=TestAdapter(tamper_request_hash=True)),
    )
    tests += 1

    expect_block(
        "verification_response_hash_mismatch_blocks",
        "ATTESTATION_VERIFICATION_RESPONSE_MISMATCH",
        lambda: runner_call(verifier=TestVerifier(tamper_response_hash=True)),
    )
    tests += 1

    expect_block(
        "empty_raw_output_blocks",
        "RUNTIME_RAW_OUTPUT_EMPTY",
        lambda: runner_call(adapter=TestAdapter(raw_output={})),
    )
    tests += 1

    expect_block(
        "adapter_exception_blocks",
        "RUNTIME_ADAPTER_EXCEPTION",
        lambda: runner_call(adapter=TestAdapter(raise_error=True)),
    )
    tests += 1

    duplicate_sources = PROFILE_SOURCES + [dict(PROFILE_SOURCES[0])]
    expect_block(
        "duplicate_profile_source_blocks",
        "PROFILE_SOURCE_DUPLICATE",
        lambda: runner_call(sources=duplicate_sources),
    )
    tests += 1

    print(f"PROFILE_RUNTIME_GATE_TESTS_PASS {tests}/{tests}")


if __name__ == "__main__":
    main()
