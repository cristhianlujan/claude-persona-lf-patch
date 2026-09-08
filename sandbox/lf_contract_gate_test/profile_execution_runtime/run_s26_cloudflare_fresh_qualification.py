#!/usr/bin/env python3
"""Fresh S26 Cloudflare primary-floor qualification: 3 frozen unseen cases, no tuning/retry."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
EXPECTED_AUTHORITY_REF = "fcc2b0d57e36a31c26f38acc2510b193aac988c8"
PLAN_NAME = "s26_cloudflare_fresh_canonical_plan_v1.json"
MAX_TOKENS = 512
TIMEOUT_SECONDS = 120
FORBIDDEN_PRIOR_CASES = {
    "S26_HOLDOUT_PAYMENT_SELECTION",
    "S26_HOLDOUT_SEARCH_LOADING",
    "S26_ADVERSARIAL_STATUS_OVERFLOW",
}


def sha_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_authority(root: Path):
    runtime = root / "sandbox/lf_contract_gate_test/profile_execution_runtime"
    sys.path.insert(0, str(runtime))
    path = runtime / "run_s26_zero_cost_primary_candidate.py"
    spec = importlib.util.spec_from_file_location("s26_frozen_authority", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("AUTHORITY_IMPORT_SPEC_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_plan(plan: dict[str, Any]) -> list[dict[str, Any]]:
    if plan.get("schema") != "S26_CLOUDFLARE_FRESH_CANONICAL_PLAN_V1":
        raise RuntimeError("FRESH_PLAN_SCHEMA_MISMATCH")
    if plan.get("strategy") != "S26" or plan.get("profile") != "ui_architect":
        raise RuntimeError("FRESH_PLAN_TARGET_MISMATCH")
    if plan.get("frozen_before_any_candidate_output") is not True:
        raise RuntimeError("FRESH_PLAN_NOT_FROZEN")
    if plan.get("tuning_from_candidate_output_forbidden") is not True:
        raise RuntimeError("FRESH_PLAN_TUNING_GUARD_MISSING")
    if plan.get("diagnostic_holdouts_reused") is not False:
        raise RuntimeError("FRESH_PLAN_REUSES_PRIOR_HOLDOUTS")
    if plan.get("qualification_calls_per_case") != 1:
        raise RuntimeError("FRESH_PLAN_CALL_COUNT_INVALID")
    if plan.get("automatic_promotion_authorized") is not False or plan.get("production_mutation_authorized") is not False:
        raise RuntimeError("FRESH_PLAN_SCOPE_ESCALATION")
    cases = plan.get("cases")
    if not isinstance(cases, list) or len(cases) != 3:
        raise RuntimeError("FRESH_PLAN_CASE_COUNT_MISMATCH")
    ids: list[str] = []
    obligation_ids: list[str] = []
    for case in cases:
        if not isinstance(case, dict):
            raise RuntimeError("FRESH_CASE_INVALID")
        case_id = str(case.get("case_id") or "")
        if not case_id or case_id in FORBIDDEN_PRIOR_CASES:
            raise RuntimeError("FRESH_CASE_ID_INVALID:" + case_id)
        ids.append(case_id)
        if not isinstance(case.get("governed_facts"), list) or not isinstance(case.get("quality_requirements"), list):
            raise RuntimeError("FRESH_CASE_CONTEXT_INVALID:" + case_id)
        obligations = case.get("obligations")
        if not isinstance(obligations, list) or len(obligations) != 4:
            raise RuntimeError("FRESH_CASE_OBLIGATION_COUNT:" + case_id)
        for obligation in obligations:
            oid = str(obligation.get("obligation_id") or "") if isinstance(obligation, dict) else ""
            if not oid:
                raise RuntimeError("FRESH_OBLIGATION_ID_MISSING:" + case_id)
            obligation_ids.append(oid)
    if len(ids) != len(set(ids)) or len(obligation_ids) != 12 or len(obligation_ids) != len(set(obligation_ids)):
        raise RuntimeError("FRESH_PLAN_UNIQUENESS_INVALID")
    return cases


def system_prompt(case: dict[str, Any]) -> str:
    return "\n".join([
        "S26 FRESH PRIMARY-WORKER QUALIFICATION ONLY.",
        "Use only the governed facts below. Do not invent authority, tokens, controls, business rules, dimensions, timing, percentages or quantities not explicitly supplied.",
        "Return exactly one naked JSON object satisfying the Focused UI Decision schema. No prose or Markdown.",
        "This is one-shot qualification: do not request or assume a revision pass.",
        "Keep status sandbox/read-only appropriate. This output cannot authorize promotion or production.",
        "GOVERNED FACTS:",
        *[f"- {item}" for item in case["governed_facts"]],
        "QUALITY REQUIREMENTS:",
        *[f"- {item}" for item in case["quality_requirements"]],
    ])


def call_cloudflare(*, account: str, token: str, schema: dict[str, Any], case: dict[str, Any]) -> tuple[str, dict[str, Any], float]:
    payload = {
        "messages": [
            {"role": "system", "content": system_prompt(case)},
            {"role": "user", "content": str(case["task"])},
        ],
        "response_format": {"type": "json_schema", "json_schema": schema},
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
        detail = exc.read().decode("utf-8", "replace")[-800:].replace("\n", " ")
        raise RuntimeError(f"CLOUDFLARE_HTTP_{exc.code}:{detail}") from exc
    except Exception as exc:
        raise RuntimeError("CLOUDFLARE_TRANSPORT_" + type(exc).__name__) from exc
    elapsed = round(time.monotonic() - started, 3)
    if not isinstance(envelope, dict) or envelope.get("success") is not True:
        raise RuntimeError("CLOUDFLARE_ENVELOPE_FAILURE")
    result = envelope.get("result")
    if not isinstance(result, dict):
        raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
    response_value = result.get("response")
    if isinstance(response_value, dict) and response_value:
        raw = json.dumps(response_value, ensure_ascii=False, sort_keys=True)
    elif isinstance(response_value, str) and response_value.strip():
        raw = response_value.strip()
    else:
        raise RuntimeError("CLOUDFLARE_RESPONSE_EMPTY")
    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
    return raw, usage, elapsed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    parser.add_argument("--plan-path", type=Path, default=Path(__file__).with_name(PLAN_NAME))
    args = parser.parse_args()

    authority_ref = os.getenv("S26_AUTHORITY_REF", "").strip()
    authority_root = Path(os.getenv("S26_AUTHORITY_ROOT", "")).resolve()
    account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if authority_ref != EXPECTED_AUTHORITY_REF or not authority_root.is_dir():
        raise SystemExit("S26_FRESH_BLOCK_AUTHORITY")
    if not account or not token:
        raise SystemExit("S26_FRESH_BLOCK_CLOUDFLARE_SECRET")

    plan = json.loads(args.plan_path.read_text(encoding="utf-8"))
    cases = validate_plan(plan)
    authority = load_authority(authority_root)
    repository = authority.RepositoryBindings(authority.REPO_ROOT, max_prompt_chars=120_000)
    gates = authority.OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = authority.governed_generation_schema(
        schema_binding.payload, profile_slug="ui_architect", schema_mode="UI_FOCUSED_DECISION"
    )

    results: list[dict[str, Any]] = []
    for case in cases:
        item: dict[str, Any] = {
            "case_id": case["case_id"],
            "kind": case["kind"],
            "task_sha256": sha_text(str(case["task"])),
            "transport_status": "NOT_EXECUTED",
            "json_status": "NOT_EVALUATED",
            "contract_status": "NOT_EVALUATED",
            "semantic_status": "NOT_EVALUATED",
            "independent_obligations_status": "NOT_EXECUTED_REQUIRES_SEPARATE_JUDGE",
        }
        try:
            raw, usage, elapsed = call_cloudflare(account=account, token=token, schema=generation_schema, case=case)
            item["transport_status"] = "PASS"
            item["elapsed_s"] = elapsed
            item["usage"] = usage
            item["raw_output_sha256"] = sha_text(raw)
            try:
                parsed_json = json.loads(raw)
                item["json_status"] = "PASS" if isinstance(parsed_json, dict) else "FAIL_NOT_OBJECT"
            except json.JSONDecodeError:
                item["json_status"] = "FAIL_INVALID_JSON"
            contract, parsed = gates.contract(profile_slug="ui_architect", raw_output=raw, schema=schema_binding)
            item["contract_gate"] = contract
            item["contract_status"] = contract.get("status")
            if item["json_status"] == "PASS":
                semantic = gates.semantic_utility(profile_slug="ui_architect", payload=parsed, contract_gate=contract)
                item["semantic_gate"] = semantic
                item["semantic_status"] = semantic.get("status")
        except Exception as exc:
            item["transport_status"] = "FAIL"
            item["transport_error"] = f"{type(exc).__name__}:{str(exc)[:800]}"
        results.append(item)

    primary_floor_pass = all(
        item.get("transport_status") == "PASS"
        and item.get("json_status") == "PASS"
        and item.get("contract_status") == "PASS"
        and item.get("semantic_status") == "PASS"
        for item in results
    )
    total_neurons = 0.0
    calls = 0
    for item in results:
        usage = item.get("usage")
        if isinstance(usage, dict):
            calls += 1
            try:
                total_neurons += float(usage.get("neurons") or 0)
            except (TypeError, ValueError):
                pass

    payload = {
        "schema": "S26_CLOUDFLARE_FRESH_PRIMARY_FLOOR_RESULT_V1",
        "status": "PRIMARY_FLOOR_PASS_INDEPENDENT_JUDGE_PENDING" if primary_floor_pass else "FAIL_CLOSED",
        "strategy": "S26",
        "provider": "cloudflare_workers_ai",
        "model": MODEL,
        "authority_ref": authority_ref,
        "plan_sha256": hashlib.sha256(args.plan_path.read_bytes()).hexdigest(),
        "generation_schema_policy": generation_policy,
        "qualification_calls": calls,
        "retries": 0,
        "neurons": round(total_neurons, 6),
        "cases": results,
        "primary_floor_pass": primary_floor_pass,
        "independent_judge": "NOT_EXECUTED_NO_DOWNLOAD_PATH_REQUIRED",
        "promotion_authorized": False,
        "production_mutation": False,
        "paid_fallback_used": False,
        "local_model_fallback_used": False,
    }
    args.result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_CLOUDFLARE_FRESH_RESULT=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
    print("FRESH_PRIMARY_FLOOR=" + ("PASS" if primary_floor_pass else "FAIL_CLOSED"))
    return 0 if primary_floor_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
