#!/usr/bin/env python3
"""Evaluate the pre-bound GPT Native Golden B run and stop before independent Quality PASS."""

from __future__ import annotations

import importlib.util
import json
import subprocess
from pathlib import Path
from typing import Any

from semantic_mini_judge import canonical_json_sha256, partition_checks, validate_bundle
from semantic_obligation_manifest import build_check_bundle
from validate_profile_execution import build_receipt, validate_receipt
from validate_semantic_quality import validate_independent_quality_receipt

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_002"
RAW_PATH = EVIDENCE / "raw_output.json"
INPUT_PATH = EVIDENCE / "input.txt"
PREPARE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/prepare_s26_native_golden_b.py"
MATERIALIZATION_COMMIT = "103b85ba67de821708256496e80c1cac6dfc4f2b"
PRODUCER_RUN_ID = "CHATGPT-NATIVE-S26-N08-GOLDEN-B-001"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_ui_validator():
    path = ROOT / "profiles/ui_architect/validators/validate_ui_architect_output.py"
    spec = importlib.util.spec_from_file_location("ui_architect_validator_s26", path)
    if spec is None or spec.loader is None:
        raise SystemExit("BLOCK_UI_VALIDATOR_LOAD")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validate


def resolve_preflight() -> dict[str, Any]:
    completed = subprocess.run(
        ["python3", str(PREPARE)],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def make_pending_quality_receipt(
    *, execution_receipt: dict[str, Any], check_bundle: dict[str, Any], manifest: dict[str, Any], raw_sha: str,
) -> dict[str, Any]:
    artifact_ref = "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_002/raw_output.json"
    source_bundle = {
        "artifact_ref": artifact_ref,
        "artifact_sha_or_digest": raw_sha,
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
        "reviewer_run_id": "PENDING-INDEPENDENT-REVIEW",
        "input_sha256": execution_receipt["input_sha256"],
        "raw_output_sha256": raw_sha,
        "execution_receipt_sha256": execution_receipt["receipt_sha256"],
        "obligation_manifest_sha256": canonical_json_sha256(manifest),
        "check_bundle_sha256": canonical_json_sha256(check_bundle),
        "source_bundle_sha256": canonical_json_sha256(source_bundle),
    }
    binding["binding_sha256"] = canonical_json_sha256(binding)
    receipt = {
        "receipt_version": "v0.1",
        "execution_mode": "INDEPENDENT_CHAT_CONTEXT",
        "semantic_status": "NOT_EXECUTED",
        "review_case_id": "S26-N08-GPT-NATIVE-GOLDEN-B-QUALITY-001",
        "reviewer_is_producer": False,
        "producer_context_available": False,
        "external_paid_model_used": False,
        "automated_semantic_judge_implemented": False,
        "review_completed": False,
        "source_bundle": source_bundle,
        "quality_review": {
            "review_id": "PENDING",
            "reviewed_artifact": artifact_ref,
            "verdict": "BLOCK_PIPELINE",
            "score_breakdown": {
                "contract_schema_compliance": 0,
                "evidence_integrity": 0,
                "lf_safety_governance": 0,
                "handoff_readiness": 0,
                "leakage_scope_control": 0,
                "total": 0,
            },
            "evidence_map": [],
            "blocking_codes": ["INDEPENDENT_REVIEW_NOT_EXECUTED"],
            "repair_actions": [],
            "remaining_risks": [],
            "next_gate": "INDEPENDENT_CHAT_CONTEXT",
            "routing": {
                "activation_path": "ROUTER",
                "via": "ORCHESTRATOR",
                "pipeline_action": "BLOCK_PIPELINE",
                "resolution_target": "NONE"
            }
        },
        "execution_blockers": ["INDEPENDENT_REVIEW_NOT_EXECUTED"],
        "semantic_binding": binding,
    }
    receipt["receipt_sha256"] = canonical_json_sha256(receipt)
    return receipt


def main() -> int:
    preflight = resolve_preflight()
    if preflight.get("verdict") != "PASS":
        raise SystemExit("BLOCK_PREFLIGHT_NOT_PASS")

    raw_output = load_json(RAW_PATH)
    input_literal = INPUT_PATH.read_text(encoding="utf-8")
    raw_sha = canonical_json_sha256(raw_output)

    ui_errors = load_ui_validator()(raw_output)
    if ui_errors:
        print(json.dumps({"status": "BLOCK_UI_VALIDATOR", "errors": ui_errors}, ensure_ascii=False, indent=2))
        return 1

    manifest = preflight["obligation_manifest"]
    bundle = validate_bundle(
        build_check_bundle(manifest, raw_output, raw_output_sha256=raw_sha)
    )
    deterministic, semantic = partition_checks(bundle)
    bad_deterministic = [result.as_dict() for result in deterministic if result.verdict != "COMPLIES"]
    if bad_deterministic:
        print(json.dumps({"status": "BLOCK_DETERMINISTIC_OBLIGATION", "checks": bad_deterministic}, indent=2))
        return 1
    semantic_ids = sorted(check["check_id"] for check in semantic)
    if semantic_ids != ["OVERFLOW-DIRECTION", "PAGINATION-DIRECTION"]:
        print(json.dumps({"status": "BLOCK_SEMANTIC_COVERAGE", "semantic_ids": semantic_ids}, indent=2))
        return 1

    native_request = {
        "schema": "LF_NATIVE_CHAT_EXECUTION_REQUEST_V1",
        "execution_id": preflight["execution_id"],
        "executor_mode": "GPT_NATIVE",
        "execution_contract_sha256": preflight["execution_contract_sha256"],
        "obligation_manifest_sha256": preflight["obligation_manifest_sha256"],
        "input_sha256": preflight["input_sha256"],
        "profile_source_sha256": preflight["profile_source_sha256"],
        "context_fingerprint": preflight["context_fingerprint"],
    }
    request_sha = canonical_json_sha256(native_request)
    response_readback = {
        "schema": "LF_NATIVE_CHAT_OUTPUT_READBACK_V1",
        "materialization_commit_sha": MATERIALIZATION_COMMIT,
        "artifact_ref": RAW_PATH.relative_to(ROOT).as_posix(),
        "raw_output_sha256": raw_sha,
    }
    response_sha = canonical_json_sha256(response_readback)
    attestation_evidence = canonical_json_sha256({
        "request": native_request,
        "response_readback": response_readback,
    })

    execution_receipt = build_receipt(
        execution_id=preflight["execution_id"],
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_source_refs=[item["ref"] for item in preflight["profile_source_manifest"]],
        profile_source_sha256=preflight["profile_source_sha256"],
        input_literal=input_literal,
        raw_output=raw_output,
        runtime_attestation={
            "provider": "OPENAI_CHATGPT_NATIVE",
            "model_id": "GPT-5.6 Sol",
            "run_id": PRODUCER_RUN_ID,
            "attested_at": "2026-09-08T19:17:00+00:00",
            "attestation_verifier": "GITHUB_MATERIALIZATION_READBACK_V1",
            "attestation_evidence_sha256": attestation_evidence,
            "verified_request_sha256": request_sha,
            "verified_response_sha256": response_sha,
            "execution_mode": "GPT_NATIVE",
            "execution_contract_sha256": preflight["execution_contract_sha256"],
            "materialization_commit_sha": MATERIALIZATION_COMMIT,
            "materialization_path": RAW_PATH.relative_to(ROOT).as_posix(),
            "attestation_boundary": "Model identity/execution is the native ChatGPT producer claim; GitHub readback verifies persisted output bytes and their contract bindings, not model internals."
        },
        obligation_manifest_sha256=preflight["obligation_manifest_sha256"],
    )
    receipt_errors = validate_receipt(
        execution_receipt,
        expected_profile_code="PERFIL-UI-ARCHITECT",
        expected_input_literal=input_literal,
        expected_raw_output=raw_output,
        expected_profile_source_sha256=preflight["profile_source_sha256"],
    )
    if receipt_errors:
        print(json.dumps({"status": "BLOCK_EXECUTION_RECEIPT", "errors": receipt_errors}, indent=2))
        return 1

    pending_quality = make_pending_quality_receipt(
        execution_receipt=execution_receipt,
        check_bundle=bundle,
        manifest=manifest,
        raw_sha=raw_sha,
    )
    pending_errors = validate_independent_quality_receipt(
        pending_quality,
        expected_bundle=bundle,
        expected_obligation_manifest=manifest,
        expected_raw_output=raw_output,
        execution_receipt=execution_receipt,
    )
    if "INDEPENDENT_QUALITY_REVIEW_NOT_COMPLETED" not in pending_errors:
        print(json.dumps({"status": "BLOCK_FAIL_CLOSED_NOT_PROVEN", "errors": pending_errors}, indent=2))
        return 1

    result = {
        "schema": "S26_NATIVE_GOLDEN_B_EVALUATION_V1",
        "status": "PASS_PRE_INDEPENDENT_REVIEW",
        "golden_declared": False,
        "next_gate": "INDEPENDENT_CHAT_CONTEXT",
        "execution_id": preflight["execution_id"],
        "materialization_commit_sha": MATERIALIZATION_COMMIT,
        "raw_output_sha256": raw_sha,
        "ui_architect_validator": {"valid": True, "errors": []},
        "deterministic_checks": [result.as_dict() for result in deterministic],
        "semantic_checks_pending": semantic_ids,
        "check_bundle": bundle,
        "check_bundle_sha256": canonical_json_sha256(bundle),
        "execution_receipt": execution_receipt,
        "execution_receipt_sha256": execution_receipt["receipt_sha256"],
        "pending_independent_quality_receipt": pending_quality,
        "pending_quality_blocking_codes": pending_errors,
        "fail_closed_proven": True,
        "forbidden_claims": [
            "GOLDEN",
            "INDEPENDENT_QUALITY_PASS",
            "AUTOMATED_SEMANTIC_JUDGE_IMPLEMENTED",
            "PRODUCTION_AUTHORIZED"
        ]
    }
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
