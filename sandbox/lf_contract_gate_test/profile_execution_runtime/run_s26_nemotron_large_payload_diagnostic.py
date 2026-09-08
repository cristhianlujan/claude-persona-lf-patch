#!/usr/bin/env python3
"""One-call S26 Nemotron transport diagnostic for a fresh large-payload class.

This probe is diagnostic-only. It does not reuse S26 canonical/holdout evidence,
does not persist model or reasoning text, and cannot change semantic authority,
routing, Golden or production state.
"""
from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

MODEL = "@cf/nvidia/nemotron-3-120b-a12b"
MAX_COMPLETION_TOKENS = 256
TIMEOUT_SECONDS = 120
SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "verdict": {"type": "string", "enum": ["COMPLIES", "CONTRADICTS", "UNCERTAIN"]},
        "reason_code": {"type": "string", "minLength": 2, "maxLength": 80},
    },
    "required": ["verdict", "reason_code"],
}
SYSTEM_TEXT = """You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE directly establishes compliance with RULE.
Do not rewrite, repair, propose, or expand the evidence.
Do not infer missing implementation facts from plausibility or adjectives.
Return COMPLIES only when evidence directly establishes the rule.
Return CONTRADICTS only when evidence explicitly violates the rule.
Return UNCERTAIN when evidence does not establish either.
Return exactly the constrained JSON object and nothing else.
"""


def shape(value: Any) -> dict[str, Any]:
    if value is None:
        return {"type": "null", "nonempty": False}
    if isinstance(value, str):
        return {"type": "string", "length": len(value), "nonempty": bool(value.strip())}
    if isinstance(value, list):
        return {"type": "array", "length": len(value), "nonempty": bool(value)}
    if isinstance(value, dict):
        return {"type": "object", "keys": sorted(str(key) for key in value), "nonempty": bool(value)}
    return {"type": type(value).__name__, "nonempty": True}


