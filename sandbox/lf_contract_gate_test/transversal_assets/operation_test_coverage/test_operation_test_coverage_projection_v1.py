#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "operation_test_coverage_projection_v1.py"
spec = importlib.util.spec_from_file_location("operation_test_coverage_projection_v1", TARGET)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def row(**overrides):
    value = {
        "operation_code": "TEST_OPERATION",
        "lifecycle_state_code": "OP_OPERATIONAL",
        "assurance_obligation": "REQUIRED",
        "required_binding_count": 1,
        "executable_suite_count": 1,
        "active_case_count": 2,
        "observed_run_count": 0,
        "coverage_state": "COVERED",
        "coverage_reason": "REQUIRED_ASSURANCE_BINDING_PRESENT",
    }
    value.update(overrides)
    return value


def assert_no_material_verdict(out):
    assert out["material_pass_claimed"] is False
    assert out["quality_verdict_state"] == "NOT_EVALUATED"
    assert out["assurance_verdict_state"] == "NOT_EVALUATED"
    assert out["qualification_verdict_state"] == "NOT_EVALUATED"


def main() -> None:
    checks = 0

    # Mandatory negative: structural binding+suite+cases with zero runs is not execution/PASS.
    out = mod.project_operation_test_coverage(row())
    assert out["projection_status"] == "PROJECTED", out
    assert out["structural_coverage_state"] == "STRUCTURALLY_COVERED"
    assert out["execution_observation_state"] == "NO_EXECUTION_OBSERVED"
    assert_no_material_verdict(out)
    checks += 1

    # Even observed execution remains only an observation; this owner has no verdict authority.
    out = mod.project_operation_test_coverage(row(observed_run_count=3))
    assert out["structural_coverage_state"] == "STRUCTURALLY_COVERED"
    assert out["execution_observation_state"] == "EXECUTION_OBSERVED"
    assert_no_material_verdict(out)
    checks += 1

    expected = {
        "DISCOVERED": "DISCOVERED",
        "EVIDENCE_UNMAPPED": "EVIDENCE_UNMAPPED",
        "NOT_COVERED": "NOT_COVERED",
        "BLOCK": "STRUCTURAL_BLOCKED",
        "COVERED": "STRUCTURALLY_COVERED",
    }
    for legacy, typed in expected.items():
        out = mod.project_operation_test_coverage(row(coverage_state=legacy))
        assert out["structural_coverage_state"] == typed, out
        assert_no_material_verdict(out)
        checks += 1

    # A caller cannot smuggle a PASS-like legacy state into the projection.
    out = mod.project_operation_test_coverage(row(coverage_state="PASS"))
    assert out["projection_status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_UNKNOWN_LEGACY_COVERAGE_STATE"
    assert_no_material_verdict(out)
    checks += 1

    out = mod.project_operation_test_coverage(row(observed_run_count=-1))
    assert out["projection_status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_OBSERVED_RUN_COUNT"
    assert_no_material_verdict(out)
    checks += 1

    print(f"OPERATION_TEST_COVERAGE_PROJECTION_V1=PASS checks={checks}")


if __name__ == "__main__":
    main()
