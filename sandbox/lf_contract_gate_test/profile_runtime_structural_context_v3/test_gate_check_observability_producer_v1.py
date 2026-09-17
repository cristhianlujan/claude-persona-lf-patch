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


def run_command_mode(tmp: Path) -> tuple[subprocess.CompletedProcess[str], dict]:
    checks = tmp / "commands"
    checks.mkdir(parents=True, exist_ok=True)
    pass_script = checks / "parameterized_pass.py"
    fail_script = checks / "parameterized_fail.py"
    write(
        pass_script,
        "import sys\nassert sys.argv[1:] == ['--expected', '42']\nprint('parameterized-pass')\n",
    )
    write(
        fail_script,
        "import sys\nassert sys.argv[1:] == ['--expected', 'fail']\nraise ValueError('parameterized_failure')\n",
    )
    artifact = tmp / "command-artifact"
    pass_spec = json.dumps(
        {
            "argv": [sys.executable, str(pass_script), "--expected", "42"],
            "source_path": str(pass_script),
        },
        separators=(",", ":"),
    )
    fail_spec = json.dumps(
        {
            "argv": [sys.executable, str(fail_script), "--expected", "fail"],
            "source_path": str(fail_script),
        },
        separators=(",", ":"),
    )
    proc = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--gate-id", "COMMAND_GATE",
            "--step-id", "parameterized_commands",
            "--mode", "COLLECT_ALL",
            "--command-json", pass_spec,
            "--command-json", fail_spec,
            "--artifact-dir", str(artifact),
            "--check-prefix", "CMD",
            "--owner", "S30",
            "--next-action", "FIX_PARAMETERIZED_COMMAND",
            "--run-id", "COMMAND-RUN",
            "--job-id", "COMMAND-JOB",
            "--source-commit", "c" * 40,
        ],
        capture_output=True,
        text=True,
    )
    report = json.loads((artifact / "lf_gate_error_v1.json").read_text(encoding="utf-8"))
    return proc, report


def test_workflow_skips_diagnostic_upload_when_deterministic_stage_not_reached() -> None:
    workflow = (ROOT / ".github/workflows/lf-contract-check.yml").read_text(encoding="utf-8")
    required = [
        "- name: Detect deterministic LF contract gate diagnostics",
        "id: deterministic_diagnostics",
        "has_files=false",
        "INFO_LF_DETERMINISTIC_DIAGNOSTICS_NOT_REACHED",
        "steps.deterministic_diagnostics.outputs.has_files == 'true'",
        "if-no-files-found: error",
    ]
    for token in required:
        assert token in workflow, token


def main() -> None:
    test_workflow_skips_diagnostic_upload_when_deterministic_stage_not_reached()
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
        proc, report = run_command_mode(Path(td))
        assert proc.returncode == 1, proc.stderr
        assert report["gate_result"] == "FAIL"
        assert report["diagnostic_complete"] is True
        assert report["expected_check_count"] == 2
        assert report["executed_check_count"] == 2
        assert report["pass_count"] == 1
        assert report["fail_count"] == 1
        assert report["checks"][0]["command"][-2:] == ["--expected", "42"]
        assert report["checks"][1]["command"][-2:] == ["--expected", "fail"]
        assert report["checks"][1]["error_class"] == "ValueError"
        assert report["checks"][1]["error_summary"] == "ValueError: parameterized_failure"
        assert report["checks"][1]["traceback_present"] is True
        assert report["manifest_sha256"] == expected_manifest_sha(report)

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

    with tempfile.TemporaryDirectory() as td:
        artifact = Path(td) / "bad-command-artifact"
        proc = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--gate-id", "BAD_COMMAND_GATE",
                "--step-id", "bad_command",
                "--mode", "COLLECT_ALL",
                "--command-json", '{"argv":"not-an-array","source_path":"x.py"}',
                "--artifact-dir", str(artifact),
                "--owner", "S30",
                "--next-action", "FIX_COMMAND_SPEC",
                "--run-id", "BAD-COMMAND-RUN",
                "--job-id", "BAD-COMMAND-JOB",
                "--source-commit", "d" * 40,
            ],
            capture_output=True,
            text=True,
        )
        report = json.loads((artifact / "lf_gate_error_v1.json").read_text(encoding="utf-8"))
        assert proc.returncode == 2, proc.stderr
        assert report["gate_result"] == "BLOCKED"
        assert report["error_class"] == "GATE_COMMAND_SPEC_INVALID"
        assert report["diagnostic_complete"] is False
        assert report["manifest_sha256"] == expected_manifest_sha(report)

    with tempfile.TemporaryDirectory() as td:
        artifact = Path(td) / "missing-executable-artifact"
        missing_spec = json.dumps(
            {
                "argv": ["lf-command-that-does-not-exist", "--probe"],
                "source_path": "virtual/missing-command",
            },
            separators=(",", ":"),
        )
        proc = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--gate-id", "MISSING_EXECUTABLE_GATE",
                "--step-id", "missing_executable",
                "--mode", "COLLECT_ALL",
                "--command-json", missing_spec,
                "--artifact-dir", str(artifact),
                "--owner", "S30",
                "--next-action", "RESTORE_EXECUTABLE",
                "--run-id", "MISSING-EXECUTABLE-RUN",
                "--job-id", "MISSING-EXECUTABLE-JOB",
                "--source-commit", "e" * 40,
            ],
            capture_output=True,
            text=True,
        )
        report = json.loads((artifact / "lf_gate_error_v1.json").read_text(encoding="utf-8"))
        assert proc.returncode == 1, proc.stderr
        assert report["gate_result"] == "FAIL"
        assert report["diagnostic_complete"] is True
        assert report["checks"][0]["exit_code"] == 127
        assert report["checks"][0]["error_class"] == "FileNotFoundError"
        assert report["checks"][0]["traceback_present"] is False
        assert report["checks"][0]["traceback_ref"]
        assert report["checks"][0]["traceback_sha256"]
        assert report["manifest_sha256"] == expected_manifest_sha(report)

    print("LF_GATE_ERROR_V1_PRODUCER_TEST_PASS")


if __name__ == "__main__":
    main()
