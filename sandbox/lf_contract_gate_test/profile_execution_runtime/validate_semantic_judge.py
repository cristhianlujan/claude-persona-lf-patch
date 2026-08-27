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
ALLOWED_DECIDERS = {"PYTHON_DETERMINISTIC", "LOCAL_SEMANTIC_MODEL"}
SEMANTIC_DECIDER = "LOCAL_SEMANTIC_MODEL"
DETERMINISTIC_DECIDER = "PYTHON_DETERMINISTIC"
ALLOWED_SEMANTIC_ADAPTER_ID = "github-standard-qwen25vl7b-semantic-minijudge-server-v3"
ALLOWED_SEMANTIC_VERIFIER_ID = "github-standard-qwen25vl7b-semantic-minijudge-readback-v3"
ALLOWED_SEMANTIC_MODEL_ID = (
    "ggml-org/Qwen2.5-VL-7B-Instruct-GGUF@"
    "508edd0afaa66bb9e9f40587acc2184f02daf1f6:"
    "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
)
ALLOWED_SEMANTIC_MODEL_SHA256 = "9258bf05b12686d097ff3b6b18d968ab393649780aa2b3cd67fec43d50554392"
ALLOWED_LLAMA_SOURCE_COMMIT = "925e1179947ea0c0ebfb0032df18af3a729822be"


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
    """Validate semantic receipt plus complete pre-bound obligation coverage.

    The obligation manifest is created before model execution and its digest is bound into
    the execution request/receipt. The check bundle is then reconstructed deterministically
    from that manifest and the exact RAW output. A caller cannot obtain PASS by supplying a
    manual subset of checks, changing a rule, or dropping an enumerated obligation.
    """

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
    if expected_derived_bundle is not None and canonical_json_sha256(bundle) != canonical_json_sha256(expected_derived_bundle):
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
        if expected_type == "SEMANTIC_RELATION" and decided_by != SEMANTIC_DECIDER:
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
        if adapter.get("model_sha256") != ALLOWED_SEMANTIC_MODEL_SHA256:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_MODEL_SHA256_MISMATCH")
        if adapter.get("llama_source_commit") != ALLOWED_LLAMA_SOURCE_COMMIT:
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_LLAMA_COMMIT_MISMATCH")
        if adapter.get("provider") != "local_llama_cpp_github_standard_public":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_PROVIDER_INVALID")
        if adapter.get("transport") != "LOCALHOST_LLAMA_SERVER":
            errors.append(f"SEMANTIC_RUNTIME_{check_id}_TRANSPORT_INVALID")
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
