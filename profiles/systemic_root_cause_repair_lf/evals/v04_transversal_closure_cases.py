#!/usr/bin/env python3
import copy
import json
import runpy
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
VALIDATORS = ROOT / "validators"
sys.path.insert(0, str(VALIDATORS))

fixture = runpy.run_path(str(ROOT / "evals" / "v03_deterministic_floor_cases.py"))
runtime_validate = fixture["runtime_validate"]
closure_proof = fixture["closure_proof"]
valid_pair = fixture["valid_pair"]

schema = json.loads((ROOT / "schemas" / "output.schema.json").read_text())
schema_validator = Draft7Validator(schema)
V04 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_4"


def v04_pair():
    candidate, evidence = valid_pair()
    candidate["profile_pack_id"] = V04
    candidate["repair_disposition"] = {
        "decision": "REPAIR_REQUIRED",
        "rationale": "Current evidence shows an active material failure that requires a bounded repair.",
        "evidence_refs": ["fixture://v04/failure"],
        "currentness_refs": ["fixture://v04/currentness"],
        "active_failure_present": True,
        "material_repair_justified": True,
    }
    candidate["quantitative_decisions"] = []
    candidate["material_process_graph"] = {
        "applies": False,
        "rationale": "No lifecycle or multi-stage process is material to this lightweight fixture.",
        "nodes": [],
    }
    return candidate, evidence


def assert_schema_valid(candidate, label):
    errors = list(schema_validator.iter_errors(candidate))
    assert not errors, (label, [e.message for e in errors[:8]])


def assert_schema_invalid(candidate, label):
    errors = list(schema_validator.iter_errors(candidate))
    assert errors, (label, "expected schema failure")


def assert_runtime_pass(candidate, evidence, label):
    result = runtime_validate.validate(candidate, evidence)
    assert result["status"] == "PASS", (label, result)


def assert_runtime_code(candidate, evidence, code, label):
    result = runtime_validate.validate(candidate, evidence)
    assert result["status"] == "FAIL", (label, result)
    assert code in result["blocking_codes"], (label, code, result["blocking_codes"])


candidate, evidence = v04_pair()
assert_schema_valid(candidate, "v04_base_schema")
assert_runtime_pass(candidate, evidence, "v04_base_runtime")

missing = copy.deepcopy(candidate)
missing.pop("repair_disposition")
assert_schema_invalid(missing, "v04_disposition_schema_required")
assert_runtime_code(missing, evidence, "V04_REPAIR_DISPOSITION_REQUIRED", "v04_disposition_runtime_required")

grounded = copy.deepcopy(candidate)
grounded["quantitative_decisions"] = [{
    "decision_id": "QD-1",
    "parameter": "readiness_deadline_seconds",
    "proposed_value": 30,
    "materiality": "MATERIAL",
    "affects": ["terminality", "rollback_timing"],
    "grounding_type": "EXISTING_AUTHORITY",
    "grounding_ref": "fixture://policy/readiness",
    "evidence_refs": ["fixture://policy/readiness"],
    "incident_specific_only": False,
    "closure_state": "GROUNDED",
    "precondition_ref": None,
}]
assert_schema_valid(grounded, "v04_grounded_quant_schema")
assert_runtime_pass(grounded, evidence, "v04_grounded_quant_runtime")

incident_only = copy.deepcopy(grounded)
incident_only["quantitative_decisions"][0]["incident_specific_only"] = True
assert_runtime_code(
    incident_only, evidence,
    "V04_MATERIAL_QUANT_INCIDENT_ONLY_CANNOT_CLOSE",
    "incident_only_numeric_policy_rejected",
)

open_value = copy.deepcopy(candidate)
open_value["quantitative_decisions"] = [{
    "decision_id": "QD-2",
    "parameter": "retry_deadline_seconds",
    "proposed_value": 30,
    "materiality": "MATERIAL",
    "affects": ["terminality"],
    "grounding_type": "IMPLEMENTATION_PRECONDITION",
    "grounding_ref": None,
    "evidence_refs": ["fixture://incident/single-sample"],
    "incident_specific_only": True,
    "closure_state": "PRECONDITION",
    "precondition_ref": "$.implementation_package.decision_closure.implementation_preconditions[0]",
}]
assert_runtime_code(
    open_value, evidence,
    "V04_UNGROUNDED_QUANT_VALUE_MUST_REMAIN_OPEN",
    "ungrounded_numeric_value_cannot_be_fixed",
)

