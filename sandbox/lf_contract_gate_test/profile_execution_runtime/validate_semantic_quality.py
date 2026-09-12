#!/usr/bin/env python3
"""Provider-agnostic semantic quality gate for governed LF profile execution.

The historical provider-specific semantic judge remains supported for old evidence.
Native-first executions may instead use the already-governed Quality Pack
INDEPENDENT_CHAT_CONTEXT receipt, cryptographically bound to the exact producer
execution, raw output, obligation manifest and deterministic check bundle.
"""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path
from typing import Any, Callable

from semantic_mini_judge import (
    canonical_json_sha256,
    partition_checks,
    validate_bundle,
    MiniJudgeInputError,
)
from semantic_obligation_manifest import (
    ObligationManifestError,
    build_check_bundle,
    obligation_manifest_sha256,
    validate_obligation_manifest,
)
from validate_semantic_judge import validate_semantic_judge_receipt

INDEPENDENT_MODE = "INDEPENDENT_CHAT_CONTEXT"
NATIVE_BINDING_SCHEMA = "LF_NATIVE_SEMANTIC_QUALITY_BINDING_V1"
STRICT_PASS_VERDICT = "PASS_TO_COMPOSER"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
IMMUTABLE_GITHUB_REF = re.compile(r"^github://[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}/.+$")


def _text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha(value: Any) -> bool:
    return isinstance(value, str) and bool(HEX64.fullmatch(value))


def _load_validator(path: Path, module_name: str, function_name: str) -> Callable[..., list[str]]:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"{module_name.upper()}_LOAD_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return getattr(module, function_name)


def _quality_pack_validator() -> Callable[[Any], list[str]]:
    repo_root = Path(__file__).resolve().parents[3]
    return _load_validator(
        repo_root / "profiles" / "quality_pack" / "validators" / "validate_independent_semantic_review.py",
        "lf_quality_pack_independent_validator",
        "validate_receipt",
    )


def _quality_pack_routing_validator() -> Callable[[Any, Any], list[str]]:
    repo_root = Path(__file__).resolve().parents[3]
    return _load_validator(
        repo_root / "profiles" / "quality_pack" / "validators" / "validate_routing.py",
        "lf_quality_pack_routing_validator",
        "validate_routing",
    )


