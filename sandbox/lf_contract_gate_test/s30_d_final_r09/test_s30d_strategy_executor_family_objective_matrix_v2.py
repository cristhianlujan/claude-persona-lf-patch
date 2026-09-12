from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from s30_strategy_executor_family_assurance import PASS, validate_family_objective_matrix


def load(name: str) -> dict:
    return json.loads((HERE / name).read_text())


def assert_all_referenced_files_exist(matrix: dict) -> int:
    checked = 0
    for objective in matrix["objectives"]:
        for key in ("positive_refs", "negative_refs", "evidence_refs"):
            for ref in objective[key]:
                filename = ref.split("::", 1)[0]
                assert (HERE / filename).exists(), (objective["id"], key, ref)
                checked += 1
    return checked


def main() -> None:
    checks = 0
    matrix = load("strategy_executor_family_objective_matrix_v2.json")
    activation = load("strategy_executor_sandbox_activation_contract_v1.json")
    live_canary = load("strategy_executor_live_canary_v2.json")
    dry_canary = load("strategy_executor_canary_blueprint_v1.json")
    bootstrap = load("strategy_executor_bootstrap_contract_v1.json")

    result = validate_family_objective_matrix(matrix, activation, live_canary, dry_canary, bootstrap)
    assert result["status"] == PASS, result
    assert result["objective_count"] == 14
    assert result["live_check_count"] == 14
    assert result["runtime_negative_check_count"] == 5
    checks += 1

    referenced_files = assert_all_referenced_files_exist(matrix)
    assert referenced_files >= 40
    checks += 1

    bad = copy.deepcopy(matrix)
    bad["objectives"] = bad["objectives"][:-1]
    assert validate_family_objective_matrix(bad, activation, live_canary, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_OBJECTIVE_COVERAGE"
    checks += 1

    bad = copy.deepcopy(matrix)
    next(o for o in bad["objectives"] if o["id"] == "F09")["runtime_check_ids"] = []
    assert validate_family_objective_matrix(bad, activation, live_canary, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_RUNTIME_MAPPING"
    checks += 1

    bad_activation = copy.deepcopy(activation)
    bad_activation["strategy_resolution"]["allowed_statuses"] = ["CANDIDATO_READ_ONLY", "ACTIVE"]
    assert validate_family_objective_matrix(matrix, bad_activation, live_canary, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_STRATEGY_AUTHORITY"
    checks += 1

    bad_activation = copy.deepcopy(activation)
    bad_activation["canary_boundary"]["production_write_allowed"] = True
    assert validate_family_objective_matrix(matrix, bad_activation, live_canary, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_ZERO_EFFECT_BOUNDARY"
    checks += 1

    bad_activation = copy.deepcopy(activation)
    bad_activation["rollback_policy"]["partial_activation_allowed"] = True
    assert validate_family_objective_matrix(matrix, bad_activation, live_canary, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_ROLLBACK_POLICY"
    checks += 1

    bad_live = copy.deepcopy(live_canary)
    bad_live["runtime_execution_status"] = "EXECUTED"
    assert validate_family_objective_matrix(matrix, activation, bad_live, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_RUNTIME_CLAIM"
    checks += 1

    bad_live = copy.deepcopy(live_canary)
    bad_live["target_strategy"]["snapshot_id"] = 999
    assert validate_family_objective_matrix(matrix, activation, bad_live, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_CANARY_TARGET_BINDING"
    checks += 1

    bad_live = copy.deepcopy(live_canary)
    bad_live["checks"] = [c for c in bad_live["checks"] if c["id"] != "L14"]
    assert validate_family_objective_matrix(matrix, activation, bad_live, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_RUNTIME_NEGATIVE_COVERAGE"
    checks += 1

    bad_live = copy.deepcopy(live_canary)
    bad_live["checks"][1]["id"] = "L01"
    assert validate_family_objective_matrix(matrix, activation, bad_live, dry_canary, bootstrap)["code"] == "BLOCK_FAMILY_LIVE_CHECK_DUPLICATE"
    checks += 1

    bad_dry = copy.deepcopy(dry_canary)
    bad_dry["cases"] = [c for c in bad_dry["cases"] if c["fault"] != "IDEMPOTENCY_HASH_CONFLICT"]
    assert validate_family_objective_matrix(matrix, activation, live_canary, bad_dry, bootstrap)["code"] == "BLOCK_FAMILY_STATIC_FAULT_COVERAGE"
    checks += 1

    bad_bootstrap = copy.deepcopy(bootstrap)
    bad_bootstrap["steps"] = bad_bootstrap["steps"][:-1]
    assert validate_family_objective_matrix(matrix, activation, live_canary, dry_canary, bad_bootstrap)["code"] == "BLOCK_FAMILY_STEP_COVERAGE"
    checks += 1

    assert matrix["runtime_execution_claimed"] is False
    assert matrix["production_activation_claimed"] is False
    assert matrix["authorization_claimed"] is False
    assert live_canary["activation_authority"] == "NONE"
    assert live_canary["runtime_execution_status"] == "NOT_EXECUTED_SOURCE_ONLY"
    checks += 1

    print(json.dumps({
        "result": "PASS",
        "contract": "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V2",
        "checks": checks,
        "objectives": 14,
        "planned_live_checks": 14,
        "mandatory_runtime_negative_checks": 5,
        "referenced_files_checked": referenced_files,
        "runtime_execution_claimed": False,
        "production_activation_claimed": False,
        "authorization_claimed": False
    }, sort_keys=True))


if __name__ == "__main__":
    main()
