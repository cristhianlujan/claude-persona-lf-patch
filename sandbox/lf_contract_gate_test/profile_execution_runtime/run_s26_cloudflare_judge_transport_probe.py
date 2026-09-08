#!/usr/bin/env python3
"""One-call structural probe for the S26 GPT-OSS challenger transport.

Records only response field names, types, lengths, finish reason and numeric usage.
It does not persist model text, reasoning text, or semantic verdicts.
"""
from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

from run_s26_cloudflare_judge_challenger_calibration import (
    CALIBRATION,
    MODEL,
    SYSTEM_TEXT,
    VERDICT_SCHEMA,
)

PROBE_MAX_TOKENS = 256


def shape(value):
    if value is None:
        return {"type": "null"}
    if isinstance(value, str):
        return {"type": "string", "length": len(value), "nonempty": bool(value.strip())}
    if isinstance(value, list):
        return {"type": "array", "length": len(value)}
    if isinstance(value, dict):
        return {"type": "object", "keys": sorted(str(k) for k in value.keys())}
    return {"type": type(value).__name__}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()
    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_REMOTE_JUDGE_PROBE_BLOCK_CLOUDFLARE_SECRET")

    case = CALIBRATION[0]
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_TEXT},
            {"role": "user", "content": json.dumps({"rule": case["rule"], "evidence": case["evidence"], "question": case["question"]}, ensure_ascii=False, sort_keys=True)},
        ],
        "response_format": {"type": "json_schema", "json_schema": VERDICT_SCHEMA},
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": PROBE_MAX_TOKENS,
    }
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/v1/chat/completions",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            envelope = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[-500:].replace("\n", " ")
        raise SystemExit(f"S26_REMOTE_JUDGE_PROBE_HTTP_{exc.code}:{detail}")
    elapsed = round(time.monotonic() - started, 3)
    if not isinstance(envelope, dict):
        raise SystemExit("S26_REMOTE_JUDGE_PROBE_NOT_OBJECT")

    choices = envelope.get("choices")
    first = choices[0] if isinstance(choices, list) and choices and isinstance(choices[0], dict) else {}
    message = first.get("message") if isinstance(first.get("message"), dict) else {}
    usage = envelope.get("usage") if isinstance(envelope.get("usage"), dict) else {}
    safe_usage = {str(k): v for k, v in usage.items() if isinstance(v, (int, float, bool)) or v is None}
    result = {
        "schema": "S26_REMOTE_JUDGE_TRANSPORT_SHAPE_PROBE_V1",
        "strategy": "S26",
        "model": MODEL,
        "protocol": "OPENAI_CHAT_COMPLETIONS",
        "case_id": case["id"],
        "max_tokens": PROBE_MAX_TOKENS,
        "response_format_type": "json_schema",
        "elapsed_s": elapsed,
        "top_level_keys": sorted(str(k) for k in envelope.keys()),
        "choice_count": len(choices) if isinstance(choices, list) else 0,
        "choice_keys": sorted(str(k) for k in first.keys()),
        "finish_reason": first.get("finish_reason"),
        "message_keys": sorted(str(k) for k in message.keys()),
        "message_field_shapes": {str(k): shape(v) for k, v in message.items()},
        "usage": safe_usage,
        "text_or_reasoning_persisted": False,
        "semantic_evaluation_executed": False,
        "authority_changed": False,
        "promotion_authorized": False,
        "production_mutation": False,
        "model_download_executed": False,
        "local_model_fallback_used": False,
        "paid_fallback_used": False,
    }
    args.result_path.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("S26_REMOTE_JUDGE_TRANSPORT_SHAPE=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
