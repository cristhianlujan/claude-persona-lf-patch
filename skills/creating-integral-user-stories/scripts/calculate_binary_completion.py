"""Compute binary completion and enforce all J13 close conditions."""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object

JUDGE = "J13_INTEGRATION_CLOSE"
VERSION = "v0.5"
ZERO_CLOSE_FIELDS = (
    "critical_steps_with_bit_zero", "steps_without_evidence", "judges_pending",
    "failed_assertions_open", "blocking_findings_open", "expected_files_not_written",
    "written_files_not_read_back", "sha_mismatches",
)


def _obj(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def _steps(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not value:
        raise ValidationInputError("execution_steps_missing")
    if not all(isinstance(item, dict) for item in value):
        raise ValidationInputError("execution_step_must_be_object")
    return value


def validate_ledger(ledger: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    steps = _steps(ledger.get("steps"))
    evaluable = [s for s in steps if s.get("applicable") is not False and (s.get("required") is True or s.get("applicable") is True)]
    passed = [s for s in evaluable if s.get("status") == "PASS_WITH_EVIDENCE" and s.get("compliance_bit") == 1 and s.get("evidence_refs") and s.get("judge_result") == "PASS_WITH_EVIDENCE" and not s.get("failed_assertions")]
    total = len(evaluable)
    calculated = round(len(passed) * 100.0 / total, 2) if total else 0.0
    close = _obj(ledger.get("close_conditions"), "close_conditions")
    checks: dict[str, int] = {
        "required_steps_not_passed": total - len(passed),
        "completion_percent_not_100": 0 if calculated == 100.0 else 1,
        "declared_completion_mismatch": 0 if ledger.get("completion_percent") == calculated else 1,
        "final_result_not_pass": 0 if ledger.get("final_result") == "PASS_WITH_EVIDENCE" else 1,
        "production_authorized": 0 if ledger.get("production_authorized") is False else 1,
        "merge_authorized": 0 if ledger.get("merge_authorized") is False else 1,
        "runtime_enabled": 0 if ledger.get("runtime_enabled") is False else 1,
        "draft_pr_not_preserved": 0 if ledger.get("draft_pr") is True else 1,
        "repository_missing": 0 if isinstance(ledger.get("repository"), str) and ledger.get("repository") else 1,
        "branch_missing": 0 if isinstance(ledger.get("branch"), str) and ledger.get("branch") else 1,
        "commit_sha_invalid": 0 if isinstance(ledger.get("commit_sha"), str) and len(ledger.get("commit_sha")) == 40 else 1,
    }
    for field in ZERO_CLOSE_FIELDS:
        checks[field] = int(close.get(field, -1)) if isinstance(close.get(field), int) else 1
    evidence = {
        "checks": checks,
        "steps_evaluable": total,
        "steps_passed_with_evidence": len(passed),
        "calculated_completion_percent": calculated,
        "declared_completion_percent": ledger.get("completion_percent"),
        "close_conditions": close,
        "final_result": ledger.get("final_result"),
        "repository": ledger.get("repository"),
        "branch": ledger.get("branch"),
        "commit_sha": ledger.get("commit_sha"),
    }
    return checks, evidence


def run(path: Path, refs: list[str], retry: int) -> int:
    ledger = _obj(load_json(path), "execution_ledger")
    try:
        checks, evidence = validate_ledger(ledger)
    except ValidationInputError as exc:
        evidence = {"checks": {"execution_steps_missing": 1}, "input_path": str(path), "error": str(exc)}
        return emit(result_object(
            JUDGE, [], evidence, refs or [f"file:{path}"],
            blocking_assertions=["execution_steps_missing"], retry_count=retry,
            forced_result="BLOCKED", judge_version=VERSION,
            executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_CLOSE_VALIDATOR",
        ))
    evidence["input_path"] = str(path)
    failed = [key for key, value in checks.items() if value]
    repairs = [failure(key, "$", f"Repair ledger until {key}=0") for key in failed]
    return emit(result_object(
        JUDGE, failed, evidence, refs or [f"file:{path}"], repairs,
        retry_count=retry, judge_version=VERSION,
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_CLOSE_VALIDATOR",
    ))


def positive() -> dict[str, Any]:
    step = {
        "step_id": "S1", "step_order": 1, "execution_order": 1,
        "required": True, "critical": True, "applicable": True,
        "status": "PASS_WITH_EVIDENCE", "compliance_bit": 1,
        "input_refs": ["I1"], "output_refs": ["O1"], "evidence_refs": ["E1"],
        "judge_code": "J01_SOURCE_INTEGRITY", "judge_result": "PASS_WITH_EVIDENCE",
        "failed_assertions": [], "retry_count": 0,
    }
    return {
        "execution_id": "EXEC-X", "operation_code": "BUILD_INTEGRAL_STORY_CREATOR_LF",
        "target_artifact": "skill", "steps": [step], "completion_percent": 100.0,
        "close_conditions": {field: 0 for field in ZERO_CLOSE_FIELDS},
        "final_result": "PASS_WITH_EVIDENCE", "repository": "owner/repo", "branch": "feat/r8",
        "commit_sha": "a" * 40, "draft_pr": True,
        "production_authorized": False, "merge_authorized": False, "runtime_enabled": False,
    }


def self_test() -> int:
    good = positive()
    bad = json.loads(json.dumps(good))
    bad["steps"][0]["evidence_refs"] = []
    bad["completion_percent"] = 100.0
    bad["close_conditions"]["steps_without_evidence"] = 1
    good_checks, _ = validate_ledger(good)
    bad_checks, _ = validate_ledger(bad)
    result = {
        "positive_pass": all(v == 0 for v in good_checks.values()),
        "false_close_rejected": bad_checks["required_steps_not_passed"] > 0 and bad_checks["completion_percent_not_100"] > 0 and bad_checks["steps_without_evidence"] > 0,
        "positive_checks": good_checks,
        "negative_checks": bad_checks,
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if result["positive_pass"] and result["false_close_rejected"] else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--evidence-ref", action="append", default=[])
    parser.add_argument("--retry-count", type=int, default=0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise ValidationInputError("input_required")
    return run(args.input, args.evidence_ref, args.retry_count)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
