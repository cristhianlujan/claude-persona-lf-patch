#!/usr/bin/env python3
"""Cloudflare Workers AI adapter for canonical LF profile-runtime receipts.

S26 sandbox only. The adapter is strictly remote, zero-download and fail-closed:
no local model fallback, no paid fallback, and HTTP 403/429 terminate the run.
"""

from __future__ import annotations

import hashlib
import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked
from validate_profile_execution import canonical_json_sha256, sha256_text

ADAPTER_ID = "cloudflare-workers-ai-llama33-profile-v1"
VERIFIER_ID = "cloudflare-workers-ai-llama33-profile-readback-v1"
MODEL_ID = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
PROVIDER = "cloudflare_workers_ai"
TRANSPORT = "CLOUDFLARE_WORKERS_AI_REST"
PLAN = "WORKERS_FREE_ZERO_COST_ONLY"
MAX_OUTPUT_TOKENS = 512
TIMEOUT_SECONDS = 120


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeExecutionBlocked(f"{name}_MISSING")
    return value


def _runtime_preflight() -> dict[str, str]:
    observed = {
        "visibility": os.getenv("LF_REPOSITORY_VISIBILITY", "").strip(),
        "runner_label": os.getenv("LF_RUNNER_LABEL", "").strip(),
        "primary_runtime": os.getenv("LF_S26_PRIMARY_RUNTIME", "").strip(),
    }
    expected = {
        "visibility": "public",
        "runner_label": "ubuntu-latest",
        "primary_runtime": "CLOUDFLARE_WORKERS_AI",
    }
    for key, value in expected.items():
        if observed[key] != value:
            raise RuntimeExecutionBlocked(
                "CLOUDFLARE_PROFILE_RUNTIME_PRECONDITION_FAILED",
                f"{key}={observed[key]!r}",
            )
    return observed


def _render_system(request: dict[str, Any]) -> str:
    parts = [
        "Execute the governed repository profile defined by the canonical sources below.",
        "Use only the canonical profile sources, the literal input, and any Router-bound adapter capsules.",
        "Return exactly one naked JSON object satisfying the supplied schema. No Markdown fences or prose.",
        "Do not invent facts, canonical values, controls, business rules, tokens, dimensions, percentages, timing, or quantities absent from the supplied authority.",
        "This is S26 sandbox/read-only evidence only. Do not claim Golden, production, routing, deployment, or promotion authority.",
        "",
    ]
    for source in request["profile_sources"]:
        parts.extend([
            f"--- BEGIN CANONICAL PROFILE SOURCE: {source['ref']} ---",
            source["content"],
            f"--- END CANONICAL PROFILE SOURCE: {source['ref']} ---",
            "",
        ])
    for source in request.get("lf_adapter_sources") or []:
        parts.extend([
            f"--- BEGIN ROUTER-BOUND LF ADAPTER: {source['adapter_code']} | {source['ref']} ---",
            source["content"],
            f"--- END ROUTER-BOUND LF ADAPTER: {source['adapter_code']} ---",
            "",
        ])
    return "\n".join(parts).rstrip()


def _extract_response(envelope: Any) -> tuple[dict[str, Any], str, dict[str, Any]]:
    if not isinstance(envelope, dict) or envelope.get("success") is not True:
        raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_ENVELOPE_INVALID")
    result = envelope.get("result")
    if not isinstance(result, dict):
        raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_RESULT_INVALID")
    value = result.get("response")
    if isinstance(value, dict) and value:
        parsed = value
        raw_text = json.dumps(value, ensure_ascii=False, sort_keys=True)
    elif isinstance(value, str) and value.strip():
        raw_text = value.strip()
        if raw_text.startswith("```") or raw_text.endswith("```"):
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_FENCED_OUTPUT_FORBIDDEN")
        try:
            parsed = json.loads(raw_text)
        except json.JSONDecodeError as exc:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_OUTPUT_NOT_JSON") from exc
        if not isinstance(parsed, dict):
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_OUTPUT_NOT_OBJECT")
    else:
        choices = result.get("choices")
        if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_RESPONSE_EMPTY")
        message = choices[0].get("message")
        if not isinstance(message, dict):
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_MESSAGE_MISSING")
        content = message.get("content")
        if not isinstance(content, str) or not content.strip():
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_CONTENT_EMPTY")
        raw_text = content.strip()
        if raw_text.startswith("```") or raw_text.endswith("```"):
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_FENCED_OUTPUT_FORBIDDEN")
        try:
            parsed = json.loads(raw_text)
        except json.JSONDecodeError as exc:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_OUTPUT_NOT_JSON") from exc
        if not isinstance(parsed, dict):
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_OUTPUT_NOT_OBJECT")
    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
    return parsed, raw_text, usage


