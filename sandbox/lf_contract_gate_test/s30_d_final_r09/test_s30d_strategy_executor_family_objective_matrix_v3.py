from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from s30_strategy_executor_family_assurance_v3 import PASS, validate_family_objective_matrix_v3


def load(name: str) -> dict:
    return json.loads((HERE / name).read_text())


def main() -> None:
    checks = 0
    matrix_v3 = load("strategy_executor_family_objective_matrix_v3.json")
    matrix_v2 = load("strategy_executor_family_objective_matrix_v2.json")
    activation = load("strategy_executor_sandbox_activation_contract_v1.json")
    live_v3 = load("strategy_executor_live_canary_v3.json")
    live_v2 = load("strategy_executor_live_canary_v2.json")
    dry = load("strategy_executor_canary_blueprint_v1.json")
    bootstrap = load("strategy_executor_bootstrap_contract_v1.json")
    performance = load("strategy_executor_performance_policy_v1.json")

    result = validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, performance
    )
    assert result["status"] == PASS, result
    assert result["objective_count"] == 14
    assert result["dimension_count"] == 4
    assert result["functional_live_check_count"] == 14
    assert result["dimension_live_check_count"] == 4
    assert result["performance_metric_count"] == 9
    checks += 1

    bad = copy.deepcopy(matrix_v3)
    bad["objective_dimension_profiles"] = bad["objective_dimension_profiles"][:-1]
    assert validate_family_objective_matrix_v3(
        bad, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, performance
    )["code"] == "BLOCK_V3_DIMENSION_PROFILE_COVERAGE"
    checks += 1

    bad = copy.deepcopy(matrix_v3)
    del bad["objective_dimension_profiles"][0]["dimensions"]["PERFORMANCE"]
    assert validate_family_objective_matrix_v3(
        bad, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, performance
    )["code"] == "BLOCK_V3_DIMENSION_SHAPE"
    checks += 1

    bad = copy.deepcopy(matrix_v3)
    f02 = next(p for p in bad["objective_dimension_profiles"] if p["objective_id"] == "F02")
    f02["dimensions"]["PERFORMANCE"]["status"] = "OBSERVE_ONLY"
    f02["dimensions"]["PERFORMANCE"]["metric_ids"] = []
    assert validate_family_objective_matrix_v3(
        bad, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, performance
    )["code"] == "BLOCK_V3_PERFORMANCE_OBJECTIVE"
    checks += 1

    bad_perf = copy.deepcopy(performance)
    bad_perf["metrics"] = [m for m in bad_perf["metrics"] if m["id"] != "P09"]
    assert validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, bad_perf
    )["code"] == "BLOCK_V3_PERFORMANCE_METRIC_COVERAGE"
    checks += 1

    bad_perf = copy.deepcopy(performance)
    next(m for m in bad_perf["metrics"] if m["id"] == "P01")["max"] = 0
    assert validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, bad_perf
    )["code"] == "BLOCK_V3_PERFORMANCE_BUDGET"
    checks += 1

    bad_perf = copy.deepcopy(performance)
    bad_perf["sample_policy"]["measured_samples_min"] = 1
    assert validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, bad_perf
    )["code"] == "BLOCK_V3_PERFORMANCE_SAMPLE_POLICY"
    checks += 1

    bad_live = copy.deepcopy(live_v3)
    bad_live["runtime_execution_status"] = "EXECUTED"
    assert validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, bad_live, live_v2, dry, bootstrap, performance
    )["code"] == "BLOCK_V3_RUNTIME_CLAIM"
    checks += 1

    bad_live = copy.deepcopy(live_v3)
    bad_live["dimension_checks"] = [c for c in bad_live["dimension_checks"] if c["id"] != "D01"]
    assert validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, bad_live, live_v2, dry, bootstrap, performance
    )["code"] == "BLOCK_V3_DIMENSION_CHECK_COVERAGE"
    checks += 1

    bad_live = copy.deepcopy(live_v3)
    bad_live["production_write_allowed"] = True
    assert validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, bad_live, live_v2, dry, bootstrap, performance
    )["code"] == "BLOCK_V3_ZERO_EFFECT"
    checks += 1

    bad_perf = copy.deepcopy(performance)
    bad_perf["budget_scope"] = "PRODUCTION_SLO"
    assert validate_family_objective_matrix_v3(
        matrix_v3, matrix_v2, activation, live_v3, live_v2, dry, bootstrap, bad_perf
    )["code"] == "BLOCK_V3_PERFORMANCE_SCOPE"
    checks += 1

    assert matrix_v3["runtime_execution_claimed"] is False
    assert matrix_v3["production_activation_claimed"] is False
    assert matrix_v3["authorization_claimed"] is False
    assert performance["runtime_execution_status"] == "NOT_EXECUTED_SOURCE_ONLY"
    assert live_v3["activation_authority"] == "NONE"
    checks += 1

    print(json.dumps({
        "result": "PASS",
        "contract": "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V3",
        "checks": checks,
        "objectives": 14,
        "dimensions": 4,
        "functional_live_checks": 14,
        "dimension_live_checks": 4,
        "performance_metrics": 9,
        "runtime_execution_claimed": False,
        "production_activation_claimed": False,
        "authorization_claimed": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
