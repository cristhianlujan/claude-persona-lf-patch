from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/run_profile_runtime_v3_owner_v1.py"


def test_profile_runtime_v3_owner_runner_boundary() -> None:
    completed = subprocess.run(
        [sys.executable, str(RUNNER), "--self-test"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, (completed.stdout, completed.stderr)
    assert "PROFILE_RUNTIME_V3_OWNER_RUNNER_V1=PASS 12/12" in completed.stdout
