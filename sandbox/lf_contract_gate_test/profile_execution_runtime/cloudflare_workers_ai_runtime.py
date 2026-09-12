#!/usr/bin/env python3
"""Cloudflare Workers AI RuntimeAdapter + read-only capability verifier for S26 sandbox.

The verifier independently re-checks token activity and model catalog availability, but
Cloudflare Workers AI does not expose historical inference-response retrieval here. The
attestation therefore has a deliberate evidence ceiling and MUST NOT be described as
provider historical response readback.
"""
from __future__ import annotations

import email.utils
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from datetime import timezone
from typing import Any, Callable

from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked
from validate_profile_execution import canonical_json_sha256

MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
ADAPTER_ID = "cloudflare-workers-ai-json-schema-v1"
VERIFIER_ID = "cloudflare-workers-ai-capability-hash-verifier-v1"
PROVIDER = "cloudflare_workers_ai"
EVIDENCE_CEILING = "PROVIDER_CAPABILITY_PLUS_HTTP_RESPONSE_ATTESTATION_NO_HISTORICAL_RESPONSE_RETRIEVAL"
DEFAULT_TIMEOUT_SECONDS = 120
DEFAULT_MAX_TOKENS = 512

PostFn = Callable[[str, dict[str, str], dict[str, Any], int], tuple[int, dict[str, str], dict[str, Any]]]
GetFn = Callable[[str, dict[str, str], int], tuple[int, dict[str, str], dict[str, Any]]]


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeExecutionBlocked(f"{name}_MISSING")
    return value


def _headers(token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "lf-s26-cloudflare-runtime/1.0",
    }


def _http_error_detail(exc: urllib.error.HTTPError) -> str:
    try:
        body = exc.read(4096).decode("utf-8", "replace")
    except Exception:
        body = ""
    return f"http={exc.code}" + (f" body={body[-800:].replace(chr(10), ' ')}" if body else "")


def _post_json(url: str, headers: dict[str, str], payload: dict[str, Any], timeout: int) -> tuple[int, dict[str, str], dict[str, Any]]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = int(response.status)
            response_headers = {str(k).lower(): str(v) for k, v in response.headers.items()}
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise RuntimeExecutionBlocked("CLOUDFLARE_HTTP_ERROR", _http_error_detail(exc)) from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeExecutionBlocked("CLOUDFLARE_TRANSPORT_ERROR", type(exc).__name__) from exc
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeExecutionBlocked("CLOUDFLARE_ENVELOPE_JSON_INVALID") from exc
    if not isinstance(parsed, dict):
        raise RuntimeExecutionBlocked("CLOUDFLARE_ENVELOPE_NOT_OBJECT")
    return status, response_headers, parsed


def _get_json(url: str, headers: dict[str, str], timeout: int) -> tuple[int, dict[str, str], dict[str, Any]]:
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = int(response.status)
            response_headers = {str(k).lower(): str(v) for k, v in response.headers.items()}
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise RuntimeExecutionBlocked("CLOUDFLARE_READONLY_HTTP_ERROR", _http_error_detail(exc)) from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeExecutionBlocked("CLOUDFLARE_READONLY_TRANSPORT_ERROR", type(exc).__name__) from exc
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeExecutionBlocked("CLOUDFLARE_READONLY_JSON_INVALID") from exc
    if not isinstance(parsed, dict):
        raise RuntimeExecutionBlocked("CLOUDFLARE_READONLY_NOT_OBJECT")
    return status, response_headers, parsed


def _provider_date_iso(headers: dict[str, str]) -> str:
    value = headers.get("date", "").strip()
    if not value:
        raise RuntimeExecutionBlocked("CLOUDFLARE_RESPONSE_DATE_MISSING")
    try:
        parsed = email.utils.parsedate_to_datetime(value)
    except (TypeError, ValueError) as exc:
        raise RuntimeExecutionBlocked("CLOUDFLARE_RESPONSE_DATE_INVALID") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _render_profile_instructions(request: dict[str, Any]) -> str:
    parts = [
        "Execute the governed repository profile from the canonical sources below.",
        "Apply them to the literal input. Return only the direct profile output.",
        "Do not summarize the sources, invent authority, or discuss this runtime wrapper.",
        "",
    ]
    for source in request["profile_sources"]:
        parts.extend([
            f"--- BEGIN CANONICAL PROFILE SOURCE: {source['ref']} ---",
            source["content"],
            f"--- END CANONICAL PROFILE SOURCE: {source['ref']} ---",
            "",
        ])
    return "\n".join(parts).rstrip()


