#!/usr/bin/env python3
import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATORS = ROOT / "validators"
sys.path.insert(0, str(VALIDATORS))

import closure_proof
import runtime_validate
import runtime_semantic_utility

BASE = json.loads((ROOT / "examples/good_output.json").read_text())

def make_manifest():
    return {
        "manifest_version": "SRCR_EVIDENCE_MANIFEST_V1",
        "bundle_id": "BUNDLE-1",
        "bundle_digest": "sha256:pending",
        "observed_at": "2026-09-20T04:30:00Z",
        "producer": {"kind": "TEST_FIXTURE", "resolver_ref": "fixture://v03-deterministic-floor"},
        "evidence": [
            {"evidence_id":"EV-ASSET","subject":"PROFILE-ASSET","evidence_class":"OBSERVED_LIVE","source_locator":"supabase://asset/current","revision_or_observed_at":"rev-1","digest":"sha256:asset","state":"CURRENT"},
            {"evidence_id":"EV-OP","subject":"PROFILE-OPERATION","evidence_class":"OBSERVED_READBACK","source_locator":"supabase://operation/current","revision_or_observed_at":"rev-1","digest":"sha256:operation","state":"CURRENT"},
            {"evidence_id":"EV-OWNER","subject":"PROFILE-OWNER","evidence_class":"GOVERNED_RECEIPT","source_locator":"receipt://owner/current","revision_or_observed_at":"rev-1","digest":"sha256:owner","state":"CURRENT"},
            {"evidence_id":"EV-CLOSURE","subject":"CLOSURE-CONTEXT","evidence_class":"SOURCE_PROVENANCE","source_locator":"provenance://closure/current","revision_or_observed_at":"rev-1","digest":"sha256:closure","state":"CURRENT"},
        ],
    }

def make_candidate():
    x = copy.deepcopy(BASE)
    x["profile_pack_id"] = closure_proof.V03_PACK_ID
    # Keep the lightweight fixture free of optional material changes.
    x["solution_depth"]["complexity_signals"] = ["NONE"]
    for row in x["omission_discovery"]:
        row["disposition"] = "REUSE_AS_IS"
        row["finding"] = "Existing behavior is sufficient for this lightweight generic fixture."
    slots = (
        ("origin_asset","PROFILE-ASSET","EV-ASSET"),
        ("origin_operation","PROFILE-OPERATION","EV-OP"),
        ("owner","PROFILE-OWNER","EV-OWNER"),
    )
    for field, subject, eid in slots:
        x[field]["code"] = subject
        x[field]["authority_kind"] = "EXISTING_AUTHORITY"
        x[field]["evidence_id"] = eid
        x[field]["subject"] = subject
        x[field]["observed_revision"] = "rev-1"
    x["closure_proof"] = {
        "contract_version":"SRCR_CLOSURE_PROOF_V1",
        "materiality":[
            {"signal":"DECISION_CLOSURE","material":True,"rationale":"Readiness must be derived from closed obligations.","obligation_ids":["PO-DECISION"]},
            {"signal":"EVIDENCE_PROVENANCE","material":True,"rationale":"Existing authority claims require external bound evidence.","obligation_ids":["PO-EVIDENCE"]},
            {"signal":"STATE_RECOVERY","material":False,"rationale":"No stateful behavior is material in this fixture.","obligation_ids":[]},
            {"signal":"WIRING","material":False,"rationale":"No cross-component wiring change is material in this fixture.","obligation_ids":[]},
        ],
        "proof_obligations":[
            {"obligation_id":"PO-AUTH","obligation_type":"AUTHORITY_EXISTENCE","derived_from":["BASELINE_EXISTING_AUTHORITY"],"status":"CLOSED","evidence_ids":["EV-ASSET","EV-OP","EV-OWNER"],"decision_refs":["$.origin_asset","$.origin_operation","$.owner"],"missing_requirements":[],"closure_basis":"All current authority slots are backed by current external evidence."},
            {"obligation_id":"PO-DECISION","obligation_type":"DECISION_CLOSURE","derived_from":["DECISION_CLOSURE"],"status":"CLOSED","evidence_ids":["EV-CLOSURE"],"decision_refs":["$.implementation_package.decision_closure"],"missing_requirements":[],"closure_basis":"All material design decisions are explicitly determined."},
            {"obligation_id":"PO-EVIDENCE","obligation_type":"EVIDENCE_PROVENANCE","derived_from":["EVIDENCE_PROVENANCE"],"status":"CLOSED","evidence_ids":["EV-CLOSURE"],"decision_refs":["$.evidence_map"],"missing_requirements":[],"closure_basis":"Proof evidence is externally bound to the candidate evaluation context."},
        ],
        "authority_bindings":[
            {"subject":"PROFILE-ASSET","authority_kind":"EXISTING_AUTHORITY","used_as_existing_authority":True,"evidence_ids":["EV-ASSET"]},
            {"subject":"PROFILE-OPERATION","authority_kind":"EXISTING_AUTHORITY","used_as_existing_authority":True,"evidence_ids":["EV-OP"]},
            {"subject":"PROFILE-OWNER","authority_kind":"EXISTING_AUTHORITY","used_as_existing_authority":True,"evidence_ids":["EV-OWNER"]},
        ],
        "wiring_proofs":[],
        "context_transport_proofs":[],
        "behavioral_proofs":[],
        "derived_decision_closure":{
            "required_obligation_ids":["PO-AUTH","PO-DECISION","PO-EVIDENCE"],
            "closed_obligation_ids":["PO-AUTH","PO-DECISION","PO-EVIDENCE"],
            "open_obligation_ids":[],
            "handoff_ready":True,
            "quality_state":"QUALITY_PENDING",
        },
    }
    x["implementation_package"]["decision_closure"]["handoff_ready"] = True
    x["implementation_package"]["decision_closure"]["open_design_decisions"] = []
    return x

