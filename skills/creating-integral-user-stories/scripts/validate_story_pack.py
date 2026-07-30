"""Read-only J03 validator for LF Story Packs."""
from __future__ import annotations

import argparse
import json
import os
from copy import deepcopy
from pathlib import Path

from lf_common import (
    ValidationInputError,
    duplicate_values,
    emit,
    failure,
    load_json,
    main_guard,
    require_object,
    result_object,
    utc_now,
)

JUDGE = "J03_STORY_CORE"
VERSION = "v0.5"
SECTIONS = ("identity", "core", "interaction", "fields", "validations", "observations", "errors", "security_privacy", "states", "audit", "tokens_messages", "analytics", "observability", "responsive_accessibility", "tests", "dependencies_risks", "judges_evidence")
CORE_KEYS = ("actor", "need", "benefit", "preconditions", "trigger", "main_flow", "alternative_flows", "postconditions", "acceptance_criteria", "out_of_scope")
METHODS = {"ANTHROPIC_COUNT_TOKENS", "TOKENIZER", "ESTIMATE"}
BANDS = {"COMPACT", "STANDARD", "WARNING", "DISCLOSURE_REQUIRED", "DIRECT_LOAD_BLOCKED"}


def schema_errors(pack: dict, schema_path: Path) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise ValidationInputError("jsonschema_not_available") from exc
    schema = load_json(schema_path)
    jsonschema.Draft7Validator.check_schema(schema)
    return sorted(
        f"{'/'.join(map(str, error.absolute_path)) or '$'}:{error.message}"
        for error in jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker()).iter_errors(pack)
    )


def budget_failures(pack: dict) -> tuple[list[str], dict]:
    deps = pack.get("dependencies_risks") if isinstance(pack.get("dependencies_risks"), dict) else {}
    budget = deps.get("context_budget") if isinstance(deps.get("context_budget"), dict) else {}
    if not budget:
        return ["context_budget_missing=1"], {"present": False}
    failed: list[str] = []
    method = budget.get("measurement_method")
    canonical = budget.get("canonical_story_tokens")
    implementation = budget.get("implementation_view_tokens")
    active = budget.get("active_context_tokens")
    for key, value in (("canonical_story_tokens", canonical), ("implementation_view_tokens", implementation), ("active_context_tokens", active)):
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            failed.append(f"context_budget_invalid_{key}=1")
    if method not in METHODS:
        failed.append("context_budget_measurement_without_method=1")
    if budget.get("context_band") not in BANDS:
        failed.append("context_budget_invalid_band=1")
    if isinstance(canonical, int) and canonical > 12000:
        if budget.get("direct_load_allowed") is not False:
            failed.append("oversized_story_direct_load_allowed=1")
        if budget.get("specialized_views_required") is not True:
            failed.append("oversized_story_without_specialized_views=1")
        if budget.get("atomicity_review_required") is not True:
            failed.append("oversized_story_without_atomicity_review=1")
    if isinstance(active, int) and active > 15000 and budget.get("direct_load_allowed") is not False:
        failed.append("active_context_over_limit_direct_load_allowed=1")
    return failed, {
        "present": True,
        "measurement_method": method,
        "canonical_story_tokens": canonical,
        "implementation_view_tokens": implementation,
        "active_context_tokens": active,
        "context_band": budget.get("context_band"),
        "direct_load_allowed": budget.get("direct_load_allowed"),
        "specialized_views_required": budget.get("specialized_views_required"),
        "atomicity_review_required": budget.get("atomicity_review_required"),
    }


def validate_pack(pack: dict, schema_path: Path) -> tuple[list[str], list[dict], dict]:
    failed: list[str] = []
    repairs: list[dict] = []
    missing = [section for section in SECTIONS if section not in pack]
    if missing:
        failed.append(f"missing_sections={len(missing)}")
        repairs.append(failure("missing_sections", "$", f"Add sections: {', '.join(missing)}"))
    core = pack.get("core") if isinstance(pack.get("core"), dict) else {}
    missing_core = [key for key in CORE_KEYS if key not in core or (key != "alternative_flows" and core.get(key) in (None, "", []))]
    if missing_core:
        failed.append(f"core_keys_missing={len(missing_core)}")
        repairs.append(failure("core_keys_missing", "core", f"Complete: {', '.join(missing_core)}"))
    criteria = core.get("acceptance_criteria", [])
    criteria = criteria if isinstance(criteria, list) else []
    invalid = [
        index for index, item in enumerate(criteria)
        if not isinstance(item, dict)
        or not all(isinstance(item.get(key), str) and item.get(key).strip() for key in ("criterion_code", "given", "when", "then", "source_ref"))
    ]
    if invalid:
        failed.append(f"criteria_without_given_when_then={len(invalid)}")
        repairs.append(failure("criteria_without_given_when_then", "core.acceptance_criteria", f"Repair indexes: {invalid}"))
    duplicates = duplicate_values(item.get("criterion_code") for item in criteria if isinstance(item, dict) and item.get("criterion_code"))
    if duplicates:
        failed.append(f"duplicate_criterion_codes={len(duplicates)}")
        repairs.append(failure("duplicate_criterion_codes", "core.acceptance_criteria", f"Assign unique codes: {duplicates}"))
    identity = pack.get("identity") if isinstance(pack.get("identity"), dict) else {}
    if not identity.get("source_decision_id") or not identity.get("source_snapshot_sha"):
        failed.append("stories_without_source_trace=1")
        repairs.append(failure("stories_without_source_trace", "identity", "Provide source_decision_id and source_snapshot_sha."))
    budget_failed, budget_evidence = budget_failures(pack)
    failed.extend(budget_failed)
    if budget_failed:
        repairs.append(failure("context_budget", "dependencies_risks.context_budget", "Provide measured budget and enforce load, views and atomicity rules."))
    schema_failed = schema_errors(pack, schema_path)
    if schema_failed:
        failed.append(f"schema_validation_errors={len(schema_failed)}")
        repairs.append(failure("schema_validation_errors", "$", "Resolve every schema error without weakening the schema."))
    evidence = {
        "sections_present": len(SECTIONS) - len(missing),
        "sections_expected": len(SECTIONS),
        "missing_sections": missing,
        "missing_core_keys": missing_core,
        "acceptance_criteria_count": len(criteria),
        "invalid_criterion_indexes": invalid,
        "duplicate_criterion_codes": duplicates,
        "context_budget": budget_evidence,
        "context_budget_failure_count": len(budget_failed),
        "schema_error_count": len(schema_failed),
        "schema_errors": schema_failed[:50],
    }
    return sorted(set(failed)), repairs, evidence


