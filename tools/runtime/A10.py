#!/usr/bin/env python3
"""Deep runtime audit for A10 simple-query fixture and E21 candidate alignment."""
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
TARGET = SKILL / "evals" / "fixtures" / "screen_simple_query.json"
REGISTRY = SKILL / "evals" / "evals.json"


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def main() -> int:
    fixture = json.loads(TARGET.read_text(encoding="utf-8"))
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    case_id = fixture["story_core_eval"]["case_id"]
    cases = registry.get("executable_cases", [])
    case = next((item for item in cases if isinstance(item, dict) and item.get("id") == case_id), None)
    if not isinstance(case, dict):
        print(json.dumps({"artifact": "A10", "passed": False, "blocking_reason": f"case_missing:{case_id}"}))
        return 1
    candidate = case.get("candidate_story_pack")
    if not isinstance(candidate, dict):
        print(json.dumps({"artifact": "A10", "passed": False, "blocking_reason": "candidate_story_pack_missing"}))
        return 1

    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A10_RUNNER")
    command = [sys.executable, "scripts/validate_story_pack.py", "--case-id", case_id]
    proc = subprocess.run(command, cwd=SKILL, env=env, text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        evidence = result.get("evidence", {})
        source = fixture["source_snapshot"]
        identity = candidate.get("identity", {})
        expected = fixture["expected"]
        fields = candidate.get("fields", [])
        analytics = candidate.get("analytics", [])
        tests = candidate.get("tests", [])
        test_families = {item.get("family") for item in tests if isinstance(item, dict)}
        pii_codes = {
            item.get("field_code")
            for item in fields
            if isinstance(item, dict) and item.get("pii_classification") in {"PII_INDIRECT", "PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL"}
        }
        analytics_properties = {
            prop
            for event in analytics
            if isinstance(event, dict)
            for prop in event.get("properties", [])
            if isinstance(prop, str)
        }
        checks = {
            "wrapper_pass": proc.returncode == 0 and result.get("result") == fixture["story_core_eval"]["expected_eval_wrapper_result"],
            "candidate_pass": evidence.get("actual_validation_result") == fixture["story_core_eval"]["expected_candidate_result"],
            "matched": evidence.get("matched") is True,
            "screen_code_aligned": identity.get("screen_code") == source.get("screen_code"),
            "module_code_aligned": identity.get("module_code") == source.get("module_code"),
            "source_version_aligned": identity.get("source_version") == source.get("version"),
            "source_hash_aligned": identity.get("source_snapshot_sha") == source.get("sha256"),
            "story_core_only_claim": expected.get("story_core_result") == "PASS_WITH_EVIDENCE" and expected.get("integration_result") == "NOT_VALIDATED",
            "minimum_test_families_present": set(expected.get("minimum_executable_test_families", [])).issubset(test_families),
            "pending_families_not_claimed_complete": not set(expected.get("test_families_pending_before_integration", [])).issubset(test_families),
            "analytics_excludes_pii_fields": not bool(pii_codes & analytics_properties) and all(event.get("pii_free") is True for event in analytics if isinstance(event, dict)),
            "hashes_present": all(isinstance(result.get(key), str) and len(result[key]) == 64 for key in ("input_sha256", "evidence_sha256", "output_sha256")),
        }
        passed = all(checks.values())
        execution = {
            "command": command,
            "process_exit_code": proc.returncode,
            "checks": checks,
            "test_families": sorted(item for item in test_families if item),
            "pii_field_codes": sorted(item for item in pii_codes if item),
            "analytics_properties": sorted(analytics_properties),
            "candidate_failed_assertions": evidence.get("candidate_failed_assertions"),
            "input_sha256": result.get("input_sha256"),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
        }
    except Exception as exc:
        checks = {"validator_output_parse": False}
        execution = {"command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-3000:], "stderr": proc.stderr[-1500:], "error": f"{type(exc).__name__}:{exc}"}
        passed = False

    output = {
        "artifact": "A10",
        "passed": passed,
        "fixture_sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        "registry_sha256": hashlib.sha256(REGISTRY.read_bytes()).hexdigest(),
        "checks": checks,
        "execution": execution,
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
