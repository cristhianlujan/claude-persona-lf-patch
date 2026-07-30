#!/usr/bin/env python3
"""Deep runtime audit for A09 sensitive-fields fixture and J04/J05 local eval suite."""
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
TARGET = SKILL / "evals" / "fixtures" / "screen_sensitive_fields.json"
SCRIPT = "scripts/validate_field_coverage.py"


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def run_case(case_id: str, judge: str, expected_candidate: str) -> dict[str, Any]:
    command = [sys.executable, SCRIPT, "--case-id", case_id, "--judge", judge]
    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A09_RUNNER")
    proc = subprocess.run(command, cwd=SKILL, env=env, text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        evidence = result.get("evidence", {})
        hashes_ok = all(isinstance(result.get(key), str) and len(result[key]) == 64 for key in ("input_sha256", "evidence_sha256", "output_sha256"))
        passed = (
            proc.returncode == 0
            and result.get("result") == "PASS_WITH_EVIDENCE"
            and evidence.get("case_id") == case_id
            and evidence.get("judge") == judge
            and evidence.get("expected_validation_result") == expected_candidate
            and evidence.get("actual_validation_result") == expected_candidate
            and evidence.get("matched") is True
            and (expected_candidate != "RETURN_TO_WORKER" or evidence.get("negative_must_be_rejected") is True)
            and hashes_ok
        )
        return {
            "case_id": case_id,
            "judge": judge,
            "passed": passed,
            "command": command,
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
        return {"case_id": case_id, "judge": judge, "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-3000:], "stderr": proc.stderr[-1500:], "error": f"{type(exc).__name__}:{exc}"}


def run_self_test() -> dict[str, Any]:
    command = [sys.executable, SCRIPT, "--self-test"]
    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A09_RUNNER")
    proc = subprocess.run(command, cwd=SKILL, env=env, text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        outcomes = result.get("outcomes", [])
        passed = proc.returncode == 0 and result.get("result") == "PASS_WITH_EVIDENCE" and len(outcomes) == 4 and all(item.get("matched") is True for item in outcomes if isinstance(item, dict))
        return {"case_id": "SELF_TEST", "passed": passed, "command": command, "process_exit_code": proc.returncode, "result": result}
    except Exception as exc:
        return {"case_id": "SELF_TEST", "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-3000:], "stderr": proc.stderr[-1500:], "error": f"{type(exc).__name__}:{exc}"}


def main() -> int:
    fixture = json.loads(TARGET.read_text(encoding="utf-8"))
    chain = fixture["field_chain_eval"]
    positive = chain["positive_case"]
    negative = chain["negative_case"]
    executions = [
        run_case(positive, "J04_FIELD_CONTRACTS", "PASS_WITH_EVIDENCE"),
        run_case(positive, "J05_OBSERVATIONS_ERRORS", "PASS_WITH_EVIDENCE"),
        run_case(negative, "J04_FIELD_CONTRACTS", "RETURN_TO_WORKER"),
        run_case(negative, "J05_OBSERVATIONS_ERRORS", "RETURN_TO_WORKER"),
        run_self_test(),
    ]
    negative_j04 = next(item for item in executions if item.get("case_id") == negative and item.get("judge") == "J04_FIELD_CONTRACTS")
    negative_j05 = next(item for item in executions if item.get("case_id") == negative and item.get("judge") == "J05_OBSERVATIONS_ERRORS")
    checks = {
        "four_declared_executions_present": len(chain.get("required_executions", [])) == 4,
        "all_five_runtime_checks_pass": all(item["passed"] for item in executions),
        "negative_j04_has_findings": bool(negative_j04.get("candidate_failed_assertions")),
        "negative_j05_has_findings": bool(negative_j05.get("candidate_failed_assertions")),
        "fixture_hash_present": len(hashlib.sha256(TARGET.read_bytes()).hexdigest()) == 64,
    }
    passed = all(checks.values())
    output = {
        "artifact": "A09",
        "passed": passed,
        "fixture_sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        "checks": checks,
        "executions": executions,
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
