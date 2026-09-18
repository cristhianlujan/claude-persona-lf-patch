#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
JUDGE = HERE / "lf_contract_check_parity_equivalence_v1.py"
HEAD = "a" * 40


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def fixture(root: Path) -> dict[str, Path]:
    legacy_input = root / "legacy.csv"
    shadow_input = root / "shadow.csv"
    write(legacy_input, "v,name,sha\n")
    write(shadow_input, "v,name,sha\n")
    legacy_stdout = root / "legacy.stdout.log"
    legacy_stderr = root / "legacy.stderr.log"
    shadow_stdout = root / "shadow.stdout.log"
    shadow_stderr = root / "shadow.stderr.log"
    write(legacy_stdout, "PASS_LF_MIGRATION_SOURCE_PARITY\n")
    write(legacy_stderr, "")
    write(shadow_stdout, "PASS_LF_MIGRATION_SOURCE_PARITY\n")
    write(shadow_stderr, "")

    child = root / "groups" / "MIGRATION_SOURCE_PARITY" / "lf_gate_error_v1.json"
    child.parent.mkdir(parents=True, exist_ok=True)
    child.write_text(
        json.dumps(
            {
                "gate_result": "PASS",
                "expected_check_count": 1,
                "executed_check_count": 1,
                "checks": [
                    {
                        "source_path": "sandbox/lf_contract_gate_test/lf_migration_source_parity.py",
                        "source_commit": HEAD,
                        "tested_commit": HEAD,
                        "stdout_ref": str(shadow_stdout),
                        "stderr_ref": str(shadow_stderr),
                        "stdout_sha256": sha(shadow_stdout),
                        "stderr_sha256": sha(shadow_stderr),
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    summary = root / "lf_gate_group_summary_v1.json"
    summary.write_text(
        json.dumps(
            {
                "producer": "LF_GATE_GROUP_ORCHESTRATOR_V1",
                "consumer_code": "LF_CONTRACT_CHECK",
                "selected_group_ids": ["MIGRATION_SOURCE_PARITY"],
                "executed_group_ids": ["MIGRATION_SOURCE_PARITY"],
                "remaining_group_ids": [],
                "gate_result": "PASS",
                "full_coverage": True,
                "manifest_sha256": "b" * 64,
                "groups": [
                    {
                        "group_id": "MIGRATION_SOURCE_PARITY",
                        "expected_check_count": 1,
                        "executed_check_count": 1,
                        "report_ref": str(child),
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    return {
        "legacy_input": legacy_input,
        "shadow_input": shadow_input,
        "legacy_stdout": legacy_stdout,
        "legacy_stderr": legacy_stderr,
        "summary": summary,
    }


def run(root: Path, fx: dict[str, Path], *, controls: str = '["MIGRATION_SOURCE_PARITY"]',
        legacy_required: str = "true", legacy_result: str = "PASS") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(JUDGE),
            "--required-controls-json",
            controls,
            "--legacy-required",
            legacy_required,
            "--legacy-result",
            legacy_result,
            "--legacy-stdout",
            str(fx["legacy_stdout"]),
            "--legacy-stderr",
            str(fx["legacy_stderr"]),
            "--shadow-summary",
            str(fx["summary"]),
            "--input-pair",
            f'{fx["legacy_input"]}={fx["shadow_input"]}',
            "--expected-source-head",
            HEAD,
            "--expected-tested-head",
            HEAD,
            "--output",
            str(root / "equivalence.json"),
        ],
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> None:
    checks = 0
    with tempfile.TemporaryDirectory() as td:
        root = Path(td); fx = fixture(root)
        proc = run(root, fx)
        assert proc.returncode == 0, (proc.stdout, proc.stderr)
        receipt = json.loads((root / "equivalence.json").read_text(encoding="utf-8"))
        assert receipt["result"] == "PASS_EQUIVALENT"
        assert receipt["divergence_count"] == 0
        checks += 1

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); fx = fixture(root)
        proc = run(root, fx, controls="[]")
        assert proc.returncode != 0
        assert "FAIL_PARITY_EQUIVALENCE_APPLICABILITY" in (proc.stdout + proc.stderr)
        checks += 1

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); fx = fixture(root)
        write(fx["shadow_input"], "different\n")
        proc = run(root, fx)
        assert proc.returncode != 0
        assert "FAIL_PARITY_EQUIVALENCE_INPUT_DIGEST" in (proc.stdout + proc.stderr)
        checks += 1

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); fx = fixture(root)
        proc = run(root, fx, legacy_result="FAIL")
        assert proc.returncode != 0
        assert "FAIL_PARITY_EQUIVALENCE_RESULT" in (proc.stdout + proc.stderr)
        checks += 1

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); fx = fixture(root)
        data = json.loads(fx["summary"].read_text(encoding="utf-8"))
        child = Path(data["groups"][0]["report_ref"])
        report = json.loads(child.read_text(encoding="utf-8"))
        report["checks"][0]["source_commit"] = "c" * 40
        child.write_text(json.dumps(report), encoding="utf-8")
        proc = run(root, fx)
        assert proc.returncode != 0
        assert "FAIL_PARITY_EQUIVALENCE_SOURCE_COMMIT" in (proc.stdout + proc.stderr)
        checks += 1

    print(f"PASS_LF_CONTRACT_CHECK_PARITY_EQUIVALENCE_TESTS={checks}/5")


if __name__ == "__main__":
    main()
