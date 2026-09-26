#!/usr/bin/env python3
"""Bounded S30 regression for migration_source_parity family CI applicability.

Reuses CI_FAST_DEEP_LANE_ROUTER + S30_BOUNDED_REGRESSION. It introduces no
new control, carrier, router, or execution authority.
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ROUTER_DIR = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router"
PLAN_PATH = ROUTER_DIR / "lf_ci_execution_plan_v2.py"
FAMILY_DIR = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity"
PROBE_PATH = "sandbox/lf_contract_gate_test/migration_source_parity/lf_migration_source_parity_repair.py"


def load_plan():
    spec = importlib.util.spec_from_file_location("lf_ci_execution_plan_v2_migration_source_parity_test", PLAN_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def assert_precise_applicability() -> None:
    plan_module = load_plan()
    temp_root = Path(tempfile.mkdtemp(prefix="lf-migration-source-parity-ci-applicability-"))
    probe = temp_root / PROBE_PATH
    probe.parent.mkdir(parents=True, exist_ok=True)
    probe.write_text("# migration source parity family probe\n", encoding="utf-8")

    plan = plan_module.build_plan(
        changed_paths=[PROBE_PATH],
        lane_required_controls=(),
        lane_mode="SPECIALIZED_REQUIRED",
        repo_root=temp_root,
    )

    assert plan["coverage_complete"] is True
    assert plan["full_regression"] is False, plan["full_regression_reason"]
    assert plan["required_controls"] == ["S30_BOUNDED_REGRESSION"], plan["required_controls"]
    assert plan["carrier_controls"] == {"VALIDATE_LF_PACKS": ["S30_BOUNDED_REGRESSION"]}
    reasons = plan["required_control_reasons"]["S30_BOUNDED_REGRESSION"]
    assert f"PATH:{PROBE_PATH}" in reasons, reasons
    assert "E16_ACTIONS_INVENTORY" not in plan["required_controls"]
    assert "E16_GOVERNANCE" not in plan["required_controls"]
    assert "MIGRATION_SOURCE_PARITY" not in plan["required_controls"]


def run_family_if_present() -> None:
    if not FAMILY_DIR.exists():
        print("PASS_MIGRATION_SOURCE_PARITY_BOUNDED_FAMILY tests=0 state=NOT_PRESENT_ON_BASE")
        return
    tests = sorted(FAMILY_DIR.glob("test_*.py"))
    if not tests:
        raise AssertionError("FAIL_MIGRATION_SOURCE_PARITY_FAMILY_NO_TESTS")
    for test_path in tests:
        completed = subprocess.run(
            [sys.executable, str(test_path)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(
                f"FAIL_MIGRATION_SOURCE_PARITY_FAMILY:{test_path.relative_to(ROOT)}:" + completed.stdout[-2000:]
            )
    print(f"PASS_MIGRATION_SOURCE_PARITY_BOUNDED_FAMILY tests={len(tests)} state=EXECUTED")


def main() -> None:
    assert_precise_applicability()
    run_family_if_present()
    print("PASS_MIGRATION_SOURCE_PARITY_CI_APPLICABILITY full_regression=false e16=not_applicable")


if __name__ == "__main__":
    main()