def registry_case(registry_path: Path, case_id: str) -> dict:
    registry = require_object(load_json(registry_path), "eval_registry")
    cases = registry.get("executable_cases")
    cases = cases if isinstance(cases, list) else []
    case = next((item for item in cases if isinstance(item, dict) and item.get("id") == case_id), None)
    if case is None:
        raise ValidationInputError(f"eval_case_not_found:{case_id}")
    return case


def eval_case(registry_path: Path, case_id: str, schema_path: Path) -> int:
    started_at = utc_now()
    case = registry_case(registry_path, case_id)
    pack = require_object(case.get("candidate_story_pack"), "candidate_story_pack")
    failed, _, evidence = validate_pack(pack, schema_path)
    actual = "PASS_WITH_EVIDENCE" if not failed else "RETURN_TO_WORKER"
    expected = case.get("expected_validation_result")
    mismatch = [] if actual == expected else [f"validator_result_mismatch:{actual}!={expected}"]
    if case.get("must_be_rejected") and actual == "PASS_WITH_EVIDENCE":
        mismatch.append("negative_case_not_rejected=1")
    eval_evidence = {
        "case_id": case_id,
        "fixture_ref": case.get("fixture_ref"),
        "validator_ref": case.get("validator_ref"),
        "schema_ref": case.get("schema_ref"),
        "expected_validation_result": expected,
        "actual_validation_result": actual,
        "matched": not mismatch,
        "candidate_failed_assertions": failed,
        "candidate_evidence": evidence,
        "negative_must_be_rejected": bool(case.get("must_be_rejected")),
        "input_path": str(registry_path),
    }
    repairs = [] if not mismatch else [failure("validator_result_mismatch", f"executable_cases.{case_id}", "Align candidate, expectation or validator without weakening assertions.")]
    return emit(result_object(
        JUDGE,
        mismatch,
        eval_evidence,
        [f"file:{registry_path}", str(case.get("fixture_ref") or "fixture:inline")],
        repairs,
        retry_count=0,
        judge_version=os.getenv("LF_JUDGE_VERSION"),
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),
        started_at=started_at,
    ))


def self_test(registry_path: Path, schema_path: Path) -> int:
    positive = registry_case(registry_path, "E21_STORY_CORE_POSITIVE")["candidate_story_pack"]
    negative = deepcopy(positive)
    negative["identity"].update({"source_decision_id": "", "source_snapshot_sha": ""})
    negative["dependencies_risks"]["context_budget"].pop("measurement_method")
    negative["dependencies_risks"]["context_budget"].update({"canonical_story_tokens": 13100, "direct_load_allowed": True, "specialized_views_required": False, "atomicity_review_required": False})
    positive_failed, _, _ = validate_pack(positive, schema_path)
    negative_failed, _, _ = validate_pack(negative, schema_path)
    passed = not positive_failed and "stories_without_source_trace=1" in negative_failed and any(item.startswith("context_budget_") or item.startswith("oversized_story_") for item in negative_failed)
    print(json.dumps({"judge_code": JUDGE, "result": "PASS_WITH_EVIDENCE" if passed else "FAIL", "compliance_bit": 1 if passed else 0, "positive_failed": positive_failed, "negative_failed": negative_failed}, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


def run() -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("input", type=Path, nargs="?")
    cli.add_argument("--schema", type=Path, default=Path(__file__).resolve().parents[1] / "schemas/story-pack.schema.json")
    cli.add_argument("--eval-registry", type=Path, default=Path(__file__).resolve().parents[1] / "evals/evals.json")
    cli.add_argument("--case-id")
    cli.add_argument("--self-test", action="store_true")
    cli.add_argument("--evidence-ref", action="append", default=[])
    cli.add_argument("--retry-count", type=int, default=0)
    args = cli.parse_args()
    if args.self_test:
        return self_test(args.eval_registry, args.schema)
    if args.case_id:
        return eval_case(args.eval_registry, args.case_id, args.schema)
    if args.input is None:
        raise ValidationInputError("story_pack_input_required")
    started_at = utc_now()
    pack = require_object(load_json(args.input), "story_pack")
    failed, repairs, evidence = validate_pack(pack, args.schema)
    evidence.update({"input_path": str(args.input), "schema_path": str(args.schema)})
    return emit(result_object(
        JUDGE,
        failed,
        evidence,
        args.evidence_ref or [f"file:{args.input}"],
        repairs,
        retry_count=args.retry_count,
        judge_version=os.getenv("LF_JUDGE_VERSION"),
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),
        started_at=started_at,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
