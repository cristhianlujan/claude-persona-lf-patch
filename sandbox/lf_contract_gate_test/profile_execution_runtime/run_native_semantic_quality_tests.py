#!/usr/bin/env python3
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import subprocess
import sys

from semantic_mini_judge import (
    build_receipt as build_legacy_semantic_receipt,
    canonical_json_sha256 as semantic_sha,
    partition_checks,
    validate_bundle,
)
from semantic_obligation_manifest import (
    build_check_bundle,
    canonical_json_sha256,
    validate_obligation_manifest,
)
from validate_profile_execution import authorize_downstream, build_receipt, sha256_text
from validate_semantic_quality import validate_semantic_quality_receipt

EXECUTION_ID = "EXEC-S26-NATIVE-SEMANTIC-TEST-001"
PROFILE_CODE = "PERFIL-UI-ARCHITECT"
INPUT = "Evaluate the frozen B2B-CARGA-001 artifact under the governed profile contract."
RAW = {
    "worker": "ui_architect",
    "output_type": "PRODUCTION_UI_SPEC",
    "deliverable_created": {
        "screen_definition": {"task_mode": "REMEDIATE_EXISTING"},
        "remediation_actions": [
            {
                "issue_id": "PAGINATION-001",
                "decision": "Derive page count from total records and page size.",
            }
        ],
    },
}
PROFILE_SOURCES = [
    {"ref": "profiles/ui_architect/SKILL.md", "content": "# UI Architect\nUse governed remediation."},
    {"ref": "profiles/ui_architect/contracts/existing_screen_review.md", "content": "# Existing screen\nDefect -> correction -> postcondition."},
]
PROFILE_SOURCE_SHA = canonical_json_sha256([
    {"ref": item["ref"], "content_sha256": sha256_text(item["content"])}
    for item in sorted(PROFILE_SOURCES, key=lambda x: x["ref"])
])
INPUT_SHA = sha256_text(INPUT)


def make_manifest(*, semantic=True):
    obligations = [
        {
            "obligation_id": "TASK-MODE",
            "rule": "Existing-screen work remains remediation.",
            "check_type": "EXACT_VALUE",
            "evidence_pointer": "/deliverable_created/screen_definition/task_mode",
            "authority_ids": ["PROFILE-CONTRACT"],
            "expected_value": "REMEDIATE_EXISTING",
        }
    ]
    profile_ids = ["TASK-MODE"]
    if semantic:
        obligations.append(
            {
                "obligation_id": "DEFECT-DIRECTION",
                "rule": "The pagination decision must reduce the observed inconsistency rather than reproduce it.",
                "check_type": "SEMANTIC_RELATION",
                "evidence_pointer": "/deliverable_created/remediation_actions/0/decision",
                "authority_ids": ["EXECUTION-INPUT"],
                "question": "Does the selected correction reduce the observed pagination defect?",
            }
        )
    return validate_obligation_manifest(
        {
            "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
            "execution_id": EXECUTION_ID,
            "profile_code": PROFILE_CODE,
            "profile_source_sha256": PROFILE_SOURCE_SHA,
            "input_sha256": INPUT_SHA,
            "authority_sources": [
                {
                    "authority_id": "PROFILE-CONTRACT",
                    "authority_type": "PROFILE_CONTRACT",
                    "source_ref": "profiles/ui_architect/SKILL.md",
                    "source_sha256": PROFILE_SOURCE_SHA,
                    "required_obligation_ids": profile_ids,
                },
                {
                    "authority_id": "EXECUTION-INPUT",
                    "authority_type": "EXECUTION_INPUT",
                    "source_ref": "input:/literal",
                    "source_sha256": INPUT_SHA,
                    "required_obligation_ids": ["DEFECT-DIRECTION"] if semantic else [],
                },
            ],
            "obligations": obligations,
        }
    )