def rebind(candidate, manifest):
    # External evidence owns only its own bundle digest. Candidate identity is
    # computed after producer output is final and is never written back by this helper.
    manifest["bundle_digest"] = "sha256:pending"
    manifest["bundle_digest"] = closure_proof.canonical_evidence_bundle_digest(manifest)
    return candidate, manifest

def valid_pair():
    return rebind(make_candidate(), make_manifest())

def assert_code(result, code, label):
    assert result["status"] == "FAIL", (label, result)
    assert code in result["blocking_codes"], (label, code, result["blocking_codes"])

candidate, manifest = valid_pair()
gate = runtime_validate.validate(candidate, manifest)
assert gate["status"] == "PASS", gate
assert gate["canonical_quality_accepted"] is False
assert gate["closure_summary"]["computed_handoff_ready"] is True
utility = runtime_semantic_utility.evaluate(candidate, gate, manifest)
assert utility["status"] == "PASS", utility
assert utility["canonical_quality_accepted"] is False
assert utility["canonical_quality_receipt_required"] is True

candidate, manifest = valid_pair()
assert_code(runtime_validate.validate(candidate), "SRCR_EVIDENCE_MANIFEST_REQUIRED", "manifest_required")

candidate, manifest = valid_pair()
manifest["evidence"][0]["state"] = "SUPERSEDED"
candidate, manifest = rebind(candidate, manifest)
assert_code(runtime_validate.validate(candidate, manifest), "SRCR_EXISTING_AUTHORITY_EVIDENCE_STALE", "stale_authority")

candidate_a, manifest_a = valid_pair()
candidate_b = copy.deepcopy(candidate_a)
candidate_b["symptom"]["statement"] += " Changed candidate."
assert closure_proof.canonical_candidate_digest(candidate_b) != closure_proof.canonical_candidate_digest(candidate_a)
assert runtime_validate.validate(candidate_b, manifest_a)["status"] == "PASS"

candidate, manifest = valid_pair()
manifest["candidate_digest"] = "sha256:producer-self-binding"
candidate, manifest = rebind(candidate, manifest)
assert_code(
    runtime_validate.validate(candidate, manifest),
    "SRCR_EVIDENCE_MANIFEST_CANDIDATE_SELF_BINDING_FORBIDDEN",
    "producer_evidence_self_binding_forbidden",
)

