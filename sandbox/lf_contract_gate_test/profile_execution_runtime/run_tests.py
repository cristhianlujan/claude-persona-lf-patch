#!/usr/bin/env python3
from copy import deepcopy

from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked, execute_profile_runtime
from run_lf_adapter_binding_tests import main as run_lf_adapter_binding_tests
from semantic_mini_judge import (
    CheckResult as SemanticCheckResult,
    build_receipt as build_semantic_receipt,
    canonical_json_sha256 as semantic_json_sha256,
    partition_checks,
    validate_bundle as validate_semantic_bundle,
)
from semantic_obligation_manifest import (
    build_check_bundle,
    canonical_json_sha256 as obligation_json_sha256,
    validate_obligation_manifest,
)
from validate_profile_execution import authorize_downstream, build_receipt, canonical_json_sha256, sha256_text

INPUT = "Modifica esta pantalla aplicando todas las decisiones del ui_architect."
RAW = {
    "worker": "ui_architect",
    "output_type": "PRODUCTION_UI_SPEC",
    "deliverable_created": {"screen_definition": {"task_mode": "REMEDIATE_EXISTING"}},
}
PROFILE_SOURCES = [
    {"ref": "profiles/ui_architect/SKILL.md", "content": "# UI Architect\nApply the profile contract."},
    {"ref": "profiles/ui_architect/contracts/existing_screen_review.md", "content": "# Existing screen review\nReturn executable remediation decisions."},
]
SOURCE_SHA = canonical_json_sha256([
    {"ref": item["ref"], "content_sha256": sha256_text(item["content"])}
    for item in sorted(PROFILE_SOURCES, key=lambda item: item["ref"])
])
INPUT_SHA = sha256_text(INPUT)


def obligation_manifest(*, two=False):
    obligations = [{
        "obligation_id": "D-TEST-01",
        "rule": "Preserve the declared task mode.",
        "check_type": "EXACT_VALUE",
        "evidence_pointer": "/deliverable_created/screen_definition/task_mode",
        "authority_ids": ["PROFILE-CONTRACT"],
        "expected_value": "REMEDIATE_EXISTING",
    }]
    if two:
        obligations.append({
            "obligation_id": "D-TEST-02",
            "rule": "The task mode must remain an existing-screen remediation.",
            "check_type": "REQUIRED_SUBSTRING",
            "evidence_pointer": "/deliverable_created/screen_definition/task_mode",
            "authority_ids": ["EXECUTION-INPUT"],
            "expected": ["REMEDIATE_EXISTING"],
        })
    return validate_obligation_manifest({
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": "EXEC-PROFILE-RUNTIME-TEST-001",
        "profile_code": "PERFIL-UI-ARCHITECT",
        "profile_source_sha256": SOURCE_SHA,
        "input_sha256": INPUT_SHA,
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT",
                "authority_type": "PROFILE_CONTRACT",
                "source_ref": "profiles/ui_architect/SKILL.md",
                "source_sha256": SOURCE_SHA,
                "required_obligation_ids": ["D-TEST-01"],
            },
            {
                "authority_id": "EXECUTION-INPUT",
                "authority_type": "EXECUTION_INPUT",
                "source_ref": "input:/literal",
                "source_sha256": INPUT_SHA,
                "required_obligation_ids": ["D-TEST-02"] if two else [],
            },
        ],
        "obligations": obligations,
    })


MANIFEST = obligation_manifest()
MANIFEST_SHA = obligation_json_sha256(MANIFEST)


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


def make_receipt(manifest=MANIFEST):
    return build_receipt(
        execution_id="EXEC-PROFILE-RUNTIME-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_source_refs=[item["ref"] for item in PROFILE_SOURCES],
        profile_source_sha256=SOURCE_SHA,
        input_literal=INPUT,
        raw_output=RAW,
        runtime_attestation=verified_attestation(),
        obligation_manifest_sha256=obligation_json_sha256(manifest),
    )


def make_semantic_pass(execution_receipt, manifest=MANIFEST):
    bundle = validate_semantic_bundle(build_check_bundle(
        manifest,
        RAW,
        raw_output_sha256=execution_receipt["raw_output_sha256"],
    ))
    deterministic, semantic = partition_checks(bundle)
    assert not semantic
    semantic_receipt = build_semantic_receipt(bundle, deterministic)
    return bundle, semantic_receipt


def rehash(receipt):
    receipt["receipt_sha256"] = canonical_json_sha256({k: v for k, v in receipt.items() if k != "receipt_sha256"})
    return receipt


def rehash_semantic(receipt):
    receipt["receipt_sha256"] = semantic_json_sha256({k: v for k, v in receipt.items() if k != "receipt_sha256"})
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
            "evidence_sha256": sha256_text(f"{self.verifier_id}:{request['request_sha256']}:{response_sha}"),
        }


class OperationalFlagVerifier(TestVerifier):
    is_test_double = False


