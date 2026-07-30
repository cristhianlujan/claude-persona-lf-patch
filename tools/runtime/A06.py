#!/usr/bin/env python3
"""Deep runtime audit for A06 evals/assertions.json."""
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
ASSERTIONS = SKILL / "evals" / "assertions.json"
EVALS = SKILL / "evals" / "evals.json"


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def run_eval(case_id: str, candidate_expected: str) -> dict[str, Any]:
    command = [sys.executable, "scripts/validate_story_pack.py", "--case-id", case_id]
    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A06_RUNNER")
    proc = subprocess.run(command, cwd=SKILL, env=env, text=True, capture_output=True, timeout=120)
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
            "case_id": case_id,
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
        return {"case_id": case_id, "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-1000:], "error": f"{type(exc).__name__}:{exc}"}


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
    orphan_ids = sorted(id_set - referenced)

    positive_cases = registry.get("positive_cases", [])
    negative_cases = registry.get("negative_cases", [])
    case_contract_errors = []
    for polarity, examples in (("positive", positive_cases), ("negative", negative_cases)):
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
    checks = {
        "assertion_count": len(rows),
        "unique_assertion_ids": len(duplicate_ids) == 0 and len(id_set) == len(rows),
        "malformed_assertions": malformed,
        "unknown_eval_assertion_refs": sorted(unknown_refs),
        "orphan_assertions": orphan_ids,
        "case_contract_errors": case_contract_errors,
        "positive_negative_executions_pass": all(item["passed"] for item in executions),
        "input_sha256": hashlib.sha256(ASSERTIONS.read_bytes()).hexdigest(),
    }
    passed = (
        checks["assertion_count"] == 22
        and checks["unique_assertion_ids"]
        and not malformed
        and not unknown_refs
        and not orphan_ids
        and not case_contract_errors
        and checks["positive_negative_executions_pass"]
    )
    output = {"artifact": "A06", "passed": passed, "checks": checks, "executions": executions}
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
