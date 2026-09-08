#!/usr/bin/env python3
"""S26 zero-download remote semantic-judge challenger calibration.

Reusable challenger-only harness. It does not change canonical judge authority,
authorize promotion, or execute production mutations.
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

DEFAULT_MODEL = "@cf/openai/gpt-oss-20b"
PRIMARY_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
DEFAULT_PROTOCOL = "WORKERS_AI_RUN_MESSAGES"
TIMEOUT_SECONDS = 90
CALIBRATION_MAX_TOKENS = 512
PREFLIGHT_MAX_TOKENS = 256
SYSTEM_TEXT = """You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE complies with RULE.
Do not rewrite, repair, propose, or expand the evidence.
Return exactly one JSON object with two keys:
{"verdict":"COMPLIES|CONTRADICTS|UNCERTAIN","reason_code":"SHORT_MACHINE_CODE"}
Use COMPLIES when the evidence directly follows the rule, even if it uses different wording.
Use CONTRADICTS when the evidence reverses, violates, or explicitly rejects the rule.
Use UNCERTAIN only when the supplied evidence is insufficient to establish compliance or contradiction.
"""

VERDICT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "verdict": {"type": "string", "enum": ["COMPLIES", "CONTRADICTS", "UNCERTAIN"]},
        "reason_code": {"type": "string", "minLength": 2, "maxLength": 80},
    },
    "required": ["verdict", "reason_code"],
}

# Fresh transport/semantic preflight case added before any Llama 4 Scout output.
# It is intentionally distinct from the frozen six-case calibration below.
PREFLIGHT_CASE = {
    "id": "PREFLIGHT_UNCERTAIN_KEYBOARD_BEHAVIOR",
    "expected": "UNCERTAIN",
    "rule": "The proposed treatment must preserve every existing keyboard behavior and may not introduce a new interaction mode.",
    "evidence": "The proposal preserves the existing layout, labels and primary action. Keyboard behavior is not described.",
    "question": "Can compliance or contradiction be established from the supplied evidence?",
}

# Standard frozen labels committed before challenger outputs were observed.
# Do not tune these cases from any challenger result.
CALIBRATION = (
    {
        "id": "CAL_POS_PRESERVE_TABLE",
        "expected": "COMPLIES",
        "rule": "The treatment must preserve all existing table columns and row actions.",
        "evidence": "The selected treatment keeps every existing table column and every row action unchanged.",
        "question": "Does the evidence comply with the rule?",
    },
    {
        "id": "CAL_POS_PASSIVE_CUE",
        "expected": "COMPLIES",
        "rule": "Use at most one passive overflow cue per overflowing table viewport and add zero controls per row.",
        "evidence": "One passive edge cue is shown for the overflowing table viewport, with no additional controls added to any row.",
        "question": "Does the evidence comply with the rule?",
    },
    {
        "id": "CAL_NEG_HIDE_COLUMNS",
        "expected": "CONTRADICTS",
        "rule": "The treatment must preserve all existing table columns and row actions.",
        "evidence": "On narrow screens, hide the final two columns and replace the row actions with a single overflow menu.",
        "question": "Does the evidence comply with the rule?",
    },
    {
        "id": "CAL_NEG_ROW_CONTROLS",
        "expected": "CONTRADICTS",
        "rule": "Add zero new controls per row.",
        "evidence": "Add a help icon button to every row so users can discover the overflow behavior.",
        "question": "Does the evidence comply with the rule?",
    },
    {
        "id": "CAL_UNCERTAIN_ROW_ACTIONS",
        "expected": "UNCERTAIN",
        "rule": "The selected treatment must preserve every existing row action.",
        "evidence": "The table keeps its current structure.",
        "question": "Can compliance or contradiction be established from the evidence?",
    },
    {
        "id": "CAL_UNCERTAIN_CUE_BEHAVIOR",
        "expected": "UNCERTAIN",
        "rule": "The passive overflow cue must remain subordinate and must not obscure row actions.",
        "evidence": "A subtle edge treatment may be used when overflow is present.",
        "question": "Can compliance or contradiction be established from the evidence?",
    },
)


def sha_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _shape_summary(result: dict[str, Any]) -> str:
    summary: list[str] = []
    for key in sorted(result):
        value = result[key]
        if isinstance(value, str):
            summary.append(f"{key}:str:{len(value)}")
        elif isinstance(value, dict):
            summary.append(f"{key}:object:{','.join(sorted(str(k) for k in value.keys()))}")
        elif isinstance(value, list):
            summary.append(f"{key}:array:{len(value)}")
        else:
            summary.append(f"{key}:{type(value).__name__}")
    return "|".join(summary)[:1200]


def _parse_value(value: Any, *, shape_source: dict[str, Any]) -> tuple[dict[str, str], str]:
    if isinstance(value, dict):
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True)
        parsed = value
    elif isinstance(value, str) and value.strip():
        raw = value.strip()
        parsed = json.loads(raw)
    else:
        raise RuntimeError("CHALLENGER_RESPONSE_EMPTY:" + _shape_summary(shape_source))
    if not isinstance(parsed, dict) or set(parsed) != {"verdict", "reason_code"}:
        raise RuntimeError("CHALLENGER_RESPONSE_SHAPE_INVALID:" + _shape_summary(parsed if isinstance(parsed, dict) else {"value": parsed}))
    verdict = parsed.get("verdict")
    reason = parsed.get("reason_code")
    if verdict not in {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}:
        raise RuntimeError("CHALLENGER_VERDICT_INVALID")
    if not isinstance(reason, str) or not (2 <= len(reason) <= 80):
        raise RuntimeError("CHALLENGER_REASON_CODE_INVALID")
    return {"verdict": verdict, "reason_code": reason}, raw


def _native_result(envelope: dict[str, Any]) -> tuple[dict[str, str], str, dict[str, Any]]:
    if envelope.get("success") is not True:
        raise RuntimeError("CLOUDFLARE_ENVELOPE_FAILURE")
    result = envelope.get("result")
    if not isinstance(result, dict):
        raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
    parsed, raw = _parse_value(result.get("response"), shape_source=result)
    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
    return parsed, raw, usage


def _openai_result(envelope: dict[str, Any]) -> tuple[dict[str, str], str, dict[str, Any]]:
    choices = envelope.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise RuntimeError("CLOUDFLARE_OPENAI_CHOICES_INVALID:" + _shape_summary(envelope))
    message = choices[0].get("message")
    if not isinstance(message, dict):
        raise RuntimeError("CLOUDFLARE_OPENAI_MESSAGE_INVALID")
    value = message.get("parsed") if message.get("parsed") is not None else message.get("content")
    parsed, raw = _parse_value(value, shape_source=message)
    usage = envelope.get("usage") if isinstance(envelope.get("usage"), dict) else {}
    return parsed, raw, usage


def call_cloudflare(
    account: str,
    token: str,
    case: dict[str, str],
    *,
    model: str,
    protocol: str,
    max_tokens: int,
) -> tuple[dict[str, str], str, dict[str, Any], float]:
    messages = [
        {"role": "system", "content": SYSTEM_TEXT},
        {
            "role": "user",
            "content": json.dumps(
                {"rule": case["rule"], "evidence": case["evidence"], "question": case["question"]},
                ensure_ascii=False,
                sort_keys=True,
            ),
        },
    ]
    payload: dict[str, Any] = {
        "messages": messages,
        "response_format": {"type": "json_schema", "json_schema": VERDICT_SCHEMA},
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": max_tokens,
    }
    if protocol == "OPENAI_CHAT_COMPLETIONS":
        payload["model"] = model
        url = f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/v1/chat/completions"
    elif protocol == "WORKERS_AI_RUN_MESSAGES":
        url = f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{model}"
    else:
        raise RuntimeError("CHALLENGER_PROTOCOL_INVALID")

    req = urllib.request.Request(
        url,
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
        code = "ZERO_COST_LIMIT_FAIL_CLOSED" if exc.code in {403, 429} else f"CLOUDFLARE_HTTP_{exc.code}"
        raise RuntimeError(f"{code}:{detail}") from exc
    except Exception as exc:
        raise RuntimeError("CLOUDFLARE_TRANSPORT_" + type(exc).__name__) from exc
    elapsed = round(time.monotonic() - started, 3)
    if not isinstance(envelope, dict):
        raise RuntimeError("CLOUDFLARE_ENVELOPE_NOT_OBJECT")
    if protocol == "OPENAI_CHAT_COMPLETIONS":
        parsed, raw, usage = _openai_result(envelope)
    else:
        parsed, raw, usage = _native_result(envelope)
    return parsed, raw, usage, elapsed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    parser.add_argument("--model", default=os.getenv("S26_JUDGE_CHALLENGER_MODEL", DEFAULT_MODEL))
    parser.add_argument(
        "--protocol",
        choices=("WORKERS_AI_RUN_MESSAGES", "OPENAI_CHAT_COMPLETIONS"),
        default=os.getenv("S26_JUDGE_CHALLENGER_PROTOCOL", DEFAULT_PROTOCOL),
    )
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--max-tokens", type=int)
    args = parser.parse_args()

    model = str(args.model).strip()
    if not model.startswith("@cf/"):
        raise SystemExit("S26_REMOTE_JUDGE_MODEL_INVALID")
    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_REMOTE_JUDGE_BLOCK_CLOUDFLARE_SECRET")

    cases = (PREFLIGHT_CASE,) if args.preflight_only else CALIBRATION
    max_tokens = args.max_tokens or (PREFLIGHT_MAX_TOKENS if args.preflight_only else CALIBRATION_MAX_TOKENS)
    if max_tokens <= 0 or max_tokens > 1024:
        raise SystemExit("S26_REMOTE_JUDGE_MAX_TOKENS_INVALID")

    calibration_sha = hashlib.sha256(
        json.dumps(cases, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()
    results: list[dict[str, Any]] = []
    total_neurons = 0.0
    total_prompt = 0
    total_completion = 0
    diagnostic_blocked = False

    for index, case in enumerate(cases):
        item: dict[str, Any] = {
            "case_id": case["id"],
            "expected": case["expected"],
            "rule_sha256": sha_text(case["rule"]),
            "evidence_sha256": sha_text(case["evidence"]),
        }
        try:
            parsed, raw, usage, elapsed = call_cloudflare(
                account,
                token,
                case,
                model=model,
                protocol=args.protocol,
                max_tokens=max_tokens,
            )
            item["transport_status"] = "PASS"
            item["raw_output_sha256"] = sha_text(raw)
            item["observed"] = parsed["verdict"]
            item["reason_code"] = parsed["reason_code"]
            item["matches_expected"] = parsed["verdict"] == case["expected"]
            item["elapsed_s"] = elapsed
            item["usage"] = usage
            try:
                total_neurons += float(usage.get("neurons") or 0)
                total_prompt += int(usage.get("prompt_tokens") or 0)
                total_completion += int(usage.get("completion_tokens") or 0)
            except (TypeError, ValueError):
                pass
        except Exception as exc:
            item["transport_status"] = "FAIL"
            item["matches_expected"] = False
            item["error"] = f"{type(exc).__name__}:{str(exc)[:1200]}"
            if index == 0:
                diagnostic_blocked = True
        results.append(item)
        if diagnostic_blocked:
            break

    matched = sum(1 for item in results if item.get("matches_expected") is True)
    transport_passed = sum(1 for item in results if item.get("transport_status") == "PASS")
    passed = len(results) == len(cases) and matched == len(cases) and transport_passed == len(cases)
    mode = "PREFLIGHT" if args.preflight_only else "CALIBRATION"
    payload = {
        "schema": "S26_REMOTE_SEMANTIC_JUDGE_CHALLENGER_CALIBRATION_V2",
        "strategy": "S26",
        "mode": mode,
        "status": f"{mode}_PASS_CHALLENGER_ONLY" if passed else "FAIL_CLOSED",
        "provider": "cloudflare_workers_ai",
        "protocol": args.protocol,
        "primary_model": PRIMARY_MODEL,
        "judge_challenger_model": model,
        "semantic_oracle_distinct": model != PRIMARY_MODEL,
        "provider_infrastructure_shared": True,
        "full_independent_authority_proven": False,
        "cases_frozen_before_output": True,
        "case_set_sha256": calibration_sha,
        "case_count": len(cases),
        "executed_case_count": len(results),
        "diagnostic_first_case_fail_closed": diagnostic_blocked,
        "transport_passed": transport_passed,
        "matched_expected": matched,
        "retries": 0,
        "max_tokens": max_tokens,
        "neurons": round(total_neurons, 6),
        "prompt_tokens": total_prompt,
        "completion_tokens": total_completion,
        "cases": results,
        "authority_changed": False,
        "canonical_judge_authority": "UNCHANGED",
        "promotion_authorized": False,
        "production_mutation": False,
        "paid_fallback_used": False,
        "local_model_fallback_used": False,
        "model_download_executed": False,
        "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
        "limit_behavior": "FAIL_CLOSED",
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_REMOTE_JUDGE_CHALLENGER_CALIBRATION=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
    print("S26_REMOTE_JUDGE_" + mode + "=" + ("PASS_CHALLENGER_ONLY" if passed else "FAIL_CLOSED"))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
