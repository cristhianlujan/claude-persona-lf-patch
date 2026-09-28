#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/lf-contract-check.yml"
OWNERSHIP = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_shared_ci_control_ownership_registry_v1.json"
IMPACT = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
LEGACY_GATE = ROOT / "sandbox/lf_contract_gate_test/s36_wp06_ci_completeness_gate.py"
LEGACY_SELFTEST = ROOT / "sandbox/lf_contract_gate_test/test_s36_wp06_ci_completeness_gate.py"


def main() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    ownership = json.loads(OWNERSHIP.read_text(encoding="utf-8"))
    impact = json.loads(IMPACT.read_text(encoding="utf-8"))

    assert "S36_ASSURANCE" not in workflow, "FAIL_S36_ASSURANCE_STILL_IN_ACTIVE_WORKFLOW"
    assert "s36_wp06_ci_completeness_gate.py" not in workflow, "FAIL_S36_GATE_STILL_IN_ACTIVE_WORKFLOW"
    assert "test_s36_wp06_ci_completeness_gate.py" not in workflow, "FAIL_S36_SELFTEST_STILL_IN_ACTIVE_WORKFLOW"

    owner_rows = ownership["controls"]
    assert all(not row["control_id"].startswith("S36_") for row in owner_rows), "FAIL_S36_SHARED_OWNERSHIP_ACTIVE"
    assert all("s36_wp06" not in row["path"] for row in owner_rows), "FAIL_S36_SHARED_PATH_ACTIVE"

    impact_ids = {row["control_id"] for row in impact["controls"]}
    assert "S36_ASSURANCE" not in impact_ids, "FAIL_S36_IMPACT_CONTROL_ACTIVE"
    assert "S36_ASSURANCE" not in set(impact["full_regression_controls"]), "FAIL_S36_FULL_REGRESSION_ACTIVE"

    # Historical implementation remains source lineage; carrier retirement must not erase history.
    assert LEGACY_GATE.is_file(), "FAIL_S36_HISTORICAL_GATE_LINEAGE_DELETED"
    assert LEGACY_SELFTEST.is_file(), "FAIL_S36_HISTORICAL_SELFTEST_LINEAGE_DELETED"

    print("PASS_ASSURANCE_CARRIER_RETIREMENT_V1 active_s36_calls=0 active_s36_ownership=0 historical_lineage=2")


if __name__ == "__main__":
    main()
