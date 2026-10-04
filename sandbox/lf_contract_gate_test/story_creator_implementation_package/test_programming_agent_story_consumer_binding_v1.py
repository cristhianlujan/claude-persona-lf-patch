#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
BINDING_PATH = HERE / "programming_agent_story_consumer_binding_v1.json"
CURRENT_PATH = HERE / "story_creator_current_contract.json"
CONSUMER_SNAPSHOT_PATH = HERE / "fixtures" / "programming_consumer_v2_contract_snapshot_20261002.json"
PACKAGE_PATH = HERE / "fixtures" / "onb_004_implementation_package_v1_1.json"

EXPECTED_FUNCTION = "programacion.fn_agent_task_execution_bundle(bigint,text,text)"
EXPECTED_RUNTIME = "programacion.fn_agent_task_runtime_context(bigint)"
REQUIRED_TARGET_FIELDS = {
    "repo_full_name",
    "base_head_sha",
    "source_snapshot_sha256",
    "context_path_patterns",
    "write_path_patterns",
    "protected_path_patterns",
}
REQUIRED_STORY_MAPPINGS = {
    "canonical_story_sha256",
    "story_identity",
    "story_contracts",
    "hard_boundaries",
    "implementation_preconditions",
    "executable_acceptance",
    "blocked_if",
    "context_transport.max_context_bytes",
    "task_views",
}


def validate_binding(binding: dict, current: dict, snapshot: dict) -> list[str]:
    errors: list[str] = []
    if binding.get("schema_version") != "PROGRAMMING_AGENT_STORY_CONSUMER_BINDING_V1":
        errors.append("BINDING_SCHEMA_INVALID")
    if binding.get("owner_scope") != "SUPER_ADMIN":
        errors.append("OWNER_SCOPE_NOT_SUPER_ADMIN")
    if binding.get("consumer") != "PROGRAMMING_AGENT":
        errors.append("CONSUMER_IDENTITY_INVALID")

    runtime = binding.get("consumer_runtime", {})
    if runtime.get("execution_bundle_function") != EXPECTED_FUNCTION:
        errors.append("EXECUTION_BUNDLE_FUNCTION_DRIFT")
    if runtime.get("runtime_context_function") != EXPECTED_RUNTIME:
        errors.append("RUNTIME_CONTEXT_FUNCTION_DRIFT")
    if runtime.get("new_runtime_created") is not False or runtime.get("new_task_store_created") is not False or runtime.get("new_context_store_created") is not False:
        errors.append("PARALLEL_PROGRAMMING_RUNTIME_CREATED")

    source = binding.get("source_contract", {})
    if source.get("current_contract") != current.get("current_contract"):
        errors.append("CURRENT_STORY_CONTRACT_DRIFT")
    if source.get("legacy_direct_semantics_consumption_allowed") is not False:
        errors.append("LEGACY_DIRECT_SEMANTICS_ALLOWED")

    projection = binding.get("handoff_projection", {})
    if projection.get("projection_mode") != "LOSSLESS_TASK_SCOPED_PROJECTION":
        errors.append("HANDOFF_PROJECTION_NOT_LOSSLESS")
    if projection.get("lossy_summary_forbidden") is not True:
        errors.append("LOSSY_SUMMARY_ALLOWED")
    if projection.get("canonical_authority_refs_preserved") is not True or projection.get("typed_blockers_preserved") is not True:
        errors.append("CANONICAL_FACTS_NOT_PRESERVED")
    mapped = {m.get("story_path") for m in projection.get("mapping", [])}
    missing = sorted(REQUIRED_STORY_MAPPINGS - mapped)
    if missing:
        errors.append("HANDOFF_MAPPING_MISSING:" + ",".join(missing))

    target = binding.get("implementation_target_binding", {})
    if set(target.get("required_fields", [])) != REQUIRED_TARGET_FIELDS:
        errors.append("TARGET_BINDING_FIELDS_DRIFT")
    if target.get("missing_required_binding_result") != "BLOCKED_AFFECTED_TASK":
        errors.append("MISSING_TARGET_NOT_FAIL_CLOSED")
    if target.get("repo_or_path_inference_forbidden") is not True:
        errors.append("TARGET_INFERENCE_ALLOWED")
    if target.get("exact_head_required") is not True:
        errors.append("EXACT_HEAD_NOT_REQUIRED")

    reread = binding.get("currentness_and_reread", {})
    if reread.get("reuse_current_handoff_first") is not True:
        errors.append("CURRENT_HANDOFF_NOT_REUSED_FIRST")
    if reread.get("downstream_reinference_forbidden") is not True:
        errors.append("DOWNSTREAM_REINFERENCE_ALLOWED")
    if reread.get("downstream_refetch_forbidden_without_trigger") is not True:
        errors.append("DOWNSTREAM_REFETCH_ALLOWED_WITHOUT_TRIGGER")

    if snapshot.get("source_function") != EXPECTED_FUNCTION:
        errors.append("CONSUMER_SNAPSHOT_FUNCTION_DRIFT")
    if snapshot.get("schema_version") != binding.get("compatibility", {}).get("existing_programming_agent_contract_snapshot"):
        errors.append("CONSUMER_SNAPSHOT_VERSION_DRIFT")
    return errors


