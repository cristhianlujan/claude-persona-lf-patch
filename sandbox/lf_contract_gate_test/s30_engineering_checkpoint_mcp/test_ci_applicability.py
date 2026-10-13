#!/usr/bin/env python3
"""Precise CI applicability and offline family for scoped LF checkpoint MCP."""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ROUTER = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
MCP_DIR = ROOT / "sandbox/lf_contract_gate_test/engineering_checkpoint_mcp"
PROBE = "sandbox/lf_contract_gate_test/engineering_checkpoint_mcp/lf_engineering_checkpoint_mcp.py"


def test_bounded_plan() -> None:
    spec = importlib.util.spec_from_file_location("lf_ci_checkpoint_mcp_probe", ROUTER)
    assert spec and spec.loader
    m = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = m
    spec.loader.exec_module(m)
    with tempfile.TemporaryDirectory(prefix="lf-cp-mcp-ci-") as path:
        root = Path(path)
        source = root / PROBE
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text("# code-only probe\n")
        plan = m.build_plan(changed_paths=[PROBE],
                            lane_required_controls=(),
                            lane_mode="SPECIALIZED_REQUIRED",
                            repo_root=root)
    assert plan["coverage_complete"] is True
    assert plan["full_regression"] is False, plan["full_regression_reason"]
    assert plan["required_controls"] == ["S30_BOUNDED_REGRESSION"], plan["required_controls"]
    assert plan["carrier_controls"] == {"VALIDATE_LF_PACKS": ["S30_BOUNDED_REGRESSION"]}
    assert f"PATH:{PROBE}" in plan["required_control_reasons"]["S30_BOUNDED_REGRESSION"]
    for unrelated in ("E16_ACTIONS_INVENTORY", "E16_GOVERNANCE",
                      "MIGRATION_SOURCE_PARITY", "PROFILE_PACK"):
        assert unrelated not in plan["required_controls"]


def test_offline_family() -> None:
    for args in [
        [str(MCP_DIR / "lf_engineering_checkpoint_mcp.py"), "--self-test"],
        ["-m", "unittest", "discover", "-s", str(MCP_DIR),
         "-p", "test_connector.py", "-v"],
    ]:
        result = subprocess.run(
            [sys.executable, *args], cwd=ROOT, timeout=25,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            check=False,
        )
        assert result.returncode == 0, result.stdout[-2500:]


if __name__ == "__main__":
    test_bounded_plan()
    test_offline_family()
    print("PASS_LF_CP_MCP_S30_BOUNDED full_regression=false negative=8 no_DB")
