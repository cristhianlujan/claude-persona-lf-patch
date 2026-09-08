#!/usr/bin/env python3
"""Fail-closed validator for semantic mini-judge receipts before final downstream use."""

from __future__ import annotations

import re
from typing import Any

from semantic_mini_judge import (
    MODEL_VERDICTS,
    RECEIPT_TYPE,
    MiniJudgeInputError,
    canonical_json_sha256,
    validate_bundle,
)
from semantic_obligation_manifest import (
    ObligationManifestError,
    build_check_bundle,
    obligation_manifest_sha256,
    validate_obligation_manifest,
)

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ALLOWED_DECIDERS = {"PYTHON_DETERMINISTIC", "LOCAL_SEMANTIC_MODEL", "REMOTE_SEMANTIC_MODEL"}
SEMANTIC_DECIDERS = {"LOCAL_SEMANTIC_MODEL", "REMOTE_SEMANTIC_MODEL"}
DETERMINISTIC_DECIDER = "PYTHON_DETERMINISTIC"
ALLOWED_SEMANTIC_ADAPTER_ID = "cloudflare-workers-ai-nemotron3-120b-semantic-minijudge-v1"
ALLOWED_SEMANTIC_VERIFIER_ID = "cloudflare-workers-ai-nemotron3-120b-semantic-minijudge-readback-v1"
ALLOWED_SEMANTIC_MODEL_ID = "@cf/nvidia/nemotron-3-120b-a12b"
ALLOWED_SEMANTIC_MODEL_BINDING_SHA256 = "345f068350a56ea809ea7de5e7a711a8f06dc0af881d555a50b42ccb9419ab39"
ALLOWED_SEMANTIC_CALIBRATION_SHA256 = "ce96a3594aaba21629cdc54ac248dcf019068a52b095ffcef80d9b71379af5cf"
ALLOWED_AUTHORITY_DECISION_REF = "S26-REMOTE-JUDGE-CHALLENGER-20260908"


def _text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha(value: Any) -> bool:
    return isinstance(value, str) and bool(SHA256_RE.fullmatch(value))


def _bundle_or_errors(bundle: Any) -> tuple[dict[str, Any] | None, list[str]]:
    if bundle is None:
        return None, ["SEMANTIC_CHECK_BUNDLE_MISSING"]
    try:
        return validate_bundle(bundle), []
    except MiniJudgeInputError as exc:
        return None, [f"SEMANTIC_CHECK_BUNDLE_INVALID:{exc}"]


def _manifest_or_errors(
    manifest: Any,
    *,
    execution_receipt: dict[str, Any],
) -> tuple[dict[str, Any] | None, list[str]]:
    if manifest is None:
        return None, ["SEMANTIC_OBLIGATION_MANIFEST_MISSING"]
    try:
        normalized = validate_obligation_manifest(
            manifest,
            expected_execution_id=execution_receipt.get("execution_id"),
            expected_profile_code=execution_receipt.get("profile_code"),
            expected_profile_source_sha256=execution_receipt.get("profile_source_sha256"),
            expected_input_sha256=execution_receipt.get("input_sha256"),
        )
        return normalized, []
    except ObligationManifestError as exc:
        return None, [f"SEMANTIC_OBLIGATION_MANIFEST_INVALID:{exc}"]


