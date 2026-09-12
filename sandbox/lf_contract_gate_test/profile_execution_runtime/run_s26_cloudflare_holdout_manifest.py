#!/usr/bin/env python3
"""S26 Cloudflare Llama 3.3 qualification against the frozen canonical holdout gate.

Primary-worker transport only is replaced with Cloudflare Workers AI. The frozen
S26 three-case plan, canonical schema/gates, independent semantic mini-judge and
12-obligation manifest are loaded from the pinned S26 authority checkout.

Sandbox qualification only: no Worker deployment, routing change, production
mutation, paid fallback, downstream authorization or promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
EXPECTED_AUTHORITY_REF = "fcc2b0d57e36a31c26f38acc2510b193aac988c8"
MAX_OUTPUT_TOKENS = 512
REQUEST_TIMEOUT_SECONDS = 120
LLAMA_COMMIT = "925e1179947ea0c0ebfb0032df18af3a729822be"


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _cloudflare_request_completion(
    *,
    base_url: str,
    messages: list[dict[str, str]],
    generation_schema: dict[str, Any],
) -> tuple[dict[str, Any], str, str, float]:
    del base_url
    account_id = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    api_token = os.environ.get("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    if not account_id or not api_token:
        raise RuntimeError("CLOUDFLARE_REQUIRED_SECRET_MISSING")

    payload = {
        "messages": messages,
        "response_format": {"type": "json_schema", "json_schema": generation_schema},
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": MAX_OUTPUT_TOKENS,
    }
    url = f"https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/{MODEL}"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            envelope = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[-1200:].replace("\n", " ")
        raise RuntimeError(f"CLOUDFLARE_HTTP_ERROR status={exc.code} detail={detail}") from exc
    except Exception as exc:
        raise RuntimeError(f"CLOUDFLARE_TRANSPORT type={type(exc).__name__}") from exc
    elapsed_s = round(time.monotonic() - started, 3)

    root: Any = envelope.get("result") if isinstance(envelope, dict) else None
    if not isinstance(root, dict):
        raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
    response_value = root.get("response")
    if isinstance(response_value, dict) and response_value:
        raw = json.dumps(response_value, ensure_ascii=False, sort_keys=True)
    elif isinstance(response_value, str) and response_value.strip():
        raw = response_value.strip()
    else:
        raise RuntimeError("CLOUDFLARE_RESPONSE_EMPTY")
    usage = root.get("usage") if isinstance(root.get("usage"), dict) else {}
    normalized_envelope = {
        "usage": usage,
        "cloudflare_success": envelope.get("success") if isinstance(envelope, dict) else None,
    }
    return normalized_envelope, raw, str(root.get("finish_reason") or "stop"), elapsed_s


def _usage_totals(candidate_results: list[dict[str, Any]]) -> dict[str, Any]:
    calls = 0
    neurons = 0.0
    prompt_tokens = 0
    completion_tokens = 0
    total_tokens = 0
    for result in candidate_results:
        for key in ("initial_usage", "usage"):
            usage = result.get(key)
            if not isinstance(usage, dict) or not usage:
                continue
            calls += 1
            try:
                neurons += float(usage.get("neurons") or 0)
            except (TypeError, ValueError):
                pass
            for field, target in (
                ("prompt_tokens", "prompt_tokens"),
                ("completion_tokens", "completion_tokens"),
                ("total_tokens", "total_tokens"),
            ):
                value = usage.get(field)
                if isinstance(value, int) and not isinstance(value, bool):
                    if target == "prompt_tokens":
                        prompt_tokens += value
                    elif target == "completion_tokens":
                        completion_tokens += value
                    else:
                        total_tokens += value
    return {
        "inference_requests": calls,
        "neurons": round(neurons, 6),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": total_tokens,
        "retries": 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    authority_ref = os.environ.get("S26_AUTHORITY_REF", "").strip()
    authority_root_raw = os.environ.get("S26_AUTHORITY_ROOT", "").strip()
    if authority_ref != EXPECTED_AUTHORITY_REF:
        raise SystemExit(
            f"BLOCK S26_CLOUDFLARE_AUTHORITY_REF_MISMATCH expected={EXPECTED_AUTHORITY_REF} observed={authority_ref}"
        )
    if not authority_root_raw:
        raise SystemExit("BLOCK S26_CLOUDFLARE_AUTHORITY_ROOT_MISSING")
    if os.environ.get("LF_REPOSITORY_VISIBILITY", "").strip() != "public":
        raise SystemExit("BLOCK S26_CLOUDFLARE_HOLDOUT_ZERO_COST_VISIBILITY")
    if os.environ.get("LF_RUNNER_LABEL", "").strip() != "ubuntu-latest":
        raise SystemExit("BLOCK S26_CLOUDFLARE_HOLDOUT_ZERO_COST_RUNNER")
    if os.environ.get("LF_LLAMA_SOURCE_COMMIT", "").strip() != LLAMA_COMMIT:
        raise SystemExit("BLOCK S26_CLOUDFLARE_HOLDOUT_LLAMA_COMMIT_MISMATCH")

    authority_root = Path(authority_root_raw).resolve()
    runtime_dir = authority_root / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
    if not runtime_dir.is_dir():
        raise SystemExit("BLOCK S26_CLOUDFLARE_AUTHORITY_RUNTIME_MISSING")
    sys.path.insert(0, str(runtime_dir))

    import run_s26_primary_candidate_holdout_manifest as holdout  # noqa: E402

    plan = holdout._load_json(holdout.PLAN_PATH)
    manifest = holdout._load_json(holdout.MANIFEST_PATH)
    holdout._validate_frozen_plan(plan)
    holdout._validate_manifest(manifest)

    repository = holdout.base.RepositoryBindings(holdout.base.REPO_ROOT, max_prompt_chars=120_000)
    gates = holdout.base.OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = holdout.base.governed_generation_schema(
        schema_binding.payload,
        profile_slug="ui_architect",
        schema_mode="UI_FOCUSED_DECISION",
    )

    preflight = {
        "strategy": "S26",
        "provider": "cloudflare_workers_ai_native_rest_json_mode",
        "model": MODEL,
        "authority_ref": authority_ref,
        "plan_sha256": holdout._sha256_file(holdout.PLAN_PATH),
        "plan_git_blob_sha": holdout._git_blob_sha(holdout.PLAN_PATH),
        "manifest_sha256": holdout._sha256_file(holdout.MANIFEST_PATH),
        "manifest_git_blob_sha": holdout._git_blob_sha(holdout.MANIFEST_PATH),
        "holdout_case_count": len(plan["cases"]),
        "manifest_obligation_count": len(manifest["obligations"]),
        "max_cloudflare_inference_requests": 6,
        "candidate_model_downloaded": False,
        "candidate_model_release_required": False,
        "worker_deployed": False,
        "routing_changed": False,
        "production_mutation": False,
        "promotion_authorized": False,
        "paid_fallback_used": False,
    }
    print("S26_CLOUDFLARE_HOLDOUT_PREFLIGHT=" + json.dumps(preflight, sort_keys=True), flush=True)

    candidate_results: list[dict[str, Any]] = []
    original_request_completion = holdout.base.request_completion
    holdout.base.request_completion = _cloudflare_request_completion
    try:
        for case in plan["cases"]:
            candidate_results.append(
                holdout._run_candidate_case(
                    case=case,
                    base_url="cloudflare://workers-ai",
                    schema_binding=schema_binding,
                    generation_schema=generation_schema,
                    gates=gates,
                )
            )
    finally:
        holdout.base.request_completion = original_request_completion

    candidate_nominal = (
        len(candidate_results) == 3
        and all(item.get("execution_status") == "COMPLETED" for item in candidate_results)
        and all(item.get("contract_gate", {}).get("status") == "PASS" for item in candidate_results)
        and all(item.get("semantic_gate", {}).get("status") == "PASS" for item in candidate_results)
    )

    judge_checks: list[dict[str, Any]] = []
    manifest_checks: list[dict[str, Any]] = []
    judge_error: str | None = None
    judge_binding = {
        "model_id": holdout.SEMANTIC_MODEL_ID,
        "model_sha256": holdout.SEMANTIC_MODEL_SHA256,
    }

    if candidate_nominal:
        try:
            judge_path = holdout._acquire_independent_judge()
            os.environ["LF_SEMANTIC_MODEL_PATH"] = str(judge_path)
            verifier = holdout.GitHubHostedSemanticMiniJudgeVerifier()
            case_by_id = {
                str(case["case_id"]): case for case in plan["cases"] if isinstance(case, dict)
            }
            result_by_id = {
                str(result["case_id"]): result
                for result in candidate_results
                if isinstance(result, dict) and result.get("case_id")
            }
            work_root = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
            with holdout.GitHubHostedSemanticMiniJudge(
                work_dir=work_root / "s26-cloudflare-holdout-independent-judge"
            ) as judge:
                for case_id in sorted(case_by_id):
                    case = case_by_id[case_id]
                    result = result_by_id[case_id]
                    evidence = holdout._case_evidence(case, result)
                    for check in case["judge_checks"]:
                        judged = holdout._judge_one(
                            judge=judge,
                            verifier=verifier,
                            check_id=str(check["check_id"]),
                            rule=str(check["rule"]),
                            question=str(check["question"]),
                            evidence=evidence,
                        )
                        judged["case_id"] = case_id
                        judge_checks.append(judged)

                witness_case = case_by_id["S26_HOLDOUT_PAYMENT_SELECTION"]
                witness_result = result_by_id["S26_HOLDOUT_PAYMENT_SELECTION"]
                witness_evidence = holdout._case_evidence(witness_case, witness_result)
                for obligation in manifest["obligations"]:
                    check_id = str(obligation["check_id"])
                    if check_id == holdout.ROUTER_DIRECT_CHECK_ID:
                        manifest_checks.append(
                            {
                                "obligation_id": obligation["obligation_id"],
                                "check_id": check_id,
                                "verdict": "NOT_APPLICABLE",
                                "reason_code": "NO_ROUTER_DIRECT_COUNTERPART_OR_CONSISTENCY_CLAIM_IN_BOUNDED_WITNESS",
                                "verification": {
                                    "verified": True,
                                    "method": "DETERMINISTIC_APPLICABILITY_FROM_FROZEN_BENCHMARK_INPUT",
                                },
                                "rule_sha256": _sha256_text(str(obligation["rule"])),
                                "witness_case_id": witness_case["case_id"],
                            }
                        )
                        continue
                    judged = holdout._judge_one(
                        judge=judge,
                        verifier=verifier,
                        check_id=check_id,
                        rule=str(obligation["rule"]),
                        question=str(obligation["question"]),
                        evidence=witness_evidence,
                    )
                    judged["obligation_id"] = obligation["obligation_id"]
                    judged["witness_case_id"] = witness_case["case_id"]
                    manifest_checks.append(judged)
        except Exception as exc:
            judge_error = f"{type(exc).__name__}:{str(exc)[:1000]}"

    holdout_judge_pass = (
        len(judge_checks) == 12
        and all(item.get("verdict") == "COMPLIES" for item in judge_checks)
        and all(item.get("verification", {}).get("verified") is True for item in judge_checks)
    )
    manifest_check_ids = [str(item.get("check_id") or "") for item in manifest_checks]
    required_manifest_check_ids = [str(item["check_id"]) for item in manifest["obligations"]]
    manifest_coverage_complete = (
        len(manifest_checks) == 12
        and len(set(manifest_check_ids)) == 12
        and set(manifest_check_ids) == set(required_manifest_check_ids)
    )
    manifest_semantic_pass = (
        manifest_coverage_complete
        and all(
            (
                item.get("verdict") == "COMPLIES"
                and item.get("verification", {}).get("verified") is True
            )
            or (
                item.get("check_id") == holdout.ROUTER_DIRECT_CHECK_ID
                and item.get("verdict") == "NOT_APPLICABLE"
                and item.get("verification", {}).get("verified") is True
            )
            for item in manifest_checks
        )
    )
    complete_profile_obligation_manifest_executed = candidate_nominal and manifest_semantic_pass
    overall_pass = (
        candidate_nominal
        and holdout_judge_pass
        and complete_profile_obligation_manifest_executed
        and judge_error is None
    )

    payload = {
        "result_schema": "S26_CLOUDFLARE_HOLDOUT_MANIFEST_V1",
        "status": "PASS" if overall_pass else "FAIL_CLOSED",
        "strategy": "S26",
        "evaluation_scope": "FROZEN_THREE_CASE_HOLDOUT_PLUS_PREBOUND_PROFILE_OBLIGATION_MANIFEST_BOUNDED_WITNESS",
        "evidence_ceiling": "CANDIDATE_CAPABILITY_ONLY_NOT_OPERATIONAL_PARITY_OR_PROFILE_GENERALIZATION",
        "candidate_binding": {
            "provider": "cloudflare_workers_ai_native_rest_json_mode",
            "model": MODEL,
            "authority_ref": authority_ref,
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_sha": os.environ.get("GITHUB_SHA", ""),
            "generation_schema_policy": generation_policy,
            "max_output_tokens": MAX_OUTPUT_TOKENS,
            "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
            "temperature": 0,
            "top_p": 1,
            "seed": 42,
        },
        "frozen_plan_binding": {
            "path": str(holdout.PLAN_PATH.relative_to(holdout.base.REPO_ROOT)),
            "sha256": preflight["plan_sha256"],
            "git_blob_sha": preflight["plan_git_blob_sha"],
            "case_ids": sorted(holdout.EXPECTED_CASE_IDS),
        },
        "manifest_binding": {
            "path": str(holdout.MANIFEST_PATH.relative_to(holdout.base.REPO_ROOT)),
            "sha256": preflight["manifest_sha256"],
            "git_blob_sha": preflight["manifest_git_blob_sha"],
            "obligation_count": len(manifest["obligations"]),
            "required_check_ids": required_manifest_check_ids,
        },
        "candidate_results": candidate_results,
        "cloudflare_usage_totals": _usage_totals(candidate_results),
        "candidate_nominal": candidate_nominal,
        "holdout_independent_checks": judge_checks,
        "holdout_judge_status": "PASS" if holdout_judge_pass else "FAIL",
        "manifest_checks": manifest_checks,
        "manifest_coverage_complete": manifest_coverage_complete,
        "manifest_semantic_status": "PASS" if manifest_semantic_pass else "FAIL",
        "complete_profile_obligation_manifest_executed": complete_profile_obligation_manifest_executed,
        "manifest_execution_scope": "ONE_FRESH_PAYMENT_SELECTION_HOLDOUT_WITNESS_NO_PROFILE_GENERALIZATION",
        "judge_binding": judge_binding,
        "judge_error": judge_error,
        "candidate_model_downloaded": False,
        "candidate_model_release_required": False,
        "operational_parity": False,
        "downstream_authorized": False,
        "authority_changed": False,
        "worker_deployed": False,
        "routing_changed": False,
        "production_mutation": False,
        "promotion_authorized": False,
        "paid_provider_call_executed": False,
        "paid_fallback_used": False,
        "api_cost_incurred": False,
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(
        json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print("S26_CLOUDFLARE_HOLDOUT_MANIFEST=" + json.dumps(payload, ensure_ascii=False, sort_keys=True), flush=True)
    if overall_pass:
        print("S26_CLOUDFLARE_HOLDOUT_MANIFEST_PASS_NO_PROMOTION", flush=True)
    else:
        print("S26_CLOUDFLARE_HOLDOUT_MANIFEST_FAIL_CLOSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