class CloudflareWorkersAIAdapter:
    adapter_id = ADAPTER_ID

    def __init__(
        self,
        *,
        generation_schema: dict[str, Any],
        account_id: str | None = None,
        api_token: str | None = None,
        timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
        max_tokens: int = DEFAULT_MAX_TOKENS,
        post_json: PostFn | None = None,
    ) -> None:
        if not isinstance(generation_schema, dict) or not generation_schema:
            raise RuntimeExecutionBlocked("CLOUDFLARE_GENERATION_SCHEMA_MISSING")
        if timeout_seconds <= 0 or max_tokens < 64 or max_tokens > 4096:
            raise RuntimeExecutionBlocked("CLOUDFLARE_RUNTIME_LIMIT_INVALID")
        self.generation_schema = generation_schema
        self.account_id = account_id
        self.api_token = api_token
        self.timeout_seconds = timeout_seconds
        self.max_tokens = max_tokens
        self._post = post_json or _post_json
        self.is_test_double = post_json is not None

    def _account(self) -> str:
        return (self.account_id or _required_env("CLOUDFLARE_ACCOUNT_ID")).strip()

    def _token(self) -> str:
        return (self.api_token or _required_env("CLOUDFLARE_AI_CANARY_TOKEN")).strip()

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        account = self._account()
        payload = {
            "messages": [
                {"role": "system", "content": _render_profile_instructions(request)},
                {"role": "user", "content": request["input_literal"]},
            ],
            "response_format": {"type": "json_schema", "json_schema": self.generation_schema},
            "stream": False,
            "temperature": 0,
            "top_p": 1,
            "seed": 42,
            "max_tokens": self.max_tokens,
        }
        url = f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}"
        status, headers, envelope = self._post(url, _headers(self._token()), payload, self.timeout_seconds)
        if status != 200:
            raise RuntimeExecutionBlocked("CLOUDFLARE_HTTP_STATUS_INVALID", str(status))
        if envelope.get("success") is not True:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROVIDER_SUCCESS_FALSE")
        root = envelope.get("result")
        if not isinstance(root, dict):
            raise RuntimeExecutionBlocked("CLOUDFLARE_RESULT_INVALID")
        response_value = root.get("response")
        if isinstance(response_value, dict) and response_value:
            raw_output: Any = response_value
        elif isinstance(response_value, str) and response_value.strip():
            raw_output = response_value.strip()
        else:
            raise RuntimeExecutionBlocked("CLOUDFLARE_RESPONSE_EMPTY")
        cf_ray = headers.get("cf-ray", "").strip()
        if not cf_ray:
            raise RuntimeExecutionBlocked("CLOUDFLARE_CF_RAY_MISSING")
        provider_date = _provider_date_iso(headers)
        usage = root.get("usage") if isinstance(root.get("usage"), dict) else {}
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": raw_output,
            "runtime_attestation": {
                "provider": PROVIDER,
                "model_id": MODEL,
                "run_id": cf_ray,
                "attested_at": provider_date,
                "adapter_id": self.adapter_id,
                "request_sha256": request["request_sha256"],
                "profile_source_sha256": request["profile_source_sha256"],
                "input_sha256": request["input_sha256"],
                "operation_code": request["operation_code"],
                "profile_code": request["profile_code"],
                "profile_slug": request["profile_slug"],
                "provider_http_status": str(status),
                "provider_cf_ray": cf_ray,
                "provider_date": provider_date,
                "provider_envelope_sha256": canonical_json_sha256(envelope),
                "provider_raw_output_sha256": canonical_json_sha256(raw_output),
                "generation_schema_sha256": canonical_json_sha256(self.generation_schema),
                "usage": usage,
                "temperature": "0",
                "top_p": "1",
                "seed": "42",
                "max_tokens": str(self.max_tokens),
                "retries": "0",
                "evidence_ceiling": EVIDENCE_CEILING,
            },
        }