def make_execution_receipt(manifest):
    return build_receipt(
        execution_id=EXECUTION_ID,
        profile_code=PROFILE_CODE,
        profile_slug="ui_architect",
        profile_source_refs=[item["ref"] for item in PROFILE_SOURCES],
        profile_source_sha256=PROFILE_SOURCE_SHA,
        input_literal=INPUT,
        raw_output=RAW,
        runtime_attestation={
            "provider": "chatgpt-native-test",
            "model_id": "gpt-native-test",
            "run_id": "producer-run-001",
            "attested_at": "2026-09-08T19:00:00+00:00",
            "attestation_verifier": "native-readback-test",
            "attestation_evidence_sha256": "a" * 64,
            "verified_request_sha256": "b" * 64,
            "verified_response_sha256": "c" * 64,
        },
        obligation_manifest_sha256=canonical_json_sha256(manifest),
    )


def make_independent_receipt(execution_receipt, manifest, bundle):
    source_bundle = {
        "artifact_ref": "github://cristhianlujan/claude-persona-lf-patch@" + ("a" * 40) + "/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/test/raw_output.json",
        "artifact_byte_sha256": "d" * 64,
        "semantic_raw_output_sha256": execution_receipt["raw_output_sha256"],
        "upstream_worker_contract_ref": "profiles/ui_architect/SKILL.md",
        "quality_gate_contract_ref": "profiles/quality_pack/contracts/quality_gate_contract.md",
        "lf_quality_controls_ref": "profiles/quality_pack/contracts/lf_quality_controls.md",
        "score_rubric_ref": "profiles/quality_pack/judges/quality_pack_score_rubric.md",
        "mini_judge_ref": "profiles/quality_pack/judges/quality_pack_mini_judge.md",
        "quality_review_schema_ref": "profiles/quality_pack/schemas/quality_review.schema.json",
    }
    binding = {
        "schema": "LF_NATIVE_SEMANTIC_QUALITY_BINDING_V1",
        "execution_id": execution_receipt["execution_id"],
        "profile_code": execution_receipt["profile_code"],
        "producer_run_id": execution_receipt["runtime_attestation"]["run_id"],
        "reviewer_run_id": "independent-review-run-001",
        "input_sha256": execution_receipt["input_sha256"],
        "raw_output_sha256": execution_receipt["raw_output_sha256"],
        "execution_receipt_sha256": execution_receipt["receipt_sha256"],
        "obligation_manifest_sha256": canonical_json_sha256(manifest),
        "check_bundle_sha256": canonical_json_sha256(bundle),
        "source_bundle_sha256": canonical_json_sha256(source_bundle),
    }
    binding["binding_sha256"] = canonical_json_sha256(binding)
    receipt = {
        "receipt_version": "v0.1",
        "execution_mode": "INDEPENDENT_CHAT_CONTEXT",
        "semantic_status": "EXECUTED_INDEPENDENT_CONTEXT",
        "review_case_id": "S26-NATIVE-SEMANTIC-TEST-001",
        "reviewer_is_producer": False,
        "producer_context_available": False,
        "external_paid_model_used": False,
        "automated_semantic_judge_implemented": False,
        "review_completed": True,
        "source_bundle": source_bundle,
        "quality_review": {
            "review_id": "QUALITY-S26-NATIVE-SEMANTIC-TEST-001",
            "reviewed_artifact": source_bundle["artifact_ref"],
            "verdict": "PASS_TO_COMPOSER",
            "score_breakdown": {
                "contract_schema_compliance": 5,
                "evidence_integrity": 5,
                "lf_safety_governance": 5,
                "handoff_readiness": 5,
                "leakage_scope_control": 5,
                "total": 25,
            },
            "evidence_map": [
                {
                    "criterion": "defect_direction",
                    "evidence": "The frozen artifact changes pagination toward a page count derived from visible totals instead of preserving phantom pages.",
                }
            ],
            "blocking_codes": [],
            "repair_actions": [],
            "remaining_risks": [],
            "next_gate": "GOLDEN_ELIGIBILITY",
            "routing": {
                "activation_path": "ROUTER",
                "via": "ORCHESTRATOR",
                "pipeline_action": "CONTINUE",
                "resolution_target": "COMPOSER"
            }
        },
        "execution_blockers": [],
        "semantic_binding": binding,
    }
    receipt["receipt_sha256"] = canonical_json_sha256(receipt)
    return receipt