class CloudflareWorkersAIProfileAdapter:
    adapter_id = ADAPTER_ID
    is_test_double = False

    def __init__(
        self,
        *,
        generation_schema: dict[str, Any],
        timeout_seconds: int = TIMEOUT_SECONDS,
        max_output_tokens: int = MAX_OUTPUT_TOKENS,
    ) -> None:
        if not isinstance(generation_schema, dict) or not generation_schema:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_SCHEMA_INVALID")
        if timeout_seconds <= 0:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_TIMEOUT_INVALID")
        if not 64 <= max_output_tokens <= 2048:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_MAX_OUTPUT_TOKENS_INVALID")
        self.generation_schema = generation_schema
        self.timeout_seconds = timeout_seconds
        self.max_output_tokens = max_output_tokens
        self.last_request_payload: dict[str, Any] | None = None
        self.last_provider_envelope: dict[str, Any] | None = None
        self.last_provider_raw: bytes | None = None
        self.last_raw_text: str = ""
        self.last_usage: dict[str, Any] = {}
        self.last_cf_ray: str = ""

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        runner = _runtime_preflight()
        account = _required_env("CLOUDFLARE_ACCOUNT_ID")
        token = _required_env("CLOUDFLARE_AI_CANARY_TOKEN")
        payload = {
            "messages": [
                {"role": "system", "content": _render_system(request)},
                {"role": "user", "content": request["input_literal"]},
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": self.generation_schema,
            },
            "stream": False,
            "temperature": 0,
            "top_p": 1,
            "seed": 42,
            "max_tokens": self.max_output_tokens,
        }
        request_obj = urllib.request.Request(
            f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL_ID}",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request_obj, timeout=self.timeout_seconds) as response:
                raw = response.read()
                cf_ray = str(response.headers.get("cf-ray") or "").strip()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[-500:].replace("\n", " ")
            if exc.code in {403, 429}:
                raise RuntimeExecutionBlocked(
                    "CLOUDFLARE_PROFILE_ZERO_COST_LIMIT_FAIL_CLOSED",
                    f"status={exc.code} body={detail}",
                ) from exc
            raise RuntimeExecutionBlocked(
                "CLOUDFLARE_PROFILE_HTTP_ERROR",
                f"status={exc.code} body={detail}",
            ) from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise RuntimeExecutionBlocked(
                "CLOUDFLARE_PROFILE_TRANSPORT_FAILURE",
                type(exc).__name__,
            ) from exc
        try:
            envelope = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_RESPONSE_JSON_INVALID") from exc

        parsed, raw_text, usage = _extract_response(envelope)
        self.last_request_payload = payload
        self.last_provider_envelope = envelope
        self.last_provider_raw = raw
        self.last_raw_text = raw_text
        self.last_usage = usage
        self.last_cf_ray = cf_ray

        response_sha = _sha256_bytes(raw)
        run_id = f"cloudflare:{cf_ray or response_sha[:24]}"
        attestation = {
            "provider": PROVIDER,
            "model_id": MODEL_ID,
            "run_id": run_id,
            "attested_at": _utc_now(),
            "adapter_id": self.adapter_id,
            "request_sha256": request["request_sha256"],
            "profile_source_sha256": request["profile_source_sha256"],
            "input_sha256": request["input_sha256"],
            "operation_code": request["operation_code"],
            "profile_code": request["profile_code"],
            "profile_slug": request["profile_slug"],
            "transport": TRANSPORT,
            "cloudflare_plan": PLAN,
            "limit_behavior": "FAIL_CLOSED",
            "model_weights_downloaded": False,
            "local_model_fallback_used": False,
            "paid_fallback_used": False,
            "provider_response_sha256": response_sha,
            "provider_raw_output_sha256": sha256_text(raw_text),
            "github_run_id": os.getenv("GITHUB_RUN_ID", ""),
            "github_sha": os.getenv("GITHUB_SHA", ""),
            "runner_label": runner["runner_label"],
            "repository_visibility": runner["visibility"],
        }
        if cf_ray:
            attestation["cloudflare_ray_id"] = cf_ray
        if request.get("lf_adapter_source_sha256"):
            attestation["lf_adapter_source_sha256"] = request["lf_adapter_source_sha256"]
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": parsed,
            "runtime_attestation": attestation,
        }


