#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent
VALIDATOR_PATH = ROOT / "validate_operation_factory_candidate.py"
spec = importlib.util.spec_from_file_location("op_factory_validator", VALIDATOR_PATH)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def load(name):
    with (ROOT / name).open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


contract = load("contrato_operacion_lf.yaml")
steps = load("creacion_operacion_lf_steps.yaml")
judge = load("judge_operacion_lf.yaml")

base_errors = validator.validate(contract, steps, judge)
assert base_errors == [], base_errors

cases = []

c = copy.deepcopy(contract)
c["state_ceiling"]["operation_status"] = "PRODUCCION_CONTROLADA"
cases.append(("production_ceiling", c, steps, judge, "STATE_CEILING_MISMATCH:operation_status"))

c = copy.deepcopy(contract)
c["router_binding_contract"]["requires_existing_target"] = True
cases.append(("contradictory_target_flags", c, steps, judge, "ROUTER_BINDING_MISMATCH:requires_existing_target"))

c = copy.deepcopy(contract)
c["negative_controls"].remove("missing_execution_row_rejected")
cases.append(("missing_negative_control", c, steps, judge, "NEGATIVE_CONTROLS_MISSING:missing_execution_row_rejected"))

s = copy.deepcopy(steps)
s["steps"][3]["order"] = 99
cases.append(("step_order_gap", contract, s, judge, "STEP_ORDER_NOT_CONTIGUOUS"))

j = copy.deepcopy(judge)
j["required_assertions"] = [x for x in j["required_assertions"] if x["id"] != "rollback_clean"]
cases.append(("judge_missing_rollback", contract, steps, j, "JUDGE_ASSERTIONS_MISSING:rollback_clean"))

for name, c_doc, s_doc, j_doc, expected in cases:
    errors = validator.validate(c_doc, s_doc, j_doc)
    assert expected in errors, (name, expected, errors)

print(f"PASS_OPERATION_FACTORY_ADVERSARIAL_TESTS {1 + len(cases)}/{1 + len(cases)}")
