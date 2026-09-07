#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import yaml

REQUIRED_BLOCKS = [
    "problem_statement", "objective", "scope", "non_goals", "baseline",
    "authorities", "dependencies", "applicable_policies", "stages", "gates",
    "tests", "metrics", "risks", "evidence_contract", "rollback_or_recovery",
    "execution_frontier", "stage_conclusions", "invalidation_triggers",
    "change_log", "closure_criteria",
]

REQUIRED_STAGE_FIELDS = [
    "stage_code", "objective_or_purpose", "status", "entry_conditions",
    "actions_or_scope", "tests", "evidence_required", "exit_gate",
    "conclusion_ref",
]

ARCHETYPE_REQUIRED_FIELDS = {
    "GOVERNANCE": [
        "authority_model", "ownership_boundaries", "lifecycle_or_policy_impact",
        "conflict_and_waiver_handling", "next_gate_or_handoff",
    ],
    "TECHNICAL_OPERATIONAL": [
        "runtime_or_system_boundary", "failure_modes_and_first_bad_hop",
        "reliability_test_plan", "performance_or_resource_metrics_or_explicit_na",
        "rollback_or_recovery", "next_gate_or_handoff",
    ],
    "PRODUCT": [
        "target_user_or_state", "selected_decision", "rejected_alternatives",
        "tradeoffs", "value_metric_or_success_proxy",
        "observable_acceptance_criteria", "next_gate_or_handoff",
    ],
    "RESEARCH_BENCHMARK": [
        "research_questions_or_hypotheses", "methodology",
        "sample_dataset_or_case_families", "evaluation_criteria",
        "leakage_and_bias_controls", "next_gate_or_handoff",
    ],
    "MIGRATION_DEPLOYMENT": [
        "source_target_versions", "parity_contract", "rollout_or_cutover_plan",
        "rollback_plan", "smoke_ci_and_readback", "production_boundary",
        "next_gate_or_handoff",
    ],
    "CANARY_VALIDATION": [
        "proof_target", "positive_case", "negative_cases",
        "exact_evidence_boundary", "cleanup_or_demotion_plan",
        "next_gate_or_handoff",
    ],
}

STALE_CONCLUSION_STATUSES = {"STALE", "SUPERSEDED", "RETIRED", "ARCHIVED"}


def present(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, dict)):
        return bool(value)
    return True


