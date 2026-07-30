#!/usr/bin/env python3
"""Deep runtime audit for A07 evals/evals.json."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
TARGET = SKILL / "evals" / "evals.json"
ASSERTIONS = SKILL / "evals" / "assertions.json"
VALID_RESULTS = {"PASS_WITH_EVIDENCE", "RETURN_TO_WORKER", "BLOCKED", "FAIL"}


def env() -> dict[str, str]:
    value = os.environ.copy()
    value.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A07_RUNNER")
    return value


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def run_case(case_id: str, expected_candidate: str) -> dict[str, Any]:
    command = [sys.executable, "scripts/validate_story_pack.py", "--case-id", case_id]
    proc = subprocess.run(command, cwd=SKILL, env=env(), text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        evidence = result.get("evidence", {})
        passed = (
            proc.returncode == 0
            and result.get("result") == "PASS_WITH_EVIDENCE"
            and evidence.get("case_id") == case_id
            and evidence.get("expected_validation_result") == expected_candidate
            and evidence.get("actual_validation_result") == expected_candidate
            and evidence.get("matched") is True
            and (expected_candidate != "RETURN_TO_WORKER" or evidence.get("negative_must_be_rejected") is True)
        )
        return {
            "case_id": case_id,
            "passed": passed,
            "process_exit_code": proc.returncode,
            "wrapper_result": result.get("result"),
            "candidate_expected": expected_candidate,
            "candidate_actual": evidence.get("actual_validation_result"),
            "candidate_failed_assertions": evidence.get("candidate_failed_assertions"),
            "input_sha256": result.get("input_sha256"),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
        }
    except Exception as exc:
        return {"case_id": case_id, "passed": False, "process_exit_code": proc.returncode, "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-1000:], "error": f"{type(exc).__name__}:{exc}"}


def run_self_test() -> dict[str, Any]:
    command = [sys.executable, "scripts/validate_story_pack.py", "--self-test"]
    proc = subprocess.run(command, cwd=SKILL, env=env(), text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        passed = proc.returncode == 0 and result.get("result") == "PASS_WITH_EVIDENCE" and not result.get("positive_failed") and bool(result.get("negative_failed"))
        return {"case_id": "J03_SELF_TEST", "passed": passed, "process_exit_code": proc.returncode, "result": result}
    except Exception as exc:
        return {"case_id": "J03_SELF_TEST", "passed": False, "process_exit_code": proc.returncode, "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-1000:], "error": f"{type(exc).__name__}:{exc}"}


def main() -> int:
    data = json.loads(TARGET.read_text(encoding="utf-8"))
    assertion_data = json.loads(ASSERTIONS.read_text(encoding="utf-8"))
    known_assertions = {row.get("id") for row in assertion_data.get("assertions", []) if isinstance(row, dict)}
    legacy = data.get("legacy_cases", [])
    executable = data.get("executable_cases", [])
    all_cases = list(legacy) + list(executable)

    ids = [case.get("id") for case in all_cases if isinstance(case, dict)]
    duplicate_ids = sorted({item for item in ids if item and ids.count(item) > 1})
    malformed: list[str] = []
    unknown_assertions: set[str] = set()
    missing_fixtures: set[str] = set()
    missing_evidence_paths: list[str] = []
    invalid_expected_results: list[str] = []
    negative_contract_errors: list[str] = []

    for index, case in enumerate(all_cases):
        label = case.get("id", f"index-{index}") if isinstance(case, dict) else f"index-{index}"
        if not isinstance(case, dict) or not case.get("id") or not isinstance(case.get("assertions"), list):
            malformed.append(str(label))
            continue
        if case.get("expected_result") not in VALID_RESULTS:
            invalid_expected_results.append(str(label))
        if not isinstance(case.get("evidence_path"), str) or not case.get("evidence_path"):
            missing_evidence_paths.append(str(label))
        for assertion_id in case.get("assertions", []):
            if assertion_id not in known_assertions:
                unknown_assertions.add(str(assertion_id))
        for assertion_id in case.get("critical_assertions", []):
            if assertion_id not in known_assertions:
                unknown_assertions.add(str(assertion_id))
        fixture = case.get("fixture_ref")
        if isinstance(fixture, str) and fixture and not (SKILL / fixture).is_file():
            missing_fixtures.add(fixture)
        if case.get("kind") == "negative" and case in executable and case.get("must_be_rejected") is not True:
            negative_contract_errors.append(str(label))

    execution_contract = data.get("execution_contract", {})
    executable_ids = {case.get("id") for case in executable if isinstance(case, dict)}
    required_executable = {execution_contract.get("positive_case"), execution_contract.get("negative_case")}
    evidence_contract = data.get("evidence_contract", {})
    evidence_required = set(evidence_contract.get("required", [])) if isinstance(evidence_contract, dict) else set()
    expected_evidence_fields = {"actual_validation_result", "expected_validation_result", "matched", "candidate_failed_assertions"}

    executions = [
        run_case("E21_STORY_CORE_POSITIVE", "PASS_WITH_EVIDENCE"),
        run_case("E22_STORY_CORE_NEGATIVE", "RETURN_TO_WORKER"),
        run_self_test(),
    ]
    checks = {
        "case_count_declared": data.get("case_count"),
        "case_count_actual": len(all_cases),
        "legacy_count": len(legacy),
        "executable_count": len(executable),
        "duplicate_case_ids": duplicate_ids,
        "malformed_cases": malformed,
        "unknown_assertion_refs": sorted(unknown_assertions),
        "missing_fixtures": sorted(missing_fixtures),
        "missing_evidence_paths": missing_evidence_paths,
        "invalid_expected_results": invalid_expected_results,
        "negative_contract_errors": negative_contract_errors,
        "required_executable_cases_present": required_executable == executable_ids,
        "evidence_contract_complete": expected_evidence_fields.issubset(evidence_required),
        "all_executions_pass": all(item["passed"] for item in executions),
        "input_sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
    }
    passed = (
        checks["case_count_declared"] == checks["case_count_actual"] == 22
        and checks["legacy_count"] == 20
        and checks["executable_count"] == 2
        and not duplicate_ids
        and not malformed
        and not unknown_assertions
        and not missing_fixtures
        and not missing_evidence_paths
        and not invalid_expected_results
        and not negative_contract_errors
        and checks["required_executable_cases_present"]
        and checks["evidence_contract_complete"]
        and checks["all_executions_pass"]
    )
    output = {"artifact": "A07", "passed": passed, "checks": checks, "executions": executions}
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