class CloudflareWorkersAIProfileReadbackVerifier:
    verifier_id = VERIFIER_ID
    is_test_double = False

    def verify(
        self,
        *,
        request: dict[str, Any],
        response: dict[str, Any],
        adapter: CloudflareWorkersAIProfileAdapter,
    ) -> dict[str, Any]:
        _runtime_preflight()
        if adapter.adapter_id != ADAPTER_ID:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_VERIFIER_ADAPTER_MISMATCH")
        if adapter.last_request_payload is None or adapter.last_provider_envelope is None:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_VERIFIER_EVIDENCE_MISSING")
        if adapter.last_provider_raw is None or not adapter.last_raw_text:
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_VERIFIER_RAW_EVIDENCE_MISSING")
        attestation = response.get("runtime_attestation")
        if not isinstance(attestation, dict):
            raise RuntimeExecutionBlocked("CLOUDFLARE_PROFILE_VERIFIER_ATTESTATION_MISSING")
        expected = {
            "provider": PROVIDER,
            "model_id": MODEL_ID,
            "adapter_id": ADAPTER_ID,
            "transport": TRANSPORT,
            "cloudflare_plan": PLAN,
            "limit_behavior": "FAIL_CLOSED",
            "request_sha256": request["request_sha256"],
            "profile_source_sha256": request["profile_source_sha256"],
            "input_sha256": request["input_sha256"],
            "operation_code": request["operation_code"],
            "profile_code": request["profile_code"],
            "profile_slug": request["profile_slug"],
            "provider_response_sha256": _sha256_bytes(adapter.last_provider_raw),
            "provider_raw_output_sha256": sha256_text(adapter.last_raw_text),
        }
        for key, value in expected.items():
            if attestation.get(key) != value:
                raise RuntimeExecutionBlocked(
                    "CLOUDFLARE_PROFILE_VERIFIER_BINDING_MISMATCH", key
                )
        for key in (
            "model_weights_downloaded",
            "local_model_fallback_used",
            "paid_fallback_used",
        ):
            if attestation.get(key) is not False:
                raise RuntimeExecutionBlocked(
                    "CLOUDFLARE_PROFILE_VERIFIER_ZERO_COST_GUARD_MISMATCH", key
                )
        response_sha = canonical_json_sha256(response)
        evidence_payload = {
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "provider_response_sha256": attestation["provider_response_sha256"],
            "provider_raw_output_sha256": attestation["provider_raw_output_sha256"],
            "model_id": MODEL_ID,
            "transport": TRANSPORT,
            "cloudflare_plan": PLAN,
            "github_run_id": os.getenv("GITHUB_RUN_ID", ""),
            "github_sha": os.getenv("GITHUB_SHA", ""),
        }
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": canonical_json_sha256(evidence_payload),
        }