def load_document(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("strategy document must be a mapping")
    return data


def add(errors: list[dict[str, str]], code: str, path: str, message: str) -> None:
    errors.append({"code": code, "path": path, "message": message})


def validate(data: dict[str, Any], mode: str = "prewrite") -> dict[str, Any]:
    errors: list[dict[str, str]] = []

    for key in REQUIRED_BLOCKS:
        if not present(data.get(key)):
            add(errors, "MISSING_REQUIRED_STRATEGY_BLOCK", key, "required block missing or empty")

    archetype = data.get("strategy_archetype")
    if archetype not in ARCHETYPE_REQUIRED_FIELDS and archetype != "CUSTOM":
        add(errors, "UNKNOWN_STRATEGY_TYPE_WITHOUT_EXTENSION", "strategy_archetype", "known archetype or CUSTOM required")
    type_extension = data.get("type_extension")
    if archetype == "CUSTOM":
        if not isinstance(type_extension, dict) or not present(type_extension.get("extension_schema_ref")):
            add(errors, "CUSTOM_EXTENSION_SCHEMA_REF_MISSING", "type_extension.extension_schema_ref", "CUSTOM requires extension_schema_ref")
    elif archetype in ARCHETYPE_REQUIRED_FIELDS:
        if not isinstance(type_extension, dict):
            add(errors, "TYPE_EXTENSION_MISSING", "type_extension", "type_extension mapping required")
        else:
            for field in ARCHETYPE_REQUIRED_FIELDS[archetype]:
                if not present(type_extension.get(field)):
                    add(errors, "MISSING_REQUIRED_TYPE_EXTENSION_FIELD", f"type_extension.{field}", f"required for {archetype}")

    stages = data.get("stages")
    stage_codes: list[str] = []
    stage_conclusion_refs: dict[str, str] = {}
    if not isinstance(stages, list) or not stages:
        add(errors, "STAGES_INVALID", "stages", "non-empty array required")
    else:
        for index, stage in enumerate(stages):
            path = f"stages[{index}]"
            if not isinstance(stage, dict):
                add(errors, "STAGE_NOT_OBJECT", path, "stage must be mapping")
                continue
            for field in REQUIRED_STAGE_FIELDS:
                if not present(stage.get(field)):
                    add(errors, "INCOMPLETE_STAGE_SCHEMA", f"{path}.{field}", "required stage field missing or empty")
            code = stage.get("stage_code")
            if isinstance(code, str) and code.strip():
                if code in stage_codes:
                    add(errors, "DUPLICATE_STAGE_CODE", f"{path}.stage_code", code)
                stage_codes.append(code)
                ref = stage.get("conclusion_ref")
                if isinstance(ref, str) and ref.strip():
                    stage_conclusion_refs[code] = ref

    conclusions = data.get("stage_conclusions")
    current_by_stage: dict[str, list[dict[str, Any]]] = {code: [] for code in stage_codes}
    if not isinstance(conclusions, list) or not conclusions:
        add(errors, "STAGE_CONCLUSIONS_INVALID", "stage_conclusions", "non-empty array required")
    else:
        for index, conclusion in enumerate(conclusions):
            path = f"stage_conclusions[{index}]"
            if not isinstance(conclusion, dict):
                add(errors, "STAGE_CONCLUSION_NOT_OBJECT", path, "conclusion must be mapping")
                continue
            for field in ["conclusion_id", "stage_code", "status", "conclusion", "claim_ceiling", "open_risks", "carry_forward", "invalidation_triggers"]:
                if not present(conclusion.get(field)) and field not in {"open_risks", "carry_forward"}:
                    add(errors, "STAGE_CONCLUSION_FIELD_MISSING", f"{path}.{field}", "required conclusion field missing")
            code = conclusion.get("stage_code")
            status = str(conclusion.get("status", "")).upper()
            if code in current_by_stage and status not in STALE_CONCLUSION_STATUSES:
                current_by_stage[code].append(conclusion)

    for code in stage_codes:
        current = current_by_stage.get(code, [])
        if len(current) == 0:
            add(errors, "MISSING_STAGE_CONCLUSION", f"stage_conclusions[{code}]", "exactly one current conclusion required")
        elif len(current) > 1:
            add(errors, "DUPLICATE_CURRENT_STAGE_CONCLUSION", f"stage_conclusions[{code}]", "more than one current conclusion")
        else:
            expected_ref = stage_conclusion_refs.get(code)
            actual_ref = current[0].get("conclusion_id")
            if expected_ref != actual_ref:
                add(errors, "STAGE_CONCLUSION_REF_MISMATCH", f"stages[{code}].conclusion_ref", f"expected {actual_ref!r}, found {expected_ref!r}")

    frontier = data.get("execution_frontier")
    if not isinstance(frontier, dict):
        add(errors, "EXECUTION_FRONTIER_INVALID", "execution_frontier", "mapping required")
    else:
        for field in ["current_stage", "current_action", "safe_parallel_work", "blockers"]:
            if field not in frontier:
                add(errors, "EXECUTION_FRONTIER_FIELD_MISSING", f"execution_frontier.{field}", "required field")
        if mode == "prewrite":
            current_stage = frontier.get("current_stage")
            if stage_codes and current_stage not in stage_codes:
                add(errors, "STALE_EXECUTION_FRONTIER", "execution_frontier.current_stage", "must reference a declared current stage before write")
        elif mode == "close":
            if frontier.get("state") != "CLOSED":
                add(errors, "STALE_EXECUTION_FRONTIER", "execution_frontier.state", "close mode requires CLOSED")
            if frontier.get("current_action") not in {"NONE", None}:
                add(errors, "STALE_EXECUTION_FRONTIER", "execution_frontier.current_action", "close mode requires NONE")
            if frontier.get("safe_parallel_work") not in ([], None):
                add(errors, "STALE_EXECUTION_FRONTIER", "execution_frontier.safe_parallel_work", "close mode requires empty list")
            if frontier.get("blockers") not in ([], None):
                add(errors, "STALE_EXECUTION_FRONTIER", "execution_frontier.blockers", "close mode requires empty list")
        else:
            add(errors, "VALIDATION_MODE_INVALID", "mode", mode)

    if not present(data.get("next_gate_or_handoff")):
        ext = data.get("type_extension") if isinstance(data.get("type_extension"), dict) else {}
        if not present(ext.get("next_gate_or_handoff")):
            add(errors, "MISSING_NEXT_GATE_OR_HANDOFF", "next_gate_or_handoff", "required at strategy or type-extension level")

    result = {
        "valid": not errors,
        "mode": mode,
        "strategy_archetype": archetype,
        "stage_count": len(stage_codes),
        "current_stage_conclusion_count": sum(len(v) for v in current_by_stage.values()),
        "errors": errors,
        "blocking_codes": sorted({e["code"] for e in errors}),
    }
    result["results_sha256"] = hashlib.sha256(
        json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return result


def self_test() -> dict[str, Any]:
    base = {
        "problem_statement": "p", "objective": "o", "scope": ["s"], "non_goals": ["n"],
        "baseline": {"b": 1}, "authorities": ["ACT-0001"], "dependencies": [{"id": "S30"}],
        "applicable_policies": [{"code": "POL"}], "gates": ["G"], "tests": [{"id": "T"}],
        "metrics": {"m": 1}, "risks": [{"id": "R"}], "evidence_contract": {"ceiling": "R3"},
        "rollback_or_recovery": {"routes": ["A"]}, "invalidation_triggers": ["x"],
        "change_log": [{"version": "v0.1"}], "closure_criteria": ["c"],
        "strategy_archetype": "CANARY_VALIDATION",
        "type_extension": {
            "proof_target": "factory", "positive_case": "positive", "negative_cases": ["negative"],
            "exact_evidence_boundary": "R3", "cleanup_or_demotion_plan": "demote",
            "next_gate_or_handoff": "quality",
        },
        "stages": [{
            "stage_code": "S0", "objective_or_purpose": "test", "status": "CURRENT",
            "entry_conditions": ["ready"], "actions_or_scope": ["run"], "tests": ["T"],
            "evidence_required": ["E"], "exit_gate": "PASS", "conclusion_ref": "C0",
        }],
        "stage_conclusions": [{
            "conclusion_id": "C0", "stage_code": "S0", "status": "PASS", "conclusion": "ok",
            "claim_ceiling": "R3", "open_risks": [], "carry_forward": [],
            "invalidation_triggers": ["x"],
        }],
        "execution_frontier": {"current_stage": "S0", "current_action": "run", "safe_parallel_work": [], "blockers": []},
        "next_gate_or_handoff": "quality",
    }
    cases: list[tuple[str, dict[str, Any], str, bool, str | None]] = []
    cases.append(("positive_prewrite", json.loads(json.dumps(base)), "prewrite", True, None))
    missing_stage = json.loads(json.dumps(base)); del missing_stage["stages"][0]["tests"]
    cases.append(("missing_stage_field", missing_stage, "prewrite", False, "INCOMPLETE_STAGE_SCHEMA"))
    missing_conclusion = json.loads(json.dumps(base)); missing_conclusion["stage_conclusions"] = []
    cases.append(("missing_conclusion", missing_conclusion, "prewrite", False, "STAGE_CONCLUSIONS_INVALID"))
    missing_extension = json.loads(json.dumps(base)); del missing_extension["type_extension"]["proof_target"]
    cases.append(("missing_type_extension", missing_extension, "prewrite", False, "MISSING_REQUIRED_TYPE_EXTENSION_FIELD"))
    stale_close = json.loads(json.dumps(base)); stale_close["execution_frontier"]["state"] = "OPEN"
    cases.append(("stale_close_frontier", stale_close, "close", False, "STALE_EXECUTION_FRONTIER"))

    results = []
    all_pass = True
    for name, payload, mode, expected_valid, expected_code in cases:
        actual = validate(payload, mode)
        ok = actual["valid"] == expected_valid and (expected_code is None or expected_code in actual["blocking_codes"])
        all_pass = all_pass and ok
        results.append({"name": name, "ok": ok, "expected_valid": expected_valid, "blocking_codes": actual["blocking_codes"]})
    return {"all_pass": all_pass, "case_count": len(results), "results": results}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", type=Path)
    parser.add_argument("--mode", choices=["prewrite", "close"], default="prewrite")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        result = self_test()
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if result["all_pass"] else 1
    if args.path is None:
        parser.error("path is required unless --self-test is used")
    try:
        result = validate(load_document(args.path), args.mode)
    except Exception as exc:
        result = {"valid": False, "errors": [{"code": "MALFORMED_INPUT", "path": "$", "message": str(exc)}], "blocking_codes": ["MALFORMED_INPUT"]}
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result.get("valid") else 1


if __name__ == "__main__":
    sys.exit(main())
