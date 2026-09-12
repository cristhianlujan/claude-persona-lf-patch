from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from s30_strategy_executor_precanary_currentness_v1 import (
    PASS,
    evaluate_authority_currentness,
    validate_precanary_source_contract,
)


def load(name: str) -> dict:
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def fresh_positive() -> dict:
    return {
        "readback_version": "S30_STRATEGY_EXECUTOR_AUTHORITY_READBACK_RUNTIME_V1",
        "operation_code": "EJECUCION_ESTRATEGIA_LF",
        "authority": "public.lf_strategy_snapshots",
        "identity_field": "snapshot_code",
        "selector": {
            "snapshot_code": "LF_S30_SHELL_ADVANCED_EXECUTION_20260903",
            "matching": "EXACT",
        },
        "exact_match_count": 1,
        "exact_matches": [
            {
                "id": 99,
                "snapshot_code": "LF_S30_SHELL_ADVANCED_EXECUTION_20260903",
                "status": "CANDIDATO_READ_ONLY",
                "runtime_state": "PLAN_ONLY",
                "impact_policy": "BLOQUEADO",
            }
        ],
        "currentness_scope": "IMMEDIATE_PRE_RUNTIME",
        "readback_current_for_execution": True,
        "observed_at": "2026-09-12T03:45:00+00:00",
    }


def main() -> None:
    checks = 0
    activation = load("strategy_executor_sandbox_activation_contract_v2.json")
    canary = load("strategy_executor_live_canary_v4.json")
    frozen = load("strategy_executor_authority_readback_20260912_v1.json")

    source = validate_precanary_source_contract(activation, canary, frozen)
    assert source["status"] == PASS, source
    assert source["runtime_execution_claimed"] is False
    assert source["runtime_activation_allowed"] is False
    checks += 1

    missing = evaluate_authority_currentness(activation, frozen)
    assert missing["code"] == "BLOCK_AUTHORITY_NOT_MATERIALIZED", missing
    checks += 1

    good = fresh_positive()
    ready = evaluate_authority_currentness(activation, good)
    assert ready["status"] == PASS, ready
    assert ready["code"] == "READY_FOR_RUNTIME_AUTHORIZATION_REQUEST"
    assert ready["resolved_snapshot_id"] == 99
    assert ready["runtime_activation_authorized"] is False
    checks += 1

    ambiguous = fresh_positive()
    ambiguous["exact_match_count"] = 2
    ambiguous["exact_matches"].append(copy.deepcopy(ambiguous["exact_matches"][0]))
    ambiguous["exact_matches"][1]["id"] = 100
    assert evaluate_authority_currentness(activation, ambiguous)["code"] == "BLOCK_AUTHORITY_AMBIGUOUS"
    checks += 1

    mismatched = fresh_positive()
    mismatched["exact_matches"][0]["snapshot_code"] = "OTHER_STRATEGY"
    assert evaluate_authority_currentness(activation, mismatched)["code"] == "BLOCK_AUTHORITY_IDENTITY_MISMATCH"
    checks += 1

    bad_status = fresh_positive()
    bad_status["exact_matches"][0]["status"] = "ACTIVE"
    assert evaluate_authority_currentness(activation, bad_status)["code"] == "BLOCK_AUTHORITY_STATUS"
    checks += 1

    bad_runtime_state = fresh_positive()
    bad_runtime_state["exact_matches"][0]["runtime_state"] = "ACTIVE_RUNTIME"
    assert evaluate_authority_currentness(activation, bad_runtime_state)["code"] == "BLOCK_AUTHORITY_RUNTIME_STATE"
    checks += 1

    bad_impact = fresh_positive()
    bad_impact["exact_matches"][0]["impact_policy"] = "PRODUCTION_WRITE_ALLOWED"
    assert evaluate_authority_currentness(activation, bad_impact)["code"] == "BLOCK_AUTHORITY_IMPACT_POLICY"
    checks += 1

    stale = fresh_positive()
    stale["currentness_scope"] = "FROZEN_SOURCE_EVIDENCE"
    stale["readback_current_for_execution"] = False
    assert evaluate_authority_currentness(activation, stale)["code"] == "BLOCK_AUTHORITY_CURRENTNESS_STALE"
    checks += 1

    bad_activation = copy.deepcopy(activation)
    bad_activation["strategy_resolution"]["resolved_snapshot_id"] = 35
    assert validate_precanary_source_contract(bad_activation, canary, frozen)["code"] == "BLOCK_CURRENTNESS_RESOLUTION_CONTRACT"
    checks += 1

    bad_canary = copy.deepcopy(canary)
    bad_canary["canary_status"] = "READY"
    assert validate_precanary_source_contract(activation, bad_canary, frozen)["code"] == "BLOCK_CURRENTNESS_CANARY_SOURCE_STATUS"
    checks += 1

    bad_canary = copy.deepcopy(canary)
    bad_canary["target_strategy"]["resolved_snapshot_id"] = 35
    assert validate_precanary_source_contract(activation, bad_canary, frozen)["code"] == "BLOCK_CURRENTNESS_HARDCODED_ID"
    checks += 1

    bad_canary = copy.deepcopy(canary)
    bad_canary["production_write_allowed"] = True
    assert validate_precanary_source_contract(activation, bad_canary, frozen)["code"] == "BLOCK_CURRENTNESS_ZERO_EFFECT_BOUNDARY"
    checks += 1

    bad_frozen = copy.deepcopy(frozen)
    bad_frozen["runtime_activation_allowed"] = True
    assert validate_precanary_source_contract(activation, canary, bad_frozen)["code"] == "BLOCK_CURRENTNESS_FROZEN_READBACK_RUNTIME_CLAIM"
    checks += 1

    print(json.dumps({
        "result": "PASS",
        "contract": "S30_STRATEGY_EXECUTOR_PRECANARY_CURRENTNESS_V1",
        "checks": checks,
        "canonical_live_readback": "BLOCK_AUTHORITY_NOT_MATERIALIZED",
        "positive_hypothetical": "READY_FOR_RUNTIME_AUTHORIZATION_REQUEST",
        "runtime_activation_authorized": False,
        "production_changed": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