def _validate_manifest_and_bundle(
    *,
    expected_obligation_manifest: Any,
    expected_bundle: Any,
    expected_raw_output: Any,
    execution_receipt: dict[str, Any],
) -> tuple[dict[str, Any] | None, dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    try:
        manifest = validate_obligation_manifest(
            expected_obligation_manifest,
            expected_execution_id=execution_receipt.get("execution_id"),
            expected_profile_code=execution_receipt.get("profile_code"),
            expected_profile_source_sha256=execution_receipt.get("profile_source_sha256"),
            expected_input_sha256=execution_receipt.get("input_sha256"),
        )
    except ObligationManifestError as exc:
        return None, None, [f"SEMANTIC_OBLIGATION_MANIFEST_INVALID:{exc}"]

    manifest_sha = obligation_manifest_sha256(manifest)
    if execution_receipt.get("obligation_manifest_sha256") != manifest_sha:
        errors.append("EXECUTION_OBLIGATION_MANIFEST_SHA256_MISMATCH")

    try:
        bundle = validate_bundle(expected_bundle)
    except MiniJudgeInputError as exc:
        return manifest, None, errors + [f"SEMANTIC_CHECK_BUNDLE_INVALID:{exc}"]

    try:
        derived = build_check_bundle(
            manifest,
            expected_raw_output,
            raw_output_sha256=execution_receipt.get("raw_output_sha256"),
        )
    except ObligationManifestError as exc:
        return manifest, bundle, errors + [f"SEMANTIC_BUNDLE_DERIVATION_FAILED:{exc}"]

    if canonical_json_sha256(bundle) != canonical_json_sha256(derived):
        errors.append("SEMANTIC_CHECK_BUNDLE_NOT_DERIVED_FROM_MANIFEST")

    deterministic, _semantic = partition_checks(bundle)
    for result in deterministic:
        if result.verdict != "COMPLIES":
            errors.append(f"DETERMINISTIC_SEMANTIC_CHECK_{result.check_id}_NOT_COMPLIANT")

    return manifest, bundle, errors


def validate_independent_quality_receipt(
    semantic_receipt: Any,
    *,
    expected_bundle: Any,
    expected_obligation_manifest: Any,
    expected_raw_output: Any,
    execution_receipt: dict[str, Any],
) -> list[str]:
    errors: list[str] = []
    if not isinstance(semantic_receipt, dict):
        return ["INDEPENDENT_QUALITY_RECEIPT_NOT_OBJECT"]

    try:
        qp_errors = _quality_pack_validator()(semantic_receipt)
    except Exception as exc:
        return [f"QUALITY_PACK_VALIDATOR_EXECUTION_FAILED:{type(exc).__name__}"]
    errors.extend(f"QUALITY_PACK_RECEIPT_INVALID:{item}" for item in qp_errors)

    if semantic_receipt.get("execution_mode") != INDEPENDENT_MODE:
        errors.append("INDEPENDENT_QUALITY_EXECUTION_MODE_INVALID")
    if semantic_receipt.get("review_completed") is not True:
        errors.append("INDEPENDENT_QUALITY_REVIEW_NOT_COMPLETED")
    if semantic_receipt.get("semantic_status") != "EXECUTED_INDEPENDENT_CONTEXT":
        errors.append("INDEPENDENT_QUALITY_SEMANTIC_STATUS_INVALID")
    if semantic_receipt.get("reviewer_is_producer") is not False:
        errors.append("INDEPENDENT_QUALITY_REVIEWER_IS_PRODUCER")
    if semantic_receipt.get("producer_context_available") is not False:
        errors.append("INDEPENDENT_QUALITY_PRODUCER_CONTEXT_LEAK")
    if semantic_receipt.get("external_paid_model_used") is not False:
        errors.append("INDEPENDENT_QUALITY_PAID_MODEL_FORBIDDEN")

    review = semantic_receipt.get("quality_review")
    if not isinstance(review, dict):
        errors.append("INDEPENDENT_QUALITY_REVIEW_MISSING")
        review = {}
    if review.get("verdict") != STRICT_PASS_VERDICT:
        errors.append("INDEPENDENT_QUALITY_VERDICT_NOT_STRICT_PASS")

    try:
        routing_errors = _quality_pack_routing_validator()(review.get("verdict"), review.get("routing"))
    except Exception as exc:
        errors.append(f"QUALITY_PACK_ROUTING_VALIDATOR_EXECUTION_FAILED:{type(exc).__name__}")
        routing_errors = []
    errors.extend(f"QUALITY_PACK_ROUTING_INVALID:{item}" for item in routing_errors)

    source = semantic_receipt.get("source_bundle")
    if not isinstance(source, dict):
        errors.append("INDEPENDENT_QUALITY_SOURCE_BUNDLE_MISSING")
        source = {}
    artifact_ref = source.get("artifact_ref")
    if not _text(artifact_ref) or not IMMUTABLE_GITHUB_REF.fullmatch(artifact_ref):
        errors.append("INDEPENDENT_QUALITY_ARTIFACT_REF_NOT_IMMUTABLE")
    if _text(artifact_ref) and review.get("reviewed_artifact") != artifact_ref:
        errors.append("INDEPENDENT_QUALITY_REVIEWED_ARTIFACT_REF_MISMATCH")
    if not _sha(source.get("artifact_byte_sha256")):
        errors.append("INDEPENDENT_QUALITY_ARTIFACT_BYTE_SHA256_INVALID")

    manifest, bundle, manifest_bundle_errors = _validate_manifest_and_bundle(
        expected_obligation_manifest=expected_obligation_manifest,
        expected_bundle=expected_bundle,
        expected_raw_output=expected_raw_output,
        execution_receipt=execution_receipt,
    )
    errors.extend(manifest_bundle_errors)

    raw_sha = execution_receipt.get("raw_output_sha256")
    if not _sha(raw_sha):
        errors.append("EXECUTION_RAW_OUTPUT_SHA256_INVALID")
    if source.get("semantic_raw_output_sha256") != raw_sha:
        errors.append("INDEPENDENT_QUALITY_SEMANTIC_RAW_SHA_MISMATCH")

    binding = semantic_receipt.get("semantic_binding")
    if not isinstance(binding, dict):
        errors.append("NATIVE_SEMANTIC_BINDING_MISSING")
        binding = {}
    if binding.get("schema") != NATIVE_BINDING_SCHEMA:
        errors.append("NATIVE_SEMANTIC_BINDING_SCHEMA_INVALID")

    required_binding_strings = (
        "execution_id", "profile_code", "producer_run_id", "reviewer_run_id",
        "input_sha256", "raw_output_sha256", "execution_receipt_sha256",
        "obligation_manifest_sha256", "check_bundle_sha256", "source_bundle_sha256",
        "binding_sha256",
    )
    for field in required_binding_strings:
        if not _text(binding.get(field)):
            errors.append(f"NATIVE_SEMANTIC_BINDING_{field.upper()}_MISSING")

    for field in (
        "input_sha256", "raw_output_sha256", "execution_receipt_sha256",
        "obligation_manifest_sha256", "check_bundle_sha256", "source_bundle_sha256",
        "binding_sha256",
    ):
        value = binding.get(field)
        if _text(value) and not _sha(value):
            errors.append(f"NATIVE_SEMANTIC_BINDING_{field.upper()}_INVALID")

    expected_pairs = {
        "execution_id": execution_receipt.get("execution_id"),
        "profile_code": execution_receipt.get("profile_code"),
        "input_sha256": execution_receipt.get("input_sha256"),
        "raw_output_sha256": raw_sha,
        "execution_receipt_sha256": execution_receipt.get("receipt_sha256"),
    }
    if manifest is not None:
        expected_pairs["obligation_manifest_sha256"] = obligation_manifest_sha256(manifest)
    if bundle is not None:
        expected_pairs["check_bundle_sha256"] = canonical_json_sha256(bundle)
    if source:
        expected_pairs["source_bundle_sha256"] = canonical_json_sha256(source)

    for field, expected in expected_pairs.items():
        if binding.get(field) != expected:
            errors.append(f"NATIVE_SEMANTIC_BINDING_{field.upper()}_MISMATCH")

    producer_run = binding.get("producer_run_id")
    reviewer_run = binding.get("reviewer_run_id")
    attestation = execution_receipt.get("runtime_attestation")
    if isinstance(attestation, dict) and producer_run != attestation.get("run_id"):
        errors.append("NATIVE_SEMANTIC_BINDING_PRODUCER_RUN_ID_MISMATCH")
    if _text(producer_run) and _text(reviewer_run) and producer_run == reviewer_run:
        errors.append("NATIVE_SEMANTIC_REVIEW_NOT_INDEPENDENT")

    receipt_sha = semantic_receipt.get("receipt_sha256")
    if not _sha(receipt_sha):
        errors.append("INDEPENDENT_QUALITY_RECEIPT_SHA256_INVALID")
    else:
        observed = canonical_json_sha256({k: v for k, v in semantic_receipt.items() if k != "receipt_sha256"})
        if receipt_sha != observed:
            errors.append("INDEPENDENT_QUALITY_RECEIPT_SHA256_MISMATCH")

    binding_sha = binding.get("binding_sha256")
    if _sha(binding_sha):
        observed_binding = canonical_json_sha256({k: v for k, v in binding.items() if k != "binding_sha256"})
        if binding_sha != observed_binding:
            errors.append("NATIVE_SEMANTIC_BINDING_SHA256_MISMATCH")

    return sorted(set(errors))


def validate_semantic_quality_receipt(
    semantic_receipt: Any,
    *,
    expected_bundle: Any,
    expected_obligation_manifest: Any,
    expected_raw_output: Any,
    execution_receipt: dict[str, Any],
) -> list[str]:
    """Select a governed semantic quality mode without provider lock-in."""
    if isinstance(semantic_receipt, dict) and semantic_receipt.get("execution_mode") == INDEPENDENT_MODE:
        return validate_independent_quality_receipt(
            semantic_receipt,
            expected_bundle=expected_bundle,
            expected_obligation_manifest=expected_obligation_manifest,
            expected_raw_output=expected_raw_output,
            execution_receipt=execution_receipt,
        )

    # Historical/legacy receipts remain verifiable, but are no longer the only
    # acceptable final quality route for native-first profile execution.
    return validate_semantic_judge_receipt(
        semantic_receipt,
        expected_bundle=expected_bundle,
        expected_obligation_manifest=expected_obligation_manifest,
        expected_raw_output=expected_raw_output,
        execution_receipt=execution_receipt,
    )