class CloudflareWorkersAICapabilityVerifier:
    verifier_id = VERIFIER_ID

    def __init__(
        self,
        *,
        account_id: str | None = None,
        api_token: str | None = None,
        timeout_seconds: int = 30,
        get_json: GetFn | None = None,
    ) -> None:
        if timeout_seconds <= 0:
            raise RuntimeExecutionBlocked("CLOUDFLARE_VERIFY_TIMEOUT_INVALID")
        self.account_id = account_id
        self.api_token = api_token
        self.timeout_seconds = timeout_seconds
        self._get = get_json or _get_json
        self.is_test_double = get_json is not None

    def _account(self) -> str:
        return (self.account_id or _required_env("CLOUDFLARE_ACCOUNT_ID")).strip()

    def _token(self) -> str:
        return (self.api_token or _required_env("CLOUDFLARE_API_TOKEN")).strip()

    def verify(self, *, request: dict[str, Any], response: dict[str, Any], adapter: Any) -> dict[str, Any]:
        if getattr(adapter, "adapter_id", None) != ADAPTER_ID:
            raise RuntimeExecutionBlocked("CLOUDFLARE_VERIFIER_ADAPTER_MISMATCH")
        att = response.get("runtime_attestation")
        if not isinstance(att, dict) or att.get("provider") != PROVIDER:
            raise RuntimeExecutionBlocked("CLOUDFLARE_ATTESTATION_PROVIDER_INVALID")
        if att.get("evidence_ceiling") != EVIDENCE_CEILING:
            raise RuntimeExecutionBlocked("CLOUDFLARE_EVIDENCE_CEILING_MISSING")
        if att.get("provider_raw_output_sha256") != canonical_json_sha256(response.get("raw_output")):
            raise RuntimeExecutionBlocked("CLOUDFLARE_ATTESTED_RAW_OUTPUT_HASH_MISMATCH")
        if att.get("generation_schema_sha256") != canonical_json_sha256(adapter.generation_schema):
            raise RuntimeExecutionBlocked("CLOUDFLARE_ATTESTED_SCHEMA_HASH_MISMATCH")
        if att.get("provider_cf_ray") != att.get("run_id") or not str(att.get("provider_cf_ray") or "").strip():
            raise RuntimeExecutionBlocked("CLOUDFLARE_ATTESTED_CF_RAY_INVALID")

        token = self._token()
        token_status, _token_headers, token_json = self._get(
            "https://api.cloudflare.com/client/v4/user/tokens/verify",
            _headers(token),
            self.timeout_seconds,
        )
        if token_status != 200 or token_json.get("success") is not True:
            raise RuntimeExecutionBlocked("CLOUDFLARE_VERIFIER_TOKEN_READBACK_FAILED")
        token_result = token_json.get("result")
        if not isinstance(token_result, dict) or str(token_result.get("status") or "").lower() != "active":
            raise RuntimeExecutionBlocked("CLOUDFLARE_VERIFIER_TOKEN_NOT_ACTIVE")

        search = urllib.parse.urlencode({
            "search": "llama-3.3-70b-instruct-fp8-fast",
            "hide_experimental": "true",
            "include_deprecated": "false",
        })
        model_url = f"https://api.cloudflare.com/client/v4/accounts/{self._account()}/ai/models/search?{search}"
        model_status, _model_headers, model_json = self._get(model_url, _headers(token), self.timeout_seconds)
        models = model_json.get("result") if isinstance(model_json, dict) else None
        if model_status != 200 or model_json.get("success") is not True or not isinstance(models, list) or not models:
            raise RuntimeExecutionBlocked("CLOUDFLARE_VERIFIER_MODEL_CATALOG_FAILED")
        model_catalog_sha = canonical_json_sha256(models)

        response_sha = canonical_json_sha256(response)
        evidence = {
            "provider": PROVIDER,
            "model_id": MODEL,
            "token_status": "active",
            "model_catalog_sha256": model_catalog_sha,
            "provider_cf_ray": att["provider_cf_ray"],
            "provider_date": att["provider_date"],
            "provider_http_status": att["provider_http_status"],
            "provider_envelope_sha256": att["provider_envelope_sha256"],
            "provider_raw_output_sha256": att["provider_raw_output_sha256"],
            "generation_schema_sha256": att["generation_schema_sha256"],
            "evidence_ceiling": EVIDENCE_CEILING,
            "historical_response_retrieval": False,
        }
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": canonical_json_sha256(evidence),
            "evidence_ceiling": EVIDENCE_CEILING,
            "historical_response_retrieval": False,
        }
