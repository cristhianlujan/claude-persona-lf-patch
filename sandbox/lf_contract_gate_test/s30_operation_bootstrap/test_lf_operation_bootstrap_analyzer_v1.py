#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from lf_operation_bootstrap_analyzer_v1 import analyze

HERE = Path(__file__).resolve().parent


def main() -> int:
    live = json.loads((HERE / "live_inventory_20260914.json").read_text(encoding="utf-8"))
    result = analyze(live)
    assert result["status"] == "BOOTSTRAP_GAP_CONFIRMED"
    assert result["operation_count_with_active_init"] == 20
    assert result["named_begin_function_count"] == 3
    assert result["structurally_ready_operation_count"] == 8
    assert result["zero_step_in_progress_total"] == 22
    assert result["zero_step_with_active_init"] == 9
    assert result["zero_step_without_active_init"] == 13
    assert result["legacy_zero_step_action"] == "EXECUTION_RECONCILIATION_REQUIRED_NOT_AUTO_BOOTSTRAP"
    assert "ACTUALIZACION_ADAPTER_LF" in result["structurally_ready_without_named_begin"]
    assert "EJECUCION_SKILL_LF" in result["structurally_ready_without_named_begin"]
    assert "ORQUESTACION_PIPELINE_LF" not in result["structurally_ready_operations"]
    assert "lf_profile_creation_begin_v1" in result["unsafe_existing_begin_or_guard_acl_functions"]
    assert result["auto_mutation_allowed"] is False

    synthetic = {
        "operations": [
            {"operation_code": "READY", "init_contracts": 1, "init_bindings": 1, "active_judges": 1},
            {"operation_code": "NO_CONTRACT", "init_contracts": 0, "init_bindings": 1, "active_judges": 1},
        ],
        "named_begin_functions": [],
        "zero_step_groups": [],
        "acl_findings": [{"function": "safe", "exposure": "SERVICE_ROLE_ONLY"}],
    }
    r2 = analyze(synthetic)
    assert r2["structurally_ready_operations"] == ["READY"]
    assert r2["topology_gap_operation_count"] == 1
    assert r2["topology_gaps"][0]["decision"] == "BLOCK_BOOTSTRAP_TOPOLOGY_INCOMPLETE"
    assert r2["unsafe_existing_begin_or_guard_acl_functions"] == []

    print(json.dumps({"status":"PASS","tests":15,"live_gap":result["status"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
