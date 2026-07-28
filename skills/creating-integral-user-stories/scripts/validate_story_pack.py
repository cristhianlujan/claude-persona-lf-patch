"""Validate one Story Pack against schema, J03 semantics and LF context budget.

Use ``--self-test`` to prove that a valid pack passes and an over-limit pack
with an incomplete budget is rejected. The validator is read-only.
"""
from __future__ import annotations

import argparse
import json
import tempfile
from copy import deepcopy
from pathlib import Path

from lf_common import (
    ValidationInputError, add_common_input, duplicate_values, emit, failure,
    load_json, main_guard, parser, require_object, result_object,
)

JUDGE = "J03_STORY_CORE"
SECTIONS = (
    "identity", "core", "interaction", "fields", "validations", "observations",
    "errors", "security_privacy", "states", "audit", "tokens_messages",
    "analytics", "observability", "responsive_accessibility", "tests",
    "dependencies_risks", "judges_evidence",
)
CORE_KEYS = (
    "actor", "need", "benefit", "preconditions", "trigger", "main_flow",
    "alternative_flows", "postconditions", "acceptance_criteria", "out_of_scope",
)
BUDGET_METHODS = {"ANTHROPIC_COUNT_TOKENS", "TOKENIZER", "ESTIMATE"}
BUDGET_BANDS = {"COMPACT", "STANDARD", "WARNING", "DISCLOSURE_REQUIRED", "DIRECT_LOAD_BLOCKED"}


def schema_errors(instance: dict, schema_path: Path) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise ValidationInputError("jsonschema_not_available") from exc
    schema = load_json(schema_path)
    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    return sorted(
        f"{'/'.join(str(part) for part in error.absolute_path) or '$'}:{error.message}"
        for error in validator.iter_errors(instance)
    )


