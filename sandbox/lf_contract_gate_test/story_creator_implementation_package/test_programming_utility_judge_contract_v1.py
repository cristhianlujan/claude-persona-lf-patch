#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "programming_utility_judge_contract_v1.json"


def validate(contract: dict, evidence: dict) -> list[str]:
    errors: list[str] = []
    if contract.get("schema_version") != "STORY_PROGRAMMING_UTILITY_JUDGE_CONTRACT_V1":
        return ["UTILITY_JUDGE_CONTRACT_SCHEMA_INVALID"]

    governance = contract.get("governance", {})
    if governance.get("owner_scope") != "SUPER_ADMIN":
        errors.append("OWNER_SCOPE_MUST_BE_SUPER_ADMIN")
    if governance.get("validation_model") != "GOVERNED_SINGLE_JUDGE":
        errors.append("VALIDATION_MODEL_MUST_BE_SINGLE_JUDGE")
    if governance.get("second_owner_required") is not False:
        errors.append("SECOND_OWNER_FORBIDDEN")
    if governance.get("second_semantic_review_required") is not False:
        errors.append("SECOND_SEMANTIC_REVIEW_FORBIDDEN")

    reuse = contract.get("reuse", {})
    if reuse.get("new_capability_created") is not False:
        errors.append("PARALLEL_JUDGE_CAPABILITY_FORBIDDEN")
    if reuse.get("strategy_review_operation_reused") is not False:
        errors.append("STRATEGY_REVIEW_OPERATION_FOR_STORY_FORBIDDEN")

    closure = contract.get("closure_rule", {})
    if closure.get("structural_pass_alone_is_sufficient") is not False:
        errors.append("STRUCTURAL_PASS_MUST_NOT_CLOSE")
    if closure.get("governed_judge_required") is not True:
        errors.append("GOVERNED_JUDGE_REQUIRED")
    if closure.get("second_judge_required") is not False:
        errors.append("SECOND_JUDGE_FORBIDDEN")
    if closure.get("independent_assurance_receipt_required") is not False:
        errors.append("SECOND_SEMANTIC_REVIEW_FORBIDDEN")
    if closure.get("strategy_independent_review_for_story_forbidden") is not True:
        errors.append("STRATEGY_REVIEW_OPERATION_FOR_STORY_FORBIDDEN")

    for key in contract.get("required_subject_bindings", []):
        if not evidence.get(key):
            errors.append(f"SUBJECT_BINDING_MISSING:{key}")

    if evidence.get("review_subject") != contract.get("subject"):
        errors.append("REVIEW_SUBJECT_MISMATCH")
    if evidence.get("structural_result") != "PASS":
        errors.append("STRUCTURAL_EVIDENCE_NOT_PASS")
    if evidence.get("judge_result") != closure.get("judge_result_required"):
        errors.append("JUDGE_RESULT_NOT_PASS_WITH_EVIDENCE")

    dims = set(contract.get("utility_dimensions", []))
    observed = set(evidence.get("utility_dimensions_checked", []))
    for missing in sorted(dims - observed):
        errors.append(f"UTILITY_DIMENSION_MISSING:{missing}")
    return errors


def valid_evidence() -> dict:
    return {
        "subject_sha256": "a" * 64,
        "source_revision": "ONB_004@v0.4",
        "review_subject": "STORY_IMPLEMENTATION_PACKAGE",
        "judge_result_ref": "judge://SC-M3.4/current",
        "structural_evidence_ref": "github-actions://story-structural/1",
        "authority_evidence_ref": "lf_ops://ONB_004/readback",
        "structural_result": "PASS",
        "judge_result": "PASS_WITH_EVIDENCE",
        "utility_dimensions_checked": [
            "implementation_actionability",
            "source_fidelity",
            "reuse_correctness",
            "context_sufficiency",
            "acceptance_executability"
        ]
    }


def main() -> int:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    base = valid_evidence()
    cases: list[tuple[str, dict, dict, str | None]] = [
        ("positive_single_governed_judge", contract, base, None)
    ]

    def neg(name: str, evidence_mutate, expected: str) -> None:
        c = copy.deepcopy(contract)
        e = copy.deepcopy(base)
        evidence_mutate(e)
        cases.append((name, c, e, expected))

    def contract_neg(name: str, contract_mutate, expected: str) -> None:
        c = copy.deepcopy(contract)
        e = copy.deepcopy(base)
        contract_mutate(c)
        cases.append((name, c, e, expected))

    neg("structural_only_without_judge", lambda e: e.__setitem__("judge_result", None), "JUDGE_RESULT_NOT_PASS_WITH_EVIDENCE")
    neg("missing_judge_result_ref", lambda e: e.pop("judge_result_ref"), "SUBJECT_BINDING_MISSING:judge_result_ref")
    neg("missing_source_revision", lambda e: e.pop("source_revision"), "SUBJECT_BINDING_MISSING:source_revision")
    neg("wrong_subject", lambda e: e.__setitem__("review_subject", "STRATEGY"), "REVIEW_SUBJECT_MISMATCH")
    neg("missing_utility_dimension", lambda e: e["utility_dimensions_checked"].remove("context_sufficiency"), "UTILITY_DIMENSION_MISSING:context_sufficiency")
    contract_neg("second_judge_requested", lambda c: c["closure_rule"].__setitem__("second_judge_required", True), "SECOND_JUDGE_FORBIDDEN")
    contract_neg("second_independent_receipt_requested", lambda c: c["closure_rule"].__setitem__("independent_assurance_receipt_required", True), "SECOND_SEMANTIC_REVIEW_FORBIDDEN")
    contract_neg("owner_split_requested", lambda c: c["governance"].__setitem__("owner_scope", "SEPARATE_OWNER"), "OWNER_SCOPE_MUST_BE_SUPER_ADMIN")
    contract_neg("strategy_review_reused", lambda c: c["reuse"].__setitem__("strategy_review_operation_reused", True), "STRATEGY_REVIEW_OPERATION_FOR_STORY_FORBIDDEN")

    results = []
    for name, case_contract, evidence, expected in cases:
        errors = validate(case_contract, evidence)
        ok = (not errors) if expected is None else expected in errors
        results.append({"case": name, "expected": expected or "PASS", "ok": ok, "errors": errors})

    passed = sum(1 for r in results if r["ok"])
    out = {
        "schema": "SC_M3_4_PROGRAMMING_UTILITY_JUDGE_SELF_TEST_V1",
        "cases_total": len(results),
        "cases_passed": passed,
        "result": "PASS" if passed == len(results) else "FAIL",
        "results": results,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