def runner_call(*, adapter=None, verifier=None, allow_test_doubles=True, sources=None, manifest=MANIFEST):
    return execute_profile_runtime(
        execution_id="EXEC-PROFILE-RUNTIME-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_sources=PROFILE_SOURCES if sources is None else sources,
        input_literal=INPUT,
        adapter=TestAdapter() if adapter is None else adapter,
        attestation_verifier=TestVerifier() if verifier is None else verifier,
        allow_test_doubles=allow_test_doubles,
        obligation_manifest=manifest,
    )


def main():
    passed = 0
    receipt = make_receipt()

    assert_status("provenance_allows_semantic_judge", authorize_downstream(
        profile_execution_required=True, recipient="SEMANTIC_JUDGE", receipt=receipt,
        expected_profile_code="PERFIL-UI-ARCHITECT", expected_input_literal=INPUT,
        expected_raw_output=RAW, expected_profile_source_sha256=SOURCE_SHA,
    ), "PASS_PROFILE_EXECUTION_PROVENANCE")
    passed += 1

    provenance_only = authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=receipt,
        expected_profile_code="PERFIL-UI-ARCHITECT", expected_input_literal=INPUT,
        expected_raw_output=RAW, expected_profile_source_sha256=SOURCE_SHA,
    )
    assert_status("provenance_only_blocks_generator", provenance_only, "BLOCK_PIPELINE")
    assert "SEMANTIC_OBLIGATION_MANIFEST_MISSING" in provenance_only["blocking_codes"]
    passed += 1

    semantic_bundle, semantic_receipt = make_semantic_pass(receipt)
    assert_status("execution_plus_complete_semantic_pass_allows_generator", authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=receipt,
        expected_profile_code="PERFIL-UI-ARCHITECT", expected_input_literal=INPUT,
        expected_raw_output=RAW, expected_profile_source_sha256=SOURCE_SHA,
        semantic_receipt=semantic_receipt, semantic_check_bundle=semantic_bundle,
        semantic_obligation_manifest=MANIFEST,
    ), "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY")
    passed += 1

    semantic_fail = deepcopy(semantic_receipt)
    semantic_fail["verdict"] = "FAIL"
    semantic_fail["downstream_disposition"] = "BLOCK"
    rehash_semantic(semantic_fail)
    result = authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=receipt,
        expected_raw_output=RAW, semantic_receipt=semantic_fail,
        semantic_check_bundle=semantic_bundle, semantic_obligation_manifest=MANIFEST,
    )
    assert_status("semantic_fail_blocks_generator", result, "BLOCK_PIPELINE")
    assert "SEMANTIC_VERDICT_NOT_PASS" in result["blocking_codes"]
    passed += 1

    full_manifest = obligation_manifest(two=True)
    full_receipt = make_receipt(full_manifest)
    full_bundle, full_semantic = make_semantic_pass(full_receipt, full_manifest)
    partial_bundle = deepcopy(full_bundle)
    partial_bundle["checks"] = partial_bundle["checks"][:1]
    partial_semantic = build_semantic_receipt(
        validate_semantic_bundle(partial_bundle),
        [SemanticCheckResult("D-TEST-01", "COMPLIES", "EXACT_VALUE_MATCH", "PYTHON_DETERMINISTIC")],
    )
    result = authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=full_receipt,
        expected_raw_output=RAW, semantic_receipt=partial_semantic,
        semantic_check_bundle=partial_bundle, semantic_obligation_manifest=full_manifest,
    )
    assert_status("partial_check_bundle_blocks", result, "BLOCK_PIPELINE")
    assert "SEMANTIC_CHECK_BUNDLE_NOT_DERIVED_FROM_MANIFEST" in result["blocking_codes"]
    passed += 1

    tampered_bundle = deepcopy(full_bundle)
    tampered_bundle["checks"][0]["rule"] = "weakened rule"
    tampered_semantic = build_semantic_receipt(
        validate_semantic_bundle(tampered_bundle),
        [
            SemanticCheckResult("D-TEST-01", "COMPLIES", "EXACT_VALUE_MATCH", "PYTHON_DETERMINISTIC"),
            SemanticCheckResult("D-TEST-02", "COMPLIES", "REQUIRED_TEXT_PRESENT", "PYTHON_DETERMINISTIC"),
        ],
    )
    result = authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=full_receipt,
        expected_raw_output=RAW, semantic_receipt=tampered_semantic,
        semantic_check_bundle=tampered_bundle, semantic_obligation_manifest=full_manifest,
    )
    assert_status("tampered_rule_bundle_blocks", result, "BLOCK_PIPELINE")
    assert "SEMANTIC_CHECK_BUNDLE_NOT_DERIVED_FROM_MANIFEST" in result["blocking_codes"]
    passed += 1

    wrong_manifest = deepcopy(MANIFEST)
    wrong_manifest["obligations"][0]["rule"] = "post-execution replacement"
    result = authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=receipt,
        expected_raw_output=RAW, semantic_receipt=semantic_receipt,
        semantic_check_bundle=semantic_bundle, semantic_obligation_manifest=wrong_manifest,
    )
    assert_status("post_execution_manifest_swap_blocks", result, "BLOCK_PIPELINE")
    assert "EXECUTION_OBLIGATION_MANIFEST_SHA256_MISMATCH" in result["blocking_codes"]
    passed += 1

    assert_status("missing_receipt_blocks", authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=None,
    ), "BLOCK_PIPELINE")
    passed += 1

    static_fixture = deepcopy(receipt)
    static_fixture["execution_origin"] = "STATIC_FIXTURE"
    rehash(static_fixture)
    result = authorize_downstream(profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=static_fixture)
    assert_status("static_fixture_blocks", result, "BLOCK_PIPELINE")
    assert "EXECUTION_ORIGIN_NOT_MODEL_RUNTIME" in result["blocking_codes"]
    passed += 1

    missing_raw = deepcopy(receipt)
    missing_raw["raw_output_captured"] = False
    rehash(missing_raw)
    result = authorize_downstream(profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=missing_raw)
    assert_status("missing_raw_blocks", result, "BLOCK_PIPELINE")
    passed += 1

    wrong_input = authorize_downstream(
        profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=receipt,
        expected_input_literal=INPUT + " CAMBIO",
    )
    assert_status("input_hash_mismatch_blocks", wrong_input, "BLOCK_PIPELINE")
    passed += 1

    self_authorized = deepcopy(receipt)
    self_authorized["downstream_authorized"] = True
    rehash(self_authorized)
    result = authorize_downstream(profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=self_authorized)
    assert_status("self_authorization_blocks", result, "BLOCK_PIPELINE")
    passed += 1

    missing_verifier = deepcopy(receipt)
    del missing_verifier["runtime_attestation"]["attestation_verifier"]
    rehash(missing_verifier)
    result = authorize_downstream(profile_execution_required=True, recipient="IMAGE_GENERATOR", receipt=missing_verifier)
    assert_status("missing_attestation_verifier_blocks", result, "BLOCK_PIPELINE")
    passed += 1

    assert_status("no_profile_needed", authorize_downstream(
        profile_execution_required=False, recipient="FINAL_USER", receipt=None,
    ), "PASS_NO_PROFILE_REQUIRED")
    passed += 1

    package = runner_call()
    runner_receipt = package["receipt"]
    assert runner_receipt["obligation_manifest_sha256"] == MANIFEST_SHA
    assert_status("runner_test_mode_success", authorize_downstream(
        profile_execution_required=True, recipient="SEMANTIC_JUDGE", receipt=runner_receipt,
        expected_profile_code="PERFIL-UI-ARCHITECT", expected_input_literal=INPUT,
        expected_raw_output=RAW, expected_profile_source_sha256=package["request"]["profile_source_sha256"],
    ), "PASS_PROFILE_EXECUTION_PROVENANCE")
    passed += 1

    expect_block("operational_mode_blocks_test_adapter", "TEST_RUNTIME_ADAPTER_FORBIDDEN", lambda: runner_call(allow_test_doubles=False))
    passed += 1
    expect_block("operational_mode_blocks_test_verifier", "TEST_ATTESTATION_VERIFIER_FORBIDDEN", lambda: runner_call(
        adapter=OperationalFlagAdapter(), verifier=TestVerifier(), allow_test_doubles=False,
    ))
    passed += 1
    expect_block("attestation_request_hash_mismatch_blocks", "RUNTIME_ATTESTATION_REQUEST_SHA256_MISMATCH", lambda: runner_call(
        adapter=TestAdapter(tamper_request_hash=True),
    ))
    passed += 1
    expect_block("verification_response_hash_mismatch_blocks", "ATTESTATION_VERIFICATION_RESPONSE_MISMATCH", lambda: runner_call(
        verifier=TestVerifier(tamper_response_hash=True),
    ))
    passed += 1
    expect_block("empty_raw_output_blocks", "RUNTIME_RAW_OUTPUT_EMPTY", lambda: runner_call(adapter=TestAdapter(raw_output={})))
    passed += 1
    expect_block("adapter_exception_blocks", "RUNTIME_ADAPTER_EXCEPTION", lambda: runner_call(adapter=TestAdapter(raise_error=True)))
    passed += 1
    duplicate_sources = PROFILE_SOURCES + [dict(PROFILE_SOURCES[0])]
    expect_block("duplicate_profile_source_blocks", "PROFILE_SOURCE_DUPLICATE", lambda: runner_call(sources=duplicate_sources))
    passed += 1

    invalid_manifest = deepcopy(MANIFEST)
    invalid_manifest["profile_source_sha256"] = "f" * 64
    expect_block("pre_execution_manifest_binding_blocks", "OBLIGATION_MANIFEST_INVALID", lambda: runner_call(manifest=invalid_manifest))
    passed += 1

    run_lf_adapter_binding_tests()
    print(f"PROFILE_RUNTIME_GATE_TESTS_PASS {passed}/{passed}")


if __name__ == "__main__":
    main()
