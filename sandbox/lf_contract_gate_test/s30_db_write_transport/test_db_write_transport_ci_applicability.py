#!/usr/bin/env python3
"""Bounded S30 regression for DB_WRITE_TRANSPORT CI applicability.

This is a test consumer of the existing CI_FAST_DEEP_LANE_ROUTER and
S30_BOUNDED_REGRESSION control. It does not introduce a new control/router.
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
DB_DIR = ROOT / "sandbox/lf_contract_gate_test/db_write_transport"
DB_SELECTOR = DB_DIR / "lf_db_write_transport.py"
PROBE_PATH = "sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py"


def load_plan():
    spec = importlib.util.spec_from_file_location("lf_ci_execution_plan_v2_db_write_test", PLAN_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def assert_precise_applicability() -> None:
    plan_module = load_plan()
    temp_root = Path(tempfile.mkdtemp(prefix="lf-db-write-ci-applicability-"))
    probe = temp_root / PROBE_PATH
    probe.parent.mkdir(parents=True, exist_ok=True)
    probe.write_text("# db write transport probe\n", encoding="utf-8")

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


def run_db_write_family() -> None:
    selector = subprocess.run(
        [sys.executable, str(DB_SELECTOR), "--self-test"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
        check=False,
    )
    if selector.returncode != 0 or "PASS_DB_WRITE_TRANSPORT_SELFTEST" not in selector.stdout:
        raise AssertionError("FAIL_DB_WRITE_TRANSPORT_SELFTEST:" + selector.stdout[-2000:])

    tests = sorted(DB_DIR.glob("test_*.py"))
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
                f"FAIL_DB_WRITE_TRANSPORT_FAMILY:{test_path.relative_to(ROOT)}:" + completed.stdout[-2000:]
            )

    print(f"PASS_DB_WRITE_TRANSPORT_BOUNDED_FAMILY selector=1 tests={len(tests)}")


def main() -> None:
    assert_precise_applicability()
    run_db_write_family()
    print("PASS_DB_WRITE_TRANSPORT_CI_APPLICABILITY full_regression=false e16=not_applicable")


if __name__ == "__main__":
    main()
