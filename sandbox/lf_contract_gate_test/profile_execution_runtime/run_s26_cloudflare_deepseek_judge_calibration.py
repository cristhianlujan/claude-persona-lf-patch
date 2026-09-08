#!/usr/bin/env python3
"""S26 zero-download DeepSeek semantic-judge challenger calibration.

The six labels below are frozen before this calibration executes. This is a
challenger-only capability panel: canonical Qwen2.5-VL-7B judge authority,
production, routing and promotion remain unchanged.
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

MODEL = "@cf/deepseek-ai/deepseek-r1-distill-qwen-32b"
PRIMARY_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
MAX_TOKENS = 512
TIMEOUT_SECONDS = 90
SYSTEM_TEXT = """You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE complies with RULE.
Do not rewrite, repair, propose, or expand the evidence.
Return exactly one JSON object with two keys:
{"verdict":"COMPLIES|CONTRADICTS|UNCERTAIN","reason_code":"SHORT_MACHINE_CODE"}
Use COMPLIES only when evidence directly establishes the rule.
Use CONTRADICTS only when evidence explicitly violates or reverses the rule.
Use UNCERTAIN when the supplied evidence is insufficient to establish either.
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

# Fresh calibration examples. None reuse the DeepSeek preflight, the Mistral
# judge preflights, or the three exposed S26 Llama holdouts.
CALIBRATION = (
    {
        "id": "DS_CAL_POS_KEEP_HELPER_COPY",
        "expected": "COMPLIES",
        "rule": "The treatment must preserve the existing helper copy below the field.",
        "evidence": "Keep the current helper copy below the field unchanged while adjusting only the surrounding visual treatment.",
    },
    {
        "id": "DS_CAL_POS_NO_NEW_ROW_CONTROL",
        "expected": "COMPLIES",
        "rule": "The treatment must add no new interactive control to each existing row.",
        "evidence": "Preserve every existing row interaction and add no new row-level controls.",
    },
    {
        "id": "DS_CAL_NEG_REMOVE_EXISTING_ACTION",
        "expected": "CONTRADICTS",
        "rule": "Every existing row action must remain available after the treatment.",
        "evidence": "Remove the existing secondary row action so each row exposes only the primary action.",
    },
    {
        "id": "DS_CAL_NEG_INVENT_UNSUPPORTED_BREAKPOINT",
        "expected": "CONTRADICTS",
        "rule": "Do not invent a breakpoint value that is not supplied by governed evidence.",
        "evidence": "Introduce a new 913px breakpoint even though no breakpoint value was supplied by the governed evidence.",
    },
    {
        "id": "DS_CAL_UNCERTAIN_COPY_PRESERVATION",
        "expected": "UNCERTAIN",
        "rule": "The treatment must preserve the current explanatory copy next to the amount.",
        "evidence": "Refine the amount area so its hierarchy is easier to scan.",
    },
    {
        "id": "DS_CAL_UNCERTAIN_ACTION_OBSCURING",
        "expected": "UNCERTAIN",
        "rule": "The visual treatment must not obscure the existing action controls.",
        "evidence": "Use a subtle surface treatment around the action region.",
    },
)


def sha_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse_response(value: Any) -> tuple[dict[str, str], str, str, bool]:
    if isinstance(value, dict) and value:
        parsed = value
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True)
        shape = "object:" + ",".join(sorted(str(key) for key in value))
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


