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


EXECUTOR_ADAPTER_IDENTITY = {
    # Native chat executors. These IDs are deliberately distinct from API adapters.
    "chatgpt-native-current-context-v1": {
        "executor_mode": "GPT_NATIVE",
        "providers": {"OPENAI_CHATGPT_NATIVE"},
        "model_markers": ("gpt",),
    },
    "claude-native-current-context-v1": {
        "executor_mode": "CLAUDE_NATIVE",
        "providers": {"ANTHROPIC_CLAUDE_NATIVE"},
        "model_markers": ("claude",),
    },
    # Remote/API executors. Availability never implies permission to use a different mode.
    "cloudflare-workers-ai-v1": {
        "executor_mode": "REMOTE_API",
        "providers": {"CLOUDFLARE_WORKERS_AI"},
        "model_markers": ("@cf/",),
    },
    "openai-responses-v1": {
        "executor_mode": "REMOTE_API",
        "providers": {"openai"},
        "model_markers": ("gpt", "o1", "o3", "o4"),
    },
    "github-standard-llamacpp-qwen25vl-v1": {
        "executor_mode": "REMOTE_API",
        "providers": {"local_llama_cpp_github_standard_public"},
        "model_markers": ("qwen",),
    },
    "persistent-cpu-llamacpp-qwen25vl-v1": {
        "executor_mode": "REMOTE_API",
        "providers": {"local_llama_cpp_persistent_cpu"},
        "model_markers": ("qwen",),
    },
    "hetzner-local-llamacpp-http-v1": {
        "executor_mode": "REMOTE_API",
        "providers": {"local_llama_cpp_hetzner_persistent"},
        "model_markers": ("qwen", "model.gguf"),
    },
}


def _executor_identity(adapter: RuntimeAdapter) -> dict[str, Any]:
    adapter_id = getattr(adapter, "adapter_id", None)
    identity = EXECUTOR_ADAPTER_IDENTITY.get(adapter_id)
    if identity is None:
        raise RuntimeExecutionBlocked(
            "EXECUTOR_ADAPTER_IDENTITY_UNREGISTERED",
            str(adapter_id or "MISSING"),
        )
    return identity


def _validate_executor_identity_pre_call(*, executor_mode: str, adapter: RuntimeAdapter) -> None:
    identity = _executor_identity(adapter)
    if identity["executor_mode"] != executor_mode:
        raise RuntimeExecutionBlocked(
            "EXECUTOR_MODE_ADAPTER_MISMATCH",
            f"mode={executor_mode};adapter_id={adapter.adapter_id};expected_mode={identity['executor_mode']}",
        )


def _validate_executor_identity_post_call(
    *, executor_mode: str, adapter: RuntimeAdapter, runtime_attestation: dict[str, Any]
) -> None:
    identity = _executor_identity(adapter)
    provider = runtime_attestation.get("provider")
    if provider not in identity["providers"]:
        raise RuntimeExecutionBlocked(
            "EXECUTOR_MODE_PROVIDER_MISMATCH",
            f"mode={executor_mode};adapter_id={adapter.adapter_id};provider={provider}",
        )
    attested_mode = runtime_attestation.get("executor_mode")
    if attested_mode != executor_mode:
        code = (
            "EXECUTOR_MODE_ATTESTATION_MISSING"
            if attested_mode is None
            else "EXECUTOR_MODE_ATTESTATION_MISMATCH"
        )
        raise RuntimeExecutionBlocked(
            code,
            f"mode={executor_mode};attested={attested_mode}",
        )
    model_id = str(runtime_attestation.get("model_id") or "").strip()
    if not model_id:
        raise RuntimeExecutionBlocked("EXECUTOR_MODE_MODEL_ID_MISSING")
    model_id_lower = model_id.lower()
    markers = tuple(str(item).lower() for item in identity.get("model_markers") or ())
    if markers and not any(marker in model_id_lower for marker in markers):
        raise RuntimeExecutionBlocked(
            "EXECUTOR_MODE_MODEL_ID_MISMATCH",
            f"mode={executor_mode};adapter_id={adapter.adapter_id};model_id={model_id}",
        )


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
    _validate_executor_identity_pre_call(
        executor_mode=execution_contract["executor_mode"],
        adapter=adapter,
    )

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
    _validate_executor_identity_post_call(
        executor_mode=execution_contract["executor_mode"],
        adapter=adapter,
        runtime_attestation=runtime_attestation,
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
