#!/usr/bin/env python3
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from s30_strategy_orchestrator_bootstrap import (
    validate_bootstrap_contract,
    validate_registration_manifest,
    validate_canary_blueprint,
    registration_readiness,
)


def load(name):
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def main():
    checks = 0
    contract = load("strategy_orchestrator_bootstrap_contract_v1.json")
    manifest = load("strategy_orchestrator_registration_manifest_v1.json")
    canary = load("strategy_orchestrator_canary_blueprint_v1.json")

    assert validate_bootstrap_contract(contract)["status"] == "PASS"; checks += 1
    assert validate_registration_manifest(manifest)["status"] == "PASS"; checks += 1
    assert validate_canary_blueprint(canary)["status"] == "PASS"; checks += 1

    bad = dict(contract); bad["operation_code"] = "ORQUESTACION_PIPELINE_LF"
    assert validate_bootstrap_contract(bad)["status"] == "BLOCKED"; checks += 1

    bad = json.loads(json.dumps(contract)); bad["business_effect_dispatch_allowed"] = True
    assert validate_bootstrap_contract(bad)["status"] == "BLOCKED"; checks += 1

    bad = json.loads(json.dumps(contract)); bad["mandatory_invariants"].remove("BLOCKED_CHILD_DOES_NOT_HIDE_UNRELATED_SAFE_CHILD")
    assert validate_bootstrap_contract(bad)["status"] == "BLOCKED"; checks += 1

    bad = json.loads(json.dumps(manifest)); bad["apply_actions"]["supabase_write"] = True
    assert validate_registration_manifest(bad)["status"] == "BLOCKED"; checks += 1

    bad = json.loads(json.dumps(canary)); bad["cases"][1]["expected"] = "BLOCK_ALL"
    assert validate_canary_blueprint(bad)["status"] == "BLOCKED"; checks += 1

    ready = registration_readiness({
        "executor_registered_candidate_read_only": True,
        "executor_readiness_validated": True,
        "c05_dynamic_pass": True,
        "abc_d_closed_or_bound": True,
        "fresh_schema_readback": True,
        "operation_code_absent": True,
        "owner_registration_authorized": True,
    })
    assert ready["registration_allowed"] is True
    assert ready["runtime_activation_allowed"] is False
    assert ready["scheduler_activation_allowed"] is False
    checks += 1

    blocked = registration_readiness({
        "executor_registered_candidate_read_only": True,
        "executor_readiness_validated": True,
        "c05_dynamic_pass": True,
        "abc_d_closed_or_bound": True,
        "fresh_schema_readback": True,
        "operation_code_absent": False,
        "owner_registration_authorized": True,
    })
    assert blocked["status"] == "BLOCKED"; checks += 1

    print(f"S30_STRATEGY_ORCHESTRATOR_BOOTSTRAP_PASS={checks}")


if __name__ == "__main__":
    main()
