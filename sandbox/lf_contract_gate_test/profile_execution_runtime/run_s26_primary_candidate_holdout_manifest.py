#!/usr/bin/env python3
"""S26 fresh holdout + prebound semantic-obligation manifest qualification.

Sandbox-only candidate evidence. This runner:
- executes the frozen 3-case candidate-specific holdout/adversarial plan;
- uses the current zero-cost Qwen3.5-4B primary candidate;
- releases that model before acquiring the independent semantic judge;
- executes the frozen UI Architect semantic-obligation manifest against one
  fresh holdout witness while preserving the bounded evidence ceiling.

It cannot authorize promotion, production, runtime routing, profile mutation,
or operational parity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import resource
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

import run_s26_zero_cost_primary_candidate as base
from github_actions_semantic_judge import (
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
    SEMANTIC_MODEL_ID,
    SEMANTIC_MODEL_SHA256,
)

PLAN_PATH = Path(__file__).with_name("s26_primary_candidate_holdout_plan_v1.json")
MANIFEST_PATH = Path(__file__).with_name("s26_ui_architect_semantic_obligation_manifest_v1.json")

JUDGE_REPO = "ggml-org/Qwen2.5-VL-7B-Instruct-GGUF"
JUDGE_COMMIT = "508edd0afaa66bb9e9f40587acc2184f02daf1f6"
JUDGE_FILENAME = "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
JUDGE_SHA256 = "9258bf05b12686d097ff3b6b18d968ab393649780aa2b3cd67fec43d50554392"

EXPECTED_CASE_IDS = {
    "S26_HOLDOUT_PAYMENT_SELECTION",
    "S26_HOLDOUT_SEARCH_LOADING",
    "S26_ADVERSARIAL_STATUS_OVERFLOW",
}
EXPECTED_MANIFEST_SCHEMA = "S26_UI_ARCHITECT_SEMANTIC_OBLIGATION_MANIFEST_V1"
EXPECTED_PLAN_SCHEMA = "S26_PRIMARY_CANDIDATE_HOLDOUT_PLAN_V1"
ROUTER_DIRECT_CHECK_ID = "S26_MANIFEST_ROUTER_DIRECT_CONSISTENCY"


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _git_blob_sha(path: Path) -> str:
    return subprocess.check_output(
        ["git", "hash-object", str(path)],
        cwd=base.REPO_ROOT,
        text=True,
    ).strip()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"INVALID_JSON:{path.name}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON_ROOT_NOT_OBJECT:{path.name}")
    return value


def _validate_frozen_plan(plan: dict[str, Any]) -> None:
    if plan.get("schema") != EXPECTED_PLAN_SCHEMA:
        raise RuntimeError("HOLDOUT_PLAN_SCHEMA_MISMATCH")
    if plan.get("strategy") != "S26":
        raise RuntimeError("HOLDOUT_PLAN_STRATEGY_MISMATCH")
    if plan.get("frozen_before_any_holdout_output") is not True:
        raise RuntimeError("HOLDOUT_PLAN_NOT_FROZEN")
    if plan.get("tuning_from_holdout_output_forbidden") is not True:
        raise RuntimeError("HOLDOUT_TUNING_GUARD_MISSING")
    if plan.get("automatic_promotion_authorized") is not False:
        raise RuntimeError("HOLDOUT_PLAN_SCOPE_ESCALATION")
    cases = plan.get("cases")
    if not isinstance(cases, list) or len(cases) != 3:
        raise RuntimeError("HOLDOUT_PLAN_CASE_COUNT_MISMATCH")
    case_ids = [str(item.get("case_id") or "") for item in cases if isinstance(item, dict)]
    if set(case_ids) != EXPECTED_CASE_IDS or len(case_ids) != len(set(case_ids)):
        raise RuntimeError("HOLDOUT_PLAN_CASE_IDS_MISMATCH")
    check_ids: list[str] = []
    for case in cases:
        checks = case.get("judge_checks")
        if not isinstance(checks, list) or len(checks) != 4:
            raise RuntimeError(f"HOLDOUT_CASE_CHECK_COUNT_MISMATCH:{case.get('case_id')}")
        for check in checks:
            if not isinstance(check, dict) or not check.get("check_id"):
                raise RuntimeError("HOLDOUT_CHECK_INVALID")
            check_ids.append(str(check["check_id"]))
    if len(check_ids) != len(set(check_ids)):
        raise RuntimeError("HOLDOUT_CHECK_IDS_NOT_UNIQUE")


def _validate_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("schema") != EXPECTED_MANIFEST_SCHEMA:
        raise RuntimeError("MANIFEST_SCHEMA_MISMATCH")
    if manifest.get("strategy") != "S26" or manifest.get("profile") != "ui_architect":
        raise RuntimeError("MANIFEST_TARGET_MISMATCH")
    if manifest.get("output_mode") != "UI_FOCUSED_DECISION":
        raise RuntimeError("MANIFEST_OUTPUT_MODE_MISMATCH")
    if manifest.get("frozen_before_manifest_execution") is not True:
        raise RuntimeError("MANIFEST_NOT_FROZEN")
    if manifest.get("automatic_promotion_authorized") is not False:
        raise RuntimeError("MANIFEST_SCOPE_ESCALATION")
    sources = manifest.get("authoritative_sources")
    if not isinstance(sources, list) or not sources:
        raise RuntimeError("MANIFEST_SOURCES_MISSING")
    for source in sources:
        if not isinstance(source, dict):
            raise RuntimeError("MANIFEST_SOURCE_INVALID")
        path = base.REPO_ROOT / str(source.get("path") or "")
        expected = str(source.get("blob_sha") or "")
        if not path.is_file() or not expected:
            raise RuntimeError(f"MANIFEST_SOURCE_UNREADABLE:{source.get('path')}")
        observed = _git_blob_sha(path)
        if observed != expected:
            raise RuntimeError(
                f"MANIFEST_SOURCE_BLOB_MISMATCH:{source.get('path')}:{expected}:{observed}"
            )
    obligations = manifest.get("obligations")
    if not isinstance(obligations, list) or len(obligations) != 12:
        raise RuntimeError("MANIFEST_OBLIGATION_COUNT_MISMATCH")
    obligation_ids = [str(item.get("obligation_id") or "") for item in obligations if isinstance(item, dict)]
    check_ids = [str(item.get("check_id") or "") for item in obligations if isinstance(item, dict)]
    if len(obligation_ids) != 12 or any(not value for value in obligation_ids):
        raise RuntimeError("MANIFEST_OBLIGATION_ID_MISSING")
    if len(check_ids) != 12 or any(not value for value in check_ids):
        raise RuntimeError("MANIFEST_CHECK_ID_MISSING")
    if len(set(obligation_ids)) != 12 or len(set(check_ids)) != 12:
        raise RuntimeError("MANIFEST_MAPPING_NOT_ONE_TO_ONE")
    if ROUTER_DIRECT_CHECK_ID not in set(check_ids):
        raise RuntimeError("MANIFEST_ROUTER_DIRECT_CHECK_MISSING")


def _case_system_prompt(case: dict[str, Any]) -> str:
    facts = case.get("governed_facts") or []
    quality = case.get("quality_requirements") or []
    return "\n".join(
        [
            "SANDBOX PRIMARY-WORKER HOLDOUT QUALIFICATION ONLY.",
            "Use only the governed facts below. Do not invent authority, tokens, controls, business rules, dimensions, timing, percentages or quantities not explicitly supplied.",
            "Return exactly one naked JSON object satisfying the supplied Focused UI Decision schema. No prose or Markdown.",
            "Keep status sandbox/read-only appropriate. This output cannot authorize promotion, runtime routing, production, or profile mutation.",
            "GOVERNED FACTS:",
            *[f"- {item}" for item in facts],
            "QUALITY REQUIREMENTS:",
            *[f"- {item}" for item in quality],
        ]
    )


def _case_revision_prompt(case: dict[str, Any], gate_codes: list[str]) -> str:
    review = case.get("declared_review_requirements") or []
    return "\n".join(
        [
            "Execute one and only one declared contract-review pass over the exact prior RAW.",
            "Re-evaluate the prior decision against every governed fact and quality requirement. Correct the underlying decision, not merely a gate label.",
            "Do not add facts, quantities, tokens, controls, business rules or authority absent from the frozen case.",
            "Return one new naked JSON object only. The prior RAW remains evidence. No promotion is authorized.",
            "DECLARED REVIEW REQUIREMENTS:",
            *[f"- {item}" for item in review],
            "MACHINE GATE CODES FROM PRIOR RAW:",
            json.dumps(gate_codes, ensure_ascii=False, sort_keys=True),
        ]
    )


def _run_candidate_case(
    *,
    case: dict[str, Any],
    base_url: str,
    schema_binding: Any,
    generation_schema: dict[str, Any],
    gates: Any,
) -> dict[str, Any]:
    case_id = str(case["case_id"])
    system_prompt = _case_system_prompt(case)
    task = str(case.get("task") or "")
    started = time.monotonic()
    result: dict[str, Any] = {
        "case_id": case_id,
        "kind": case.get("kind"),
        "task_sha256": _sha256_text(task),
        "governed_facts_sha256": _sha256_text(
            json.dumps(case.get("governed_facts") or [], ensure_ascii=False, sort_keys=True)
        ),
        "quality_requirements_sha256": _sha256_text(
            json.dumps(case.get("quality_requirements") or [], ensure_ascii=False, sort_keys=True)
        ),
    }
    try:
        initial_envelope, initial_raw, initial_finish_reason, initial_elapsed_s = base.request_completion(
            base_url=base_url,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": task},
            ],
            generation_schema=generation_schema,
        )
        initial_contract, initial_parsed = gates.contract(
            profile_slug="ui_architect",
            raw_output=initial_raw,
            schema=schema_binding,
        )
        initial_semantic = gates.semantic_utility(
            profile_slug="ui_architect",
            payload=initial_parsed,
            contract_gate=initial_contract,
        )
        gate_codes = sorted(
            set(
                list(initial_contract.get("blocking_codes") or [])
                + list(initial_semantic.get("blocking_codes") or [])
            )
        )
        revision_request = _case_revision_prompt(case, gate_codes)
        envelope, raw, finish_reason, revision_elapsed_s = base.request_completion(
            base_url=base_url,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": task},
                {"role": "assistant", "content": initial_raw},
                {"role": "user", "content": revision_request},
            ],
            generation_schema=generation_schema,
        )
        contract, parsed = gates.contract(
            profile_slug="ui_architect",
            raw_output=raw,
            schema=schema_binding,
        )
        semantic = gates.semantic_utility(
            profile_slug="ui_architect",
            payload=parsed,
            contract_gate=contract,
        )
        result.update(
            {
                "execution_status": "COMPLETED",
                "initial_elapsed_s": initial_elapsed_s,
                "revision_elapsed_s": revision_elapsed_s,
                "elapsed_s": round(initial_elapsed_s + revision_elapsed_s, 3),
                "initial_finish_reason": initial_finish_reason,
                "finish_reason": finish_reason,
                "initial_usage": initial_envelope.get("usage") if isinstance(initial_envelope.get("usage"), dict) else {},
                "usage": envelope.get("usage") if isinstance(envelope.get("usage"), dict) else {},
                "initial_contract_gate": initial_contract,
                "initial_semantic_gate": initial_semantic,
                "initial_raw_output": initial_raw,
                "initial_raw_output_sha256": _sha256_text(initial_raw),
                "revision_gate_trigger_codes": gate_codes,
                "contract_gate": contract,
                "semantic_gate": semantic,
                "raw_output": raw,
                "raw_output_sha256": _sha256_text(raw),
                "output": parsed if isinstance(parsed, dict) else None,
            }
        )
    except Exception as exc:
        result.update(
            {
                "execution_status": "FAIL_CLOSED",
                "error_type": type(exc).__name__,
                "error": str(exc)[:1000],
            }
        )
    result["wall_elapsed_s"] = round(time.monotonic() - started, 3)
    return result


def _acquire_independent_judge() -> Path:
    runner_temp = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    judge_dir = runner_temp / "lf-semantic-model"
    judge_dir.mkdir(parents=True, exist_ok=True)
    judge_path = judge_dir / "model.gguf"
    if judge_path.is_file() and _sha256_file(judge_path) == JUDGE_SHA256:
        return judge_path
    if judge_path.exists():
        judge_path.unlink()
    url = (
        f"https://huggingface.co/{JUDGE_REPO}/resolve/{JUDGE_COMMIT}/"
        f"{JUDGE_FILENAME}?download=true"
    )
    subprocess.run(
        [
            "curl",
            "-L",
            "--fail",
            "--retry",
            "5",
            "--retry-all-errors",
            "--retry-delay",
            "5",
            url,
            "-o",
            str(judge_path),
        ],
        check=True,
    )
    observed = _sha256_file(judge_path)
    if observed != JUDGE_SHA256:
        judge_path.unlink(missing_ok=True)
        raise RuntimeError(
            f"INDEPENDENT_JUDGE_SHA_MISMATCH expected={JUDGE_SHA256} observed={observed}"
        )
    return judge_path


def _judge_one(
    *,
    judge: Any,
    verifier: Any,
    check_id: str,
    rule: str,
    question: str,
    evidence: str,
) -> dict[str, Any]:
    check = {
        "check_id": check_id,
        "check_type": "SEMANTIC_RELATION",
        "rule": rule,
        "evidence": evidence,
        "question": question,
    }
    classification, execution_evidence = judge.classify(check)
    verification = verifier.verify(
        check=check,
        result=classification,
        evidence=execution_evidence,
        adapter=judge,
    )
    return {
        "check_id": check_id,
        "rule_sha256": _sha256_text(rule),
        "verdict": classification.verdict,
        "reason_code": classification.reason_code,
        "verification": verification,
        "execution_evidence": execution_evidence,
    }


def _case_evidence(case: dict[str, Any], candidate_result: dict[str, Any]) -> str:
    return json.dumps(
        {
            "case_id": case.get("case_id"),
            "kind": case.get("kind"),
            "task": case.get("task"),
            "governed_facts": case.get("governed_facts"),
            "quality_requirements": case.get("quality_requirements"),
            "candidate_output": candidate_result.get("output"),
        },
        ensure_ascii=False,
        sort_keys=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    if os.getenv("LF_REPOSITORY_VISIBILITY", "").strip() != "public":
        raise SystemExit("BLOCK S26_HOLDOUT_ZERO_COST_VISIBILITY")
    if os.getenv("LF_RUNNER_LABEL", "").strip() != "ubuntu-latest":
        raise SystemExit("BLOCK S26_HOLDOUT_ZERO_COST_RUNNER")
    if os.getenv("LF_LLAMA_SOURCE_COMMIT", "").strip() != base.LLAMA_COMMIT:
        raise SystemExit("BLOCK S26_HOLDOUT_LLAMA_COMMIT_MISMATCH")

    plan = _load_json(PLAN_PATH)
    manifest = _load_json(MANIFEST_PATH)
    _validate_frozen_plan(plan)
    _validate_manifest(manifest)

    candidate_head = base.exact_candidate_head()
    server = base.required_path("LF_LLAMA_SERVER_PATH")
    model = base.prepare_candidate_model()
    if not os.access(server, os.X_OK):
        raise SystemExit("BLOCK S26_HOLDOUT_SERVER_NOT_EXECUTABLE")
    observed_model_sha = base.sha256_file(model)
    if observed_model_sha != base.MODEL_SHA256:
        raise SystemExit("BLOCK S26_HOLDOUT_MODEL_SHA_MISMATCH")

    repository = base.RepositoryBindings(base.REPO_ROOT, max_prompt_chars=120_000)
    gates = base.OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = base.governed_generation_schema(
        schema_binding.payload,
        profile_slug="ui_architect",
        schema_mode="UI_FOCUSED_DECISION",
    )

    preflight = {
        "strategy": "S26",
        "candidate_code": base.CANDIDATE_CODE,
        "candidate_head": candidate_head,
        "model_id": base.MODEL_ID,
        "model_sha256": observed_model_sha,
        "model_bytes": model.stat().st_size,
        "prompt_policy": base.PROMPT_POLICY,
        "plan_sha256": _sha256_file(PLAN_PATH),
        "plan_git_blob_sha": _git_blob_sha(PLAN_PATH),
        "manifest_sha256": _sha256_file(MANIFEST_PATH),
        "manifest_git_blob_sha": _git_blob_sha(MANIFEST_PATH),
        "holdout_case_count": len(plan["cases"]),
        "manifest_obligation_count": len(manifest["obligations"]),
        "complete_profile_obligation_manifest_executed": False,
        "operational_parity": False,
        "promotion_authorized": False,
        "production_mutation": False,
        "paid_provider_call_executed": False,
        "api_cost_incurred": False,
    }
    print("S26_HOLDOUT_MANIFEST_PREFLIGHT=" + json.dumps(preflight, sort_keys=True), flush=True)

    candidate_mem_before = base._linux_meminfo_kib()
    candidate_server_started = time.monotonic()
    server_ready_elapsed_s: float | None = None
    candidate_results: list[dict[str, Any]] = []
    candidate_child_usage: dict[str, float | int] = {}
    candidate_model_released_after_run = False
    base_url = f"http://127.0.0.1:{base.PORT}"

    try:
        with tempfile.TemporaryDirectory(prefix="s26-holdout-candidate-") as td:
            work = Path(td)
            stdout_path = work / "llama.stdout.log"
            stderr_path = work / "llama.stderr.log"
            with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open(
                "w", encoding="utf-8"
            ) as stderr:
                process = subprocess.Popen(
                    [
                        str(server),
                        "-m",
                        str(model),
                        "--host",
                        "127.0.0.1",
                        "--port",
                        str(base.PORT),
                        "-c",
                        str(base.CONTEXT_TOKENS),
                        "-t",
                        "4",
                    ],
                    cwd=work,
                    stdin=subprocess.DEVNULL,
                    stdout=stdout,
                    stderr=stderr,
                    text=True,
                )
                try:
                    deadline = time.monotonic() + 120
                    while time.monotonic() < deadline:
                        if process.poll() is not None:
                            detail = stderr_path.read_text(
                                encoding="utf-8", errors="replace"
                            )[-1200:]
                            raise RuntimeError(
                                "HOLDOUT_CANDIDATE_SERVER_START_FAILED:"
                                + detail.replace("\n", " ")
                            )
                        if base.health_ready(base_url):
                            server_ready_elapsed_s = round(
                                time.monotonic() - candidate_server_started, 3
                            )
                            break
                        time.sleep(0.5)
                    else:
                        raise RuntimeError("HOLDOUT_CANDIDATE_SERVER_START_TIMEOUT")

                    for case in plan["cases"]:
                        candidate_results.append(
                            _run_candidate_case(
                                case=case,
                                base_url=base_url,
                                schema_binding=schema_binding,
                                generation_schema=generation_schema,
                                gates=gates,
                            )
                        )
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=8)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=5)
                    usage_snapshot = resource.getrusage(resource.RUSAGE_CHILDREN)
                    candidate_child_usage = {
                        "max_rss_kib": int(usage_snapshot.ru_maxrss),
                        "user_cpu_s": round(float(usage_snapshot.ru_utime), 3),
                        "system_cpu_s": round(float(usage_snapshot.ru_stime), 3),
                    }
    finally:
        try:
            candidate_model_released_after_run = base._release_candidate_model_after_run(model)
        except Exception as exc:
            print(
                "BLOCK S26_HOLDOUT_CANDIDATE_RELEASE_ERROR="
                + f"{type(exc).__name__}:{str(exc)[:500]}",
                flush=True,
            )
            candidate_model_released_after_run = False

    candidate_mem_after = base._linux_meminfo_kib()
    candidate_nominal = (
        len(candidate_results) == 3
        and all(item.get("execution_status") == "COMPLETED" for item in candidate_results)
        and all(item.get("contract_gate", {}).get("status") == "PASS" for item in candidate_results)
        and all(item.get("semantic_gate", {}).get("status") == "PASS" for item in candidate_results)
        and candidate_model_released_after_run
    )

    judge_checks: list[dict[str, Any]] = []
    manifest_checks: list[dict[str, Any]] = []
    judge_error: str | None = None
    judge_binding: dict[str, Any] = {
        "model_id": SEMANTIC_MODEL_ID,
        "model_sha256": SEMANTIC_MODEL_SHA256,
    }

    if candidate_nominal:
        try:
            judge_path = _acquire_independent_judge()
            os.environ["LF_SEMANTIC_MODEL_PATH"] = str(judge_path)
            verifier = GitHubHostedSemanticMiniJudgeVerifier()
            case_by_id = {
                str(case["case_id"]): case for case in plan["cases"] if isinstance(case, dict)
            }
            result_by_id = {
                str(result["case_id"]): result
                for result in candidate_results
                if isinstance(result, dict) and result.get("case_id")
            }
            work_root = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
            with GitHubHostedSemanticMiniJudge(
                work_dir=work_root / "s26-holdout-independent-judge"
            ) as judge:
                for case_id in sorted(case_by_id):
                    case = case_by_id[case_id]
                    result = result_by_id[case_id]
                    evidence = _case_evidence(case, result)
                    for check in case["judge_checks"]:
                        judged = _judge_one(
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
                witness_evidence = _case_evidence(witness_case, witness_result)
                for obligation in manifest["obligations"]:
                    check_id = str(obligation["check_id"])
                    if check_id == ROUTER_DIRECT_CHECK_ID:
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
                    judged = _judge_one(
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
                item.get("check_id") == ROUTER_DIRECT_CHECK_ID
                and item.get("verdict") == "NOT_APPLICABLE"
                and item.get("verification", {}).get("verified") is True
            )
            for item in manifest_checks
        )
    )
    complete_profile_obligation_manifest_executed = (
        candidate_nominal and manifest_semantic_pass
    )
    overall_pass = (
        candidate_nominal
        and holdout_judge_pass
        and complete_profile_obligation_manifest_executed
        and judge_error is None
    )

    payload = {
        "result_schema": "S26_PRIMARY_CANDIDATE_HOLDOUT_MANIFEST_V1",
        "status": "PASS" if overall_pass else "FAIL_CLOSED",
        "strategy": "S26",
        "evaluation_scope": "FRESH_THREE_CASE_HOLDOUT_PLUS_PREBOUND_PROFILE_OBLIGATION_MANIFEST_BOUNDED_WITNESS",
        "evidence_ceiling": "CANDIDATE_CAPABILITY_ONLY_NOT_OPERATIONAL_PARITY_OR_PROFILE_GENERALIZATION",
        "candidate_binding": {
            "candidate_code": base.CANDIDATE_CODE,
            "candidate_head": candidate_head,
            "github_run_id": os.getenv("GITHUB_RUN_ID", ""),
            "github_sha": os.getenv("GITHUB_SHA", ""),
            "model_id": base.MODEL_ID,
            "model_sha256": observed_model_sha,
            "model_bytes": preflight["model_bytes"],
            "prompt_policy": base.PROMPT_POLICY,
            "generation_schema_policy": generation_policy,
        },
        "frozen_plan_binding": {
            "path": str(PLAN_PATH.relative_to(base.REPO_ROOT)),
            "sha256": preflight["plan_sha256"],
            "git_blob_sha": preflight["plan_git_blob_sha"],
            "case_ids": sorted(EXPECTED_CASE_IDS),
        },
        "manifest_binding": {
            "path": str(MANIFEST_PATH.relative_to(base.REPO_ROOT)),
            "sha256": preflight["manifest_sha256"],
            "git_blob_sha": preflight["manifest_git_blob_sha"],
            "obligation_count": len(manifest["obligations"]),
            "required_check_ids": required_manifest_check_ids,
        },
        "candidate_results": candidate_results,
        "holdout_independent_checks": judge_checks,
        "holdout_judge_status": "PASS" if holdout_judge_pass else "FAIL",
        "manifest_checks": manifest_checks,
        "manifest_coverage_complete": manifest_coverage_complete,
        "manifest_semantic_status": "PASS" if manifest_semantic_pass else "FAIL",
        "complete_profile_obligation_manifest_executed": complete_profile_obligation_manifest_executed,
        "manifest_execution_scope": "ONE_FRESH_PAYMENT_SELECTION_HOLDOUT_WITNESS_NO_PROFILE_GENERALIZATION",
        "judge_binding": judge_binding,
        "judge_error": judge_error,
        "resource_readback": {
            "candidate_server_ready_elapsed_s": server_ready_elapsed_s,
            "candidate_child_process_resource_usage": candidate_child_usage,
            "runner_meminfo_before": candidate_mem_before,
            "runner_meminfo_after": candidate_mem_after,
            "candidate_model_released_after_run": candidate_model_released_after_run,
        },
        "operational_parity": False,
        "downstream_authorized": False,
        "authority_changed": False,
        "production_mutation": False,
        "promotion_authorized": False,
        "paid_provider_call_executed": False,
        "api_cost_incurred": False,
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(
        json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "S26_PRIMARY_CANDIDATE_HOLDOUT_MANIFEST="
        + json.dumps(
            {
                "status": payload["status"],
                "candidate_head": candidate_head,
                "holdout_judge_status": payload["holdout_judge_status"],
                "manifest_semantic_status": payload["manifest_semantic_status"],
                "complete_profile_obligation_manifest_executed": complete_profile_obligation_manifest_executed,
                "candidate_model_released_after_run": candidate_model_released_after_run,
                "result_path": str(args.result_path),
            },
            sort_keys=True,
        ),
        flush=True,
    )
    if overall_pass:
        print("S26_PRIMARY_CANDIDATE_HOLDOUT_MANIFEST_PASS_NO_PROMOTION", flush=True)
    else:
        print("S26_PRIMARY_CANDIDATE_HOLDOUT_MANIFEST_FAIL_CLOSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
