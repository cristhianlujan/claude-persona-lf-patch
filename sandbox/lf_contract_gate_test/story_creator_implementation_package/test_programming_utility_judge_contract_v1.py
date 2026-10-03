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
    reuse = contract.get("reuse", {})
    if reuse.get("review_capability") != "INDEPENDENT_ASSURANCE":
        errors.append("INDEPENDENT_ASSURANCE_NOT_REUSED")
    if reuse.get("qualification_owner") != "QUALIFICATION_FRAMEWORK":
        errors.append("QUALIFICATION_OWNER_DRIFT")
    if reuse.get("new_capability_created") is not False:
        errors.append("PARALLEL_JUDGE_CAPABILITY_FORBIDDEN")

    independence = contract.get("independence", {})
    if independence.get("reviewer_binding_resolution") != "TRANSVERSAL_SUBJECT_BINDING_AT_EXECUTION_TIME":
        errors.append("SUBJECT_BINDING_RESOLUTION_DRIFT")
    if contract.get("subject") != "STRATEGY" and (
        independence.get("reviewer_operation") == "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"
        or independence.get("router_action") == "STRATEGY_INDEPENDENT_REVIEW"
    ):
        errors.append("STRATEGY_SPECIFIC_REVIEW_ROUTE_FORBIDDEN")

    closure = contract.get("closure_rule", {})
    if closure.get("structural_pass_alone_is_sufficient") is not False:
        errors.append("STRUCTURAL_PASS_MUST_NOT_CLOSE")
    if closure.get("independent_review_required") is not True:
        errors.append("INDEPENDENT_REVIEW_NOT_REQUIRED")
    if closure.get("review_receipt_required") is not True:
        errors.append("REVIEW_RECEIPT_NOT_REQUIRED")

    for key in contract.get("required_subject_bindings", []):
        if not evidence.get(key):
            errors.append(f"SUBJECT_BINDING_MISSING:{key}")

    if evidence.get("review_subject") != contract.get("subject"):
        errors.append("REVIEW_SUBJECT_MISMATCH")
    if evidence.get("structural_result") != "PASS":
        errors.append("STRUCTURAL_EVIDENCE_NOT_PASS")
    if evidence.get("review_capability") != "INDEPENDENT_ASSURANCE":
        errors.append("REVIEW_CAPABILITY_MISMATCH")
    if evidence.get("builder_execution_id") == evidence.get("reviewer_execution_id"):
        errors.append("BUILDER_REVIEWER_NOT_INDEPENDENT")
    if evidence.get("review_result") != "PASS_WITH_EVIDENCE":
        errors.append("INDEPENDENT_REVIEW_NOT_PASS_WITH_EVIDENCE")
    if not evidence.get("review_receipt_ref"):
        errors.append("REVIEW_RECEIPT_MISSING")

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
        "reviewer_binding_ref": "assurance-subject-binding://story-implementation-package/current",
        "builder_execution_id": "EXEC-STORY-BUILDER-001",
        "reviewer_execution_id": "EXEC-INDEPENDENT-REVIEW-001",
        "structural_evidence_ref": "github-actions://story-structural/1",
        "authority_evidence_ref": "lf_ops://ONB_004/readback",
        "structural_result": "PASS",
        "review_capability": "INDEPENDENT_ASSURANCE",
        "review_result": "PASS_WITH_EVIDENCE",
        "review_receipt_ref": "review-receipt://candidate/1",
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
        ("positive_independent_review", contract, base, None)
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

    neg("structural_only_no_receipt", lambda e: (e.__setitem__("review_result", None), e.__setitem__("review_receipt_ref", None)), "INDEPENDENT_REVIEW_NOT_PASS_WITH_EVIDENCE")
    neg("same_builder_and_reviewer", lambda e: e.__setitem__("reviewer_execution_id", e["builder_execution_id"]), "BUILDER_REVIEWER_NOT_INDEPENDENT")
    neg("wrong_review_capability", lambda e: e.__setitem__("review_capability", "LOCAL_STORY_JUDGE"), "REVIEW_CAPABILITY_MISMATCH")
    neg("missing_source_revision", lambda e: e.pop("source_revision"), "SUBJECT_BINDING_MISSING:source_revision")
    neg("missing_reviewer_binding", lambda e: e.pop("reviewer_binding_ref"), "SUBJECT_BINDING_MISSING:reviewer_binding_ref")
    neg("wrong_subject", lambda e: e.__setitem__("review_subject", "STRATEGY"), "REVIEW_SUBJECT_MISMATCH")
    neg("missing_utility_dimension", lambda e: e["utility_dimensions_checked"].remove("context_sufficiency"), "UTILITY_DIMENSION_MISSING:context_sufficiency")
    contract_neg("strategy_specific_router_hardcode", lambda c: c["independence"].__setitem__("router_action", "STRATEGY_INDEPENDENT_REVIEW"), "STRATEGY_SPECIFIC_REVIEW_ROUTE_FORBIDDEN")
    contract_neg("strategy_specific_operation_hardcode", lambda c: c["independence"].__setitem__("reviewer_operation", "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"), "STRATEGY_SPECIFIC_REVIEW_ROUTE_FORBIDDEN")

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
