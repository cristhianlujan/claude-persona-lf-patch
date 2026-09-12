#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

SCORE_KEYS = [
    "contract_schema_compliance",
    "evidence_integrity",
    "lf_safety_governance",
    "handoff_readiness",
    "leakage_scope_control",
]
REVIEW_KEYS = [
    "review_id",
    "reviewed_artifact",
    "verdict",
    "score_breakdown",
    "evidence_map",
    "blocking_codes",
    "repair_actions",
    "remaining_risks",
    "next_gate",
]
SOURCE_KEYS = [
    "artifact_ref",
    "upstream_worker_contract_ref",
    "quality_gate_contract_ref",
    "lf_quality_controls_ref",
    "score_rubric_ref",
    "mini_judge_ref",
    "quality_review_schema_ref",
]
VERDICTS = {
    "PASS_TO_COMPOSER",
    "PASS_WITH_RESTRICTIONS",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR",
    "BLOCK_PIPELINE",
}


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def require_nonempty_string(value, field, errors):
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{field}: expected non-empty string")


def validate_receipt(data):
    errors = []

    expected_constants = {
        "receipt_version": "v0.1",
        "execution_mode": "INDEPENDENT_CHAT_CONTEXT",
        "reviewer_is_producer": False,
        "producer_context_available": False,
        "external_paid_model_used": False,
        "automated_semantic_judge_implemented": False,
    }
    for field, expected in expected_constants.items():
        if data.get(field) != expected:
            errors.append(f"{field}: expected {expected!r}, got {data.get(field)!r}")

    require_nonempty_string(data.get("review_case_id"), "review_case_id", errors)

    review_completed = data.get("review_completed")
    if not isinstance(review_completed, bool):
        errors.append("review_completed: expected boolean")
    expected_status = "EXECUTED_INDEPENDENT_CONTEXT" if review_completed is True else "NOT_EXECUTED"
    if data.get("semantic_status") != expected_status:
        errors.append(
            f"semantic_status: expected {expected_status!r} for review_completed={review_completed!r}"
        )

    blockers = data.get("execution_blockers")
    if not isinstance(blockers, list):
        errors.append("execution_blockers: expected array")
    elif review_completed is True and blockers:
        errors.append("execution_blockers: must be empty when review_completed=true")
    elif review_completed is False and not blockers:
        errors.append("execution_blockers: must explain why review was not executed")

    source = data.get("source_bundle")
    if not isinstance(source, dict):
        errors.append("source_bundle: expected object")
    else:
        for field in SOURCE_KEYS:
            require_nonempty_string(source.get(field), f"source_bundle.{field}", errors)

    review = data.get("quality_review")
    if not isinstance(review, dict):
        errors.append("quality_review: expected object")
        return errors

    for field in REVIEW_KEYS:
        if field not in review:
            errors.append(f"quality_review.{field}: missing")

    require_nonempty_string(review.get("review_id"), "quality_review.review_id", errors)
    require_nonempty_string(review.get("reviewed_artifact"), "quality_review.reviewed_artifact", errors)
    require_nonempty_string(review.get("next_gate"), "quality_review.next_gate", errors)

    verdict = review.get("verdict")
    if verdict not in VERDICTS:
        errors.append(f"quality_review.verdict: unsupported verdict {verdict!r}")

    for field in ["evidence_map", "blocking_codes", "repair_actions", "remaining_risks"]:
        if not isinstance(review.get(field), list):
            errors.append(f"quality_review.{field}: expected array")

    if review_completed is True and isinstance(review.get("evidence_map"), list) and not review["evidence_map"]:
        errors.append("quality_review.evidence_map: completed semantic review requires observable evidence")

    score = review.get("score_breakdown")
    total = None
    if not isinstance(score, dict):
        errors.append("quality_review.score_breakdown: expected object")
    else:
        values = []
        for field in SCORE_KEYS:
            value = score.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 5:
                errors.append(f"quality_review.score_breakdown.{field}: expected integer 0..5")
            else:
                values.append(value)
        total = score.get("total")
        if not isinstance(total, int) or isinstance(total, bool) or not 0 <= total <= 25:
            errors.append("quality_review.score_breakdown.total: expected integer 0..25")
        elif len(values) == len(SCORE_KEYS) and total != sum(values):
            errors.append(
                f"quality_review.score_breakdown.total: expected arithmetic sum {sum(values)}, got {total}"
            )

    if review_completed is True and isinstance(total, int) and verdict in VERDICTS:
        allowed = set()
        if 23 <= total <= 25:
            allowed = {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"}
        elif 20 <= total <= 22:
            allowed = {"PASS_WITH_RESTRICTIONS"}
        elif 10 <= total <= 19:
            allowed = {"RETURN_TO_WORKER_FOR_SELF_REPAIR", "RETURN_TO_ORCHESTRATOR"}
        elif 0 <= total <= 9:
            allowed = {"BLOCK_PIPELINE"}
        if verdict not in allowed:
            errors.append(
                f"quality_review.verdict: {verdict} incompatible with rubric total {total}; allowed={sorted(allowed)}"
            )

        if verdict == "PASS_TO_COMPOSER" and review.get("blocking_codes"):
            errors.append("quality_review.blocking_codes: PASS_TO_COMPOSER cannot carry blocking codes")
        if verdict == "PASS_WITH_RESTRICTIONS" and not review.get("remaining_risks"):
            errors.append("quality_review.remaining_risks: PASS_WITH_RESTRICTIONS requires explicit remaining risk")
        if verdict in {"RETURN_TO_WORKER_FOR_SELF_REPAIR", "RETURN_TO_ORCHESTRATOR"} and not review.get("repair_actions"):
            errors.append(f"quality_review.repair_actions: {verdict} requires repair actions")

    return errors


def run_matrix(matrix_path: Path):
    matrix = load_json(matrix_path)
    repo_root = Path(__file__).resolve().parents[3]
    results = []
    failed = False
    for case in matrix.get("cases", []):
        case_id = case.get("case_id", "UNKNOWN")
        fixture = repo_root / case["fixture"]
        errors = validate_receipt(load_json(fixture))
        actual_valid = not errors
        expected_valid = bool(case["expected_valid"])
        passed = actual_valid == expected_valid
        failed = failed or not passed
        results.append(
            {
                "case_id": case_id,
                "expected_valid": expected_valid,
                "actual_valid": actual_valid,
                "passed": passed,
                "errors": errors,
            }
        )
    print(json.dumps({"matrix": str(matrix_path), "passed": not failed, "results": results}, indent=2))
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("receipt", nargs="?", help="receipt JSON to validate")
    parser.add_argument("--matrix", help="eval matrix JSON")
    args = parser.parse_args()

    if bool(args.receipt) == bool(args.matrix):
        parser.error("provide exactly one receipt path or --matrix")

    if args.matrix:
        return run_matrix(Path(args.matrix))

    path = Path(args.receipt)
    errors = validate_receipt(load_json(path))
    result = {"receipt": str(path), "valid": not errors, "errors": errors}
    print(json.dumps(result, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
