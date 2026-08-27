#!/usr/bin/env python3
"""OpenAI Responses API adapter + independent provider readback verifier."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked
from validate_profile_execution import canonical_json_sha256

OPENAI_API_BASE = "https://api.openai.com/v1"
DEFAULT_MODEL = "gpt-5.6-terra"
DEFAULT_REASONING_EFFORT = "medium"
ADAPTER_ID = "openai-responses-v1"
VERIFIER_ID = "openai-responses-readback-v1"
ALLOWED_REASONING_EFFORTS = {"none", "low", "medium", "high", "xhigh", "max"}


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _utc_iso_from_unix(value: Any) -> str:
    if not isinstance(value, (int, float)):
        raise RuntimeExecutionBlocked("OPENAI_CREATED_AT_INVALID")
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def _load_env_key(primary: str, *, fallback: str | None = None) -> str:
    value = os.getenv(primary, "").strip()
    if not value and fallback:
        value = os.getenv(fallback, "").strip()
    if not value:
        raise RuntimeExecutionBlocked(f"{primary}_MISSING")
    return value


def _headers(api_key: str) -> dict[str, str]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "lf-profile-runtime/1.0",
    }
    organization = os.getenv("OPENAI_ORGANIZATION", "").strip()
    project = os.getenv("OPENAI_PROJECT", "").strip()
    if organization:
        headers["OpenAI-Organization"] = organization
    if project:
        headers["OpenAI-Project"] = project
    return headers


def _provider_error_detail(exc: urllib.error.HTTPError) -> str:
    provider_code = ""
    try:
        body = exc.read(8192).decode("utf-8", "replace")
        parsed = json.loads(body)
        error = parsed.get("error") if isinstance(parsed, dict) else None
        if isinstance(error, dict):
            provider_code = str(error.get("code") or error.get("type") or "").strip()
    except Exception:
        provider_code = ""
    return f"http={exc.code}" + (f" provider_code={provider_code}" if provider_code else "")


def _request_json(
    *,
    method: str,
    path: str,
    api_key: str,
    payload: dict[str, Any] | None,
    timeout_seconds: int,
) -> dict[str, Any]:
    url = f"{OPENAI_API_BASE}{path}"
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers=_headers(api_key),
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeExecutionBlocked("OPENAI_HTTP_ERROR", _provider_error_detail(exc)) from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeExecutionBlocked("OPENAI_TRANSPORT_ERROR", type(exc).__name__) from exc

    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeExecutionBlocked("OPENAI_RESPONSE_JSON_INVALID") from exc
    if not isinstance(parsed, dict):
        raise RuntimeExecutionBlocked("OPENAI_RESPONSE_NOT_OBJECT")
    return parsed


def _render_profile_instructions(request: dict[str, Any]) -> str:
    parts = [
        "Execute the governed repository profile defined by the canonical sources below.",
        "Treat those sources as the governing profile instructions for this run.",
        "Apply them to the user's literal input exactly as provided.",
        "Return the profile's direct output only. Do not summarize the sources, reconstruct an expected answer, or discuss the runtime wrapper.",
        "",
    ]
    for source in request["profile_sources"]:
        ref = source["ref"]
        parts.extend(
            [
                f"--- BEGIN CANONICAL PROFILE SOURCE: {ref} ---",
                source["content"],
                f"--- END CANONICAL PROFILE SOURCE: {ref} ---",
                "",
            ]
        )
    return "\n".join(parts).rstrip()


def _metadata(request: dict[str, Any]) -> dict[str, str]:
    keys = (
        "execution_id",
        "operation_code",
        "profile_code",
        "profile_slug",
        "profile_source_sha256",
        "input_sha256",
        "request_sha256",
    )
    return {key: str(request[key]) for key in keys}


def _validate_reasoning_effort(value: str) -> str:
    normalized = value.strip().lower()
    if normalized not in ALLOWED_REASONING_EFFORTS:
        raise RuntimeExecutionBlocked("OPENAI_REASONING_EFFORT_INVALID", normalized)
    return normalized


class OpenAIResponsesAdapter:
    adapter_id = ADAPTER_ID
    is_test_double = False

    def __init__(
        self,
        *,
        api_key: str | None = None,
        model: str | None = None,
        reasoning_effort: str | None = None,
        timeout_seconds: int = 120,
        max_output_tokens: int = 16000,
    ) -> None:
        self._api_key = api_key
        self.model = (model or os.getenv("OPENAI_PROFILE_RUNTIME_MODEL", DEFAULT_MODEL)).strip()
        if not self.model:
            raise RuntimeExecutionBlocked("OPENAI_MODEL_MISSING")
        effort = reasoning_effort or os.getenv(
            "OPENAI_PROFILE_RUNTIME_REASONING_EFFORT", DEFAULT_REASONING_EFFORT
        )
        self.reasoning_effort = _validate_reasoning_effort(effort)
        if timeout_seconds <= 0:
            raise RuntimeExecutionBlocked("OPENAI_TIMEOUT_INVALID")
        if max_output_tokens < 256 or max_output_tokens > 128000:
            raise RuntimeExecutionBlocked("OPENAI_MAX_OUTPUT_TOKENS_INVALID")
        self.timeout_seconds = timeout_seconds
        self.max_output_tokens = max_output_tokens

    def _resolved_key(self) -> str:
        if self._api_key is not None:
            value = self._api_key.strip()
            if not value:
                raise RuntimeExecutionBlocked("OPENAI_API_KEY_MISSING")
            return value
        return _load_env_key("OPENAI_API_KEY")

    def _create_response(self, payload: dict[str, Any]) -> dict[str, Any]:
        return _request_json(
            method="POST",
            path="/responses",
            api_key=self._resolved_key(),
            payload=payload,
            timeout_seconds=self.timeout_seconds,
        )

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        payload = {
            "model": self.model,
            "instructions": _render_profile_instructions(request),
            "input": request["input_literal"],
            "store": True,
            "metadata": _metadata(request),
            "reasoning": {"effort": self.reasoning_effort},
            "max_output_tokens": self.max_output_tokens,
        }
        provider_response = self._create_response(payload)

        if provider_response.get("object") != "response":
            raise RuntimeExecutionBlocked("OPENAI_RESPONSE_OBJECT_INVALID")
        if provider_response.get("status") != "completed":
            status = str(provider_response.get("status") or "missing")
            raise RuntimeExecutionBlocked("OPENAI_RESPONSE_NOT_COMPLETED", status)

        response_id = provider_response.get("id")
        model_id = provider_response.get("model")
        output = provider_response.get("output")
        if not _nonempty(response_id):
            raise RuntimeExecutionBlocked("OPENAI_RESPONSE_ID_MISSING")
        if not _nonempty(model_id):
            raise RuntimeExecutionBlocked("OPENAI_RESPONSE_MODEL_MISSING")
        if not isinstance(output, list) or not output:
            raise RuntimeExecutionBlocked("OPENAI_RESPONSE_OUTPUT_EMPTY")

        attested_at = _utc_iso_from_unix(provider_response.get("created_at"))
        output_sha256 = canonical_json_sha256(output)
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": output,
            "runtime_attestation": {
                "provider": "openai",
                "model_id": model_id,
                "run_id": response_id,
                "attested_at": attested_at,
                "adapter_id": self.adapter_id,
                "request_sha256": request["request_sha256"],
                "profile_source_sha256": request["profile_source_sha256"],
                "input_sha256": request["input_sha256"],
                "operation_code": request["operation_code"],
                "profile_code": request["profile_code"],
                "profile_slug": request["profile_slug"],
                "provider_response_id": response_id,
                "provider_created_at_unix": provider_response.get("created_at"),
                "provider_output_sha256": output_sha256,
            },
        }


class OpenAIResponsesReadbackVerifier:
    verifier_id = VERIFIER_ID
    is_test_double = False

    def __init__(
        self,
        *,
        api_key: str | None = None,
        timeout_seconds: int = 120,
    ) -> None:
        self._api_key = api_key
        if timeout_seconds <= 0:
            raise RuntimeExecutionBlocked("OPENAI_VERIFY_TIMEOUT_INVALID")
        self.timeout_seconds = timeout_seconds

    def _resolved_key(self) -> str:
        if self._api_key is not None:
            value = self._api_key.strip()
            if not value:
                raise RuntimeExecutionBlocked("OPENAI_PROFILE_RUNTIME_VERIFY_API_KEY_MISSING")
            return value
        return _load_env_key(
            "OPENAI_PROFILE_RUNTIME_VERIFY_API_KEY",
            fallback="OPENAI_API_KEY",
        )

    def _retrieve_response(self, response_id: str) -> dict[str, Any]:
        return _request_json(
            method="GET",
            path=f"/responses/{response_id}",
            api_key=self._resolved_key(),
            payload=None,
            timeout_seconds=self.timeout_seconds,
        )

    def verify(
        self,
        *,
        request: dict[str, Any],
        response: dict[str, Any],
        adapter: Any,
    ) -> dict[str, Any]:
        if getattr(adapter, "adapter_id", None) != ADAPTER_ID:
            raise RuntimeExecutionBlocked("OPENAI_VERIFIER_ADAPTER_MISMATCH")
        attestation = response.get("runtime_attestation")
        if not isinstance(attestation, dict) or attestation.get("provider") != "openai":
            raise RuntimeExecutionBlocked("OPENAI_ATTESTATION_PROVIDER_INVALID")

        response_id = attestation.get("run_id")
        if not _nonempty(response_id):
            raise RuntimeExecutionBlocked("OPENAI_READBACK_RESPONSE_ID_MISSING")
        readback = self._retrieve_response(response_id)

        if readback.get("object") != "response":
            raise RuntimeExecutionBlocked("OPENAI_READBACK_OBJECT_INVALID")
        if readback.get("id") != response_id:
            raise RuntimeExecutionBlocked("OPENAI_READBACK_ID_MISMATCH")
        if readback.get("status") != "completed":
            raise RuntimeExecutionBlocked(
                "OPENAI_READBACK_NOT_COMPLETED",
                str(readback.get("status") or "missing"),
            )
        if readback.get("model") != attestation.get("model_id"):
            raise RuntimeExecutionBlocked("OPENAI_READBACK_MODEL_MISMATCH")

        expected_metadata = _metadata(request)
        metadata = readback.get("metadata")
        if not isinstance(metadata, dict):
            raise RuntimeExecutionBlocked("OPENAI_READBACK_METADATA_MISSING")
        for key, value in expected_metadata.items():
            if metadata.get(key) != value:
                raise RuntimeExecutionBlocked("OPENAI_READBACK_METADATA_MISMATCH", key)

        readback_output = readback.get("output")
        if not isinstance(readback_output, list) or not readback_output:
            raise RuntimeExecutionBlocked("OPENAI_READBACK_OUTPUT_EMPTY")
        readback_output_sha = canonical_json_sha256(readback_output)
        wrapper_output_sha = canonical_json_sha256(response.get("raw_output"))
        if readback_output_sha != wrapper_output_sha:
            raise RuntimeExecutionBlocked("OPENAI_READBACK_OUTPUT_MISMATCH")
        if attestation.get("provider_output_sha256") != readback_output_sha:
            raise RuntimeExecutionBlocked("OPENAI_ATTESTED_OUTPUT_SHA256_MISMATCH")

        readback_attested_at = _utc_iso_from_unix(readback.get("created_at"))
        if readback_attested_at != attestation.get("attested_at"):
            raise RuntimeExecutionBlocked("OPENAI_READBACK_CREATED_AT_MISMATCH")

        evidence = {
            "provider": "openai",
            "provider_response_id": response_id,
            "provider_model": readback.get("model"),
            "provider_status": readback.get("status"),
            "provider_created_at": readback_attested_at,
            "provider_metadata": {key: metadata[key] for key in sorted(expected_metadata)},
            "provider_output_sha256": readback_output_sha,
            "provider_readback_sha256": canonical_json_sha256(readback),
        }
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": canonical_json_sha256(response),
            "evidence_sha256": canonical_json_sha256(evidence),
            "provider_readback_sha256": evidence["provider_readback_sha256"],
            "provider_response_id": response_id,
        }
