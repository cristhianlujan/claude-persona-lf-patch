#!/usr/bin/env python3
"""Offline regressions for the Cloudflare canonical RuntimeAdapter boundary."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

AUTHORITY_ROOT = Path(os.environ.get("S26_AUTHORITY_ROOT", ".")).resolve()
AUTHORITY_RUNTIME = AUTHORITY_ROOT / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
if not AUTHORITY_RUNTIME.is_dir():
    raise SystemExit("BLOCK_TEST_AUTHORITY_RUNTIME_MISSING")
sys.path.insert(0, str(AUTHORITY_RUNTIME))

from profile_runtime_runner import RuntimeExecutionBlocked, build_runtime_request, execute_profile_runtime  # noqa: E402
from semantic_obligation_manifest import validate_obligation_manifest  # noqa: E402
from validate_profile_execution import canonical_json_sha256, sha256_text  # noqa: E402

from cloudflare_workers_ai_runtime import (  # noqa: E402
    EVIDENCE_CEILING,
    MODEL,
    CloudflareWorkersAIAdapter,
    CloudflareWorkersAICapabilityVerifier,
)

PROFILE_CODE = "PERFIL-UI-ARCHITECT"
PROFILE_SLUG = "ui_architect"
EXECUTION_ID = "EXEC-S26-CF-ADAPTER-TEST-001"
INPUT = "Return the governed focused UI decision."
PROFILE_SOURCES = [
    {"ref": "profiles/ui_architect/SKILL.md", "content": "# UI Architect\nReturn one governed JSON object."},
    {"ref": "profiles/ui_architect/contracts/existing_screen_review.md", "content": "# Existing review\nPreserve governed facts."},
]
GENERATION_SCHEMA = {
    "type": "object",
    "properties": {"decision": {"type": "string"}},
    "required": ["decision"],
    "additionalProperties": False,
}


def manifest() -> dict:
    preliminary = build_runtime_request(
        execution_id=EXECUTION_ID,
        profile_code=PROFILE_CODE,
        profile_slug=PROFILE_SLUG,
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
    )
    return validate_obligation_manifest({
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": EXECUTION_ID,
        "profile_code": PROFILE_CODE,
        "profile_source_sha256": preliminary["profile_source_sha256"],
        "input_sha256": preliminary["input_sha256"],
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT",
                "authority_type": "PROFILE_CONTRACT",
                "source_ref": "profile-sources:/aggregate",
                "source_sha256": preliminary["profile_source_sha256"],
                "required_obligation_ids": ["S26-CF-TEST-OBLIGATION"],
            },
            {
                "authority_id": "EXECUTION-INPUT",
                "authority_type": "EXECUTION_INPUT",
                "source_ref": "input:/literal",
                "source_sha256": preliminary["input_sha256"],
                "required_obligation_ids": ["S26-CF-TEST-OBLIGATION"],
            },
        ],
        "obligations": [
            {
                "obligation_id": "S26-CF-TEST-OBLIGATION",
                "rule": "The decision must be governed by the supplied profile and literal input.",
                "check_type": "SEMANTIC_RELATION",
                "evidence_pointer": "$",
                "authority_ids": ["PROFILE-CONTRACT", "EXECUTION-INPUT"],
                "question": "Does the decision comply with the governed input?",
            }
        ],
    })


def fake_post(url, headers, payload, timeout):
    assert MODEL in url
    assert headers.get("Authorization") == "Bearer test-ai-token"
    assert payload["temperature"] == 0
    assert payload["seed"] == 42
    assert payload["response_format"]["type"] == "json_schema"
    return (
        200,
        {"cf-ray": "test-ray-001-IAD", "date": "Mon, 07 Sep 2026 23:00:00 GMT"},
        {
            "success": True,
            "errors": [],
            "messages": [],
            "result": {
                "response": {"decision": "preserve governed input"},
                "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15, "neurons": 1.25},
            },
        },
    )


def fake_get(url, headers, timeout):
    assert headers.get("Authorization") == "Bearer test-read-token"
    if url.endswith("/user/tokens/verify"):
        return 200, {"date": "Mon, 07 Sep 2026 23:00:01 GMT"}, {"success": True, "result": {"status": "active"}}
    assert "/ai/models/search?" in url
    return 200, {}, {"success": True, "result": [{"name": MODEL}]}


def assert_block(code: str, fn) -> None:
    try:
        fn()
    except RuntimeExecutionBlocked as exc:
        if exc.code != code:
            raise AssertionError(f"expected {code}, got {exc.code}: {exc}") from exc
        print(f"PASS {code}")
        return
    raise AssertionError(f"expected block {code}")


def main() -> int:
    m = manifest()
    adapter = CloudflareWorkersAIAdapter(
        generation_schema=GENERATION_SCHEMA,
        account_id="test-account",
        api_token="test-ai-token",
        post_json=fake_post,
    )
    verifier = CloudflareWorkersAICapabilityVerifier(
        account_id="test-account",
        api_token="test-read-token",
        get_json=fake_get,
    )
    result = execute_profile_runtime(
        execution_id=EXECUTION_ID,
        profile_code=PROFILE_CODE,
        profile_slug=PROFILE_SLUG,
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
        obligation_manifest=m,
        adapter=adapter,
        attestation_verifier=verifier,
        allow_test_doubles=True,
    )
    request = result["request"]
    receipt = result["receipt"]
    assert request["obligation_manifest_sha256"]
    assert receipt["obligation_manifest_sha256"] == request["obligation_manifest_sha256"]
    assert receipt["raw_output_sha256"] == canonical_json_sha256(result["raw_output"])
    verification = result["runtime_attestation_verification"]
    assert verification["verified"] is True
    assert verification["evidence_ceiling"] == EVIDENCE_CEILING
    assert verification["historical_response_retrieval"] is False
    print("PASS CANONICAL_REQUEST_RECEIPT_MANIFEST_BINDING")

    base_request = build_runtime_request(
        execution_id=EXECUTION_ID,
        profile_code=PROFILE_CODE,
        profile_slug=PROFILE_SLUG,
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
        obligation_manifest=m,
    )
    response = adapter.execute(base_request)
    tampered = json.loads(json.dumps(response))
    tampered["raw_output"]["decision"] = "tampered"
    assert_block(
        "CLOUDFLARE_ATTESTED_RAW_OUTPUT_HASH_MISMATCH",
        lambda: verifier.verify(request=base_request, response=tampered, adapter=adapter),
    )

    def empty_post(url, headers, payload, timeout):
        return 200, {"cf-ray": "test-ray-empty", "date": "Mon, 07 Sep 2026 23:00:00 GMT"}, {"success": True, "result": {"response": None}}

    empty_adapter = CloudflareWorkersAIAdapter(
        generation_schema=GENERATION_SCHEMA,
        account_id="test-account",
        api_token="test-ai-token",
        post_json=empty_post,
    )
    assert_block("CLOUDFLARE_RESPONSE_EMPTY", lambda: empty_adapter.execute(base_request))

    def transport_post(url, headers, payload, timeout):
        raise RuntimeExecutionBlocked("CLOUDFLARE_TRANSPORT_ERROR", "synthetic")

    transport_adapter = CloudflareWorkersAIAdapter(
        generation_schema=GENERATION_SCHEMA,
        account_id="test-account",
        api_token="test-ai-token",
        post_json=transport_post,
    )
    assert_block("CLOUDFLARE_TRANSPORT_ERROR", lambda: transport_adapter.execute(base_request))

    assert sha256_text(INPUT) == base_request["input_sha256"]
    print("S26_CLOUDFLARE_CANONICAL_ADAPTER_TESTS_PASS 4/4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
