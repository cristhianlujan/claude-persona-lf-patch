#!/usr/bin/env python3
"""Provider-agnostic runner boundary for governed LF profile execution."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Protocol

from validate_profile_execution import (
    OPERATION_CODE,
    build_receipt,
    canonical_json_sha256,
    sha256_text,
)

REQUEST_TYPE = "PROFILE_RUNTIME_REQUEST_V1"
RESPONSE_TYPE = "PROFILE_RUNTIME_RESPONSE_V1"
RESULT_TYPE = "PROFILE_RUNTIME_RESULT_V1"


class RuntimeExecutionBlocked(RuntimeError):
    def __init__(self, code: str, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


class RuntimeAdapter(Protocol):
    adapter_id: str
    is_test_double: bool

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        ...


class RuntimeAttestationVerifier(Protocol):
    verifier_id: str
    is_test_double: bool

    def verify(
        self,
        *,
        request: dict[str, Any],
        response: dict[str, Any],
        adapter: RuntimeAdapter,
    ) -> dict[str, Any]:
        ...


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_sha256(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def _validate_attested_at(value: Any) -> None:
    if not _nonempty_string(value):
        raise RuntimeExecutionBlocked("RUNTIME_ATTESTATION_ATTESTED_AT_MISSING")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise RuntimeExecutionBlocked("RUNTIME_ATTESTATION_ATTESTED_AT_INVALID") from exc
    if parsed.tzinfo is None:
        raise RuntimeExecutionBlocked("RUNTIME_ATTESTATION_ATTESTED_AT_TIMEZONE_MISSING")


def _validate_sources(
    profile_sources: list[dict[str, str]],
) -> tuple[list[dict[str, str]], list[str], str]:
    if not isinstance(profile_sources, list) or not profile_sources:
        raise RuntimeExecutionBlocked("PROFILE_SOURCES_MISSING")

    normalized: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in profile_sources:
        if not isinstance(item, dict):
            raise RuntimeExecutionBlocked("PROFILE_SOURCE_INVALID")
        ref = item.get("ref")
        content = item.get("content")
        if not _nonempty_string(ref) or not isinstance(content, str) or not content:
            raise RuntimeExecutionBlocked("PROFILE_SOURCE_INVALID")
        if ref in seen:
            raise RuntimeExecutionBlocked("PROFILE_SOURCE_DUPLICATE", ref)
        seen.add(ref)
        normalized.append({"ref": ref, "content": content})

    normalized.sort(key=lambda item: item["ref"])
    source_manifest = [
        {"ref": item["ref"], "content_sha256": sha256_text(item["content"])}
        for item in normalized
    ]
    source_refs = [item["ref"] for item in normalized]
    source_sha256 = canonical_json_sha256(source_manifest)
    return normalized, source_refs, source_sha256


def build_runtime_request(
    *,
    execution_id: str,
    profile_code: str,
    profile_slug: str,
    profile_sources: list[dict[str, str]],
    input_literal: str,
) -> dict[str, Any]:
    for name, value in (
        ("execution_id", execution_id),
        ("profile_code", profile_code),
        ("profile_slug", profile_slug),
    ):
        if not _nonempty_string(value):
            raise RuntimeExecutionBlocked(f"{name.upper()}_MISSING")
    if not isinstance(input_literal, str) or not input_literal.strip():
        raise RuntimeExecutionBlocked("INPUT_LITERAL_MISSING")

    normalized_sources, source_refs, source_sha256 = _validate_sources(profile_sources)
    request = {
        "request_type": REQUEST_TYPE,
        "operation_code": OPERATION_CODE,
        "execution_id": execution_id,
        "profile_code": profile_code,
        "profile_slug": profile_slug,
        "profile_sources": normalized_sources,
        "profile_source_refs": source_refs,
        "profile_source_sha256": source_sha256,
        "input_literal": input_literal,
        "input_sha256": sha256_text(input_literal),
    }
    request["request_sha256"] = canonical_json_sha256(request)
    return request


def _validate_adapter(adapter: RuntimeAdapter, *, allow_test_doubles: bool) -> None:
    if not _nonempty_string(getattr(adapter, "adapter_id", None)):
        raise RuntimeExecutionBlocked("RUNTIME_ADAPTER_ID_MISSING")
    if not callable(getattr(adapter, "execute", None)):
        raise RuntimeExecutionBlocked("RUNTIME_ADAPTER_EXECUTE_MISSING")
    if getattr(adapter, "is_test_double", False) and not allow_test_doubles:
        raise RuntimeExecutionBlocked("TEST_RUNTIME_ADAPTER_FORBIDDEN")


def _validate_verifier(
    verifier: RuntimeAttestationVerifier,
    *,
    allow_test_doubles: bool,
) -> None:
    if not _nonempty_string(getattr(verifier, "verifier_id", None)):
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFIER_ID_MISSING")
    if not callable(getattr(verifier, "verify", None)):
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFIER_METHOD_MISSING")
    if getattr(verifier, "is_test_double", False) and not allow_test_doubles:
        raise RuntimeExecutionBlocked("TEST_ATTESTATION_VERIFIER_FORBIDDEN")


def _validate_response(
    *,
    request: dict[str, Any],
    response: Any,
    adapter: RuntimeAdapter,
) -> tuple[Any, dict[str, Any]]:
    if not isinstance(response, dict):
        raise RuntimeExecutionBlocked("RUNTIME_RESPONSE_NOT_OBJECT")
    if response.get("response_type") != RESPONSE_TYPE:
        raise RuntimeExecutionBlocked("RUNTIME_RESPONSE_TYPE_INVALID")

    raw_output = response.get("raw_output")
    if raw_output is None or raw_output == "" or raw_output == {} or raw_output == []:
        raise RuntimeExecutionBlocked("RUNTIME_RAW_OUTPUT_EMPTY")
    try:
        canonical_json_sha256(raw_output)
    except (TypeError, ValueError) as exc:
        raise RuntimeExecutionBlocked("RUNTIME_RAW_OUTPUT_NOT_JSON_SERIALIZABLE") from exc

    attestation = response.get("runtime_attestation")
    if not isinstance(attestation, dict):
        raise RuntimeExecutionBlocked("RUNTIME_ATTESTATION_MISSING")

    required = (
        "provider",
        "model_id",
        "run_id",
        "attested_at",
        "adapter_id",
        "request_sha256",
        "profile_source_sha256",
        "input_sha256",
        "operation_code",
        "profile_code",
        "profile_slug",
    )
    for key in required:
        if not _nonempty_string(attestation.get(key)):
            raise RuntimeExecutionBlocked(f"RUNTIME_ATTESTATION_{key.upper()}_MISSING")
    _validate_attested_at(attestation.get("attested_at"))

    expected = {
        "adapter_id": adapter.adapter_id,
        "request_sha256": request["request_sha256"],
        "profile_source_sha256": request["profile_source_sha256"],
        "input_sha256": request["input_sha256"],
        "operation_code": request["operation_code"],
        "profile_code": request["profile_code"],
        "profile_slug": request["profile_slug"],
    }
    for key, value in expected.items():
        if attestation.get(key) != value:
            raise RuntimeExecutionBlocked(f"RUNTIME_ATTESTATION_{key.upper()}_MISMATCH")

    return raw_output, dict(attestation)


def _validate_verification(
    *,
    request: dict[str, Any],
    response: dict[str, Any],
    verification: Any,
    verifier: RuntimeAttestationVerifier,
) -> dict[str, Any]:
    if not isinstance(verification, dict):
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFICATION_NOT_OBJECT")
    if verification.get("verified") is not True:
        raise RuntimeExecutionBlocked("ATTESTATION_NOT_VERIFIED")
    if verification.get("verifier_id") != verifier.verifier_id:
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFIER_ID_MISMATCH")
    if verification.get("request_sha256") != request["request_sha256"]:
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFICATION_REQUEST_MISMATCH")
    response_sha256 = canonical_json_sha256(response)
    if verification.get("response_sha256") != response_sha256:
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFICATION_RESPONSE_MISMATCH")
    evidence_sha256 = verification.get("evidence_sha256")
    if not _is_sha256(evidence_sha256):
        raise RuntimeExecutionBlocked("ATTESTATION_VERIFICATION_EVIDENCE_INVALID")
    return dict(verification)


def execute_profile_runtime(
    *,
    execution_id: str,
    profile_code: str,
    profile_slug: str,
    profile_sources: list[dict[str, str]],
    input_literal: str,
    adapter: RuntimeAdapter,
    attestation_verifier: RuntimeAttestationVerifier,
    allow_test_doubles: bool = False,
) -> dict[str, Any]:
    _validate_adapter(adapter, allow_test_doubles=allow_test_doubles)
    _validate_verifier(attestation_verifier, allow_test_doubles=allow_test_doubles)
    request = build_runtime_request(
        execution_id=execution_id,
        profile_code=profile_code,
        profile_slug=profile_slug,
        profile_sources=profile_sources,
        input_literal=input_literal,
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

    receipt = build_receipt(
        execution_id=execution_id,
        profile_code=profile_code,
        profile_slug=profile_slug,
        profile_source_refs=request["profile_source_refs"],
        profile_source_sha256=request["profile_source_sha256"],
        input_literal=input_literal,
        raw_output=raw_output,
        runtime_attestation=runtime_attestation,
    )

    return {
        "result_type": RESULT_TYPE,
        "request": request,
        "raw_output": raw_output,
        "runtime_attestation_verification": verification,
        "receipt": receipt,
    }
