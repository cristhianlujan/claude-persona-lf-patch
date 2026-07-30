#!/usr/bin/env python3
"""Deep runtime audit for A06 evals/assertions.json."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
ASSERTIONS = SKILL / "evals" / "assertions.json"
EVALS = SKILL / "evals" / "evals.json"


def runtime_env() -> dict[str, str]:
    value = os.environ.copy()
    value.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A06_RUNNER")
    return value


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def run_command(name: str, command: list[str], expected_result: str = "PASS_WITH_EVIDENCE") -> dict[str, Any]:
    proc = subprocess.run(command, cwd=SKILL, env=runtime_env(), text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        passed = proc.returncode == (0 if expected_result == "PASS_WITH_EVIDENCE" else 1) and result.get("result") == expected_result
        return {
            "name": name,
            "passed": passed,
            "command": command,
            "process_exit_code": proc.returncode,
            "expected_result": expected_result,
            "actual_result": result.get("result"),
            "assertions_total": result.get("assertions_total"),
            "assertions_passed": result.get("assertions_passed"),
            "failed_assertions": result.get("failed_assertions"),
            "blocking_assertions": result.get("blocking_assertions"),
            "input_sha256": result.get("input_sha256"),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
            "evidence": result.get("evidence"),
        }
    except Exception as exc:
        return {"name": name, "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-1000:], "error": f"{type(exc).__name__}:{exc}"}


def run_payload(name: str, script: str, payload: dict[str, Any], expected_result: str) -> dict[str, Any]:
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8", delete=False) as handle:
        json.dump(payload, handle, ensure_ascii=False)
        handle.write("\n")
        path = Path(handle.name)
    try:
        return run_command(name, [sys.executable, script, str(path)], expected_result)
    finally:
        path.unlink(missing_ok=True)


def run_eval(case_id: str, candidate_expected: str) -> dict[str, Any]:
    command = [sys.executable, "scripts/validate_story_pack.py", "--case-id", case_id]
    proc = subprocess.run(command, cwd=SKILL, env=runtime_env(), text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        evidence = result.get("evidence", {})
        passed = (
            proc.returncode == 0
            and result.get("result") == "PASS_WITH_EVIDENCE"
            and evidence.get("case_id") == case_id
            and evidence.get("expected_validation_result") == candidate_expected
            and evidence.get("actual_validation_result") == candidate_expected
            and evidence.get("matched") is True
            and (candidate_expected != "RETURN_TO_WORKER" or evidence.get("negative_must_be_rejected") is True)
        )
        return {
            "name": case_id,
            "passed": passed,
            "command": command,
            "process_exit_code": proc.returncode,
            "wrapper_result": result.get("result"),
            "candidate_expected": candidate_expected,
            "candidate_actual": evidence.get("actual_validation_result"),
            "candidate_failed_assertions": evidence.get("candidate_failed_assertions"),
            "input_sha256": result.get("input_sha256"),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
        }
    except Exception as exc:
        return {"name": case_id, "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-1000:], "error": f"{type(exc).__name__}:{exc}"}


def exact_fixture(test_code: str, expected: str) -> dict[str, Any]:
    return {
        "actor": "AUTHORIZED_OPERATOR",
        "tenant": "TENANT-A",
        "initial_state": {"authenticated": True},
        "exact_inputs": {"request_id": "REQ-1"},
        "steps": [f"execute {test_code} with REQ-1"],
        "expected_result": expected,
        "evidence_path": f"evidence/{test_code}.json",
    }


def j10_payload(rule: dict[str, Any], family: str, test_code: str, negative: bool = False) -> dict[str, Any]:
    criterion_code = f"AC-{test_code}"
    test = {
        "test_code": test_code,
        "family": family,
        "criterion_ref": criterion_code,
        "rule_ref": rule["rule_code"],
        "preconditions": ["authorized test environment exists"],
        "steps": [f"execute {test_code}"],
        "expected_result": "observable expected result",
        "negative": negative,
        "critical": True,
        "automatable": True,
        "evidence_path": f"evidence/{test_code}.json",
    }
    return {
        "story_pack": {
            "core": {"acceptance_criteria": [{"criterion_code": criterion_code, "given": "test state exists", "when": "action executes", "then": "observable result occurs", "source_ref": "SRC-R8"}]},
            "tests": [test],
        },
        "critical_rules": [rule],
        "fixtures": {test_code: exact_fixture(test_code, "observable expected result")},
    }


def direct_assertion_executions() -> tuple[set[str], list[dict[str, Any]]]:
    executions: list[dict[str, Any]] = []
    covered: set[str] = set()

    accessibility_rule = {"rule_code": "A11Y-1", "family": "ACCESSIBILITY"}
    a11y_positive = j10_payload(accessibility_rule, "ACCESSIBILITY", "TEST-A11Y")
    a11y_negative = json.loads(json.dumps(a11y_positive))
    a11y_negative["story_pack"]["tests"] = []
    a11y_negative["fixtures"] = {}
    a11y_runs = [
        run_payload("A17_ACCESSIBILITY_POSITIVE", "scripts/validate_test_coverage.py", a11y_positive, "PASS_WITH_EVIDENCE"),
        run_payload("A17_ACCESSIBILITY_NEGATIVE", "scripts/validate_test_coverage.py", a11y_negative, "RETURN_TO_WORKER"),
    ]
    executions.extend(a11y_runs)
    if all(item["passed"] for item in a11y_runs):
        covered.add("A17_ACCESSIBILITY")

    j09_positive = {
        "fields": [{"field_code": "dni", "pii_classification": "PII_DIRECT", "analytics_allowed": False, "logs_allowed": True, "masking_rule": "MASK_LAST_4"}],
        "analytics": [{"event_code": "customer_opened", "properties": ["screen_id"], "pii_free": True, "correlation_id_required": True, "audit_event": False}],
        "observability": {"logs": [{"level": "INFO"}], "metrics": [], "alerts": []},
        "errors": [],
    }
    j09_negative = {
        "fields": [{"field_code": "dni", "pii_classification": "PII_DIRECT", "analytics_allowed": True, "logs_allowed": True, "masking_rule": None}],
        "analytics": [{"event_code": "customer_opened", "properties": ["dni"], "pii_free": False, "correlation_id_required": True, "audit_event": False}],
        "observability": {"logs": [{"fields": ["dni"]}], "metrics": [], "alerts": []},
        "errors": [],
    }
    observability_runs = [
        run_payload("A18_OBSERVABILITY_POSITIVE", "scripts/detect_pii_telemetry.py", j09_positive, "PASS_WITH_EVIDENCE"),
        run_payload("A18_OBSERVABILITY_NEGATIVE", "scripts/detect_pii_telemetry.py", j09_negative, "RETURN_TO_WORKER"),
    ]
    executions.extend(observability_runs)
    if all(item["passed"] for item in observability_runs):
        covered.add("A18_OBSERVABILITY")

    idempotency_rule = {"rule_code": "IDEM-1", "family": "IDEMPOTENCY", "idempotent": True}
    idem_positive = j10_payload(idempotency_rule, "IDEMPOTENCY", "TEST-IDEM")
    idem_negative = json.loads(json.dumps(idem_positive))
    idem_negative["story_pack"]["tests"] = []
    idem_negative["fixtures"] = {}
    idempotency_runs = [
        run_payload("A19_IDEMPOTENCY_POSITIVE", "scripts/validate_test_coverage.py", idem_positive, "PASS_WITH_EVIDENCE"),
        run_payload("A19_IDEMPOTENCY_NEGATIVE", "scripts/validate_test_coverage.py", idem_negative, "RETURN_TO_WORKER"),
    ]
    executions.extend(idempotency_runs)
    if all(item["passed"] for item in idempotency_runs):
        covered.add("A19_IDEMPOTENCY")

    package_command = [sys.executable, "scripts/validate_package.py", "--self-test"]
    package_proc = subprocess.run(package_command, cwd=SKILL, env=runtime_env(), text=True, capture_output=True, timeout=180)
    try:
        package_result = emitted(package_proc.stdout)
        package_passed = package_proc.returncode == 0 and package_result.get("result") == "PASS_WITH_EVIDENCE" and package_result.get("self_test", {}).get("positive", {}).get("consistency_pass") is True and package_result.get("self_test", {}).get("negative", {}).get("consistency_pass") is False
    except Exception as exc:
        package_result = {"error": f"{type(exc).__name__}:{exc}", "stdout": package_proc.stdout[-2000:], "stderr": package_proc.stderr[-1000:]}
        package_passed = False
    package_run = {"name": "A20_PACKAGE_INTEGRITY_SELF_TEST", "passed": package_passed, "command": package_command, "process_exit_code": package_proc.returncode, "result": package_result}
    executions.append(package_run)
    if package_passed:
        covered.add("A20_PACKAGE_INTEGRITY")

    return covered, executions


def main() -> int:
    registry = json.loads(ASSERTIONS.read_text(encoding="utf-8"))
    evals = json.loads(EVALS.read_text(encoding="utf-8"))
    rows = registry.get("assertions", [])
    ids = [row.get("id") for row in rows if isinstance(row, dict)]
    id_set = {item for item in ids if isinstance(item, str) and item}
    duplicate_ids = sorted({item for item in id_set if ids.count(item) > 1})
    malformed = [index for index, row in enumerate(rows) if not isinstance(row, dict) or not all(row.get(key) not in (None, "", []) for key in ("id", "target", "pass_if", "required_evidence", "repair"))]

    referenced: set[str] = set()
    unknown_refs: set[str] = set()
    cases = list(evals.get("legacy_cases", [])) + list(evals.get("executable_cases", []))
    for case in cases:
        if not isinstance(case, dict):
            continue
        for assertion_id in case.get("assertions", []):
            if assertion_id in id_set:
                referenced.add(assertion_id)
            else:
                unknown_refs.add(str(assertion_id))
        for assertion_id in case.get("critical_assertions", []):
            if assertion_id not in id_set:
                unknown_refs.add(str(assertion_id))

    case_contract_errors: list[str] = []
    for polarity, examples in (("positive", registry.get("positive_cases", [])), ("negative", registry.get("negative_cases", []))):
        if not isinstance(examples, list) or not examples:
            case_contract_errors.append(f"{polarity}_cases_missing")
            continue
        for index, case in enumerate(examples):
            if not isinstance(case, dict) or not all(case.get(key) not in (None, "", []) for key in ("case_id", "fixture_ref", "expected_result", "assertions")):
                case_contract_errors.append(f"{polarity}_case_{index}_malformed")
            if polarity == "negative" and case.get("must_be_rejected") is not True:
                case_contract_errors.append(f"negative_case_{index}_must_be_rejected_missing")
            fixture = case.get("fixture_ref") if isinstance(case, dict) else None
            if isinstance(fixture, str) and not (SKILL / fixture).is_file():
                case_contract_errors.append(f"fixture_missing:{fixture}")

    executions = [
        run_eval("E21_STORY_CORE_POSITIVE", "PASS_WITH_EVIDENCE"),
        run_eval("E22_STORY_CORE_NEGATIVE", "RETURN_TO_WORKER"),
    ]
    direct_covered, direct_runs = direct_assertion_executions()
    executions.extend(direct_runs)
    covered = referenced | direct_covered
    orphan_ids = sorted(id_set - covered)

    checks = {
        "assertion_count": len(rows),
        "unique_assertion_ids": len(duplicate_ids) == 0 and len(id_set) == len(rows),
        "malformed_assertions": malformed,
        "unknown_eval_assertion_refs": sorted(unknown_refs),
        "directly_executed_assertions": sorted(direct_covered),
        "orphan_assertions": orphan_ids,
        "case_contract_errors": case_contract_errors,
        "all_executions_pass": all(item["passed"] for item in executions),
        "input_sha256": hashlib.sha256(ASSERTIONS.read_bytes()).hexdigest(),
    }
    passed = (
        checks["assertion_count"] == 22
        and checks["unique_assertion_ids"]
        and not malformed
        and not unknown_refs
        and not orphan_ids
        and not case_contract_errors
        and checks["all_executions_pass"]
    )
    output = {"artifact": "A06", "passed": passed, "checks": checks, "executions": executions}
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
