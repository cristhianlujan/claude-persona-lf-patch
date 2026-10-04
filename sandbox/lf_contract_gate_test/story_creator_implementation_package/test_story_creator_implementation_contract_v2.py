#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "story_creator_implementation_contract_v2.json"
CURRENT_PATH = HERE / "story_creator_current_contract.json"
LEGACY_PACKAGE_PATH = HERE / "fixtures" / "onb_004_implementation_package_v1_1.json"

REQUIRED_CLASSES = {
    "API_ENDPOINT",
    "FILE_LIMIT",
    "NFR",
    "RESPONSIVE",
    "MOBILE",
    "ANALYTICS",
    "DESIGN_TOKEN",
    "PHYSICAL_BINDING",
    "DOMAIN_APP_SHELL",
}
OPEN_PHRASES = {"funciona bien", "se ve correcto", "se ve igual", "guarda bien"}
UNRESOLVED = {"PENDING_SOURCE_DEFINITION", "SOURCE_CONFLICT", "IMPLEMENTATION_PRECONDITION"}


def validate_contract(contract: dict, pointer: dict) -> list[str]:
    errors: list[str] = []
    if contract.get("schema_version") != "STORY_CREATOR_IMPLEMENTATION_CONTRACT_V2":
        errors.append("CONTRACT_SCHEMA_INVALID")
    if contract.get("contract_state") != "CURRENT":
        errors.append("CONTRACT_NOT_CURRENT")
    if contract.get("owner_scope") != "SUPER_ADMIN":
        errors.append("OWNER_SCOPE_NOT_SUPER_ADMIN")

    carrier = contract.get("carrier_compatibility", {})
    if carrier.get("direct_legacy_semantics_consumption_allowed") is not False:
        errors.append("LEGACY_DIRECT_CONSUMPTION_NOT_BLOCKED")
    if carrier.get("current_projection_required") is not True:
        errors.append("CURRENT_PROJECTION_NOT_REQUIRED")

    vm = contract.get("validation_model", {})
    if vm.get("semantic_judges_per_candidate") != 1:
        errors.append("JUDGE_CARDINALITY_NOT_ONE")
    if vm.get("second_judge_required") is not False or vm.get("second_semantic_review_required") is not False:
        errors.append("SECOND_REVIEW_REINTRODUCED")
    if vm.get("strategy_specific_review_route_for_story_forbidden") is not True:
        errors.append("STRATEGY_ROUTE_NOT_FORBIDDEN_FOR_STORY")

    reuse = contract.get("reuse_and_creation", {})
    if reuse.get("owner_separation_requirement_for_story_forbidden") is not True:
        errors.append("OWNER_SEPARATION_RESTRICTION_REINTRODUCED")
    if reuse.get("owner_scope") != "SUPER_ADMIN":
        errors.append("REUSE_OWNER_SCOPE_DRIFT")
    if reuse.get("parallel_transversal_engine_forbidden") is not True:
        errors.append("PARALLEL_ENGINE_NOT_FORBIDDEN")

    classes = set(contract.get("material_requirement_classes", []))
    missing = sorted(REQUIRED_CLASSES - classes)
    if missing:
        errors.append("MATERIAL_CLASSES_MISSING:" + ",".join(missing))

    material = contract.get("material_requirement_contract", {})
    if material.get("blocking_rule") != "UNRESOLVED_REQUIRED_BLOCKS_AFFECTED_SCOPE_ONLY":
        errors.append("LOCAL_BLOCKING_RULE_DRIFT")
    if material.get("global_story_block_from_local_gap_forbidden") is not True:
        errors.append("LOCAL_GAP_GLOBAL_BLOCK_ALLOWED")
    if material.get("silent_default_or_inference_forbidden") is not True:
        errors.append("SILENT_INFERENCE_ALLOWED")

    authority = contract.get("authority_precedence", {})
    if authority.get("business_rule_from_visual_only_forbidden") is not True:
        errors.append("VISUAL_TO_BUSINESS_RULE_PROMOTION_ALLOWED")
    if authority.get("design_literals_require_canonical_design_authority") is not True:
        errors.append("DESIGN_LITERAL_WITHOUT_AUTHORITY_ALLOWED")
    if authority.get("domain_and_app_shell_must_match_exact_target") is not True:
        errors.append("DOMAIN_APP_SHELL_BINDING_NOT_REQUIRED")

    actions = contract.get("implementation_action_contract", {})
    if actions.get("high_impact_action_requires_affected_surface_evidence") is not True:
        errors.append("HIGH_IMPACT_ACTION_WITHOUT_EVIDENCE_ALLOWED")
    if actions.get("scope_inflation_forbidden") is not True:
        errors.append("SCOPE_INFLATION_ALLOWED")

    acceptance = contract.get("executable_acceptance_contract", {})
    if acceptance.get("free_text_only_forbidden") is not True:
        errors.append("FREE_TEXT_ACCEPTANCE_ALLOWED")
    if acceptance.get("open_phrases_without_fixture_expected_or_error_behavior_forbidden") is not True:
        errors.append("OPEN_ACCEPTANCE_ALLOWED")

    if pointer.get("current_contract") != contract.get("schema_version"):
        errors.append("CURRENT_POINTER_DRIFT")
    if pointer.get("legacy_direct_consumption_allowed") is not False:
        errors.append("CURRENT_POINTER_ALLOWS_LEGACY")
    if pointer.get("owner_scope") != "SUPER_ADMIN":
        errors.append("CURRENT_POINTER_OWNER_DRIFT")
    return errors


