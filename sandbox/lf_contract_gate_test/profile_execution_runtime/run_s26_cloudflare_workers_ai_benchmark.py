#!/usr/bin/env python3
"""S26 Cloudflare Workers AI bounded capability benchmark.

Uses the exact S26 focused UI task/prompt/schema/gates from a pinned authority
checkout. Produces sandbox evidence only; no Worker deployment, routing,
promotion, or production mutation is performed.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

MODEL = "@cf/qwen/qwen3-30b-a3b-fp8"
MAX_OUTPUT_TOKENS = 256
REQUEST_TIMEOUT_SECONDS = 120
EXPECTED_AUTHORITY_REF = "fcc2b0d57e36a31c26f38acc2510b193aac988c8"


def load_authority_module(authority_root: Path):
    path = (
        authority_root
        / "sandbox"
        / "lf_contract_gate_test"
        / "profile_execution_runtime"
        / "run_s26_zero_cost_primary_candidate.py"
    )
    if not path.is_file():
        raise RuntimeError(f"S26_AUTHORITY_MODULE_MISSING:{path}")
    spec = importlib.util.spec_from_file_location("s26_authority_benchmark", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("S26_AUTHORITY_MODULE_IMPORT_SPEC_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def extract_content(envelope: dict[str, Any]) -> tuple[str, str, dict[str, Any]]:
    choices = envelope.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise RuntimeError("CLOUDFLARE_CHOICES_MISSING")
    message = choices[0].get("message")
    if not isinstance(message, dict):
        raise RuntimeError("CLOUDFLARE_MESSAGE_MISSING")
    content = message.get("content")
    if isinstance(content, list):
        content = "".join(
            part.get("text", "") for part in content if isinstance(part, dict)
        )
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("CLOUDFLARE_CONTENT_EMPTY")
    usage = envelope.get("usage")
    return (
        content.strip(),
        str(choices[0].get("finish_reason") or ""),
        usage if isinstance(usage, dict) else {},
    )


def main() -> int:
    account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    api_token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    authority_root_raw = os.getenv("S26_AUTHORITY_ROOT", "").strip()
    authority_ref = os.getenv("S26_AUTHORITY_REF", "").strip()

    if not account_id or not api_token:
        print("BLOCK S26_CLOUDFLARE_REQUIRED_SECRET_MISSING")
        return 2
    if not authority_root_raw:
        print("BLOCK S26_AUTHORITY_ROOT_MISSING")
        return 2
    if authority_ref != EXPECTED_AUTHORITY_REF:
        print(
            "BLOCK S26_AUTHORITY_REF_MISMATCH "
            f"expected={EXPECTED_AUTHORITY_REF} observed={authority_ref}"
        )
        return 2

    authority_root = Path(authority_root_raw).resolve()
    authority = load_authority_module(authority_root)

    repository = authority.RepositoryBindings(authority.REPO_ROOT, max_prompt_chars=120_000)
    gates = authority.OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = authority.governed_generation_schema(
        schema_binding.payload,
        profile_slug="ui_architect",
        schema_mode="UI_FOCUSED_DECISION",
    )

    system_prompt = authority.build_system_prompt()
    task = authority.TASK
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": task},
        ],
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": MAX_OUTPUT_TOKENS,
        "response_format": {
            "type": "json_schema",
            "json_schema": generation_schema,
        },
    }

    url = (
        "https://api.cloudflare.com/client/v4/accounts/"
        + account_id
        + "/ai/v1/chat/completions"
    )
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )

    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            envelope = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[-1600:]
        print(
            "BLOCK S26_CLOUDFLARE_HTTP_ERROR "
            f"status={exc.code} detail={detail.replace(chr(10), ' ')}"
        )
        return 3
    except Exception as exc:
        print(f"BLOCK S26_CLOUDFLARE_TRANSPORT type={type(exc).__name__}")
        return 3

    elapsed_s = round(time.monotonic() - started, 3)
    try:
        raw, finish_reason, usage = extract_content(envelope)
    except RuntimeError as exc:
        print("BLOCK S26_" + str(exc))
        return 4

    contract_gate, parsed = gates.contract(
        profile_slug="ui_architect",
        raw_output=raw,
        schema=schema_binding,
    )
    semantic_gate = gates.semantic_utility(
        profile_slug="ui_architect",
        payload=parsed,
        contract_gate=contract_gate,
    )

    result = {
        "scope": "S26_CLOUDFLARE_SANDBOX_CAPABILITY_ONLY_NOT_PROMOTION",
        "provider": "cloudflare_workers_ai_openai_compatible_rest",
        "model": MODEL,
        "authority_ref": authority_ref,
        "authority_source_hashes": authority.source_hashes(),
        "prompt_policy": "S26_PINNED_FOCUSED_UI_SINGLE_SHOT_CF_V1",
        "generation_schema_policy": generation_policy,
        "max_output_tokens": MAX_OUTPUT_TOKENS,
        "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "inference_requests": 1,
        "retries": 0,
        "elapsed_s": elapsed_s,
        "finish_reason": finish_reason,
        "usage": usage,
        "raw_output_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
        "raw_output": raw,
        "output": parsed if isinstance(parsed, dict) else None,
        "contract_gate": contract_gate,
        "semantic_gate": semantic_gate,
        "production_mutation": False,
        "worker_deployed": False,
        "routing_changed": False,
        "promotion_authorized": False,
        "paid_fallback_used": False,
    }

    out_path = Path(
        os.getenv("S26_CLOUDFLARE_RESULT_PATH", "s26-cloudflare-benchmark-result.json")
    )
    out_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "S26_CLOUDFLARE_BENCHMARK="
        + json.dumps(result, ensure_ascii=False, sort_keys=True),
        flush=True,
    )

    if contract_gate.get("status") == "PASS" and semantic_gate.get("status") == "PASS":
        print("S26_CLOUDFLARE_CAPABILITY_PASS_NO_PROMOTION", flush=True)
    else:
        print("S26_CLOUDFLARE_CAPABILITY_FAIL_CLOSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
