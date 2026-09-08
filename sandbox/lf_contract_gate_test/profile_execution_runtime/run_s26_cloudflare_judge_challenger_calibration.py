#!/usr/bin/env python3
"""S26 zero-download remote semantic-judge challenger calibration.

Challenger only. This script does not change the canonical judge authority,
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

MODEL = "@cf/openai/gpt-oss-20b"
PRIMARY_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
PROTOCOL = "OPENAI_CHAT_COMPLETIONS"
TIMEOUT_SECONDS = 90
MAX_TOKENS = 96
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

# Frozen labels are committed before the first challenger output is observed.
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


def parse_chat_completion(envelope: dict[str, Any]) -> tuple[dict[str, str], str]:
    try:
        value = envelope["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        keys = ",".join(sorted(str(key) for key in envelope.keys())) if isinstance(envelope, dict) else "NOT_OBJECT"
        raise RuntimeError("CHALLENGER_CHAT_COMPLETION_SHAPE_INVALID:" + keys) from exc
    if isinstance(value, dict):
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True)
        parsed = value
    elif isinstance(value, str) and value.strip():
        raw = value.strip()
        parsed = json.loads(raw)
    else:
        raise RuntimeError("CHALLENGER_CHAT_COMPLETION_CONTENT_EMPTY")
    if not isinstance(parsed, dict) or set(parsed) != {"verdict", "reason_code"}:
        raise RuntimeError("CHALLENGER_RESPONSE_SHAPE_INVALID")
    verdict = parsed.get("verdict")
    reason = parsed.get("reason_code")
    if verdict not in {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}:
        raise RuntimeError("CHALLENGER_VERDICT_INVALID")
    if not isinstance(reason, str) or not (2 <= len(reason) <= 80):
        raise RuntimeError("CHALLENGER_REASON_CODE_INVALID")
    return {"verdict": verdict, "reason_code": reason}, raw


def call_cloudflare(account: str, token: str, case: dict[str, str]) -> tuple[dict[str, str], str, dict[str, Any], float]:
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_TEXT},
            {
                "role": "user",
                "content": json.dumps(
                    {"rule": case["rule"], "evidence": case["evidence"], "question": case["question"]},
                    ensure_ascii=False,
                    sort_keys=True,
                ),
            },
        ],
        "response_format": {"type": "json_schema", "json_schema": VERDICT_SCHEMA},
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": MAX_TOKENS,
    }
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/v1/chat/completions",
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
    if not isinstance(envelope, dict):
        raise RuntimeError("CHALLENGER_CHAT_COMPLETION_NOT_OBJECT")
    parsed, raw = parse_chat_completion(envelope)
    usage = envelope.get("usage") if isinstance(envelope.get("usage"), dict) else {}
    return parsed, raw, usage, elapsed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account or not token:
        raise SystemExit("S26_REMOTE_JUDGE_BLOCK_CLOUDFLARE_SECRET")

    calibration_sha = hashlib.sha256(
        json.dumps(CALIBRATION, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()
    results: list[dict[str, Any]] = []
    total_neurons = 0.0
    total_prompt = 0
    total_completion = 0
    for case in CALIBRATION:
        item: dict[str, Any] = {
            "case_id": case["id"],
            "expected": case["expected"],
            "rule_sha256": sha_text(case["rule"]),
            "evidence_sha256": sha_text(case["evidence"]),
        }
        try:
            parsed, raw, usage, elapsed = call_cloudflare(account, token, case)
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
            item["error"] = f"{type(exc).__name__}:{str(exc)[:700]}"
        results.append(item)

    matched = sum(1 for item in results if item.get("matches_expected") is True)
    transport_passed = sum(1 for item in results if item.get("transport_status") == "PASS")
    passed = matched == len(CALIBRATION) and transport_passed == len(CALIBRATION)
    payload = {
        "schema": "S26_REMOTE_SEMANTIC_JUDGE_CHALLENGER_CALIBRATION_V1",
        "strategy": "S26",
        "status": "CALIBRATION_PASS_CHALLENGER_ONLY" if passed else "FAIL_CLOSED",
        "provider": "cloudflare_workers_ai",
        "protocol": PROTOCOL,
        "primary_model": PRIMARY_MODEL,
        "judge_challenger_model": MODEL,
        "semantic_oracle_distinct": MODEL != PRIMARY_MODEL,
        "provider_infrastructure_shared": True,
        "full_independent_authority_proven": False,
        "calibration_frozen_before_output": True,
        "calibration_sha256": calibration_sha,
        "case_count": len(CALIBRATION),
        "transport_passed": transport_passed,
        "matched_expected": matched,
        "retries": 0,
        "neurons": round(total_neurons, 6),
        "prompt_tokens": total_prompt,
        "completion_tokens": total_completion,
        "cases": results,
        "authority_changed": False,
        "canonical_judge_authority": "QWEN2_5_VL_7B_Q4_K_M_UNCHANGED",
        "promotion_authorized": False,
        "production_mutation": False,
        "paid_fallback_used": False,
        "local_model_fallback_used": False,
        "model_download_executed": False,
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_REMOTE_JUDGE_CHALLENGER_CALIBRATION=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
    print("S26_REMOTE_JUDGE_CALIBRATION=" + ("PASS_CHALLENGER_ONLY" if passed else "FAIL_CLOSED"))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