def evaluate_material_requirements(requirements: list[dict]) -> dict:
    blocked: list[dict] = []
    for req in requirements:
        if req["requiredness"] == "REQUIRED" and req["state"] in UNRESOLVED:
            blocked.append({"requirement_code": req["requirement_code"], "affected_scope": req["affected_scope"]})
    return {
        "result": "BLOCKED" if blocked else "PASS",
        "blocked": blocked,
        "whole_story_blocked": any(x["affected_scope"] == "WHOLE_HANDOFF" for x in blocked),
    }


def acceptance_case_valid(case: dict) -> bool:
    required = {"case_code", "kind", "fixture_ref", "expected_result", "error_behavior"}
    if not required.issubset(case):
        return False
    text = " ".join(str(case.get(k, "")).strip().lower() for k in ("expected_result", "error_behavior"))
    if any(phrase in text for phrase in OPEN_PHRASES):
        return False
    return bool(case["fixture_ref"] and case["expected_result"] and case["error_behavior"])


def main() -> int:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    pointer = json.loads(CURRENT_PATH.read_text(encoding="utf-8"))
    legacy = json.loads(LEGACY_PACKAGE_PATH.read_text(encoding="utf-8"))
    cases: list[dict] = []

    errors = validate_contract(contract, pointer)
    cases.append({"case": "current_contract_positive", "ok": not errors, "errors": errors})

    cases.append({
        "case": "legacy_carrier_is_compatibility_input_not_current_semantics",
        "ok": legacy.get("package_version") in contract["carrier_compatibility"]["accepted_input_carriers"]
              and contract["carrier_compatibility"]["direct_legacy_semantics_consumption_allowed"] is False,
        "errors": [],
    })

    reqs = [
        {
            "requirement_code": "API-1", "requirement_class": "API_ENDPOINT", "applicability": "APPLICABLE",
            "requiredness": "REQUIRED", "state": "PENDING_SOURCE_DEFINITION", "affected_scope": "DELIVERABLE",
            "authority_ref": "authority://api", "evidence_refs": [], "resolution_rule": "resolve exact endpoint or block",
        },
        {
            "requirement_code": "DS-1", "requirement_class": "DESIGN_TOKEN", "applicability": "APPLICABLE",
            "requiredness": "REQUIRED", "state": "RESOLVED_FROM_AUTHORITY", "affected_scope": "DELIVERABLE",
            "authority_ref": "lf_design://token", "evidence_refs": ["lf_design://token#sha"], "resolution_rule": "use exact token",
        },
    ]
    evaluation = evaluate_material_requirements(reqs)
    cases.append({
        "case": "missing_api_blocks_only_affected_deliverable",
        "ok": evaluation["result"] == "BLOCKED" and evaluation["whole_story_blocked"] is False
              and evaluation["blocked"] == [{"requirement_code": "API-1", "affected_scope": "DELIVERABLE"}],
        "errors": [] if evaluation["whole_story_blocked"] is False else ["LOCAL_GAP_GLOBAL_BLOCKED"],
    })

    good_acceptance = {
        "case_code": "SAVE-VALID-001", "kind": "POSITIVE", "fixture_ref": "fixture://valid-client-data",
        "expected_result": "HTTP_200_AND_CLIENT_ONBOARDING_COMPLETED", "error_behavior": "NONE",
    }
    bad_acceptance = {
        "case_code": "VAGUE-001", "kind": "POSITIVE", "fixture_ref": "fixture://x",
        "expected_result": "funciona bien", "error_behavior": "se ve correcto",
    }
    cases.append({"case": "executable_acceptance_positive", "ok": acceptance_case_valid(good_acceptance), "errors": []})
    cases.append({"case": "vague_acceptance_rejected", "ok": not acceptance_case_valid(bad_acceptance), "errors": []})

    mutations = [
        ("second_judge_rejected", lambda c: c["validation_model"].__setitem__("second_judge_required", True), "SECOND_REVIEW_REINTRODUCED"),
        ("owner_separation_rejected", lambda c: c["reuse_and_creation"].__setitem__("owner_separation_requirement_for_story_forbidden", False), "OWNER_SEPARATION_RESTRICTION_REINTRODUCED"),
        ("visual_business_rule_rejected", lambda c: c["authority_precedence"].__setitem__("business_rule_from_visual_only_forbidden", False), "VISUAL_TO_BUSINESS_RULE_PROMOTION_ALLOWED"),
        ("unbounded_impact_rejected", lambda c: c["implementation_action_contract"].__setitem__("high_impact_action_requires_affected_surface_evidence", False), "HIGH_IMPACT_ACTION_WITHOUT_EVIDENCE_ALLOWED"),
    ]
    for name, mutate, expected in mutations:
        candidate = copy.deepcopy(contract)
        mutate(candidate)
        errs = validate_contract(candidate, pointer)
        cases.append({"case": name, "ok": expected in errs, "errors": errs})

    passed = sum(1 for c in cases if c["ok"])
    out = {
        "schema": "SC_M5_1_CURRENT_CONTRACT_SELF_TEST_V1",
        "cases_total": len(cases),
        "cases_passed": passed,
        "result": "PASS" if passed == len(cases) else "FAIL",
        "cases": cases,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
