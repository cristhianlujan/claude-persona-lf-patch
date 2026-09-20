#!/usr/bin/env python3
import copy
import json
from pathlib import Path
from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
schema = json.loads((ROOT / "schemas/output.schema.json").read_text())
validator = Draft7Validator(schema)
base = json.loads((ROOT / "examples/good_output.json").read_text())

def assert_valid(obj, label):
    errs = sorted(validator.iter_errors(obj), key=lambda e: list(e.path))
    assert not errs, f"{label}: {[e.message for e in errs[:8]]}"

def assert_invalid(obj, label):
    errs = list(validator.iter_errors(obj))
    assert errs, f"{label}: expected invalid"

def v03_base():
    x = copy.deepcopy(base)
    x["profile_pack_id"] = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3"
    for name, eid in (("origin_asset","EV-A"),("origin_operation","EV-O"),("owner","EV-W")):
        x[name]["authority_kind"] = "EXISTING_AUTHORITY"
        x[name]["evidence_id"] = eid
        x[name]["subject"] = x[name].get("code")
        x[name]["observed_revision"] = "rev-current"
    x["solution_depth"]["complexity_signals"] = ["NONE"]
    for row in x["omission_discovery"]:
        if row["dimension"] == "WIRING":
            row["disposition"] = "NOT_APPLICABLE"
            row["finding"] = "No cross-component wiring is material to this lightweight fixture."
    x["closure_proof"] = {
      "contract_version":"SRCR_CLOSURE_PROOF_V1",
      "materiality":[
        {"signal":"DECISION_CLOSURE","material":True,"rationale":"Readiness must be derived from proof closure.","obligation_ids":["PO-CLOSE"]},
        {"signal":"STATE_RECOVERY","material":False,"rationale":"No stateful behavior exists in this fixture.","obligation_ids":[]},
        {"signal":"WIRING","material":False,"rationale":"No material cross-component edge exists in this fixture.","obligation_ids":[]}
      ],
      "proof_obligations":[{"obligation_id":"PO-CLOSE","obligation_type":"DECISION_CLOSURE","derived_from":["DECISION_CLOSURE"],"status":"CLOSED","evidence_ids":["EV-A"],"decision_refs":["$.implementation_package.decision_closure"],"missing_requirements":[],"closure_basis":"All material design decisions are explicitly closed."}],
      "authority_bindings":[
        {"subject":x["origin_asset"]["code"],"authority_kind":"EXISTING_AUTHORITY","used_as_existing_authority":True,"evidence_ids":["EV-A"]},
        {"subject":x["origin_operation"]["code"],"authority_kind":"EXISTING_AUTHORITY","used_as_existing_authority":True,"evidence_ids":["EV-O"]},
        {"subject":x["owner"]["code"],"authority_kind":"EXISTING_AUTHORITY","used_as_existing_authority":True,"evidence_ids":["EV-W"]}
      ],
      "wiring_proofs":[],
      "behavioral_proofs":[],
      "derived_decision_closure":{"required_obligation_ids":["PO-CLOSE"],"closed_obligation_ids":["PO-CLOSE"],"open_obligation_ids":[],"handoff_ready":True,"quality_state":"QUALITY_PENDING"}
    }
    return x

assert_valid(base, "v02_compatibility")
light = v03_base()
assert_valid(light, "v03_lightweight")
missing = v03_base(); missing.pop("closure_proof")
assert_invalid(missing, "v03_requires_closure_proof")
bad_auth = v03_base(); bad_auth["origin_asset"]["authority_kind"] = "PROPOSED_DELIVERABLE"
assert_invalid(bad_auth, "proposed_deliverable_cannot_be_origin_authority")

stateful = v03_base()
stateful["solution_depth"]["complexity_signals"] = ["STATE_RECOVERY"]
stateful["closure_proof"]["materiality"][1] = {"signal":"STATE_RECOVERY","material":True,"rationale":"Worker retry and terminal behavior are material.","obligation_ids":["PO-STATE"]}
stateful["closure_proof"]["proof_obligations"].append({"obligation_id":"PO-STATE","obligation_type":"STATE_RECOVERY_SEMANTICS","derived_from":["STATE_RECOVERY"],"status":"CLOSED","evidence_ids":["EV-A"],"decision_refs":["$.transition_plan"],"missing_requirements":[],"closure_basis":"State, illegal transition, recovery and terminal semantics are explicit."})
stateful["closure_proof"]["derived_decision_closure"]["required_obligation_ids"].append("PO-STATE")
stateful["closure_proof"]["derived_decision_closure"]["closed_obligation_ids"].append("PO-STATE")
stateful["closure_proof"]["behavioral_proofs"].append({"behavior_id":"BEH-1","materiality_signal":"STATE_RECOVERY","states_or_steps":["READY","RUNNING","BLOCKED","DONE"],"entry_conditions":["READY may start only with required evidence."],"terminal_conditions":["DONE is terminal only after readback."],"illegal_transitions":["BLOCKED cannot jump directly to DONE."],"recovery_paths":["BLOCKED retries the same governed step."],"decision_refs":["$.transition_plan"],"evidence_ids":["EV-A"]})
assert_valid(stateful, "v03_stateful_complete")
state_missing = copy.deepcopy(stateful); state_missing["closure_proof"]["behavioral_proofs"] = []
assert_invalid(state_missing, "state_recovery_requires_behavioral_proof")

wiring = v03_base()
for row in wiring["omission_discovery"]:
    if row["dimension"] == "WIRING":
        row["disposition"] = "REQUIRED_CHANGE"
        row["finding"] = "A material producer-consumer edge must be implemented."
assert_invalid(wiring, "material_wiring_requires_wiring_proof")

open_claim = v03_base()
open_claim["closure_proof"]["derived_decision_closure"]["open_obligation_ids"] = ["PO-CLOSE"]
assert_invalid(open_claim, "handoff_ready_rejects_declared_open_ids")

producer_self_binding = v03_base()
producer_self_binding["closure_proof"]["candidate_binding"] = {
    "candidate_revision":"producer-rev",
    "candidate_digest":"sha256:producer",
    "evidence_bundle_id":"producer-bundle",
    "evidence_bundle_digest":"sha256:producer-evidence",
}
assert_invalid(producer_self_binding, "producer_candidate_self_binding_forbidden")

print("PASS_SRCR_V03_CONTRACT_SCHEMA=9/9")