candidate, manifest = valid_pair()
candidate["closure_proof"]["proof_obligations"] = [x for x in candidate["closure_proof"]["proof_obligations"] if x["obligation_id"] != "PO-EVIDENCE"]
candidate["closure_proof"]["derived_decision_closure"]["required_obligation_ids"] = ["PO-AUTH","PO-DECISION"]
candidate["closure_proof"]["derived_decision_closure"]["closed_obligation_ids"] = ["PO-AUTH","PO-DECISION"]
candidate, manifest = rebind(candidate, manifest)
assert_code(runtime_validate.validate(candidate, manifest), "SRCR_REQUIRED_PROOF_OBLIGATION_MISSING", "required_type_missing")

candidate, manifest = valid_pair()
for row in candidate["closure_proof"]["proof_obligations"]:
    if row["obligation_id"] == "PO-DECISION":
        row["status"] = "OPEN"
        row["missing_requirements"] = ["Need one unresolved design decision."]
        row["closure_basis"] = None
candidate, manifest = rebind(candidate, manifest)
r = runtime_validate.validate(candidate, manifest)
assert r["status"] == "FAIL"
assert "SRCR_HANDOFF_READY_NOT_DERIVED" in r["blocking_codes"] or "SRCR_CLOSURE_PROOF_INCOMPLETE" in r["blocking_codes"]

candidate, manifest = valid_pair()
manifest["evidence"].append(copy.deepcopy(manifest["evidence"][0]))
candidate, manifest = rebind(candidate, manifest)
assert_code(runtime_validate.validate(candidate, manifest), "SRCR_EVIDENCE_ID_DUPLICATED", "duplicate_evidence")

candidate, manifest = valid_pair()
manifest["evidence"][0]["evidence_class"] = "OBSERVED_HISTORY"
candidate, manifest = rebind(candidate, manifest)
assert_code(runtime_validate.validate(candidate, manifest), "SRCR_EXISTING_AUTHORITY_EVIDENCE_CLASS_INSUFFICIENT", "history_not_current_authority")

candidate, manifest = valid_pair()
candidate["solution_depth"]["complexity_signals"] = ["STATE_RECOVERY"]
candidate["closure_proof"]["materiality"][2] = {"signal":"STATE_RECOVERY","material":True,"rationale":"Recovery and terminal semantics are material.","obligation_ids":["PO-STATE"]}
candidate["closure_proof"]["proof_obligations"].append({"obligation_id":"PO-STATE","obligation_type":"STATE_RECOVERY_SEMANTICS","derived_from":["STATE_RECOVERY"],"status":"CLOSED","evidence_ids":["EV-CLOSURE"],"decision_refs":["$.transition_plan"],"missing_requirements":[],"closure_basis":"State transition decisions are declared."})
candidate["closure_proof"]["derived_decision_closure"]["required_obligation_ids"].append("PO-STATE")
candidate["closure_proof"]["derived_decision_closure"]["closed_obligation_ids"].append("PO-STATE")
candidate, manifest = rebind(candidate, manifest)
assert_code(runtime_validate.validate(candidate, manifest), "SRCR_MATERIAL_BEHAVIOR_UNDERCLOSED", "state_behavior_required")

candidate, manifest = valid_pair()
assert candidate["closure_proof"]["behavioral_proofs"] == []
assert runtime_validate.validate(candidate, manifest)["status"] == "PASS"

candidate, manifest = valid_pair()
candidate["closure_proof"]["authority_bindings"][0]["authority_kind"] = "PROPOSED_DELIVERABLE"
candidate, manifest = rebind(candidate, manifest)
assert_code(runtime_validate.validate(candidate, manifest), "SRCR_PROPOSED_DELIVERABLE_AS_EXISTING_AUTHORITY", "proposed_as_existing")

candidate, manifest = valid_pair()
candidate["closure_proof"]["proof_obligations"][0]["evidence_ids"].append("EV-NOT-THERE")
candidate, manifest = rebind(candidate, manifest)
assert_code(runtime_validate.validate(candidate, manifest), "SRCR_PROOF_EVIDENCE_ID_UNRESOLVED", "unresolved_evidence_id")

# V0.2 remains compatible and requires no external manifest.
v02 = copy.deepcopy(BASE)
v02_gate = runtime_validate.validate(v02)
assert v02_gate["status"] == "PASS", v02_gate
v02_utility = runtime_semantic_utility.evaluate(v02, v02_gate)
assert v02_utility["status"] == "PASS", v02_utility
assert v02_utility["canonical_quality_accepted"] is False

print("PASS_SRCR_V03_DETERMINISTIC_FLOORS=12/12")
