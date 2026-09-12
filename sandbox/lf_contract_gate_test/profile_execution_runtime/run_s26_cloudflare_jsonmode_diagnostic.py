#!/usr/bin/env python3
"""Diagnostic-only repeatability probe for S26 Cloudflare Llama JSON mode.

Re-executes the exact frozen PAYMENT_SELECTION case three times with the same
prompt/schema/temperature/seed and the same mandatory single review pass.
No prompt tuning, holdout edits, semantic-judge calls, promotion evidence or
production/routing changes are permitted. This probe exists only to separate
structured-output reliability from semantic capability after run 34171062395.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any

EXPECTED_AUTHORITY_REF = "fcc2b0d57e36a31c26f38acc2510b193aac988c8"
CASE_ID = "S26_HOLDOUT_PAYMENT_SELECTION"
REPETITIONS = 3


def _json_valid(raw: Any) -> bool:
    if not isinstance(raw, str) or not raw.strip():
        return False
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return False
    return isinstance(value, dict)


def _sha(raw: Any) -> str | None:
    if not isinstance(raw, str):
        return None
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    authority_ref = os.environ.get("S26_AUTHORITY_REF", "").strip()
    authority_root_raw = os.environ.get("S26_AUTHORITY_ROOT", "").strip()
    if authority_ref != EXPECTED_AUTHORITY_REF:
        raise SystemExit("BLOCK S26_JSONMODE_DIAGNOSTIC_AUTHORITY_REF_MISMATCH")
    if not authority_root_raw:
        raise SystemExit("BLOCK S26_JSONMODE_DIAGNOSTIC_AUTHORITY_ROOT_MISSING")
    if not os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip():
        raise SystemExit("BLOCK S26_JSONMODE_DIAGNOSTIC_ACCOUNT_MISSING")
    if not os.environ.get("CLOUDFLARE_AI_CANARY_TOKEN", "").strip():
        raise SystemExit("BLOCK S26_JSONMODE_DIAGNOSTIC_TOKEN_MISSING")

    # Import the branch adapter first, then pin all frozen holdout logic to the
    # authority checkout. No prompt/schema content is copied or modified here.
    import run_s26_cloudflare_holdout_manifest as cf  # noqa: E402

    authority_root = Path(authority_root_raw).resolve()
    runtime_dir = authority_root / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
    if not runtime_dir.is_dir():
        raise SystemExit("BLOCK S26_JSONMODE_DIAGNOSTIC_RUNTIME_MISSING")
    sys.path.insert(0, str(runtime_dir))
    import run_s26_primary_candidate_holdout_manifest as holdout  # noqa: E402

    plan = holdout._load_json(holdout.PLAN_PATH)
    holdout._validate_frozen_plan(plan)
    case = next((item for item in plan["cases"] if item.get("case_id") == CASE_ID), None)
    if not isinstance(case, dict):
        raise SystemExit("BLOCK S26_JSONMODE_DIAGNOSTIC_CASE_MISSING")

    repository = holdout.base.RepositoryBindings(holdout.base.REPO_ROOT, max_prompt_chars=120_000)
    gates = holdout.base.OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = holdout.base.governed_generation_schema(
        schema_binding.payload,
        profile_slug="ui_architect",
        schema_mode="UI_FOCUSED_DECISION",
    )

    results: list[dict[str, Any]] = []
    original_request_completion = holdout.base.request_completion
    holdout.base.request_completion = cf._cloudflare_request_completion
    try:
        for index in range(1, REPETITIONS + 1):
            result = holdout._run_candidate_case(
                case=case,
                base_url="cloudflare://workers-ai",
                schema_binding=schema_binding,
                generation_schema=generation_schema,
                gates=gates,
            )
            results.append(
                {
                    "iteration": index,
                    "execution_status": result.get("execution_status"),
                    "initial_elapsed_s": result.get("initial_elapsed_s"),
                    "revision_elapsed_s": result.get("revision_elapsed_s"),
                    "elapsed_s": result.get("elapsed_s"),
                    "initial_json_valid": _json_valid(result.get("initial_raw_output")),
                    "final_json_valid": _json_valid(result.get("raw_output")),
                    "initial_raw_output_sha256": _sha(result.get("initial_raw_output")),
                    "final_raw_output_sha256": _sha(result.get("raw_output")),
                    "initial_contract_status": (result.get("initial_contract_gate") or {}).get("status"),
                    "initial_contract_blockers": (result.get("initial_contract_gate") or {}).get("blocking_codes") or [],
                    "initial_semantic_status": (result.get("initial_semantic_gate") or {}).get("status"),
                    "initial_semantic_blockers": (result.get("initial_semantic_gate") or {}).get("blocking_codes") or [],
                    "revision_gate_trigger_codes": result.get("revision_gate_trigger_codes") or [],
                    "final_contract_status": (result.get("contract_gate") or {}).get("status"),
                    "final_contract_blockers": (result.get("contract_gate") or {}).get("blocking_codes") or [],
                    "final_semantic_status": (result.get("semantic_gate") or {}).get("status"),
                    "final_semantic_blockers": (result.get("semantic_gate") or {}).get("blocking_codes") or [],
                    "initial_usage": result.get("initial_usage") or {},
                    "revision_usage": result.get("usage") or {},
                }
            )
    finally:
        holdout.base.request_completion = original_request_completion

    summary = {
        "repetitions": REPETITIONS,
        "initial_json_valid": sum(1 for item in results if item["initial_json_valid"]),
        "final_json_valid": sum(1 for item in results if item["final_json_valid"]),
        "initial_contract_pass": sum(1 for item in results if item["initial_contract_status"] == "PASS"),
        "initial_semantic_pass": sum(1 for item in results if item["initial_semantic_status"] == "PASS"),
        "final_contract_pass": sum(1 for item in results if item["final_contract_status"] == "PASS"),
        "final_semantic_pass": sum(1 for item in results if item["final_semantic_status"] == "PASS"),
        "distinct_initial_raw": len({item["initial_raw_output_sha256"] for item in results}),
        "distinct_final_raw": len({item["final_raw_output_sha256"] for item in results}),
    }
    payload = {
        "result_schema": "S26_CLOUDFLARE_JSONMODE_DIAGNOSTIC_V1",
        "strategy": "S26",
        "scope": "DIAGNOSTIC_ONLY_CONTAMINATED_HOLDOUT_NOT_PROMOTION_EVIDENCE",
        "case_id": CASE_ID,
        "authority_ref": authority_ref,
        "provider": "cloudflare_workers_ai_native_rest_json_mode",
        "model": cf.MODEL,
        "generation_schema_policy": generation_policy,
        "prompt_tuning_applied": False,
        "holdout_modified": False,
        "judge_executed": False,
        "production_mutation": False,
        "routing_changed": False,
        "promotion_authorized": False,
        "results": results,
        "summary": summary,
    }
    args.result_path.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("S26_CLOUDFLARE_JSONMODE_DIAGNOSTIC=" + json.dumps(payload, ensure_ascii=False, sort_keys=True), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