def validate_semantic_judge_receipt(
    semantic_receipt: Any,
    *,
    expected_bundle: Any,
    expected_obligation_manifest: Any,
    expected_raw_output: Any,
    execution_receipt: dict[str, Any],
) -> list[str]:
    """Validate semantic receipt plus complete pre-bound obligation coverage."""

    errors: list[str] = []
    bundle, bundle_errors = _bundle_or_errors(expected_bundle)
    errors.extend(bundle_errors)
    manifest, manifest_errors = _manifest_or_errors(
        expected_obligation_manifest,
        execution_receipt=execution_receipt,
    )
    errors.extend(manifest_errors)

    if semantic_receipt is None:
        errors.append("PROFILE_SEMANTIC_JUDGE_RECEIPT_MISSING")
        return sorted(set(errors))
    if not isinstance(semantic_receipt, dict):
        errors.append("PROFILE_SEMANTIC_JUDGE_RECEIPT_NOT_OBJECT")
        return sorted(set(errors))
    if bundle is None or manifest is None:
        return sorted(set(errors))
    if expected_raw_output is None:
        errors.append("SEMANTIC_RAW_OUTPUT_REQUIRED_FOR_COMPLETENESS")
        return sorted(set(errors))

    manifest_sha = obligation_manifest_sha256(manifest)
    execution_manifest_sha = execution_receipt.get("obligation_manifest_sha256")
    if not _sha(execution_manifest_sha):
        errors.append("EXECUTION_OBLIGATION_MANIFEST_SHA256_MISSING")
    elif execution_manifest_sha != manifest_sha:
        errors.append("EXECUTION_OBLIGATION_MANIFEST_SHA256_MISMATCH")

    try:
        expected_derived_bundle = build_check_bundle(
            manifest,
            expected_raw_output,
            raw_output_sha256=execution_receipt.get("raw_output_sha256"),
        )
    except ObligationManifestError as exc:
        errors.append(f"SEMANTIC_BUNDLE_DERIVATION_FAILED:{exc}")
        expected_derived_bundle = None
    if (
        expected_derived_bundle is not None
        and canonical_json_sha256(bundle) != canonical_json_sha256(expected_derived_bundle)
    ):
        errors.append("SEMANTIC_CHECK_BUNDLE_NOT_DERIVED_FROM_MANIFEST")

    for field in (
        "receipt_type",
        "execution_id",
        "profile_code",
        "input_sha256",
        "raw_output_sha256",
        "obligation_manifest_sha256",
        "check_bundle_sha256",
        "verdict",
        "downstream_disposition",
        "receipt_sha256",
    ):
        if not _text(semantic_receipt.get(field)):
            errors.append(f"SEMANTIC_RECEIPT_{field.upper()}_MISSING")

    for field in (
        "input_sha256",
        "raw_output_sha256",
        "obligation_manifest_sha256",
        "check_bundle_sha256",
        "receipt_sha256",
    ):
        value = semantic_receipt.get(field)
        if _text(value) and not _sha(value):
            errors.append(f"SEMANTIC_RECEIPT_{field.upper()}_INVALID")

    if semantic_receipt.get("receipt_type") != RECEIPT_TYPE:
        errors.append("SEMANTIC_RECEIPT_TYPE_INVALID")
    if semantic_receipt.get("uncertain_blocks") is not True:
        errors.append("SEMANTIC_UNCERTAIN_MUST_BLOCK")
    if semantic_receipt.get("self_authorizes_downstream") is not False:
        errors.append("SEMANTIC_SELF_AUTHORIZATION_FORBIDDEN")
    if semantic_receipt.get("verdict") != "PASS":
        errors.append("SEMANTIC_VERDICT_NOT_PASS")
    if semantic_receipt.get("downstream_disposition") != "ELIGIBLE":
        errors.append("SEMANTIC_DOWNSTREAM_NOT_ELIGIBLE")

    if bundle.get("obligation_manifest_sha256") != manifest_sha:
        errors.append("BUNDLE_OBLIGATION_MANIFEST_SHA256_MISMATCH")
    if semantic_receipt.get("obligation_manifest_sha256") != manifest_sha:
        errors.append("SEMANTIC_OBLIGATION_MANIFEST_SHA256_MISMATCH")

    expected_bundle_sha = canonical_json_sha256(bundle)
    if semantic_receipt.get("check_bundle_sha256") != expected_bundle_sha:
        errors.append("SEMANTIC_CHECK_BUNDLE_SHA256_MISMATCH")

    execution_pairs = (
        ("execution_id", "SEMANTIC_EXECUTION_ID_MISMATCH"),
        ("profile_code", "SEMANTIC_PROFILE_CODE_MISMATCH"),
        ("input_sha256", "SEMANTIC_INPUT_SHA256_MISMATCH"),
        ("raw_output_sha256", "SEMANTIC_RAW_OUTPUT_SHA256_MISMATCH"),
    )
    for field, code in execution_pairs:
        if bundle.get(field) != execution_receipt.get(field):
            errors.append(f"BUNDLE_{code}")
        if semantic_receipt.get(field) != execution_receipt.get(field):
            errors.append(code)

    claimed_receipt_sha = semantic_receipt.get("receipt_sha256")
    if _sha(claimed_receipt_sha):
        observed = canonical_json_sha256(
            {key: value for key, value in semantic_receipt.items() if key != "receipt_sha256"}
        )
        if observed != claimed_receipt_sha:
            errors.append("SEMANTIC_RECEIPT_SHA256_MISMATCH")

    expected_checks = {check["check_id"]: check for check in bundle["checks"]}
    manifest_obligation_ids = {item["obligation_id"] for item in manifest["obligations"]}
    if set(expected_checks) != manifest_obligation_ids:
        errors.append("SEMANTIC_OBLIGATION_COVERAGE_MISMATCH")

    receipt_checks = semantic_receipt.get("checks")
    if not isinstance(receipt_checks, list) or not receipt_checks:
        errors.append("SEMANTIC_RECEIPT_CHECKS_INVALID")
        receipt_checks = []

    observed_checks: dict[str, dict[str, Any]] = {}
    for item in receipt_checks:
        if not isinstance(item, dict):
            errors.append("SEMANTIC_RECEIPT_CHECK_NOT_OBJECT")
            continue
        check_id = item.get("check_id")
        if not _text(check_id):
            errors.append("SEMANTIC_RECEIPT_CHECK_ID_MISSING")
            continue
        if check_id in observed_checks:
            errors.append("SEMANTIC_RECEIPT_CHECK_ID_DUPLICATE")
            continue
        observed_checks[check_id] = item
        if check_id not in expected_checks:
            errors.append("SEMANTIC_RECEIPT_UNKNOWN_CHECK_ID")
            continue
        verdict = item.get("verdict")
        if verdict not in MODEL_VERDICTS:
            errors.append(f"SEMANTIC_CHECK_{check_id}_VERDICT_INVALID")
        elif verdict != "COMPLIES":
            errors.append(f"SEMANTIC_CHECK_{check_id}_NOT_COMPLIANT")
        if not _text(item.get("reason_code")):
            errors.append(f"SEMANTIC_CHECK_{check_id}_REASON_MISSING")
        decided_by = item.get("decided_by")
        if decided_by not in ALLOWED_DECIDERS:
            errors.append(f"SEMANTIC_CHECK_{check_id}_DECIDER_INVALID")
        expected_type = expected_checks[check_id]["check_type"]
        if expected_type == "SEMANTIC_RELATION" and decided_by not in SEMANTIC_DECIDERS:
            errors.append(f"SEMANTIC_CHECK_{check_id}_MODEL_DECIDER_REQUIRED")
        if expected_type != "SEMANTIC_RELATION" and decided_by != DETERMINISTIC_DECIDER:
            errors.append(f"SEMANTIC_CHECK_{check_id}_DETERMINISTIC_DECIDER_REQUIRED")

    if set(observed_checks) != set(expected_checks):
        errors.append("SEMANTIC_CHECK_COVERAGE_MISMATCH")

    semantic_ids = {
        check_id
        for check_id, check in expected_checks.items()
        if check["check_type"] == "SEMANTIC_RELATION"
    }
    runtime_evidence = semantic_receipt.get("runtime_evidence")
    if not isinstance(runtime_evidence, list):
        errors.append("SEMANTIC_RUNTIME_EVIDENCE_INVALID")
        runtime_evidence = []

    evidence_by_check: dict[str, dict[str, Any]] = {}
    for entry in runtime_evidence:
        if not isinstance(entry, dict):
            errors.append("SEMANTIC_RUNTIME_EVIDENCE_ENTRY_INVALID")
            continue
        check_id = entry.get("check_id")
        if not _text(check_id) or check_id in evidence_by_check:
            errors.append("SEMANTIC_RUNTIME_EVIDENCE_CHECK_ID_INVALID")
            continue
        evidence_by_check[check_id] = entry
        if check_id not in semantic_ids:
            errors.append("SEMANTIC_RUNTIME_EVIDENCE_UNKNOWN_CHECK")
            continue
        adapter = entry.get("adapter_evidence")
        verification = entry.get("verification")
        if not isinstance(adapter, dict):
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_ADAPTER_EVIDENCE_MISSING")
            continue
        if not isinstance(verification, dict):
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_VERIFICATION_MISSING")
            continue
        if adapter.get("adapter_id") != ALLOWED_SEMANTIC_ADAPTER_ID:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_ADAPTER_NOT_ALLOWED")
        if adapter.get("model_id") != ALLOWED_SEMANTIC_MODEL_ID:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_MODEL_NOT_ALLOWED")
        if adapter.get("model_binding_sha256") != ALLOWED_SEMANTIC_MODEL_BINDING_SHA256:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_MODEL_BINDING_SHA256_MISMATCH")
        if adapter.get("calibration_sha256") != ALLOWED_SEMANTIC_CALIBRATION_SHA256:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_CALIBRATION_SHA256_MISMATCH")
        if adapter.get("authority_decision_ref") != ALLOWED_AUTHORITY_DECISION_REF:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_AUTHORITY_DECISION_MISMATCH")
        if adapter.get("authority_status") != "ACTIVE_SANDBOX_SEMANTIC_AUTHORITY":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_AUTHORITY_STATUS_INVALID")
        if adapter.get("provider") != "cloudflare_workers_ai":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_PROVIDER_INVALID")
        if adapter.get("transport") != "CLOUDFLARE_WORKERS_AI_REST":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_TRANSPORT_INVALID")
        if adapter.get("cloudflare_plan") != "WORKERS_FREE_ZERO_COST_ONLY":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_FREE_ONLY_INVALID")
        if adapter.get("limit_behavior") != "FAIL_CLOSED":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_LIMIT_BEHAVIOR_INVALID")
        if adapter.get("provider_infrastructure_shared_with_primary") is not True:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_SHARED_PROVIDER_FLAG_MISSING")
        if adapter.get("shared_provider_owner_approved") is not True:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_SHARED_PROVIDER_APPROVAL_MISSING")
        if adapter.get("provider_managed_model_weights") is not True:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_PROVIDER_MANAGED_MODEL_REQUIRED")
        if adapter.get("model_weights_downloaded") is not False:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_MODEL_DOWNLOAD_FORBIDDEN")
        if adapter.get("local_model_fallback_used") is not False:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_LOCAL_FALLBACK_FORBIDDEN")
        if adapter.get("paid_fallback_used") is not False:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_PAID_FALLBACK_FORBIDDEN")
        if adapter.get("repository_visibility") != "public":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_VISIBILITY_INVALID")
        if adapter.get("runner_label") != "ubuntu-latest":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_RUNNER_INVALID")
        if not _text(adapter.get("github_run_id")) or not _text(adapter.get("github_sha")):
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_GITHUB_BINDING_MISSING")
        if verification.get("verified") is not True:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_NOT_VERIFIED")
        if verification.get("verifier_id") != ALLOWED_SEMANTIC_VERIFIER_ID:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_VERIFIER_NOT_ALLOWED")
        if not _sha(verification.get("evidence_sha256")):
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_VERIFIER_EVIDENCE_INVALID")
        classification = adapter.get("classification")
        observed_check = observed_checks.get(check_id)
        if not isinstance(classification, dict) or observed_check is None:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_CLASSIFICATION_MISSING")
        else:
            for key in ("check_id", "verdict", "reason_code", "decided_by"):
                if classification.get(key) != observed_check.get(key):
                    errors.append(f"SEMANTIC_RUNTIME_{check_id}_CLASSIFICATION_MISMATCH")
                    break

    if set(evidence_by_check) != semantic_ids:
        errors.append("SEMANTIC_RUNTIME_EVIDENCE_COVERAGE_MISMATCH")

    return sorted(set(errors))
