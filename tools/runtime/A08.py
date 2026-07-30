#!/usr/bin/env python3
"""Deep runtime audit for A08 insufficient-source fixture and E22 rejection."""
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
TARGET = SKILL / "evals" / "fixtures" / "screen_insufficient_definition.json"


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def main() -> int:
    fixture = json.loads(TARGET.read_text(encoding="utf-8"))
    source = fixture["source_snapshot"]
    activation = fixture["activation_expectation"]
    candidate = fixture["candidate_validation_expectation"]

    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A08_RUNNER")
    command = [sys.executable, "scripts/validate_story_pack.py", "--case-id", candidate["case_id"]]
    proc = subprocess.run(command, cwd=SKILL, env=env, text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        evidence = result.get("evidence", {})
        failed = list(evidence.get("candidate_failed_assertions") or [])
        normalized_failed = {str(item).split("=", 1)[0] for item in failed}
        required_failed = set(candidate.get("required_failed_assertions", []))
        checks = {
            "source_version_absent": source.get("version") is None,
            "source_hash_absent": source.get("sha256") is None,
            "main_responsibility_absent": source.get("main_responsibility") is None,
            "activation_blocked": activation.get("activation") == "NEEDS_SOURCE_CONTEXT" and activation.get("result") == "BLOCKED",
            "must_not_invent": activation.get("must_not_invent") is True and activation.get("story_count") == 0,
            "wrapper_passed": result.get("result") == candidate.get("eval_wrapper_result"),
            "candidate_returned_expected": evidence.get("actual_validation_result") == candidate.get("expected_candidate_result"),
            "expectation_matched": evidence.get("matched") is True,
            "negative_must_be_rejected": evidence.get("negative_must_be_rejected") is True,
            "required_failures_detected": required_failed.issubset(normalized_failed),
            "input_hash_present": isinstance(result.get("input_sha256"), str) and len(result["input_sha256"]) == 64,
            "evidence_hash_present": isinstance(result.get("evidence_sha256"), str) and len(result["evidence_sha256"]) == 64,
            "output_hash_present": isinstance(result.get("output_sha256"), str) and len(result["output_sha256"]) == 64,
        }
        execution = {
            "command": command,
            "process_exit_code": proc.returncode,
            "wrapper_result": result.get("result"),
            "candidate_result": evidence.get("actual_validation_result"),
            "candidate_failed_assertions": failed,
            "checks": checks,
            "input_sha256": result.get("input_sha256"),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
        }
        passed = proc.returncode == 0 and all(checks.values())
    except Exception as exc:
        checks = {"validator_output_parse": False}
        execution = {"command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-3000:], "stderr": proc.stderr[-1500:], "error": f"{type(exc).__name__}:{exc}"}
        passed = False

    output = {
        "artifact": "A08",
        "passed": passed,
        "fixture_sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        "checks": checks,
        "execution": execution,
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
