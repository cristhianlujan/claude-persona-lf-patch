from __future__ import annotations

import runpy
from pathlib import Path


def test_srcr_v06_lifecycle_escape_replay() -> None:
    root = Path(__file__).resolve().parents[3]
    script = (
        root
        / "sandbox"
        / "lf_contract_gate_test"
        / "srcr_v06_lifecycle_regression"
        / "run_escape_replay.py"
    )
    runpy.run_path(str(script), run_name="srcr_v06_lifecycle_escape_replay_ci")