def call_cloudflare(account: str, token: str, case: dict[str, str]) -> tuple[dict[str, str], str, str, bool, dict[str, Any], float]:
    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_TEXT},
            {"role": "user", "content": json.dumps({"rule": case["rule"], "evidence": case["evidence"]}, ensure_ascii=False, sort_keys=True)},
        ],
        "response_format": {"type": "json_schema", "json_schema": SCHEMA},
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": MAX_TOKENS,
    }
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as response:
            envelope = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[-600:].replace("\n", " ")
        raise RuntimeError(f"CLOUDFLARE_HTTP_{exc.code}:{detail}") from exc
    except Exception as exc:
        raise RuntimeError("CLOUDFLARE_TRANSPORT_" + type(exc).__name__) from exc
    elapsed = round(time.monotonic() - started, 3)
    if not isinstance(envelope, dict) or envelope.get("success") is not True:
        raise RuntimeError("CLOUDFLARE_ENVELOPE_FAILURE")
    result = envelope.get("result")
    if not isinstance(result, dict):
        raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
    parsed, raw, shape, fenced = parse_response(result.get("response"))
    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
    return parsed, raw, shape, fenced, usage, elapsed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_DEEPSEEK_CALIBRATION_BLOCK_CLOUDFLARE_SECRET")

    calibration_sha256 = hashlib.sha256(
        json.dumps(CALIBRATION, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()
    results: list[dict[str, Any]] = []
    totals = {"neurons": 0.0, "prompt_tokens": 0, "completion_tokens": 0}

    for case in CALIBRATION:
        item: dict[str, Any] = {
            "case_id": case["id"],
            "expected": case["expected"],
            "rule_sha256": sha_text(case["rule"]),
            "evidence_sha256": sha_text(case["evidence"]),
            "transport_status": "NOT_EXECUTED",
        }
        try:
            parsed, raw, shape, fenced, usage, elapsed = call_cloudflare(account, token, case)
            item.update({
                "transport_status": "PASS",
                "observed": parsed["verdict"],
                "reason_code": parsed["reason_code"],
                "matches_expected": parsed["verdict"] == case["expected"],
                "provider_response_shape": shape,
                "fenced_output": fenced,
                "raw_output_sha256": sha_text(raw),
                "elapsed_s": elapsed,
                "usage": {str(k): v for k, v in usage.items() if isinstance(v, (int, float, bool)) or v is None},
            })
            try:
                totals["neurons"] += float(usage.get("neurons") or 0)
                totals["prompt_tokens"] += int(usage.get("prompt_tokens") or 0)
                totals["completion_tokens"] += int(usage.get("completion_tokens") or 0)
            except (TypeError, ValueError):
                pass
        except Exception as exc:
            item.update({
                "transport_status": "FAIL",
                "matches_expected": False,
                "error": f"{type(exc).__name__}:{str(exc)[:700]}",
            })
        results.append(item)

    matched = sum(1 for item in results if item.get("matches_expected") is True and item.get("fenced_output") is False)
    transport_passed = sum(1 for item in results if item.get("transport_status") == "PASS")
    passed = matched == 6 and transport_passed == 6
    payload = {
        "schema": "S26_DEEPSEEK_REMOTE_JUDGE_CALIBRATION_V1",
        "strategy": "S26",
        "status": "CALIBRATION_PASS_CHALLENGER_ONLY" if passed else "FAIL_CLOSED",
        "provider": "cloudflare_workers_ai",
        "primary_model": PRIMARY_MODEL,
        "judge_challenger_model": MODEL,
        "semantic_oracle_distinct": MODEL != PRIMARY_MODEL,
        "provider_infrastructure_shared": True,
        "full_independent_authority_proven": False,
        "calibration_frozen_before_output": True,
        "preflight_case_reused": False,
        "prior_mistral_cases_reused": False,
        "prior_llama_holdouts_reused": False,
        "calibration_sha256": calibration_sha256,
        "case_count": 6,
        "transport_passed": transport_passed,
        "matched_expected": matched,
        "retries": 0,
        "max_tokens": MAX_TOKENS,
        "neurons": round(totals["neurons"], 6),
        "prompt_tokens": totals["prompt_tokens"],
        "completion_tokens": totals["completion_tokens"],
        "cases": results,
        "authority_changed": False,
        "canonical_judge_authority": "QWEN2_5_VL_7B_Q4_K_M_UNCHANGED",
        "promotion_authorized": False,
        "production_mutation": False,
        "model_download_executed": False,
        "local_model_fallback_used": False,
        "paid_fallback_used": False,
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_DEEPSEEK_JUDGE_CALIBRATION=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
    print("S26_DEEPSEEK_JUDGE_CALIBRATION_STATUS=" + ("PASS_CHALLENGER_ONLY" if passed else "FAIL_CLOSED"))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
