#!/usr/bin/env python3
from copy import deepcopy

from validate_profile_execution import authorize_downstream, build_receipt, canonical_json_sha256

INPUT = "Modifica esta pantalla aplicando todas las decisiones del ui_architect."
RAW = {"worker":"ui_architect","output_type":"PRODUCTION_UI_SPEC","deliverable_created":{"screen_definition":{"task_mode":"REMEDIATE_EXISTING"}}}
SOURCE_SHA = "a" * 64


def make_receipt():
    return build_receipt(
        execution_id="EXEC-PROFILE-RUNTIME-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_source_refs=["profiles/ui_architect/SKILL.md","profiles/ui_architect/contracts/existing_screen_review.md"],
        profile_source_sha256=SOURCE_SHA,
        input_literal=INPUT,
        raw_output=RAW,
        runtime_attestation={"provider":"test-model-runtime","model_id":"model-test","run_id":"run-test-001","attested_at":"2026-08-27T07:00:00Z"},
    )


def rehash(receipt):
    receipt["receipt_sha256"] = canonical_json_sha256({key:value for key,value in receipt.items() if key != "receipt_sha256"})
    return receipt


def assert_status(name, result, expected):
    if result["status"] != expected:
        raise AssertionError(f"{name}: expected {expected}, got {result}")
    print(f"PASS {name}: {result['status']}")


def main():
    receipt = make_receipt()
    assert_status("valid_runtime_receipt", authorize_downstream(profile_execution_required=True,recipient="IMAGE_GENERATOR",receipt=receipt,expected_profile_code="PERFIL-UI-ARCHITECT",expected_input_literal=INPUT,expected_raw_output=RAW,expected_profile_source_sha256=SOURCE_SHA), "PASS_PROFILE_EXECUTION_PROVENANCE")
    assert_status("missing_receipt_blocks", authorize_downstream(profile_execution_required=True,recipient="IMAGE_GENERATOR",receipt=None), "BLOCK_PIPELINE")
    static_fixture = deepcopy(receipt); static_fixture["execution_origin"] = "STATIC_FIXTURE"; rehash(static_fixture)
    result = authorize_downstream(profile_execution_required=True,recipient="IMAGE_GENERATOR",receipt=static_fixture); assert_status("static_fixture_blocks",result,"BLOCK_PIPELINE"); assert "EXECUTION_ORIGIN_NOT_MODEL_RUNTIME" in result["blocking_codes"]
    missing_raw = deepcopy(receipt); missing_raw["raw_output_captured"] = False; rehash(missing_raw)
    result = authorize_downstream(profile_execution_required=True,recipient="IMAGE_GENERATOR",receipt=missing_raw); assert_status("missing_raw_blocks",result,"BLOCK_PIPELINE"); assert "RAW_OUTPUT_NOT_CAPTURED" in result["blocking_codes"]
    wrong_input = authorize_downstream(profile_execution_required=True,recipient="IMAGE_GENERATOR",receipt=receipt,expected_input_literal=INPUT+" CAMBIO"); assert_status("input_hash_mismatch_blocks",wrong_input,"BLOCK_PIPELINE"); assert "INPUT_SHA256_MISMATCH" in wrong_input["blocking_codes"]
    self_authorized = deepcopy(receipt); self_authorized["downstream_authorized"] = True; rehash(self_authorized)
    result = authorize_downstream(profile_execution_required=True,recipient="IMAGE_GENERATOR",receipt=self_authorized); assert_status("self_authorization_blocks",result,"BLOCK_PIPELINE"); assert "SELF_AUTHORIZATION_FORBIDDEN" in result["blocking_codes"]
    assert_status("no_profile_needed", authorize_downstream(profile_execution_required=False,recipient="FINAL_USER",receipt=None), "PASS_NO_PROFILE_REQUIRED")
    print("PROFILE_RUNTIME_GATE_TESTS_PASS 6/6")


if __name__ == "__main__":
    main()
