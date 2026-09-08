#!/usr/bin/env python3
"""Two-call S26 Nemotron reasoning-effort transport diagnostic.

Fresh synthetic case only. Compares the current default reasoning behavior with one
predeclared low-effort adjustment. It does not reuse canonical/holdout outputs,
change authority, recalibrate, promote, or persist model/reasoning text.
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
    return {str(k): v for k, v in value.items() if isinstance(v, (int, float, bool)) or v is None}


def diagnostics(envelope: dict[str, Any]) -> dict[str, Any]:
    result = envelope.get("result") if envelope.get("success") is True and isinstance(envelope.get("result"), dict) else envelope
    if not isinstance(result, dict):
        return {"result_shape": shape(result), "top_level_keys": sorted(str(k) for k in envelope)}
    out: dict[str, Any] = {
        "result_keys": sorted(str(k) for k in result),
        "response_shape": shape(result.get("response")) if "response" in result else {"type": "missing", "nonempty": False},
        "reasoning_shape": shape(result.get("reasoning")) if "reasoning" in result else {"type": "missing", "nonempty": False},
        "reasoning_content_shape": shape(result.get("reasoning_content")) if "reasoning_content" in result else {"type": "missing", "nonempty": False},
        "usage": safe_usage(result.get("usage")),
    }
    choices = result.get("choices")
    out["choices_shape"] = shape(choices)
    if isinstance(choices, list) and choices and isinstance(choices[0], dict):
        first = choices[0]
        out["finish_reason"] = first.get("finish_reason") if isinstance(first.get("finish_reason"), (str, int, float, bool)) or first.get("finish_reason") is None else type(first.get("finish_reason")).__name__
        message = first.get("message")
        out["message_shape"] = shape(message)
        if isinstance(message, dict):
            out["content_shape"] = shape(message.get("content"))
            out["message_reasoning_shape"] = shape(message.get("reasoning")) if "reasoning" in message else {"type": "missing", "nonempty": False}
            out["message_reasoning_content_shape"] = shape(message.get("reasoning_content")) if "reasoning_content" in message else {"type": "missing", "nonempty": False}
    return out


def frozen_case() -> dict[str, str]:
    facts = [
        "The synthetic screen contains a neutral header, one metadata line, one filter strip, one data region and one existing primary action.",
        "The metadata line is informational and must remain subordinate to the header and primary action.",
        "The filter strip must remain operable and may not be replaced by a new control.",
        "The data region must remain visible while metadata treatment changes.",
        "No timeout, urgency copy, guarantee, debt-pressure cue or new business state is supplied.",
        "No numeric spacing token is supplied; invented pixel precision is forbidden.",
        "A soft neutral surface token exists, but no canonical elevation token is supplied.",
        "The existing primary action must remain the only primary action.",
        "Keyboard order is not supplied and therefore cannot be asserted as preserved.",
        "The candidate may change presentation only; it may not change labels, business meaning or interaction semantics.",
        "The candidate must distinguish source-bound values from relative design choices.",
        "The diagnostic is synthetic and has no authority over S26 production or Golden state.",
    ]
    candidate = {
        "target": "synthetic metadata line",
        "treatment": "soft neutral surface",
        "position": "below header and above filters",
        "controls_added": 0,
        "primary_actions": 1,
        "business_copy_changed": False,
        "numeric_spacing_claim": None,
        "keyboard_order_claim": "preserved",
    }
    rule = (
        "Evaluate the complete candidate against every supplied synthetic fact. A COMPLIES verdict requires direct evidence for all material claims; "
        "an explicit violation requires CONTRADICTS; otherwise use UNCERTAIN. The facts are: "
        + " | ".join(facts)
    )
    evidence = "Candidate decision: " + json.dumps(candidate, ensure_ascii=False, sort_keys=True)
    payload = {
        "check_id": "S26_NEMOTRON_REASONING_EFFORT_DIAGNOSTIC_001",
        "rule": rule,
        "evidence": evidence,
        "question": "Does the complete synthetic candidate directly satisfy the complete synthetic rule without unsupported claims?",
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True)
    if not 2500 <= len(encoded) <= 5000:
        raise RuntimeError(f"DIAGNOSTIC_PAYLOAD_SIZE_OUT_OF_RANGE:{len(encoded)}")
    return payload


def call(account: str, token: str, semantic_payload: dict[str, str], effort: str | None) -> dict[str, Any]:
    user_json = json.dumps(semantic_payload, ensure_ascii=False, sort_keys=True)
    request_payload: dict[str, Any] = {
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
    if effort is not None:
        request_payload["reasoning_effort"] = effort
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}",
        data=json.dumps(request_payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            envelope = json.loads(response.read().decode("utf-8"))
        elapsed = round(time.monotonic() - started, 3)
        if not isinstance(envelope, dict):
            raise RuntimeError("CLOUDFLARE_ENVELOPE_NOT_OBJECT")
        diag = diagnostics(envelope)
        final_present = bool(diag.get("response_shape", {}).get("nonempty")) or bool(diag.get("content_shape", {}).get("nonempty"))
        return {
            "status": "PASS_FINAL_CONTENT_PRESENT" if final_present else "FAIL_FINAL_CONTENT_EMPTY",
            "reasoning_effort": effort or "DEFAULT",
            "elapsed_s": elapsed,
            "final_content_present": final_present,
            "provider_diagnostics": diag,
        }
    except urllib.error.HTTPError as exc:
        elapsed = round(time.monotonic() - started, 3)
        return {
            "status": "FAIL_CLOSED",
            "reasoning_effort": effort or "DEFAULT",
            "elapsed_s": elapsed,
            "error_code": "ZERO_COST_LIMIT_FAIL_CLOSED" if exc.code in {403, 429} else "CLOUDFLARE_HTTP_ERROR",
            "http_status": exc.code,
        }
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError, RuntimeError) as exc:
        elapsed = round(time.monotonic() - started, 3)
        return {
            "status": "FAIL_CLOSED",
            "reasoning_effort": effort or "DEFAULT",
            "elapsed_s": elapsed,
            "error_code": type(exc).__name__,
            "error": str(exc)[:300],
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()
    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_NEMOTRON_REASONING_DIAGNOSTIC_BLOCK_CLOUDFLARE_SECRET")

    case = frozen_case()
    user_chars = len(json.dumps(case, ensure_ascii=False, sort_keys=True))
    default_result = call(account, token, case, None)
    low_result = call(account, token, case, "low")
    payload = {
        "schema": "S26_NEMOTRON_REASONING_EFFORT_DIAGNOSTIC_V1",
        "strategy": "S26",
        "diagnostic_id": case["check_id"],
        "model": MODEL,
        "request_user_payload_chars": user_chars,
        "max_completion_tokens": MAX_COMPLETION_TOKENS,
        "fresh_synthetic_case": True,
        "canonical_or_holdout_output_reused": False,
        "predeclared_effort_variants": ["DEFAULT", "low"],
        "results": [default_result, low_result],
        "raw_model_text_persisted": False,
        "reasoning_text_persisted": False,
        "semantic_qualification_executed": False,
        "authority_changed": False,
        "calibration_changed": False,
        "promotion_authorized": False,
        "production_mutation": False,
        "model_download_executed": False,
        "local_model_fallback_used": False,
        "paid_fallback_used": False,
        "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
        "limit_behavior": "FAIL_CLOSED",
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_NEMOTRON_REASONING_EFFORT_DIAGNOSTIC=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0 if all(item.get("status") != "FAIL_CLOSED" for item in payload["results"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
