#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox" / "lf_contract_gate_test" / "gate_check_observability" / "run_gate_checks_v1.py"


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def run_runner(tmp: Path, mode: str, critical: bool = False) -> tuple[subprocess.CompletedProcess[str], dict]:
    checks = tmp / "checks"
    checks.mkdir(parents=True, exist_ok=True)
    write(checks / "test_01_pass.py", "print('pass-1')\n")
    if critical:
        write(checks / "test_02_critical_fail.py", "raise SystemExit(7)\n")
        write(checks / "test_03_never.py", "print('must-not-run')\n")
    else:
        write(checks / "test_02_fail.py", "raise SystemExit(3)\n")
        write(checks / "test_03_pass.py", "print('pass-3')\n")
        write(checks / "test_04_fail.py", "raise SystemExit(4)\n")
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
    with tempfile.TemporaryDirectory() as td:
        proc, report = run_runner(Path(td), "COLLECT_ALL")
        assert proc.returncode == 1, proc.stderr
        assert report["contract"] == "LF_GATE_ERROR_V1"
        assert report["gate_result"] == "FAIL"
        assert report["expected_check_count"] == 4
        assert report["executed_check_count"] == 4
        assert report["pass_count"] == 2
        assert report["fail_count"] == 2
        failed = [c for c in report["checks"] if c["check_status"] == "FAIL"]
        assert len(failed) == 2
        assert all(c["error_id"] for c in failed)
        assert len({c["trace_id"] for c in failed}) == 2
        assert len({c["parent_trace_id"] for c in report["checks"]}) == 1
        assert all(Path(c["stderr_ref"]).is_file() for c in report["checks"])

    with tempfile.TemporaryDirectory() as td:
        proc, report = run_runner(Path(td), "FAIL_FAST_CRITICAL", critical=True)
        assert proc.returncode == 1, proc.stderr
        assert report["gate_result"] == "FAIL"
        assert report["expected_check_count"] == 3
        assert report["executed_check_count"] == 2
        assert report["remaining_after_fail_fast"] == ["T-003"]
        assert report["checks"][1]["critical"] is True
        assert report["checks"][1]["actual"] == {"rc": 7}

    print("LF_GATE_ERROR_V1_PRODUCER_TEST_PASS")


if __name__ == "__main__":
    main()