def safe_usage(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    return {
        str(key): item
        for key, item in value.items()
        if isinstance(item, (int, float, bool)) or item is None
    }


def provider_diagnostics(envelope: dict[str, Any]) -> dict[str, Any]:
    result = envelope.get("result") if envelope.get("success") is True and isinstance(envelope.get("result"), dict) else envelope
    if not isinstance(result, dict):
        return {
            "top_level_keys": sorted(str(key) for key in envelope),
            "result_shape": shape(result),
        }

    diagnostics: dict[str, Any] = {
        "top_level_keys": sorted(str(key) for key in envelope),
        "result_keys": sorted(str(key) for key in result),
        "response_present": "response" in result,
        "response_shape": shape(result.get("response")) if "response" in result else {"type": "missing", "nonempty": False},
        "reasoning_shape": shape(result.get("reasoning")) if "reasoning" in result else {"type": "missing", "nonempty": False},
        "reasoning_content_shape": shape(result.get("reasoning_content")) if "reasoning_content" in result else {"type": "missing", "nonempty": False},
        "finish_reason": result.get("finish_reason") if isinstance(result.get("finish_reason"), (str, int, float, bool)) or result.get("finish_reason") is None else type(result.get("finish_reason")).__name__,
        "usage": safe_usage(result.get("usage")),
    }
    choices = result.get("choices")
    diagnostics["choices_shape"] = shape(choices)
    if isinstance(choices, list) and choices and isinstance(choices[0], dict):
        first = choices[0]
        diagnostics["first_choice_keys"] = sorted(str(key) for key in first)
        diagnostics["first_choice_finish_reason"] = first.get("finish_reason") if isinstance(first.get("finish_reason"), (str, int, float, bool)) or first.get("finish_reason") is None else type(first.get("finish_reason")).__name__
        message = first.get("message")
        diagnostics["message_shape"] = shape(message)
        if isinstance(message, dict):
            diagnostics["message_keys"] = sorted(str(key) for key in message)
            diagnostics["message_content_shape"] = shape(message.get("content"))
            diagnostics["message_reasoning_shape"] = shape(message.get("reasoning")) if "reasoning" in message else {"type": "missing", "nonempty": False}
            diagnostics["message_reasoning_content_shape"] = shape(message.get("reasoning_content")) if "reasoning_content" in message else {"type": "missing", "nonempty": False}
    return diagnostics


def fresh_payload() -> dict[str, str]:
    # Synthetic constraints are deliberately unrelated to S26 holdout/canonical outputs.
    clauses = []
    for index in range(1, 31):
        clauses.append(
            f"Synthetic governed constraint {index:02d}: retain source-bound element alpha_{index:02d}, "
            f"do not invent beta_{index:02d}, and preserve the declared relationship to gamma_{index:02d}."
        )
    rule = (
        "For this transport diagnostic only, evidence must directly establish every supplied synthetic constraint; "
        "missing facts must remain uncertain and no unstated implementation detail may be inferred. "
        + " ".join(clauses)
    )
    evidence = (
        "Synthetic evidence states that the existing alpha elements remain unchanged, but it does not explicitly "
        "establish every beta exclusion or every gamma relationship. This text exists only to exercise a large "
        "source-bound payload class and is not an S26 qualification case."
    )
    payload = {
        "check_id": "S26_NEMOTRON_LARGE_PAYLOAD_DIAGNOSTIC_001",
        "rule": rule,
        "evidence": evidence,
        "question": "Does the synthetic evidence directly establish the entire synthetic rule?",
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True)
    if not 3000 <= len(encoded) <= 6000:
        raise RuntimeError(f"DIAGNOSTIC_PAYLOAD_SIZE_OUT_OF_RANGE:{len(encoded)}")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()
    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_NEMOTRON_DIAGNOSTIC_BLOCK_CLOUDFLARE_SECRET")

    semantic_payload = fresh_payload()
    user_json = json.dumps(semantic_payload, ensure_ascii=False, sort_keys=True)
    request_payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_TEXT},
            {"role": "user", "content": user_json},
        ],
        "response_format": {"type": "json_schema", "json_schema": SCHEMA},
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_completion_tokens": MAX_COMPLETION_TOKENS,
    }
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}",
        data=json.dumps(request_payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )

    base = {
        "schema": "S26_NEMOTRON_LARGE_PAYLOAD_DIAGNOSTIC_V1",
        "strategy": "S26",
        "diagnostic_id": semantic_payload["check_id"],
        "model": MODEL,
        "protocol": "CLOUDFLARE_WORKERS_AI_RUN_REST",
        "request_user_payload_chars": len(user_json),
        "max_completion_tokens": MAX_COMPLETION_TOKENS,
        "fresh_synthetic_case": True,
        "canonical_or_holdout_output_reused": False,
        "raw_model_text_persisted": False,
        "reasoning_text_persisted": False,
        "semantic_qualification_executed": False,
        "authority_changed": False,
        "promotion_authorized": False,
        "production_mutation": False,
        "model_download_executed": False,
        "local_model_fallback_used": False,
        "paid_fallback_used": False,
        "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
        "limit_behavior": "FAIL_CLOSED",
    }

    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            envelope = json.loads(response.read().decode("utf-8"))
        elapsed = round(time.monotonic() - started, 3)
        if not isinstance(envelope, dict):
            raise RuntimeError("CLOUDFLARE_ENVELOPE_NOT_OBJECT")
        diagnostics = provider_diagnostics(envelope)
        response_shape = diagnostics.get("response_shape", {})
        choices_shape = diagnostics.get("choices_shape", {})
        content_shape = diagnostics.get("message_content_shape", {})
        final_nonempty = bool(response_shape.get("nonempty")) or bool(content_shape.get("nonempty"))
        base.update({
            "status": "PASS_FINAL_CONTENT_PRESENT" if final_nonempty else "FAIL_FINAL_CONTENT_EMPTY",
            "elapsed_s": elapsed,
            "provider_diagnostics": diagnostics,
            "final_content_present": final_nonempty,
            "choices_nonempty": bool(choices_shape.get("nonempty")),
        })
        exit_code = 0 if final_nonempty else 2
    except urllib.error.HTTPError as exc:
        elapsed = round(time.monotonic() - started, 3)
        code = "ZERO_COST_LIMIT_FAIL_CLOSED" if exc.code in {403, 429} else "CLOUDFLARE_HTTP_ERROR"
        base.update({"status": "FAIL_CLOSED", "error_code": code, "http_status": exc.code, "elapsed_s": elapsed})
        exit_code = 2
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError, RuntimeError) as exc:
        elapsed = round(time.monotonic() - started, 3)
        base.update({"status": "FAIL_CLOSED", "error_code": type(exc).__name__, "error": str(exc)[:300], "elapsed_s": elapsed})
        exit_code = 2

    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(json.dumps(base, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_NEMOTRON_LARGE_PAYLOAD_DIAGNOSTIC=" + json.dumps(base, ensure_ascii=False, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
