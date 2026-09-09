#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("validator", ROOT / "validate_experience_card_candidate.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def load(name):
    with (ROOT / name).open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


contract = load("contrato_learning_bridge_experience_card_lf.yaml")
steps = load("learning_bridge_experience_card_lf_steps.yaml")
judge = load("judge_learning_bridge_experience_card_lf.yaml")
assert validator.validate(contract, steps, judge) == []

cases = []

c = copy.deepcopy(contract)
c["eligibility"]["required_fields"].remove("source_ref")
cases.append(("missing_source_ref_contract", c, steps, judge, "REQUIRED_FIELDS_MISSING:source_ref"))

c = copy.deepcopy(contract)
c["eligibility"]["required_fields"].append("competitor")
cases.append(("competitor_wrongly_required", c, steps, judge, "COMPETITOR_REQUIREMENT_FORBIDDEN"))

s = copy.deepcopy(steps)
contradiction = next(i for i,x in enumerate(s["steps"]) if x["id"] == "contradiction_gate")
dedup = next(i for i,x in enumerate(s["steps"]) if x["id"] == "deterministic_dedup")
s["steps"][contradiction]["id"], s["steps"][dedup]["id"] = s["steps"][dedup]["id"], s["steps"][contradiction]["id"]
cases.append(("dedup_before_contradiction", contract, s, judge, "DEDUP_PRECEDES_CONTRADICTION"))

c = copy.deepcopy(contract)
c["output_contract"]["direct_card_write"] = True
cases.append(("direct_card_write", c, steps, judge, "DIRECT_CARD_WRITE_MUST_BE_FALSE"))

c = copy.deepcopy(contract)
c["factory_dependency"]["active_router_binding_required_before_registration"] = False
cases.append(("factory_bypass", c, steps, judge, "FACTORY_DEPENDENCY_NOT_FAIL_CLOSED"))

c = copy.deepcopy(contract)
del c["invocation_route"]
cases.append(("missing_experience_route", c, steps, judge, "INVOCATION_ROUTE_MISSING"))

c = copy.deepcopy(contract)
c["invocation_route"]["write_allowed"] = True
cases.append(("experience_route_write_enabled", c, steps, judge, "INVOCATION_ROUTE_MISMATCH:write_allowed"))

c = copy.deepcopy(contract)
c["invocation_route"]["action_code"] = "KNOWLEDGE_LEARNING_BRIDGE"
cases.append(("experience_route_wrong_action", c, steps, judge, "INVOCATION_ROUTE_MISMATCH:action_code"))

s = copy.deepcopy(steps)
s["steps"] = [x for x in s["steps"] if x["id"] != "factory_and_invocation_route_check"]
for i, item in enumerate(s["steps"], start=1):
    item["order"] = i
cases.append(("missing_factory_and_route_step", contract, s, judge, "STEP_MISSING:factory_and_invocation_route_check"))

j = copy.deepcopy(judge)
j["blocked_if"].remove("independent_evidence_missing_for_promotion")
cases.append(("self_confirmation_guard_removed", contract, steps, j, "JUDGE_BLOCKED_CONDITION_MISSING:independent_evidence_missing_for_promotion"))

j = copy.deepcopy(judge)
j["blocked_if"].remove("experience_learning_bridge_route_missing")
cases.append(("route_missing_not_fail_closed", contract, steps, j, "JUDGE_BLOCKED_CONDITION_MISSING:experience_learning_bridge_route_missing"))

j = copy.deepcopy(judge)
j["fail_if"].remove("experience_route_write_enabled")
cases.append(("route_write_guard_removed", contract, steps, j, "JUDGE_FAIL_CONDITION_MISSING:experience_route_write_enabled"))

for name, c_doc, s_doc, j_doc, expected in cases:
    errors = validator.validate(c_doc, s_doc, j_doc)
    assert expected in errors, (name, expected, errors)

print(f"PASS_EXPERIENCE_CARD_ADVERSARIAL_TESTS {1 + len(cases)}/{1 + len(cases)}")
