#!/usr/bin/env python3
"""S26 one-call zero-download GLM-4.7-Flash judge challenger preflight.

This is challenger evidence only. It does not change canonical judge authority,
authorize promotion, or mutate production.
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

MODEL = "@cf/zai-org/glm-4.7-flash"
PRIMARY_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
MAX_COMPLETION_TOKENS = 256
SYSTEM_TEXT = """You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE complies with RULE. Do not rewrite or repair it.
Return exactly one JSON object with keys verdict and reason_code.
verdict must be COMPLIES, CONTRADICTS, or UNCERTAIN.
Use UNCERTAIN only when the evidence is insufficient to establish either compliance or contradiction.
"""
SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "verdict": {"type": "string", "enum": ["COMPLIES", "CONTRADICTS", "UNCERTAIN"]},
        "reason_code": {"type": "string", "minLength": 2, "maxLength": 80},
    },
    "required": ["verdict", "reason_code"],
}
# Fresh preflight case, frozen in source before first GLM output.
CASE = {
    "id": "GLM47_PREFLIGHT_STATUS_PRESERVATION",
    "expected": "COMPLIES",
    "rule": "The status treatment must keep the full status text visible and must add no new interactive control.",
    "evidence": "The treatment keeps the full status text visible and adds no button, menu, icon control, or extra interaction.",
}


def sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()
    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_GLM47_PREFLIGHT_BLOCK_CLOUDFLARE_SECRET")

    request_payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_TEXT},
            {"role": "user", "content": json.dumps({"rule": CASE["rule"], "evidence": CASE["evidence"]}, ensure_ascii=False, sort_keys=True)},
        ],
        "response_format": {"type": "json_schema", "json_schema": SCHEMA},
        "reasoning_effort": "low",
        "max_completion_tokens": MAX_COMPLETION_TOKENS,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "stream": False,
    }
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/v1/chat/completions",
        data=json.dumps(request_payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    started = time.monotonic()
    result: dict[str, Any] = {
        "schema": "S26_GLM47_REMOTE_JUDGE_PREFLIGHT_V1",
        "strategy": "S26",
        "provider": "cloudflare_workers_ai",
        "model": MODEL,
        "primary_model": PRIMARY_MODEL,
        "case_id": CASE["id"],
        "case_sha256": sha(json.dumps(CASE, ensure_ascii=False, sort_keys=True)),
        "expected": CASE["expected"],
        "reasoning_effort": "low",
        "max_completion_tokens": MAX_COMPLETION_TOKENS,
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
    rc = 2
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            envelope = json.loads(response.read().decode("utf-8"))
        result["elapsed_s"] = round(time.monotonic() - started, 3)
        if not isinstance(envelope, dict):
            raise RuntimeError("CHAT_COMPLETION_NOT_OBJECT")
        choices = envelope.get("choices")
        if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
            raise RuntimeError("CHAT_COMPLETION_CHOICES_INVALID")
        choice = choices[0]
        message = choice.get("message") if isinstance(choice.get("message"), dict) else {}
        content = message.get("content")
        result["finish_reason"] = choice.get("finish_reason")
        result["content_present"] = isinstance(content, str) and bool(content.strip())
        reasoning = message.get("reasoning_content")
        result["reasoning_present"] = isinstance(reasoning, str) and bool(reasoning.strip())
        result["reasoning_length"] = len(reasoning) if isinstance(reasoning, str) else 0
        usage = envelope.get("usage") if isinstance(envelope.get("usage"), dict) else {}
        result["usage"] = {str(k): v for k, v in usage.items() if isinstance(v, (int, float, bool)) or v is None}
        if not result["content_present"]:
            raise RuntimeError("FINAL_CONTENT_EMPTY")
        raw = content.strip()
        parsed = json.loads(raw)
        if not isinstance(parsed, dict) or set(parsed) != {"verdict", "reason_code"}:
            raise RuntimeError("FINAL_JSON_SHAPE_INVALID")
        if parsed.get("verdict") not in {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}:
            raise RuntimeError("FINAL_VERDICT_INVALID")
        reason_code = parsed.get("reason_code")
        if not isinstance(reason_code, str) or not (2 <= len(reason_code) <= 80):
            raise RuntimeError("FINAL_REASON_CODE_INVALID")
        result["raw_output_sha256"] = sha(raw)
        result["observed"] = parsed["verdict"]
        result["reason_code"] = reason_code
        result["matches_expected"] = parsed["verdict"] == CASE["expected"]
        result["status"] = "PREFLIGHT_PASS_CHALLENGER_ONLY" if result["matches_expected"] else "FAIL_CLOSED"
        rc = 0 if result["matches_expected"] else 2
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[-500:].replace("\n", " ")
        result["elapsed_s"] = round(time.monotonic() - started, 3)
        result["status"] = "FAIL_CLOSED"
        result["error"] = f"CLOUDFLARE_HTTP_{exc.code}:{detail}"
    except Exception as exc:
        result["elapsed_s"] = round(time.monotonic() - started, 3)
        result["status"] = "FAIL_CLOSED"
        result["error"] = f"{type(exc).__name__}:{str(exc)[:500]}"

    args.result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_GLM47_JUDGE_PREFLIGHT=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    print("S26_GLM47_JUDGE_PREFLIGHT_STATUS=" + result.get("status", "FAIL_CLOSED"))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
