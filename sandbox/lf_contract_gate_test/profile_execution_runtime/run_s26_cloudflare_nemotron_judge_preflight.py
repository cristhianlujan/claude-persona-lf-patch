#!/usr/bin/env python3
"""S26 one-call Nemotron remote semantic-judge challenger preflight.

Challenger only. Canonical Qwen2.5-VL-7B judge authority, production and
promotion remain unchanged. This case is frozen before first Nemotron output.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

MODEL = "@cf/nvidia/nemotron-3-120b-a12b"
PRIMARY_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
MAX_TOKENS = 256
CASE = {
    "id": "NEMOTRON_JUDGE_PREFLIGHT_ACCESSIBLE_NAME",
    "expected": "UNCERTAIN",
    "rule": "The reused icon must retain an accessible name after the header treatment.",
    "evidence": "Reuse the current icon in the revised header and align it with the title.",
}
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
Do not infer missing implementation facts from plausibility or adjectives.
Return COMPLIES only when evidence directly establishes the rule.
Return CONTRADICTS only when evidence explicitly violates the rule.
Return UNCERTAIN when evidence does not establish either.
Return exactly the constrained JSON object and nothing else.
"""


def sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse_value(value: Any) -> tuple[dict[str, str], str, str, bool]:
    if isinstance(value, dict) and value:
        parsed = value
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True)
        shape = "object:" + ",".join(sorted(str(k) for k in value))
        fenced = False
    elif isinstance(value, str) and value.strip():
        raw = value.strip()
        shape = f"string:{len(raw)}"
        fenced = raw.startswith("```")
        parsed = json.loads(raw)
    else:
        raise RuntimeError("FINAL_CONTENT_EMPTY")
    if not isinstance(parsed, dict) or set(parsed) != {"verdict", "reason_code"}:
        raise RuntimeError("FINAL_JSON_SHAPE_INVALID:" + shape)
    verdict = parsed.get("verdict")
    reason = parsed.get("reason_code")
    if verdict not in {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}:
        raise RuntimeError("FINAL_VERDICT_INVALID")
    if not isinstance(reason, str) or not 2 <= len(reason) <= 80:
        raise RuntimeError("FINAL_REASON_CODE_INVALID")
    return {"verdict": verdict, "reason_code": reason}, raw, shape, fenced


def extract_result(envelope: dict[str, Any]) -> tuple[dict[str, str], str, str, bool, dict[str, Any]]:
    if envelope.get("success") is True and isinstance(envelope.get("result"), dict):
        result = envelope["result"]
    else:
        result = envelope
    if not isinstance(result, dict):
        raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
    if "response" in result:
        parsed, raw, shape, fenced = parse_value(result.get("response"))
    else:
        choices = result.get("choices")
        if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
            raise RuntimeError("CHAT_CHOICES_MISSING")
        message = choices[0].get("message")
        if not isinstance(message, dict):
            raise RuntimeError("CHAT_MESSAGE_MISSING")
        parsed, raw, inner_shape, fenced = parse_value(message.get("content"))
        shape = "chat_content:" + inner_shape
    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
    return parsed, raw, shape, fenced, usage


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()
    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_NEMOTRON_JUDGE_BLOCK_CLOUDFLARE_SECRET")

    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_TEXT},
            {"role": "user", "content": json.dumps({"rule": CASE["rule"], "evidence": CASE["evidence"]}, ensure_ascii=False, sort_keys=True)},
        ],
        "response_format": {"type": "json_schema", "json_schema": SCHEMA},
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_completion_tokens": MAX_TOKENS,
    }
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    result: dict[str, Any] = {
        "schema": "S26_NEMOTRON_REMOTE_JUDGE_PREFLIGHT_V1",
        "strategy": "S26",
        "provider": "cloudflare_workers_ai",
        "model": MODEL,
        "primary_model": PRIMARY_MODEL,
        "case_id": CASE["id"],
        "case_sha256": sha(json.dumps(CASE, ensure_ascii=False, sort_keys=True)),
        "expected": CASE["expected"],
        "max_tokens": MAX_TOKENS,
        "authority_changed": False,
        "canonical_judge_authority": "QWEN2_5_VL_7B_Q4_K_M_UNCHANGED",
        "promotion_authorized": False,
        "production_mutation": False,
        "model_download_executed": False,
        "local_model_fallback_used": False,
        "paid_fallback_used": False,
        "provider_infrastructure_shared": True,
        "full_independent_authority_proven": False,
    }
    started = time.monotonic()
    rc = 2
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            envelope = json.loads(response.read().decode("utf-8"))
        result["elapsed_s"] = round(time.monotonic() - started, 3)
        if not isinstance(envelope, dict):
            raise RuntimeError("CLOUDFLARE_ENVELOPE_INVALID")
        parsed, raw, shape, fenced, usage = extract_result(envelope)
        result["provider_response_shape"] = shape
        result["fenced_output"] = fenced
        result["raw_output_sha256"] = sha(raw)
        result["usage"] = {str(k): v for k, v in usage.items() if isinstance(v, (int, float, bool)) or v is None}
        result["observed"] = parsed["verdict"]
        result["reason_code"] = parsed["reason_code"]
        result["matches_expected"] = parsed["verdict"] == CASE["expected"]
        result["status"] = "PREFLIGHT_PASS_CHALLENGER_ONLY" if result["matches_expected"] and not fenced else "FAIL_CLOSED"
        rc = 0 if result["status"] == "PREFLIGHT_PASS_CHALLENGER_ONLY" else 2
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[-600:].replace("\n", " ")
        result["elapsed_s"] = round(time.monotonic() - started, 3)
        result["status"] = "FAIL_CLOSED"
        result["error"] = f"CLOUDFLARE_HTTP_{exc.code}:{detail}"
    except Exception as exc:
        result["elapsed_s"] = round(time.monotonic() - started, 3)
        result["status"] = "FAIL_CLOSED"
        result["error"] = f"{type(exc).__name__}:{str(exc)[:700]}"

    args.result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_NEMOTRON_JUDGE_PREFLIGHT=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    print("S26_NEMOTRON_JUDGE_PREFLIGHT_STATUS=" + result.get("status", "FAIL_CLOSED"))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
