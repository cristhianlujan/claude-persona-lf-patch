from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox/lf_contract_gate_test/gate_check_observability/run_gate_check_observability_owner_v1.py"


def main() -> int:
    completed = subprocess.run(
        [sys.executable, str(RUNNER), "--self-test"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, (completed.stdout, completed.stderr)
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    assert "GATE_CHECK_OBSERVABILITY_OWNER_RUNNER_V1=PASS 15/15" in lines
    payload = json.loads(lines[-1])
    assert payload["status"] == "PASS"
    assert payload["owner"] == "GATE_CHECK_OBSERVABILITY"
    assert payload["engine"].endswith("run_gate_checks_v1.py")
    assert payload["test_glob"].endswith("gate_check_observability/test_*.py")
    print("PASS_GCO_OWNER_RUNNER_BOUNDARY_V1=5/5")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
