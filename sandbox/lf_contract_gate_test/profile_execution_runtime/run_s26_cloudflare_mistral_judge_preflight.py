#!/usr/bin/env python3
"""S26 one-call Mistral Small 3.1 remote semantic-judge preflight.

Uses the model-native guided_json path. Challenger only: canonical judge authority,
promotion and production remain unchanged.
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

MODEL = "@cf/mistralai/mistral-small-3.1-24b-instruct"
PRIMARY_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
MAX_TOKENS = 96
SYSTEM_TEXT = """You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE complies with RULE. Do not rewrite or repair it.
Return the constrained JSON verdict only. verdict must be COMPLIES, CONTRADICTS, or UNCERTAIN.
Use UNCERTAIN only when evidence is insufficient to establish compliance or contradiction.
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
# Fresh case frozen in source before first judge-role Mistral output.
CASE = {
    "id": "MISTRAL_JUDGE_PREFLIGHT_SEARCH_CONTINUITY",
    "expected": "CONTRADICTS",
    "rule": "During loading, existing search results must remain visible and search must remain operable.",
    "evidence": "Hide all result rows and disable the search field until loading completes.",
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
        raise SystemExit("S26_MISTRAL_JUDGE_BLOCK_CLOUDFLARE_SECRET")

    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_TEXT},
            {"role": "user", "content": json.dumps({"rule": CASE["rule"], "evidence": CASE["evidence"]}, ensure_ascii=False, sort_keys=True)},
        ],
        "guided_json": SCHEMA,
        "stream": False,
        "max_tokens": MAX_TOKENS,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
    }
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    started = time.monotonic()
    result: dict[str, Any] = {
        "schema": "S26_MISTRAL_REMOTE_JUDGE_PREFLIGHT_V1",
        "strategy": "S26",
        "provider": "cloudflare_workers_ai",
        "model": MODEL,
        "primary_model": PRIMARY_MODEL,
        "protocol": "WORKERS_AI_RUN_GUIDED_JSON",
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
    rc = 2
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            envelope = json.loads(response.read().decode("utf-8"))
        result["elapsed_s"] = round(time.monotonic() - started, 3)
        if not isinstance(envelope, dict) or envelope.get("success") is not True:
            raise RuntimeError("CLOUDFLARE_ENVELOPE_FAILURE")
        model_result = envelope.get("result")
        if not isinstance(model_result, dict):
            raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
        raw = model_result.get("response")
        if not isinstance(raw, str) or not raw.strip():
            raise RuntimeError("FINAL_CONTENT_EMPTY")
        raw = raw.strip()
        result["raw_output_sha256"] = sha(raw)
        result["fenced_output"] = raw.startswith("```")
        parsed = json.loads(raw)
        if not isinstance(parsed, dict) or set(parsed) != {"verdict", "reason_code"}:
            raise RuntimeError("FINAL_JSON_SHAPE_INVALID")
        verdict = parsed.get("verdict")
        reason_code = parsed.get("reason_code")
        if verdict not in {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}:
            raise RuntimeError("FINAL_VERDICT_INVALID")
        if not isinstance(reason_code, str) or not (2 <= len(reason_code) <= 80):
            raise RuntimeError("FINAL_REASON_CODE_INVALID")
        usage = model_result.get("usage") if isinstance(model_result.get("usage"), dict) else {}
        result["usage"] = {str(k): v for k, v in usage.items() if isinstance(v, (int, float, bool)) or v is None}
        result["observed"] = verdict
        result["reason_code"] = reason_code
        result["matches_expected"] = verdict == CASE["expected"]
        result["status"] = "PREFLIGHT_PASS_CHALLENGER_ONLY" if result["matches_expected"] and not result["fenced_output"] else "FAIL_CLOSED"
        rc = 0 if result["status"] == "PREFLIGHT_PASS_CHALLENGER_ONLY" else 2
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
    print("S26_MISTRAL_JUDGE_PREFLIGHT=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    print("S26_MISTRAL_JUDGE_PREFLIGHT_STATUS=" + result.get("status", "FAIL_CLOSED"))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
