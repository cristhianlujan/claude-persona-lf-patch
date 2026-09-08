#!/usr/bin/env python3
"""Canonical S26 profile manifest/receipt/parity gate over Cloudflare Workers AI.

Flow:
direct counterpart -> prebind PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1 ->
Router-bound canonical profile runtime -> PROFILE_EXECUTION_RECEIPT_V1 ->
derived PROFILE_SEMANTIC_CHECK_BUNDLE_V2 -> Nemotron semantic authority ->
PROFILE_SEMANTIC_JUDGE_RECEIPT_V2 -> authorize_downstream -> parity readback.

The gate is sandbox/read-only evidence. It never authorizes Golden or production.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
RUNTIME_DIR = REPO_ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime"
sys.path.insert(0, str(RUNTIME_DIR))
sys.path.insert(0, str(REPO_ROOT / "services/profile_runtime_api"))

from cloudflare_workers_ai_profile_runtime import (
    MODEL_ID as PRIMARY_MODEL_ID,
    CloudflareWorkersAIProfileAdapter,
    CloudflareWorkersAIProfileReadbackVerifier,
)
from github_actions_semantic_judge import (
    SEMANTIC_MODEL_ID,
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
)
from profile_runtime_api.llama import governed_generation_schema
from profile_runtime_api.repository import RepositoryBindings
from profile_runtime_api.validation import OutputGates
from profile_runtime_runner import execute_profile_runtime
from semantic_mini_judge import (
    build_receipt as build_semantic_receipt,
    partition_checks,
    validate_bundle,
)
from semantic_obligation_manifest import (
    build_check_bundle,
    obligation_manifest_sha256,
    validate_obligation_manifest,
)
from validate_profile_execution import (
    authorize_downstream,
    canonical_json_sha256,
    sha256_text,
)

PLAN_PATH = RUNTIME_DIR / "s26_canonical_profile_gate_plan_v1.json"
FROZEN_MANIFEST_PATH = RUNTIME_DIR / "s26_ui_architect_semantic_obligation_manifest_v1.json"
ROUTE_PATH = RUNTIME_DIR / "s26_runtime_route_v1.json"
ADAPTER_CAPSULE_PATH = REPO_ROOT / "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml"
PROFILE_SOURCE_PATHS = (
    "profiles/ui_architect/SKILL.md",
    "profiles/ui_architect/judges/ui_architect_mini_judge.md",
    "profiles/ui_architect/judges/ui_architect_semantic_judge.md",
)
PROFILE_CODE = "PERFIL-UI-ARCHITECT"
PROFILE_SLUG = "ui_architect"
SCHEMA_MODE = "UI_FOCUSED_DECISION"
ROUTER_CHECK_ID = "S26_MANIFEST_ROUTER_DIRECT_CONSISTENCY"


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON_ROOT_NOT_OBJECT:{path}")
    return value


def _profile_sources(repository: RepositoryBindings) -> list[dict[str, str]]:
    return repository.profile_sources(PROFILE_SLUG, list(PROFILE_SOURCE_PATHS))


def _profile_source_sha(sources: list[dict[str, str]]) -> str:
    manifest = [
        {"ref": item["ref"], "content_sha256": sha256_text(item["content"])}
        for item in sorted(sources, key=lambda item: item["ref"])
    ]
    return canonical_json_sha256(manifest)


def _input_literal(plan: dict[str, Any]) -> str:
    task = str(plan.get("task") or "").strip()
    facts = plan.get("governed_facts")
    requirements = plan.get("quality_requirements")
    if not task or not isinstance(facts, list) or not facts:
        raise RuntimeError("PLAN_TASK_OR_FACTS_INVALID")
    if not isinstance(requirements, list) or not requirements:
        raise RuntimeError("PLAN_REQUIREMENTS_INVALID")
    lines = [
        "S26 CANONICAL FRESH SANDBOX CASE.",
        f"TASK: {task}",
        "GOVERNED FACTS:",
        *[f"- {str(item)}" for item in facts],
        "QUALITY REQUIREMENTS:",
        *[f"- {str(item)}" for item in requirements],
        "Return only the Focused UI Decision JSON object. No prose or Markdown.",
    ]
    return "\n".join(lines)


def _validate_plan(plan: dict[str, Any]) -> None:
    if plan.get("schema") != "S26_CANONICAL_PROFILE_GATE_PLAN_V1":
        raise RuntimeError("PLAN_SCHEMA_INVALID")
    if plan.get("strategy") != "S26" or plan.get("profile") != PROFILE_SLUG:
        raise RuntimeError("PLAN_TARGET_INVALID")
    if plan.get("frozen_before_candidate_output") is not True:
        raise RuntimeError("PLAN_NOT_FROZEN")
    if plan.get("diagnostic_holdouts_reused") is not False:
        raise RuntimeError("PLAN_REUSES_DIAGNOSTIC_HOLDOUT")
    if plan.get("tuning_from_candidate_output_forbidden") is not True:
        raise RuntimeError("PLAN_TUNING_GUARD_MISSING")
    if plan.get("production_mutation_authorized") is not False:
        raise RuntimeError("PLAN_PRODUCTION_SCOPE_ESCALATION")
    if plan.get("golden_promotion_authorized") is not False:
        raise RuntimeError("PLAN_GOLDEN_SCOPE_ESCALATION")


def _validate_route(route: dict[str, Any]) -> None:
    expected = {
        "schema": "S26_RUNTIME_ROUTE_V1",
        "strategy": "S26",
        "status": "ACTIVE_SANDBOX_PRIMARY",
        "environment_scope": "NON_PRODUCTION",
        "primary_runtime": "CLOUDFLARE_WORKERS_AI",
        "model": PRIMARY_MODEL_ID,
        "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
        "paid_fallback": "DISABLED",
        "local_gguf_fallback": "DISABLED",
        "model_download": "DISABLED",
        "limit_behavior": "FAIL_CLOSED",
        "semantic_judge_status": "ACTIVE_SANDBOX_SEMANTIC_AUTHORITY",
        "semantic_judge_runtime": "CLOUDFLARE_WORKERS_AI",
        "semantic_judge_model": SEMANTIC_MODEL_ID,
        "semantic_judge_model_download": "DISABLED",
        "semantic_judge_local_fallback": "DISABLED",
        "semantic_judge_paid_fallback": "DISABLED",
        "semantic_judge_limit_behavior": "FAIL_CLOSED",
    }
    bad = {key: route.get(key) for key, value in expected.items() if route.get(key) != value}
    if bad:
        raise RuntimeError("ROUTE_BINDING_INVALID:" + json.dumps(bad, sort_keys=True))


def _validate_frozen_obligations(frozen: dict[str, Any]) -> list[dict[str, Any]]:
    if frozen.get("schema") != "S26_UI_ARCHITECT_SEMANTIC_OBLIGATION_MANIFEST_V1":
        raise RuntimeError("FROZEN_MANIFEST_SCHEMA_INVALID")
    obligations = frozen.get("obligations")
    if not isinstance(obligations, list) or len(obligations) != 12:
        raise RuntimeError("FROZEN_MANIFEST_OBLIGATION_COUNT_INVALID")
    ids = [str(item.get("check_id") or "") for item in obligations if isinstance(item, dict)]
    if len(ids) != 12 or len(set(ids)) != 12 or ROUTER_CHECK_ID not in ids:
        raise RuntimeError("FROZEN_MANIFEST_CHECK_IDS_INVALID")
    return obligations


def _adapter_source() -> dict[str, Any]:
    content = ADAPTER_CAPSULE_PATH.read_text(encoding="utf-8")
    if not content or len(content) > 1800:
        raise RuntimeError("ROUTER_ADAPTER_CAPSULE_INVALID")
    return {
        "adapter_code": "ADAPTER_LF_SHELL_PROFILE",
        "assurance_revision": "v2",
        "activation_source": "ROUTER",
        "binding_ref": "ACT-0001|ADAPTER-LF-SHELL-PROFILE-20260827",
        "target_ref": PROFILE_CODE,
        "ref": str(ADAPTER_CAPSULE_PATH.relative_to(REPO_ROOT)),
        "content": content,
    }


def _facts_for_rule(plan: dict[str, Any]) -> str:
    facts = [str(x) for x in plan["governed_facts"]]
    requirements = [str(x) for x in plan["quality_requirements"]]
    return " | ".join([*facts, *requirements])


def _build_canonical_manifest(
    *,
    execution_id: str,
    plan: dict[str, Any],
    frozen_obligations: list[dict[str, Any]],
    profile_source_sha256: str,
    input_sha256: str,
    direct_raw: dict[str, Any],
) -> dict[str, Any]:
    all_ids = [str(item["check_id"]) for item in frozen_obligations]
    direct_sha = canonical_json_sha256(direct_raw)
    facts = _facts_for_rule(plan)
    obligations: list[dict[str, Any]] = []
    for item in frozen_obligations:
        check_id = str(item["check_id"])
        base_rule = str(item["rule"]).strip()
        if check_id == ROUTER_CHECK_ID:
            rule = (
                base_rule
                + " For this fresh parity execution, a direct counterpart exists and is bound as authority. "
                + "The direct counterpart canonical decision is: "
                + json.dumps(direct_raw, ensure_ascii=False, sort_keys=True)
                + ". The Router-bound decision must remain materially equivalent in selected treatment, "
                  "preservation constraints, implementation behavior and semantic meaning; Router application "
                  "may only add compatible target/application constraints."
            )
            authority_ids = ["PROFILE-CONTRACT", "EXECUTION-INPUT", "DIRECT-COUNTERPART"]
        else:
            rule = (
                base_rule
                + " For this fresh execution, the complete source-bound case authority is: "
                + facts
            )
            authority_ids = ["PROFILE-CONTRACT", "EXECUTION-INPUT"]
        obligations.append({
            "obligation_id": check_id,
            "rule": rule,
            "check_type": "SEMANTIC_RELATION",
            "evidence_pointer": "$",
            "authority_ids": authority_ids,
            "question": str(item.get("question") or "Does the complete decision comply with this rule?"),
        })

    manifest = {
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": execution_id,
        "profile_code": PROFILE_CODE,
        "profile_source_sha256": profile_source_sha256,
        "input_sha256": input_sha256,
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT",
                "authority_type": "PROFILE_CONTRACT",
                "source_ref": "profile-sources://ui_architect/S26-canonical-set",
                "source_sha256": profile_source_sha256,
                "required_obligation_ids": all_ids,
            },
            {
                "authority_id": "EXECUTION-INPUT",
                "authority_type": "EXECUTION_INPUT",
                "source_ref": str(PLAN_PATH.relative_to(REPO_ROOT)),
                "source_sha256": input_sha256,
                "required_obligation_ids": all_ids,
            },
            {
                "authority_id": "DIRECT-COUNTERPART",
                "authority_type": "UPSTREAM_CONSTRAINTS",
                "source_ref": "runtime-evidence://S26/direct-counterpart",
                "source_sha256": direct_sha,
                "required_obligation_ids": [ROUTER_CHECK_ID],
            },
        ],
        "obligations": obligations,
    }
    return validate_obligation_manifest(
        manifest,
        expected_execution_id=execution_id,
        expected_profile_code=PROFILE_CODE,
        expected_profile_source_sha256=profile_source_sha256,
        expected_input_sha256=input_sha256,
    )


def _contract_floor(
    gates: OutputGates,
    schema: Any,
    raw_output: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    raw_text = json.dumps(raw_output, ensure_ascii=False, sort_keys=True)
    contract, parsed = gates.contract(
        profile_slug=PROFILE_SLUG,
        raw_output=raw_text,
        schema=schema,
    )
    if contract.get("status") != "PASS":
        raise RuntimeError("CANONICAL_CONTRACT_FAIL:" + json.dumps(contract, sort_keys=True))
    semantic = gates.semantic_utility(
        profile_slug=PROFILE_SLUG,
        payload=parsed,
        contract_gate=contract,
    )
    if semantic.get("status") != "PASS":
        raise RuntimeError("DETERMINISTIC_SEMANTIC_FLOOR_FAIL:" + json.dumps(semantic, sort_keys=True))
    return contract, semantic


def offline_preflight() -> dict[str, Any]:
    plan = _load_json(PLAN_PATH)
    route = _load_json(ROUTE_PATH)
    frozen = _load_json(FROZEN_MANIFEST_PATH)
    _validate_plan(plan)
    _validate_route(route)
    obligations = _validate_frozen_obligations(frozen)
    repository = RepositoryBindings(REPO_ROOT, max_prompt_chars=120_000)
    repository.validate()
    sources = _profile_sources(repository)
    schema = repository.runtime_schema(PROFILE_SLUG, SCHEMA_MODE)
    generation_schema, generation_policy = governed_generation_schema(
        schema.payload, profile_slug=PROFILE_SLUG, schema_mode=SCHEMA_MODE
    )
    _adapter_source()
    CloudflareWorkersAIProfileAdapter(generation_schema=generation_schema)
    input_literal = _input_literal(plan)
    provisional_manifest = _build_canonical_manifest(
        execution_id="S26-CANONICAL-OFFLINE-PREFLIGHT",
        plan=plan,
        frozen_obligations=obligations,
        profile_source_sha256=_profile_source_sha(sources),
        input_sha256=sha256_text(input_literal),
        direct_raw={"offline_preflight_counterpart": True},
    )
    result = {
        "status": "PASS",
        "strategy": "S26",
        "plan_sha256": sha256_text(PLAN_PATH.read_text(encoding="utf-8")),
        "frozen_manifest_sha256": sha256_text(FROZEN_MANIFEST_PATH.read_text(encoding="utf-8")),
        "canonical_obligation_count": len(obligations),
        "canonical_manifest_preflight_sha256": obligation_manifest_sha256(provisional_manifest),
        "profile_source_count": len(sources),
        "profile_source_sha256": _profile_source_sha(sources),
        "schema_sha256": schema.sha256,
        "generation_policy": generation_policy,
        "primary_model": PRIMARY_MODEL_ID,
        "semantic_model": SEMANTIC_MODEL_ID,
        "production_mutation": False,
        "golden_promotion_authorized": False,
    }
    print("S26_CANONICAL_OFFLINE_PREFLIGHT=" + json.dumps(result, sort_keys=True))
    print("S26_CANONICAL_OFFLINE_PREFLIGHT_STATUS=PASS")
    return result


def _usage_neurons(usage: Any) -> float:
    if not isinstance(usage, dict):
        return 0.0
    try:
        return float(usage.get("neurons") or 0)
    except (TypeError, ValueError):
        return 0.0


def live_gate(result_dir: Path) -> dict[str, Any]:
    if os.getenv("LF_REPOSITORY_VISIBILITY", "").strip() != "public":
        raise RuntimeError("LIVE_VISIBILITY_INVALID")
    if os.getenv("LF_RUNNER_LABEL", "").strip() != "ubuntu-latest":
        raise RuntimeError("LIVE_RUNNER_INVALID")
    if os.getenv("LF_S26_PRIMARY_RUNTIME", "").strip() != "CLOUDFLARE_WORKERS_AI":
        raise RuntimeError("LIVE_PRIMARY_RUNTIME_INVALID")

    plan = _load_json(PLAN_PATH)
    route = _load_json(ROUTE_PATH)
    frozen = _load_json(FROZEN_MANIFEST_PATH)
    _validate_plan(plan)
    _validate_route(route)
    frozen_obligations = _validate_frozen_obligations(frozen)

    repository = RepositoryBindings(REPO_ROOT, max_prompt_chars=120_000)
    repository.validate()
    sources = _profile_sources(repository)
    source_sha = _profile_source_sha(sources)
    input_literal = _input_literal(plan)
    input_sha = sha256_text(input_literal)
    schema = repository.runtime_schema(PROFILE_SLUG, SCHEMA_MODE)
    generation_schema, generation_policy = governed_generation_schema(
        schema.payload, profile_slug=PROFILE_SLUG, schema_mode=SCHEMA_MODE
    )
    gates = OutputGates(repository)
    run_id = os.getenv("GITHUB_RUN_ID", "local")
    direct_execution_id = f"S26-CANONICAL-DIRECT-{run_id}"
    router_execution_id = f"S26-CANONICAL-ROUTER-{run_id}"

    direct_adapter = CloudflareWorkersAIProfileAdapter(generation_schema=generation_schema)
    direct_verifier = CloudflareWorkersAIProfileReadbackVerifier()
    direct_package = execute_profile_runtime(
        execution_id=direct_execution_id,
        profile_code=PROFILE_CODE,
        profile_slug=PROFILE_SLUG,
        profile_sources=sources,
        input_literal=input_literal,
        adapter=direct_adapter,
        attestation_verifier=direct_verifier,
        allow_test_doubles=False,
        obligation_manifest=None,
        lf_adapter_sources=None,
    )
    if not isinstance(direct_package.get("raw_output"), dict):
        raise RuntimeError("DIRECT_RAW_NOT_OBJECT")
    direct_contract, direct_floor = _contract_floor(
        gates, schema, direct_package["raw_output"]
    )

    manifest = _build_canonical_manifest(
        execution_id=router_execution_id,
        plan=plan,
        frozen_obligations=frozen_obligations,
        profile_source_sha256=source_sha,
        input_sha256=input_sha,
        direct_raw=direct_package["raw_output"],
    )
    manifest_sha = obligation_manifest_sha256(manifest)

    router_adapter = CloudflareWorkersAIProfileAdapter(generation_schema=generation_schema)
    router_verifier = CloudflareWorkersAIProfileReadbackVerifier()
    router_package = execute_profile_runtime(
        execution_id=router_execution_id,
        profile_code=PROFILE_CODE,
        profile_slug=PROFILE_SLUG,
        profile_sources=sources,
        input_literal=input_literal,
        adapter=router_adapter,
        attestation_verifier=router_verifier,
        allow_test_doubles=False,
        obligation_manifest=manifest,
        lf_adapter_sources=[_adapter_source()],
    )
    if not isinstance(router_package.get("raw_output"), dict):
        raise RuntimeError("ROUTER_RAW_NOT_OBJECT")
    router_contract, router_floor = _contract_floor(
        gates, schema, router_package["raw_output"]
    )
    receipt = router_package["receipt"]
    if receipt.get("obligation_manifest_sha256") != manifest_sha:
        raise RuntimeError("EXECUTION_RECEIPT_MANIFEST_BINDING_MISMATCH")

    bundle = validate_bundle(
        build_check_bundle(
            manifest,
            router_package["raw_output"],
            raw_output_sha256=receipt["raw_output_sha256"],
        )
    )
    deterministic, semantic_checks = partition_checks(bundle)
    if deterministic:
        raise RuntimeError("S26_EXPECTED_ALL_SEMANTIC_CHECKS")
    if len(semantic_checks) != 12:
        raise RuntimeError(f"S26_SEMANTIC_CHECK_COUNT_INVALID:{len(semantic_checks)}")

    judge_results = []
    runtime_evidence = []
    work_root = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    verifier = GitHubHostedSemanticMiniJudgeVerifier()
    with GitHubHostedSemanticMiniJudge(
        work_dir=work_root / "s26-canonical-semantic-authority"
    ) as judge:
        for check in semantic_checks:
            classification, evidence = judge.classify(check)
            verification = verifier.verify(
                check=check,
                result=classification,
                evidence=evidence,
                adapter=judge,
            )
            judge_results.append(classification)
            runtime_evidence.append({
                "check_id": check["check_id"],
                "adapter_evidence": evidence,
                "verification": verification,
            })

    semantic_receipt = build_semantic_receipt(
        bundle,
        judge_results,
        runtime_evidence=runtime_evidence,
    )
    downstream = authorize_downstream(
        profile_execution_required=True,
        recipient="INTERNAL_AGENT",
        receipt=receipt,
        expected_profile_code=PROFILE_CODE,
        expected_input_literal=input_literal,
        expected_raw_output=router_package["raw_output"],
        expected_profile_source_sha256=source_sha,
        semantic_receipt=semantic_receipt,
        semantic_check_bundle=bundle,
        semantic_obligation_manifest=manifest,
    )

    checks_by_id = {item.check_id: item.verdict for item in judge_results}
    router_invocations = receipt.get("lf_adapter_invocations") or []
    direct_invocations = direct_package["receipt"].get("lf_adapter_invocations") or []
    parity_checks = {
        "route_primary_model_matches": route.get("model") == PRIMARY_MODEL_ID,
        "route_semantic_model_matches": route.get("semantic_judge_model") == SEMANTIC_MODEL_ID,
        "same_input_sha256": direct_package["receipt"].get("input_sha256") == receipt.get("input_sha256") == input_sha,
        "same_profile_source_sha256": direct_package["receipt"].get("profile_source_sha256") == receipt.get("profile_source_sha256") == source_sha,
        "direct_has_no_router_adapter": not direct_invocations,
        "router_has_exactly_one_adapter": len(router_invocations) == 1,
        "router_adapter_is_router_bound": (
            len(router_invocations) == 1
            and router_invocations[0].get("activation_source") == "ROUTER"
            and router_invocations[0].get("adapter_code") == "ADAPTER_LF_SHELL_PROFILE"
        ),
        "direct_contract_floor": direct_contract.get("status") == "PASS" and direct_floor.get("status") == "PASS",
        "router_contract_floor": router_contract.get("status") == "PASS" and router_floor.get("status") == "PASS",
        "router_direct_semantic_consistency": checks_by_id.get(ROUTER_CHECK_ID) == "COMPLIES",
        "semantic_receipt_pass": semantic_receipt.get("verdict") == "PASS",
        "downstream_validation_pass": downstream.get("status") == "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY",
        "primary_no_local_or_paid_fallback": (
            direct_package["receipt"]["runtime_attestation"].get("model_weights_downloaded") is False
            and direct_package["receipt"]["runtime_attestation"].get("local_model_fallback_used") is False
            and direct_package["receipt"]["runtime_attestation"].get("paid_fallback_used") is False
            and receipt["runtime_attestation"].get("model_weights_downloaded") is False
            and receipt["runtime_attestation"].get("local_model_fallback_used") is False
            and receipt["runtime_attestation"].get("paid_fallback_used") is False
        ),
        "judge_no_local_or_paid_fallback": all(
            item["adapter_evidence"].get("model_weights_downloaded") is False
            and item["adapter_evidence"].get("local_model_fallback_used") is False
            and item["adapter_evidence"].get("paid_fallback_used") is False
            for item in runtime_evidence
        ),
    }
    operational_parity = all(parity_checks.values())

    primary_neurons = _usage_neurons(direct_adapter.last_usage) + _usage_neurons(router_adapter.last_usage)
    judge_neurons = sum(_usage_neurons(item["adapter_evidence"].get("usage")) for item in runtime_evidence)
    overall = (
        operational_parity
        and semantic_receipt.get("verdict") == "PASS"
        and downstream.get("status") == "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY"
        and len(judge_results) == 12
        and all(item.verdict == "COMPLIES" for item in judge_results)
    )

    payload = {
        "schema": "S26_CANONICAL_PROFILE_GATE_RESULT_V1",
        "strategy": "S26",
        "status": "PASS_SANDBOX_CANONICAL_GATE" if overall else "FAIL_CLOSED",
        "scope": "SANDBOX_ONLY_NOT_GOLDEN_NOT_PRODUCTION",
        "github_run_id": run_id,
        "github_sha": os.getenv("GITHUB_SHA", ""),
        "plan_sha256": sha256_text(PLAN_PATH.read_text(encoding="utf-8")),
        "frozen_source_manifest_sha256": sha256_text(FROZEN_MANIFEST_PATH.read_text(encoding="utf-8")),
        "canonical_manifest_sha256": manifest_sha,
        "canonical_obligation_count": len(manifest["obligations"]),
        "profile_source_sha256": source_sha,
        "input_sha256": input_sha,
        "generation_schema_policy": generation_policy,
        "direct_execution_id": direct_execution_id,
        "router_execution_id": router_execution_id,
        "direct_contract_gate": direct_contract,
        "direct_deterministic_semantic_gate": direct_floor,
        "router_contract_gate": router_contract,
        "router_deterministic_semantic_gate": router_floor,
        "execution_receipt_sha256": receipt.get("receipt_sha256"),
        "check_bundle_sha256": semantic_receipt.get("check_bundle_sha256"),
        "semantic_receipt_sha256": semantic_receipt.get("receipt_sha256"),
        "semantic_verdict": semantic_receipt.get("verdict"),
        "semantic_checks_total": len(judge_results),
        "semantic_checks_comply": sum(item.verdict == "COMPLIES" for item in judge_results),
        "downstream_validation": downstream,
        "parity_checks": parity_checks,
        "operational_parity": operational_parity,
        "primary_model": PRIMARY_MODEL_ID,
        "semantic_model": SEMANTIC_MODEL_ID,
        "primary_inference_calls": 2,
        "semantic_judge_calls": len(judge_results),
        "primary_neurons": round(primary_neurons, 6),
        "semantic_judge_neurons": round(judge_neurons, 6),
        "total_neurons": round(primary_neurons + judge_neurons, 6),
        "model_download": "DISABLED",
        "local_gguf_fallback": "DISABLED",
        "paid_fallback": "DISABLED",
        "limit_behavior": "FAIL_CLOSED",
        "production_mutation": False,
        "golden_promotion_authorized": False,
        "promotion_authorized": False,
    }

    result_dir.mkdir(parents=True, exist_ok=True)
    files = {
        "result.json": payload,
        "direct_package.json": direct_package,
        "manifest.json": manifest,
        "router_package.json": router_package,
        "check_bundle.json": bundle,
        "semantic_receipt.json": semantic_receipt,
    }
    for name, value in files.items():
        (result_dir / name).write_text(
            json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print("S26_CANONICAL_PROFILE_GATE=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
    print("S26_CANONICAL_PROFILE_GATE_STATUS=" + payload["status"])
    print("S26_CANONICAL_OPERATIONAL_PARITY=" + ("PASS" if operational_parity else "FAIL"))
    print("S26_CANONICAL_SEMANTIC_CHECKS=" + f"{payload['semantic_checks_comply']}/{payload['semantic_checks_total']}")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline-preflight", action="store_true")
    parser.add_argument("--result-dir", type=Path)
    args = parser.parse_args()
    if args.offline_preflight:
        offline_preflight()
        return 0
    if args.result_dir is None:
        raise SystemExit("--result-dir required for live gate")
    try:
        payload = live_gate(args.result_dir)
    except Exception as exc:
        args.result_dir.mkdir(parents=True, exist_ok=True)
        failure = {
            "schema": "S26_CANONICAL_PROFILE_GATE_RESULT_V1",
            "strategy": "S26",
            "status": "FAIL_CLOSED",
            "error_type": type(exc).__name__,
            "error": str(exc)[:1200],
            "production_mutation": False,
            "golden_promotion_authorized": False,
            "promotion_authorized": False,
        }
        (args.result_dir / "result.json").write_text(
            json.dumps(failure, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print("S26_CANONICAL_PROFILE_GATE=" + json.dumps(failure, ensure_ascii=False, sort_keys=True))
        print("S26_CANONICAL_PROFILE_GATE_STATUS=FAIL_CLOSED")
        return 2
    return 0 if payload["status"] == "PASS_SANDBOX_CANONICAL_GATE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
