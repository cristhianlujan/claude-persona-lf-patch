#!/usr/bin/env python3
"""Fail-closed contract gate for independent J00/J00R P0 decisions."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

from p0_schema import validate_instance

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "schemas" / "p0-judge-decision.schema.json"
FIXTURES = ROOT / "evals" / "p0-contract-fixtures.json"


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def schema_errors(payload: Any) -> list[str]:
    schema = load(SCHEMA)
    return validate_instance(schema, payload)


def validate(payload: Any) -> dict[str, Any]:
    errors = schema_errors(payload)
    if not isinstance(payload, dict):
        return {"result": "BLOCKED", "blocking_assertions": ["judge_schema_invalid"], "schema_errors": errors}

    judge_code = payload.get("judge_code")
    result = payload.get("result")
    ready_result = result in {"J00_READY_FOR_P1", "J00R_READY_FOR_P1"}
    expected_ready = {
        "J00_P0_VISUAL_READING": "J00_READY_FOR_P1",
        "J00R_P0_REJUDGMENT": "J00R_READY_FOR_P1",
    }.get(judge_code)
    checks = {
        "judge_schema_invalid": len(errors),
        "worker_judge_execution_not_independent": 0 if payload.get("worker_execution_id") != payload.get("judge_execution_id") else 1,
        "worker_judge_identity_not_independent": 0 if payload.get("worker_identity") != payload.get("judge_identity") else 1,
        "critical_screen_requires_l3": 1 if ready_result and payload.get("critical_screen") is True and payload.get("independence_level") != "L3" else 0,
        "judge_ready_result_mismatch": 1 if ready_result and result != expected_ready else 0,
        "human_review_cannot_be_ready": 1 if payload.get("requires_human_review") is True and ready_result else 0,
        "j00r_requires_adjudication_overlay": 1 if judge_code == "J00R_P0_REJUDGMENT" and not payload.get("adjudication_overlay_ref") else 0,
        "j00_cannot_use_adjudication_overlay": 1 if judge_code == "J00_P0_VISUAL_READING" and payload.get("adjudication_overlay_ref") is not None else 0,
    }
    failed = sorted(key for key, value in checks.items() if value)
    return {
        "result": "PASS_WITH_EVIDENCE" if not failed else "BLOCKED",
        "blocking_assertions": failed,
        "checks": checks,
        "schema_errors": errors,
        "decision_id": payload.get("decision_id"),
        "empirical_visual_quality_claimed": False,
    }


def positive_fixture() -> dict[str, Any]:
    doc = load(FIXTURES)
    return copy.deepcopy(next(case["positive"] for case in doc["cases"] if case["schema"] == "p0-judge-decision.schema.json"))


def self_test() -> int:
    good = positive_fixture()
    positive = validate(good)
    cases: list[tuple[str, dict[str, Any], str]] = []
    x = copy.deepcopy(good); x["judge_identity"] = x["worker_identity"]; cases.append(("self_approval_identity", x, "worker_judge_identity_not_independent"))
    x = copy.deepcopy(good); x["judge_execution_id"] = x["worker_execution_id"]; cases.append(("shared_execution", x, "worker_judge_execution_not_independent"))
    x = copy.deepcopy(good); x["critical_screen"] = True; x["independence_level"] = "L2"; cases.append(("critical_screen_l2", x, "critical_screen_requires_l3"))
    x = copy.deepcopy(good); x["requires_human_review"] = True; cases.append(("review_required_but_ready", x, "human_review_cannot_be_ready"))
    x = copy.deepcopy(good); x["judge_code"] = "J00R_P0_REJUDGMENT"; x["result"] = "J00R_READY_FOR_P1"; cases.append(("j00r_without_adjudication", x, "j00r_requires_adjudication_overlay"))
    x = copy.deepcopy(good); x["result"] = "J00R_READY_FOR_P1"; cases.append(("judge_result_mismatch", x, "judge_ready_result_mismatch"))

    outcomes = []
    for name, candidate, expected in cases:
        result = validate(candidate)
        outcomes.append({"name": name, "expected_assertion": expected, "passed": result["result"] == "BLOCKED" and expected in result["blocking_assertions"]})

    good_j00r = copy.deepcopy(good)
    good_j00r.update({"decision_id": "DEC-P0R-1", "judge_code": "J00R_P0_REJUDGMENT", "result": "J00R_READY_FOR_P1", "judge_execution_id": "EXEC-J00R-1", "judge_identity": "AGENT-J00R-1", "adjudication_overlay_ref": "p0://adjudication/REV-1"})
    positive_j00r = validate(good_j00r)
    passed = positive["result"] == "PASS_WITH_EVIDENCE" and positive_j00r["result"] == "PASS_WITH_EVIDENCE" and all(item["passed"] for item in outcomes)
    print(json.dumps({"positive_j00_pass": positive["result"] == "PASS_WITH_EVIDENCE", "positive_j00r_pass": positive_j00r["result"] == "PASS_WITH_EVIDENCE", "negative_cases_passed": sum(item["passed"] for item in outcomes), "negative_cases_total": len(outcomes), "negative_results": outcomes, "empirical_visual_quality_claimed": False, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    result = validate(load(args.input))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["result"] == "PASS_WITH_EVIDENCE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
