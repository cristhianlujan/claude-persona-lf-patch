#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox" / "lf_contract_gate_test" / "gate_check_observability" / "run_gate_checks_v1.py"
SCHEMA = ROOT / "sandbox" / "lf_contract_gate_test" / "gate_check_observability" / "lf_gate_error_v1.schema.json"


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def expected_manifest_sha(report: dict) -> str:
    payload = dict(report)
    payload.pop("manifest_sha256", None)
    return hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def run_runner(tmp: Path, mode: str, critical: bool = False) -> tuple[subprocess.CompletedProcess[str], dict]:
    checks = tmp / "checks"
    checks.mkdir(parents=True, exist_ok=True)
    write(checks / "test_01_pass.py", "print('pass-1')\n")
    if critical:
        write(checks / "test_02_critical_fail.py", "raise RuntimeError('critical_stop')\n")
        write(checks / "test_03_never.py", "print('must-not-run')\n")
    else:
        write(checks / "test_02_assert.py", "assert False, 'expected_deterministic_failure'\n")
        write(checks / "test_03_pass.py", "print('pass-3')\n")
        write(checks / "test_04_value.py", "raise ValueError('second_failure_not_collapsed')\n")
    artifact = tmp / "artifact"
    cmd = [
        sys.executable,
        str(RUNNER),
        "--gate-id", "TEST_GATE",
        "--step-id", "deterministic_and_semantic_judge",
        "--mode", mode,
        "--glob", str(checks / "test_*.py"),
        "--artifact-dir", str(artifact),
        "--check-prefix", "T",
        "--owner", "S36",
        "--next-action", "FIX_AND_RERUN",
        "--run-id", "TEST-RUN",
        "--job-id", "TEST-JOB",
        "--source-commit", "a" * 40,
        "--downstream-impact", "NEXT_GATE",
    ]
    if critical:
        cmd += ["--critical-pattern", "critical_fail"]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    report = json.loads((artifact / "lf_gate_error_v1.json").read_text(encoding="utf-8"))
    return proc, report


def main() -> None:
    assert RUNNER.is_file(), RUNNER
    assert SCHEMA.is_file(), SCHEMA

    with tempfile.TemporaryDirectory() as td:
        proc, report = run_runner(Path(td), "COLLECT_ALL")
        assert proc.returncode == 1, proc.stderr
        assert report["contract"] == "LF_GATE_ERROR_V1"
        assert report["producer"] == "LF_GATE_CHECK_OBSERVABILITY_V1"
        assert report["gate_result"] == "FAIL"
        assert report["diagnostic_complete"] is True
        assert report["source_commit"] == "a" * 40
        assert len(report["tested_commit"]) == 40
        assert report["schema_sha256"] == hashlib.sha256(SCHEMA.read_bytes()).hexdigest()
        assert report["manifest_sha256"] == expected_manifest_sha(report)
        assert report["expected_check_count"] == 4
        assert report["executed_check_count"] == 4
        assert report["pass_count"] == 2
        assert report["fail_count"] == 2
        failed = [c for c in report["checks"] if c["check_status"] == "FAIL"]
        assert len(failed) == 2
        assert failed[0]["error_class"] == "AssertionError", failed[0]
        assert failed[0]["assertion_text"] == "AssertionError: expected_deterministic_failure", failed[0]
        assert failed[1]["error_class"] == "ValueError", failed[1]
        assert failed[1]["error_summary"] == "ValueError: second_failure_not_collapsed", failed[1]
        assert all(c["failure_id"] and len(c["failure_id"]) == 64 for c in failed)
        assert all(c["diagnostic_complete"] is True for c in failed)
        assert all(c["traceback_present"] is True for c in failed)
        assert all(c["traceback_ref"] and Path(c["traceback_ref"]).is_file() for c in failed)
        assert all(c["traceback_sha256"] and len(c["traceback_sha256"]) == 64 for c in failed)
        assert all(c["stdout_sha256"] and c["stderr_sha256"] for c in failed)
        assert len({c["trace_id"] for c in failed}) == 2
        assert len({c["parent_trace_id"] for c in report["checks"]}) == 1

    with tempfile.TemporaryDirectory() as td:
        proc, report = run_runner(Path(td), "FAIL_FAST_CRITICAL", critical=True)
        assert proc.returncode == 1, proc.stderr
        assert report["gate_result"] == "FAIL"
        assert report["diagnostic_complete"] is True
        assert report["expected_check_count"] == 3
        assert report["executed_check_count"] == 2
        assert report["remaining_after_fail_fast"] == ["T-003"]
        assert report["checks"][1]["critical"] is True
        assert report["checks"][1]["actual"] == {"rc": 1}
        assert report["checks"][1]["error_class"] == "RuntimeError"
        assert report["checks"][1]["traceback_present"] is True

    with tempfile.TemporaryDirectory() as td:
        artifact = Path(td) / "artifact"
        proc = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--gate-id", "EMPTY_GATE",
                "--step-id", "empty",
                "--mode", "COLLECT_ALL",
                "--glob", str(Path(td) / "missing" / "test_*.py"),
                "--artifact-dir", str(artifact),
                "--owner", "S30",
                "--next-action", "FIX_CHECK_DISCOVERY",
                "--run-id", "EMPTY-RUN",
                "--job-id", "EMPTY-JOB",
                "--source-commit", "b" * 40,
            ],
            capture_output=True,
            text=True,
        )
        report = json.loads((artifact / "lf_gate_error_v1.json").read_text(encoding="utf-8"))
        assert proc.returncode == 2, proc.stderr
        assert report["gate_result"] == "BLOCKED"
        assert report["diagnostic_complete"] is False
        assert report["error_class"] == "GATE_CHECK_SET_MISSING"
        assert report["manifest_sha256"] == expected_manifest_sha(report)

    print("LF_GATE_ERROR_V1_PRODUCER_TEST_PASS")


if __name__ == "__main__":
    main()
