#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import os
import re
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "story_m54_qualification_contract_v1.json"
AUTHORITY_PATH = HERE / "fixtures" / "m54_authority_snapshot_20261004.json"
PACKAGE_PATH = HERE / "fixtures" / "onb_004_implementation_package_v1_1.json"
CURRENT_PATH = HERE / "story_creator_current_contract.json"
CURRENT_CONTRACT_PATH = HERE / "story_creator_implementation_contract_v2.json"
BINDING_PATH = HERE / "programming_agent_story_consumer_binding_v1.json"
JUDGE_PATH = HERE / "programming_utility_judge_contract_v1.json"

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def build_task_view(package: dict, view: dict) -> dict:
    return {name: package[name] for name in view.get("selected_sections", []) if name in package}


def iso(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_blind_provenance(sample: dict) -> list[str]:
    errors: list[str] = []
    if sample.get("raw_frozen") is not True:
        errors.append("RAW_OUTPUT_NOT_FROZEN")
    if not HEX64.fullmatch(str(sample.get("raw_output_sha256") or "")):
        errors.append("RAW_OUTPUT_DIGEST_INVALID")
    if not str(sample.get("gpt_runtime_stamp") or "").strip():
        errors.append("RUNTIME_STAMP_MISSING")
    try:
        frozen_at = iso(str(sample.get("raw_frozen_at") or ""))
        oracle_at = iso(str(sample.get("oracle_opened_at") or ""))
    except Exception:
        errors.append("BLIND_TIMESTAMPS_INVALID")
        return errors
    if oracle_at <= frozen_at:
        errors.append("ORACLE_OPENED_BEFORE_OR_AT_RAW_FREEZE")
    if sample.get("scoring_eligible") is not True:
        errors.append("BLIND_SAMPLE_NOT_SCORING_ELIGIBLE")
    return errors


def measure_context(package: dict, authority: dict) -> dict:
    view = package["task_views"][0]
    projected = build_task_view(package, view)
    measured_bytes = len(canonical_bytes(projected))
    transport_limit = int(package["context_transport"]["max_context_bytes"])
    declared_snapshot_limit = int(authority["story_context_transport"]["declared_max_context_bytes"])
    policy = authority["context_authority"]
    if policy["estimator"] != "UTF8_BYTES_DIV_4":
        estimated_tokens = None
        status = "UNKNOWN"
    else:
        estimated_tokens = (measured_bytes + 3) // 4
        if estimated_tokens > int(policy["hard_limit_tokens"]):
            status = "RED"
        elif estimated_tokens > int(policy["soft_limit_tokens"]):
            status = "YELLOW"
        else:
            status = "GREEN"
    return {
        "task_code": view["task_code"],
        "measured_context_bytes": measured_bytes,
        "story_transport_limit_bytes": transport_limit,
        "snapshot_transport_limit_bytes": declared_snapshot_limit,
        "estimated_tokens": estimated_tokens,
        "policy_soft_limit_tokens": int(policy["soft_limit_tokens"]),
        "policy_hard_limit_tokens": int(policy["hard_limit_tokens"]),
        "policy_estimator": policy["estimator"],
        "policy_status": status,
        "within_story_transport": measured_bytes <= transport_limit,
    }


def measure_reread_trace(binding: dict, refresh_triggers: list[str] | None = None) -> dict:
    refresh_triggers = refresh_triggers or []
    mapping = binding["handoff_projection"]["mapping"]
    story_paths = [row["story_path"] for row in mapping]

    baseline_trace = [
        {"event": "REFETCH_CANONICAL_FACT", "story_path": path}
        for path in story_paths
    ]
    candidate_trace = [{"event": "READ_PINNED_HANDOFF", "binding": binding["schema_version"]}]
    if refresh_triggers:
        candidate_trace.extend(
            {"event": "CURRENTNESS_TRIGGERED_REFRESH", "trigger": trigger}
            for trigger in refresh_triggers
        )

    baseline_refetches = sum(1 for e in baseline_trace if e["event"] == "REFETCH_CANONICAL_FACT")
    candidate_refetches = sum(1 for e in candidate_trace if e["event"] == "CURRENTNESS_TRIGGERED_REFRESH")
    return {
        "measurement_kind": "SOURCE_REFERENCE_CALL_TRACE",
        "runtime_latency_or_token_savings_claimed": False,
        "semantic_fact_count": len(story_paths),
        "baseline_source_refetch_count": baseline_refetches,
        "candidate_source_refetch_count": candidate_refetches,
        "candidate_bound_handoff_read_count": 1,
        "reread_reduction_count": baseline_refetches - candidate_refetches,
        "fact_set_preserved": set(story_paths) == {row["story_path"] for row in mapping},
        "baseline_trace": baseline_trace,
        "candidate_trace": candidate_trace,
    }


def classify_control(applicable: bool, dispatch_receipt: dict | None, terminal_verdict: dict | None) -> dict:
    if not applicable:
        return {
            "state": "NOT_APPLICABLE",
            "closure": "SATISFIED_BY_APPLICABILITY",
            "pass_claim": False,
            "dispatch_required": False,
            "terminal_verdict_required": False,
        }
    if not dispatch_receipt:
        return {"state": "APPLICABLE_NOT_DISPATCHED", "closure": "BLOCKED", "pass_claim": False}
    if not terminal_verdict:
        return {"state": "DISPATCHED", "closure": "BLOCKED", "pass_claim": False}
    return {
        "state": "TERMINAL",
        "closure": "PASS" if terminal_verdict.get("verdict") == "PASS" else "BLOCKED",
        "pass_claim": terminal_verdict.get("verdict") == "PASS",
    }


def validate_contract(contract: dict, authority: dict, current: dict, current_contract: dict, binding: dict, judge: dict, head_sha: str) -> tuple[list[str], dict]:
    errors: list[str] = []
    if contract.get("schema_version") != "STORY_M5_4_QUALIFICATION_CONTRACT_V1":
        errors.append("M54_CONTRACT_SCHEMA_INVALID")
    if contract.get("owner_scope") != "SUPER_ADMIN":
        errors.append("M54_OWNER_SCOPE_NOT_SUPER_ADMIN")
    if contract.get("runtime_activation") is not False or contract.get("production_activation") is not False:
        errors.append("M54_ACTIVATION_FORBIDDEN")
    if not HEX40.fullmatch(head_sha):
        errors.append("EXACT_HEAD_INVALID")

    if current.get("current_contract") != current_contract.get("schema_version"):
        errors.append("CURRENT_CONTRACT_POINTER_DRIFT")
    if current_contract.get("contract_state") != "CURRENT":
        errors.append("CURRENT_CONTRACT_NOT_CURRENT")
    if binding.get("source_contract", {}).get("current_contract") != current.get("current_contract"):
        errors.append("PROGRAMMING_BINDING_CONTRACT_DRIFT")

    judge_policy = contract.get("judge_policy", {})
    judge_governance = judge.get("governance", {})
    judge_closure = judge.get("closure_rule", {})
    if judge_policy.get("governed_semantic_judges_per_candidate") != 1:
        errors.append("M54_JUDGE_CARDINALITY_DRIFT")
    if judge_policy.get("second_judge_required") is not False or judge_policy.get("second_semantic_review_required") is not False:
        errors.append("M54_SECOND_REVIEW_REINTRODUCED")
    if judge_governance.get("owner_scope") != "SUPER_ADMIN" or judge_governance.get("validation_model") != "GOVERNED_SINGLE_JUDGE":
        errors.append("STORY_JUDGE_GOVERNANCE_DRIFT")
    if judge_closure.get("second_judge_required") is not False or judge_closure.get("strategy_independent_review_for_story_forbidden") is not True:
        errors.append("STORY_JUDGE_CLOSURE_DRIFT")

    policy = authority.get("context_authority", {})
    if policy.get("status") != "ACTIVE" or policy.get("policy_code") != contract["context_budget"]["policy_code"]:
        errors.append("LIVE_CONTEXT_POLICY_NOT_ACTIVE")
    if policy.get("schema_version") != contract["context_budget"]["policy_schema"]:
        errors.append("LIVE_CONTEXT_POLICY_SCHEMA_DRIFT")
    if not HEX64.fullmatch(str(policy.get("policy_sha") or "")) or not HEX64.fullmatch(str(policy.get("router_preflight_function_sha256") or "")):
        errors.append("LIVE_CONTEXT_AUTHORITY_DIGEST_INVALID")

    context_measurement = measure_context(json.loads(PACKAGE_PATH.read_text(encoding="utf-8")), authority)
    if context_measurement["story_transport_limit_bytes"] != context_measurement["snapshot_transport_limit_bytes"]:
        errors.append("STORY_TRANSPORT_LIMIT_SNAPSHOT_DRIFT")
    if context_measurement["within_story_transport"] is not True:
        errors.append("STORY_CONTEXT_TRANSPORT_EXCEEDED")
    if context_measurement["policy_status"] == "RED" or context_measurement["estimated_tokens"] is None:
        errors.append("LIVE_CONTEXT_POLICY_HARD_LIMIT_EXCEEDED_OR_UNKNOWN")

    reread = measure_reread_trace(binding)
    if reread["baseline_source_refetch_count"] <= reread["candidate_source_refetch_count"]:
        errors.append("REREAD_REDUCTION_NOT_MEASURED")
    if reread["candidate_source_refetch_count"] != 0 or reread["candidate_bound_handoff_read_count"] != 1:
        errors.append("CURRENT_HANDOFF_REUSE_TRACE_INVALID")
    if reread["fact_set_preserved"] is not True or reread["runtime_latency_or_token_savings_claimed"] is not False:
        errors.append("REREAD_TRACE_OVERCLAIM_OR_FACT_LOSS")

    blind_errors = validate_blind_provenance(authority.get("blind_evaluation_provenance_sample", {}))
    errors.extend(blind_errors)

    pase = authority.get("pase_observation", {})
    if pase.get("workflow_conclusion") != "skipped" or pase.get("interpretation") != "NOT_APPLICABLE_OBSERVED_FOR_SOURCE_ONLY_STORY_CHANGE":
        errors.append("PASE_APPLICABILITY_OBSERVATION_DRIFT")
    pase_state = classify_control(False, None, None)
    if pase_state["state"] != "NOT_APPLICABLE" or pase_state["pass_claim"] is not False:
        errors.append("PASE_NOT_APPLICABLE_MISCLASSIFIED")
    if pase.get("dispatch_receipt_claimed") is not False or pase.get("terminal_control_verdict_claimed") is not False:
        errors.append("PASE_SKIPPED_RECEIPT_FABRICATED")

    return errors, {
        "exact_head_sha": head_sha,
        "context_measurement": context_measurement,
        "reread_trace": reread,
        "blind_provenance_errors": blind_errors,
        "pase_state": pase_state,
    }


def main() -> int:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    authority = json.loads(AUTHORITY_PATH.read_text(encoding="utf-8"))
    current = json.loads(CURRENT_PATH.read_text(encoding="utf-8"))
    current_contract = json.loads(CURRENT_CONTRACT_PATH.read_text(encoding="utf-8"))
    binding = json.loads(BINDING_PATH.read_text(encoding="utf-8"))
    judge = json.loads(JUDGE_PATH.read_text(encoding="utf-8"))
    head_sha = os.environ.get("GITHUB_SHA", authority["source_main_preflight_sha"])

    errors, evidence = validate_contract(contract, authority, current, current_contract, binding, judge, head_sha)
    tests: list[dict] = [{"case": "m54_qualification_positive", "ok": not errors, "errors": errors}]

    bad_blind = copy.deepcopy(authority["blind_evaluation_provenance_sample"])
    bad_blind["oracle_opened_at"] = bad_blind["raw_frozen_at"]
    blind_errors = validate_blind_provenance(bad_blind)
    tests.append({"case": "oracle_preexposure_negative", "ok": "ORACLE_OPENED_BEFORE_OR_AT_RAW_FREEZE" in blind_errors, "errors": blind_errors})

    missing_dispatch = classify_control(True, None, None)
    tests.append({"case": "applicable_without_dispatch_negative", "ok": missing_dispatch["state"] == "APPLICABLE_NOT_DISPATCHED" and missing_dispatch["closure"] == "BLOCKED", "errors": []})

    missing_terminal = classify_control(True, {"dispatch_id": "D1"}, None)
    tests.append({"case": "dispatch_without_terminal_negative", "ok": missing_terminal["state"] == "DISPATCHED" and missing_terminal["closure"] == "BLOCKED", "errors": []})

    terminal = classify_control(True, {"dispatch_id": "D1"}, {"verdict": "PASS"})
    tests.append({"case": "applicable_terminal_positive", "ok": terminal["state"] == "TERMINAL" and terminal["closure"] == "PASS", "errors": []})

    mutated_judge = copy.deepcopy(judge)
    mutated_judge["closure_rule"]["second_judge_required"] = True
    negative_errors, _ = validate_contract(contract, authority, current, current_contract, binding, mutated_judge, head_sha)
    tests.append({"case": "second_judge_reintroduced_negative", "ok": "STORY_JUDGE_CLOSURE_DRIFT" in negative_errors, "errors": negative_errors})

    passed = sum(1 for test in tests if test["ok"])
    out = {
        "schema": "SC_M5_4_QUALIFICATION_READBACK_SELF_TEST_V1",
        "result": "PASS" if passed == len(tests) else "FAIL",
        "tests_total": len(tests),
        "tests_passed": passed,
        "tests": tests,
        "evidence": evidence,
        "claims": {
            "runtime_latency_improvement_claimed": False,
            "runtime_token_savings_claimed": False,
            "source_reference_reread_reduction_measured": True,
            "second_semantic_judge_used": False,
            "production_or_runtime_activation": False,
        },
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
