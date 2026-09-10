#!/usr/bin/env python3
"""Contract-bound wrapper over the existing governed profile runtime runner."""

from __future__ import annotations

from typing import Any

from profile_execution_contract import validate_execution_contract
from profile_runtime_runner import (
    RESULT_TYPE,
    RuntimeAdapter,
    RuntimeAttestationVerifier,
    RuntimeExecutionBlocked,
    _build_lf_adapter_invocations,
    _validate_adapter,
    _validate_response,
    _validate_verification,
    _validate_verifier,
    build_runtime_request,
)
from validate_profile_execution import build_receipt, canonical_json_sha256


def execute_contract_bound_profile_runtime(
    *,
    execution_contract: dict[str, Any],
    execution_id: str,
    profile_code: str,
    profile_slug: str,
    profile_sources: list[dict[str, str]],
    input_literal: str,
    adapter: RuntimeAdapter,
    attestation_verifier: RuntimeAttestationVerifier,
    allow_test_doubles: bool = False,
    obligation_manifest: dict[str, Any] | None = None,
    lf_adapter_sources: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    contract_errors = validate_execution_contract(
        execution_contract,
        expected_profile_code=profile_code,
    )
    if contract_errors:
        raise RuntimeExecutionBlocked("EXECUTION_CONTRACT_INVALID", ",".join(contract_errors))
    if execution_contract.get("run_id") != execution_id:
        raise RuntimeExecutionBlocked("EXECUTION_CONTRACT_RUN_ID_MISMATCH")
    if execution_contract.get("executor_mode") not in {"GPT_NATIVE", "CLAUDE_NATIVE", "REMOTE_API"}:
        raise RuntimeExecutionBlocked("EXECUTION_CONTRACT_EXECUTOR_MODE_INVALID")

    _validate_adapter(adapter, allow_test_doubles=allow_test_doubles)
    _validate_verifier(attestation_verifier, allow_test_doubles=allow_test_doubles)

    request = build_runtime_request(
        execution_id=execution_id,
        profile_code=profile_code,
        profile_slug=profile_slug,
        profile_sources=profile_sources,
        input_literal=input_literal,
        obligation_manifest=obligation_manifest,
        lf_adapter_sources=lf_adapter_sources,
    )
    request["executor_mode"] = execution_contract["executor_mode"]
    request["execution_contract_sha256"] = execution_contract["contract_sha256"]
    request["execution_contract"] = execution_contract
    request["request_sha256"] = canonical_json_sha256(
        {key: value for key, value in request.items() if key != "request_sha256"}
    )

    try:
        response = adapter.execute(request)
    except RuntimeExecutionBlocked:
        raise
    except Exception as exc:
        raise RuntimeExecutionBlocked("RUNTIME_ADAPTER_EXCEPTION", type(exc).__name__) from exc

    raw_output, runtime_attestation = _validate_response(
        request=request,
        response=response,
        adapter=adapter,
    )

    try:
        verification = attestation_verifier.verify(
            request=request,
            response=response,
            adapter=adapter,
        )
    except RuntimeExecutionBlocked:
        raise
    except Exception as exc:
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFIER_EXCEPTION", type(exc).__name__) from exc

    verification = _validate_verification(
        request=request,
        response=response,
        verification=verification,
        verifier=attestation_verifier,
    )
    runtime_attestation["attestation_verifier"] = verification["verifier_id"]
    runtime_attestation["attestation_evidence_sha256"] = verification["evidence_sha256"]
    runtime_attestation["verified_request_sha256"] = verification["request_sha256"]
    runtime_attestation["verified_response_sha256"] = verification["response_sha256"]
    runtime_attestation["executor_mode"] = execution_contract["executor_mode"]
    runtime_attestation["execution_contract_sha256"] = execution_contract["contract_sha256"]

    invocations = _build_lf_adapter_invocations(request)
    receipt = build_receipt(
        execution_id=execution_id,
        profile_code=profile_code,
        profile_slug=profile_slug,
        profile_source_refs=request["profile_source_refs"],
        profile_source_sha256=request["profile_source_sha256"],
        input_literal=input_literal,
        raw_output=raw_output,
        runtime_attestation=runtime_attestation,
        obligation_manifest_sha256=request.get("obligation_manifest_sha256"),
        lf_adapter_invocations=invocations,
    )
    receipt["executor_mode"] = execution_contract["executor_mode"]
    receipt["execution_contract_sha256"] = execution_contract["contract_sha256"]
    receipt["receipt_sha256"] = canonical_json_sha256(
        {key: value for key, value in receipt.items() if key != "receipt_sha256"}
    )

    return {
        "result_type": RESULT_TYPE,
        "request": request,
        "raw_output": raw_output,
        "runtime_attestation_verification": verification,
        "receipt": receipt,
        "execution_contract_sha256": execution_contract["contract_sha256"],
        "executor_mode": execution_contract["executor_mode"],
    }
