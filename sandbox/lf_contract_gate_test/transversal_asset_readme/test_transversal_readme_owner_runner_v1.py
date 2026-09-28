from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox/lf_contract_gate_test/transversal_asset_readme/run_transversal_readme_owner_v1.py"


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
    assert "TRANSVERSAL_README_OWNER_RUNNER_V1=PASS 16/16" in lines
    payload = json.loads(lines[-1])
    assert payload["status"] == "PASS"
    assert payload["owner"] == "TRANSVERSAL_README"
    assert payload["commands"] == 2
    print("PASS_TRANSVERSAL_README_OWNER_RUNNER_BOUNDARY_V1=4/4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