def context_budget_failures(pack: dict) -> tuple[list[str], dict]:
    deps = pack.get("dependencies_risks") if isinstance(pack.get("dependencies_risks"), dict) else {}
    budget = deps.get("context_budget") if isinstance(deps.get("context_budget"), dict) else {}
    failed: list[str] = []
    if not budget:
        return ["context_budget_missing=1"], {"present": False}
    method = budget.get("measurement_method")
    canonical = budget.get("canonical_story_tokens")
    implementation = budget.get("implementation_view_tokens")
    active = budget.get("active_context_tokens")
    for key, value in (("canonical_story_tokens", canonical), ("implementation_view_tokens", implementation), ("active_context_tokens", active)):
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            failed.append(f"context_budget_invalid_{key}=1")
    if method not in BUDGET_METHODS:
        failed.append("context_budget_measurement_without_method=1")
    if budget.get("context_band") not in BUDGET_BANDS:
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
    evidence = {
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
    return failed, evidence


def validate_pack(pack: dict, schema_path: Path) -> tuple[list[str], list[dict], dict]:
    failed: list[str] = []
    repairs: list[dict] = []
    missing_sections = [section for section in SECTIONS if section not in pack]
    if missing_sections:
        failed.append(f"missing_sections={len(missing_sections)}")
        repairs.append(failure("missing_sections", "$", f"Add sections: {', '.join(missing_sections)}"))
    core = pack.get("core") if isinstance(pack.get("core"), dict) else {}
    missing_core = [key for key in CORE_KEYS if key not in core or core.get(key) in (None, "", [])]
    missing_core = [key for key in missing_core if key != "alternative_flows"]
    if missing_core:
        failed.append(f"core_keys_missing={len(missing_core)}")
        repairs.append(failure("core_keys_missing", "core", f"Complete: {', '.join(missing_core)}"))
    criteria = core.get("acceptance_criteria", [])
    criteria = criteria if isinstance(criteria, list) else []
    invalid_gwt = [index for index, item in enumerate(criteria) if not isinstance(item, dict) or not all(isinstance(item.get(key), str) and item.get(key).strip() for key in ("criterion_code", "given", "when", "then", "source_ref"))]
    if invalid_gwt:
        failed.append(f"criteria_without_given_when_then={len(invalid_gwt)}")
        repairs.append(failure("criteria_without_given_when_then", "core.acceptance_criteria", f"Repair criteria at indexes: {invalid_gwt}"))
    codes = [item.get("criterion_code") for item in criteria if isinstance(item, dict)]
    duplicate_codes = duplicate_values(code for code in codes if code)
    if duplicate_codes:
        failed.append(f"duplicate_criterion_codes={len(duplicate_codes)}")
        repairs.append(failure("duplicate_criterion_codes", "core.acceptance_criteria", f"Assign unique codes: {duplicate_codes}"))
    identity = pack.get("identity") if isinstance(pack.get("identity"), dict) else {}
    if not identity.get("source_decision_id") or not identity.get("source_snapshot_sha"):
        failed.append("stories_without_source_trace=1")
        repairs.append(failure("stories_without_source_trace", "identity", "Provide source_decision_id and source_snapshot_sha."))
    budget_failed, budget_evidence = context_budget_failures(pack)
    if budget_failed:
        failed.extend(budget_failed)
        repairs.append(failure("context_budget", "dependencies_risks.context_budget", "Provide measured budget and enforce direct-load, specialized-view and atomicity rules."))
    schema_failures = schema_errors(pack, schema_path)
    if schema_failures:
        failed.append(f"schema_validation_errors={len(schema_failures)}")
        repairs.append(failure("schema_validation_errors", "$", "Resolve every JSON Schema error without weakening the schema."))
    evidence = {
        "sections_present": len(SECTIONS) - len(missing_sections), "sections_expected": len(SECTIONS),
        "missing_sections": missing_sections, "missing_core_keys": missing_core,
        "acceptance_criteria_count": len(criteria), "invalid_criterion_indexes": invalid_gwt,
        "duplicate_criterion_codes": duplicate_codes, "context_budget": budget_evidence,
        "context_budget_failure_count": len(budget_failed), "schema_error_count": len(schema_failures),
        "schema_errors": schema_failures[:50],
    }
    return sorted(set(failed)), repairs, evidence


def sample_pack() -> dict:
    return {
        "identity":{"story_code":"ST-TEST-001","title":"Consultar saldo disponible","epic_code":None,"module_code":"MOD.TEST","screen_code":"SCR.TEST","functional_unit_code":"FU.TEST","source_decision_id":"DEC-001","source_version":"v01","source_snapshot_sha":"a"*64,"status":"CANDIDATO_READ_ONLY","priority":"P1"},
        "core":{"actor":"operador autorizado","need":"consultar el saldo disponible","benefit":"decidir una operación informada","preconditions":["sesión autenticada"],"trigger":"abre la pantalla","main_flow":["consulta el saldo y recibe respuesta"],"alternative_flows":[],"postconditions":["consulta registrada"],"acceptance_criteria":[{"criterion_code":"AC-01","given":"operador autenticado","when":"consulta el saldo","then":"visualiza el saldo autorizado","source_ref":"fixture:self-test"}],"out_of_scope":["modificar saldo"]},
        "interaction":{},"fields":[],"validations":[],"observations":[],"errors":[],"security_privacy":{},"states":{},"audit":{},"tokens_messages":{},"analytics":[],"observability":{},"responsive_accessibility":{},
        "tests":[{"test_code":"TC-01","family":"FUNCTIONAL","criterion_ref":"AC-01","rule_ref":None,"preconditions":["sesión autenticada"],"steps":["consultar saldo"],"expected_result":"saldo visible","negative":False,"critical":True,"automatable":True,"actor_profile":"OPERADOR","tenant_scope":"TENANT_A","evidence_path":"evidence/self-test.json"}],
        "dependencies_risks":{"dependencies":[],"risks":[],"pending_decisions":[],"context_budget":{"measurement_method":"ESTIMATE","canonical_story_tokens":5200,"implementation_view_tokens":2400,"active_context_tokens":9000,"context_band":"STANDARD","direct_load_allowed":True,"specialized_views_required":False,"atomicity_review_required":False,"atomicity_review_result":"NOT_REQUIRED","measured_at":"2026-07-28T00:00:00Z","model_reference":"estimate:utf8_chars_div_4","source_ref":"policy:event:795"}},
        "judges_evidence":[{"judge_code":"J03_STORY_CORE","result":"PASS_WITH_EVIDENCE"}],
    }


def self_test(schema_path: Path) -> int:
    positive = sample_pack()
    negative = deepcopy(positive)
    negative["dependencies_risks"]["context_budget"].pop("measurement_method")
    negative["dependencies_risks"]["context_budget"].update({"canonical_story_tokens":13100,"direct_load_allowed":True,"specialized_views_required":False,"atomicity_review_required":False})
    pos_failed, _, pos_evidence = validate_pack(positive, schema_path)
    neg_failed, _, neg_evidence = validate_pack(negative, schema_path)
    passed = not pos_failed and bool(neg_failed) and any("context_budget" in item or "oversized_story" in item for item in neg_failed)
    print(json.dumps({"judge_code":JUDGE,"result":"PASS_WITH_EVIDENCE" if passed else "FAIL","compliance_bit":1 if passed else 0,"positive_failed":pos_failed,"negative_failed":neg_failed,"positive_evidence":pos_evidence,"negative_evidence":neg_evidence},ensure_ascii=False,sort_keys=True))
    return 0 if passed else 1


def run() -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("input",type=Path,nargs="?")
    cli.add_argument("--schema",type=Path,default=Path(__file__).resolve().parents[1]/"schemas/story-pack.schema.json")
    cli.add_argument("--evidence-ref",action="append",default=[])
    cli.add_argument("--retry-count",type=int,default=0)
    cli.add_argument("--self-test",action="store_true")
    args=cli.parse_args()
    if args.self_test:
        return self_test(args.schema)
    if args.input is None:
        raise ValidationInputError("story_pack_input_required")
    pack=require_object(load_json(args.input),"story_pack")
    failed,repairs,evidence=validate_pack(pack,args.schema)
    evidence.update({"input_path":str(args.input),"schema_path":str(args.schema)})
    return emit(result_object(JUDGE,failed,evidence,args.evidence_ref or [f"file:{args.input}"],repairs,retry_count=args.retry_count))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE,run))