def rehash_binding_and_receipt(receipt):
    receipt["semantic_binding"]["binding_sha256"] = canonical_json_sha256(
        {k: v for k, v in receipt["semantic_binding"].items() if k != "binding_sha256"}
    )
    receipt["receipt_sha256"] = canonical_json_sha256(
        {k: v for k, v in receipt.items() if k != "receipt_sha256"}
    )
    return receipt


def run_semantic_binding_gate():
    test_path = Path(__file__).with_name("run_semantic_binding_validator_tests.py")
    if not test_path.is_file():
        raise SystemExit("SEMANTIC_BINDING_GATE_TEST_MISSING")
    completed = subprocess.run(
        [sys.executable, str(test_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.stderr:
        print(completed.stderr, file=sys.stderr, end="" if completed.stderr.endswith("\n") else "\n")
    marker = "SEMANTIC_BINDING_REGRESSIONS_PASS=7/7"
    if completed.returncode != 0:
        raise SystemExit(f"SEMANTIC_BINDING_GATE_FAIL exit={completed.returncode}")
    if marker not in completed.stdout:
        raise SystemExit("SEMANTIC_BINDING_GATE_MARKER_MISSING")
    print("NATIVE_SEMANTIC_BINDING_GATE_PASS 7/7")


def main():
    passed = 0

    manifest = make_manifest(semantic=True)
    execution_receipt = make_execution_receipt(manifest)
    bundle = validate_bundle(
        build_check_bundle(manifest, RAW, raw_output_sha256=execution_receipt["raw_output_sha256"])
    )
    independent = make_independent_receipt(execution_receipt, manifest, bundle)

    assert validate_semantic_quality_receipt(
        independent,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=RAW,
        execution_receipt=execution_receipt,
    ) == []
    passed += 1

    downstream = authorize_downstream(
        profile_execution_required=True,
        recipient="INTERNAL_AGENT",
        receipt=execution_receipt,
        expected_profile_code=PROFILE_CODE,
        expected_input_literal=INPUT,
        expected_raw_output=RAW,
        expected_profile_source_sha256=PROFILE_SOURCE_SHA,
        semantic_receipt=independent,
        semantic_check_bundle=bundle,
        semantic_obligation_manifest=manifest,
    )
    assert downstream["status"] == "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY"
    passed += 1

    missing_routing = deepcopy(independent)
    missing_routing["quality_review"].pop("routing")
    missing_routing["receipt_sha256"] = canonical_json_sha256(
        {k: v for k, v in missing_routing.items() if k != "receipt_sha256"}
    )
    errors = validate_semantic_quality_receipt(
        missing_routing,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=RAW,
        execution_receipt=execution_receipt,
    )
    assert "QUALITY_PACK_ROUTING_INVALID:ROUTING_OBJECT_REQUIRED" in errors
    passed += 1

    self_review = deepcopy(independent)
    self_review["semantic_binding"]["reviewer_run_id"] = self_review["semantic_binding"]["producer_run_id"]
    rehash_binding_and_receipt(self_review)
    errors = validate_semantic_quality_receipt(
        self_review,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=RAW,
        execution_receipt=execution_receipt,
    )
    assert "NATIVE_SEMANTIC_REVIEW_NOT_INDEPENDENT" in errors
    passed += 1

    wrong_semantic_sha = deepcopy(independent)
    wrong_semantic_sha["source_bundle"]["semantic_raw_output_sha256"] = "f" * 64
    wrong_semantic_sha["semantic_binding"]["source_bundle_sha256"] = canonical_json_sha256(wrong_semantic_sha["source_bundle"])
    rehash_binding_and_receipt(wrong_semantic_sha)
    errors = validate_semantic_quality_receipt(
        wrong_semantic_sha,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=RAW,
        execution_receipt=execution_receipt,
    )
    assert "INDEPENDENT_QUALITY_SEMANTIC_RAW_SHA_MISMATCH" in errors
    passed += 1

    incomplete = deepcopy(independent)
    incomplete["review_completed"] = False
    incomplete["semantic_status"] = "NOT_EXECUTED"
    incomplete["execution_blockers"] = ["NO_INDEPENDENT_CONTEXT"]
    incomplete["receipt_sha256"] = canonical_json_sha256(
        {k: v for k, v in incomplete.items() if k != "receipt_sha256"}
    )
    errors = validate_semantic_quality_receipt(
        incomplete,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=RAW,
        execution_receipt=execution_receipt,
    )
    assert "INDEPENDENT_QUALITY_REVIEW_NOT_COMPLETED" in errors
    passed += 1

    restricted = deepcopy(independent)
    restricted["quality_review"]["verdict"] = "PASS_WITH_RESTRICTIONS"
    restricted["quality_review"]["score_breakdown"] = {
        "contract_schema_compliance": 5,
        "evidence_integrity": 5,
        "lf_safety_governance": 4,
        "handoff_readiness": 4,
        "leakage_scope_control": 4,
        "total": 22,
    }
    restricted["quality_review"]["remaining_risks"] = ["One non-blocking risk remains."]
    restricted["quality_review"]["routing"] = {
        "activation_path": "ROUTER",
        "via": "ORCHESTRATOR",
        "pipeline_action": "CONTINUE_WITH_RESTRICTIONS",
        "resolution_target": "COMPOSER"
    }
    restricted["receipt_sha256"] = canonical_json_sha256(
        {k: v for k, v in restricted.items() if k != "receipt_sha256"}
    )
    errors = validate_semantic_quality_receipt(
        restricted,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=RAW,
        execution_receipt=execution_receipt,
    )
    assert "INDEPENDENT_QUALITY_VERDICT_NOT_STRICT_PASS" in errors
    passed += 1

    tampered_binding = deepcopy(independent)
    tampered_binding["semantic_binding"]["check_bundle_sha256"] = "e" * 64
    rehash_binding_and_receipt(tampered_binding)
    errors = validate_semantic_quality_receipt(
        tampered_binding,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=RAW,
        execution_receipt=execution_receipt,
    )
    assert "NATIVE_SEMANTIC_BINDING_CHECK_BUNDLE_SHA256_MISMATCH" in errors
    passed += 1

    legacy_manifest = make_manifest(semantic=False)
    legacy_execution = make_execution_receipt(legacy_manifest)
    legacy_bundle = validate_bundle(
        build_check_bundle(legacy_manifest, RAW, raw_output_sha256=legacy_execution["raw_output_sha256"])
    )
    deterministic, semantic = partition_checks(legacy_bundle)
    assert not semantic
    legacy_semantic = build_legacy_semantic_receipt(legacy_bundle, deterministic)
    assert validate_semantic_quality_receipt(
        legacy_semantic,
        expected_bundle=legacy_bundle,
        expected_obligation_manifest=legacy_manifest,
        expected_raw_output=RAW,
        execution_receipt=legacy_execution,
    ) == []
    assert legacy_semantic["receipt_sha256"] == semantic_sha(
        {k: v for k, v in legacy_semantic.items() if k != "receipt_sha256"}
    )
    passed += 1

    if passed != 9:
        raise SystemExit(f"NATIVE_SEMANTIC_QUALITY_TESTS_FAIL {passed}/9")

    run_semantic_binding_gate()
    print("NATIVE_SEMANTIC_QUALITY_TESTS_PASS 9/9")


if __name__ == "__main__":
    main()