process = copy.deepcopy(candidate)
process["material_process_graph"] = {
    "applies": True,
    "rationale": "A governed lifecycle is material to the selected repair.",
    "nodes": [{
        "node_id": "N-CREATE",
        "phase": "CREATE",
        "authority_refs": ["fixture://authority/create"],
        "inputs": ["request"],
        "outputs": ["candidate"],
        "state_transition": "REQUESTED -> CANDIDATE",
        "producer_refs": ["fixture://producer/create"],
        "consumer_refs": ["fixture://consumer/update"],
        "wiring_refs": ["fixture://wiring/create-update"],
        "control_refs": ["fixture://control/create"],
        "failure_recovery": "Failure remains non-promoted and retry reuses the same governed identity.",
        "disposition": "REUSE_AS_IS",
        "evidence_refs": ["fixture://readback/create"],
        "acceptance_refs": ["AC-CREATE"],
    }]
}
assert_schema_valid(process, "v04_process_graph_schema")
assert_runtime_pass(process, evidence, "v04_process_graph_runtime")

blocked_process = copy.deepcopy(process)
blocked_process["material_process_graph"]["nodes"][0]["disposition"] = "DESIGN_BLOCKING"
assert_runtime_code(
    blocked_process, evidence,
    "V04_SYSTEMIC_SPEC_WITH_BLOCKED_PROCESS_NODE",
    "blocked_process_node_prevents_ready_spec",
)

no_repair = copy.deepcopy(candidate)
no_repair["status"] = "NO_REPAIR_REQUIRED"
no_repair["repair_disposition"] = {
    "decision": "ALREADY_RESOLVED",
    "rationale": "Exact current source and readback prove the historical defect is no longer present.",
    "evidence_refs": ["fixture://history/defect"],
    "currentness_refs": ["fixture://current/readback"],
    "active_failure_present": False,
    "material_repair_justified": False,
}
no_repair["preferred_alternative"] = None
no_repair["selected_alternative"] = None
no_repair["alternatives"] = []
no_repair["rejected_alternatives"] = []
no_repair["implementation_delta"] = []
no_repair["implementation_package"] = None
no_repair["transition_plan"] = None
no_repair["rollback_plan"] = None
no_repair["residual_risks"] = []
no_repair["blocking_codes"] = []
no_repair["repair_level"] = "UNDETERMINED"
for row in no_repair["closure_proof"]["proof_obligations"]:
    if row["obligation_id"] == "PO-DECISION":
        row["decision_refs"] = ["$.repair_disposition"]
assert_schema_valid(no_repair, "v04_no_repair_schema")
assert_runtime_pass(no_repair, evidence, "v04_no_repair_runtime")

hidden_delta = copy.deepcopy(no_repair)
hidden_delta["implementation_delta"] = [{
    "target": "fixture://should-not-change",
    "action": "Modify current behavior despite no-repair disposition.",
    "rationale": "This is intentionally invalid test data.",
    "evidence_refs": ["fixture://invalid"],
}]
assert_schema_invalid(hidden_delta, "v04_no_repair_hidden_delta_schema")
assert_runtime_code(hidden_delta, evidence, "V04_NO_REPAIR_WITH_REPAIR_DELTA", "v04_no_repair_hidden_delta_runtime")

bad_resolved = copy.deepcopy(no_repair)
bad_resolved["repair_disposition"]["active_failure_present"] = True
assert_runtime_code(
    bad_resolved, evidence,
    "V04_ALREADY_RESOLVED_WITH_ACTIVE_FAILURE",
    "already_resolved_requires_no_active_failure",
)

skill = (ROOT / "SKILL.md").read_text()
judge = (ROOT / "judges" / "systemic_root_cause_semantic_judge.md").read_text()
for token in (
    "NO_REPAIR_REQUIRED",
    "quantitative_decisions",
    "material_process_graph",
):
    assert token in skill, ("skill_missing", token)
for token in (
    "Current repair disposition",
    "Quantitative policy grounding",
    "Material process graph completeness",
):
    assert token in judge, ("judge_missing", token)

print("PASS_SRCR_V04_TRANSVERSAL_CLOSURE=10/10")