def resolve_target(binding: dict, target: dict) -> dict:
    missing = [f for f in binding["implementation_target_binding"]["required_fields"] if not target.get(f)]
    if missing:
        return {"result": "BLOCKED_AFFECTED_TASK", "missing": sorted(missing), "inferred": False}
    return {"result": "RESOLVED", "missing": [], "inferred": False}


def main() -> int:
    binding = json.loads(BINDING_PATH.read_text(encoding="utf-8"))
    current = json.loads(CURRENT_PATH.read_text(encoding="utf-8"))
    snapshot = json.loads(CONSUMER_SNAPSHOT_PATH.read_text(encoding="utf-8"))
    package = json.loads(PACKAGE_PATH.read_text(encoding="utf-8"))

    cases: list[dict] = []
    errors = validate_binding(binding, current, snapshot)
    cases.append({"case": "binding_contract_positive", "ok": not errors, "errors": errors})

    exact_target = {
        "repo_full_name": "cristhianlujan/libertad-financiera",
        "base_head_sha": "a" * 40,
        "source_snapshot_sha256": package["canonical_story_sha256"],
        "context_path_patterns": ["src/onboarding/**"],
        "write_path_patterns": ["src/onboarding/**"],
        "protected_path_patterns": ["src/auth/**"],
    }
    resolved = resolve_target(binding, exact_target)
    cases.append({"case": "exact_target_binding_positive", "ok": resolved["result"] == "RESOLVED" and not resolved["inferred"], "errors": []})

    unresolved = copy.deepcopy(exact_target)
    unresolved.pop("repo_full_name")
    unresolved.pop("write_path_patterns")
    blocked = resolve_target(binding, unresolved)
    cases.append({
        "case": "missing_target_repo_path_blocks_affected_task",
        "ok": blocked["result"] == "BLOCKED_AFFECTED_TASK" and blocked["inferred"] is False and blocked["missing"] == ["repo_full_name", "write_path_patterns"],
        "errors": [],
    })

    mut = copy.deepcopy(binding)
    mut["handoff_projection"]["lossy_summary_forbidden"] = False
    errs = validate_binding(mut, current, snapshot)
    cases.append({"case": "lossy_summary_negative", "ok": "LOSSY_SUMMARY_ALLOWED" in errs, "errors": errs})

    mut = copy.deepcopy(binding)
    mut["currentness_and_reread"]["downstream_refetch_forbidden_without_trigger"] = False
    errs = validate_binding(mut, current, snapshot)
    cases.append({"case": "redundant_refetch_negative", "ok": "DOWNSTREAM_REFETCH_ALLOWED_WITHOUT_TRIGGER" in errs, "errors": errs})

    mut = copy.deepcopy(binding)
    mut["consumer_runtime"]["new_runtime_created"] = True
    errs = validate_binding(mut, current, snapshot)
    cases.append({"case": "parallel_runtime_negative", "ok": "PARALLEL_PROGRAMMING_RUNTIME_CREATED" in errs, "errors": errs})

    passed = sum(1 for c in cases if c["ok"])
    out = {
        "schema": "SC_M5_2_PROGRAMMING_AGENT_CONSUMER_BINDING_SELF_TEST_V1",
        "cases_total": len(cases),
        "cases_passed": passed,
        "result": "PASS" if passed == len(cases) else "FAIL",
        "cases": cases,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
