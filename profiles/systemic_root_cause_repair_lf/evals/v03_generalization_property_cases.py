#!/usr/bin/env python3
"""Cross-domain deterministic/metamorphic assurance for SRCR V0.3.

The fixtures are intentionally unrelated to the historical lifecycle escape.
They exercise generic materiality, authority, wiring, closure and currentness
properties without adding case-specific production rules.
"""

import copy
import json
import runpy
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
VALIDATORS = ROOT / "validators"
sys.path.insert(0, str(VALIDATORS))

import runtime_validate

fixture_globals = runpy.run_path(str(ROOT / "evals" / "v03_deterministic_floor_cases.py"))
valid_pair = fixture_globals["valid_pair"]
rebind = fixture_globals["rebind"]

schema = json.loads((ROOT / "schemas" / "output.schema.json").read_text())
schema_validator = Draft7Validator(schema)


def schema_valid(candidate):
    return not list(schema_validator.iter_errors(candidate))


def runtime_pass(candidate, manifest):
    return runtime_validate.validate(candidate, manifest)["status"] == "PASS"


def assert_runtime_code(candidate, manifest, code, label):
    result = runtime_validate.validate(candidate, manifest)
    assert result["status"] == "FAIL", (label, result)
    assert code in result["blocking_codes"], (label, code, result["blocking_codes"])


# 1. Lightweight local-deterministic domain is not forced into a state machine.
light, light_manifest = valid_pair()
light["symptom"]["statement"] = "A local deterministic formatter can return a structurally valid but incomplete maintenance recommendation."
light["origin_asset"]["code"] = "LOCAL_FORMATTER"
light["origin_asset"]["subject"] = "LOCAL_FORMATTER"
light["closure_proof"]["authority_bindings"][0]["subject"] = "LOCAL_FORMATTER"
for row in light_manifest["evidence"]:
    if row["evidence_id"] == "EV-ASSET":
        row["subject"] = "LOCAL_FORMATTER"
light, light_manifest = rebind(light, light_manifest)
assert schema_valid(light), "lightweight schema"
assert runtime_pass(light, light_manifest), "lightweight runtime"
assert light["closure_proof"]["behavioral_proofs"] == []


# 2. Permission/policy domain: proposed deliverable cannot masquerade as current authority.
policy, policy_manifest = valid_pair()
policy["symptom"]["statement"] = "A permission policy is proposed but has not been observed in the current authority registry."
policy["origin_asset"]["code"] = "ACCESS_POLICY_ALPHA"
policy["origin_asset"]["subject"] = "ACCESS_POLICY_ALPHA"
policy["origin_asset"]["authority_kind"] = "PROPOSED_DELIVERABLE"
policy["closure_proof"]["authority_bindings"][0].update(
    {"subject": "ACCESS_POLICY_ALPHA", "authority_kind": "PROPOSED_DELIVERABLE", "used_as_existing_authority": True}
)
for row in policy_manifest["evidence"]:
    if row["evidence_id"] == "EV-ASSET":
        row["subject"] = "ACCESS_POLICY_ALPHA"
policy, policy_manifest = rebind(policy, policy_manifest)
assert not schema_valid(policy), "proposed policy authority must violate V0.3 schema"
assert_runtime_code(policy, policy_manifest, "SRCR_EXISTING_AUTHORITY_REQUIRED", "proposed policy current authority")


# 3. Queue-worker domain: material state/recovery is valid only with complete behavior proof.
queue, queue_manifest = valid_pair()
queue["symptom"]["statement"] = "A queue worker can be interrupted between claim, processing, retry and terminal acknowledgement."
queue["solution_depth"]["complexity_signals"] = ["STATE_RECOVERY"]
for row in queue["closure_proof"]["materiality"]:
    if row["signal"] == "STATE_RECOVERY":
        row.update(
            {
                "material": True,
                "rationale": "Retry, interruption and terminal acknowledgement are material.",
                "obligation_ids": ["PO-STATE"],
            }
        )
queue["closure_proof"]["proof_obligations"].append(
    {
        "obligation_id": "PO-STATE",
        "obligation_type": "STATE_RECOVERY_SEMANTICS",
        "derived_from": ["STATE_RECOVERY"],
        "status": "CLOSED",
        "evidence_ids": ["EV-CLOSURE"],
        "decision_refs": ["$.transition_plan"],
        "missing_requirements": [],
        "closure_basis": "Queue transition, retry, illegal transition and terminal semantics are explicit.",
    }
)
queue["closure_proof"]["behavioral_proofs"] = [
    {
        "behavior_id": "QUEUE-BEHAVIOR",
        "materiality_signal": "STATE_RECOVERY",
        "states_or_steps": ["READY", "CLAIMED", "PROCESSING", "RETRYABLE", "DONE"],
        "entry_conditions": ["READY can be claimed only with an available work item."],
        "terminal_conditions": ["DONE requires durable acknowledgement after processing."],
        "illegal_transitions": ["RETRYABLE cannot jump directly to DONE without processing."],
        "recovery_paths": ["Interrupted PROCESSING becomes RETRYABLE and resumes the same work item."],
        "decision_refs": ["$.transition_plan"],
        "evidence_ids": ["EV-CLOSURE"],
    }
]
queue["closure_proof"]["derived_decision_closure"]["required_obligation_ids"].append("PO-STATE")
queue["closure_proof"]["derived_decision_closure"]["closed_obligation_ids"].append("PO-STATE")
queue, queue_manifest = rebind(queue, queue_manifest)
assert schema_valid(queue), "complete queue state proof schema"
assert runtime_pass(queue, queue_manifest), "complete queue state proof runtime"

for field in ("entry_conditions", "terminal_conditions", "illegal_transitions", "recovery_paths"):
    mutant = copy.deepcopy(queue)
    mutant["closure_proof"]["behavioral_proofs"][0][field] = []
    mutant, mutant_manifest = rebind(mutant, copy.deepcopy(queue_manifest))
    assert not schema_valid(mutant), ("queue incomplete behavioral proof", field)
    # Runtime closure floor is intentionally not a duplicate JSON Schema engine;
    # schema + runtime are both required at the profile boundary.


# 4. ETL/wiring domain: conceptual wiring is insufficient when the edge is material.
etl, etl_manifest = valid_pair()
etl["symptom"]["statement"] = "An ETL repair changes a producer-to-consumer boundary and therefore physical wiring is material."
etl["solution_depth"]["complexity_signals"] = ["CROSS_OPERATION"]
for row in etl["omission_discovery"]:
    if row["dimension"] == "WIRING":
        row.update(
            {
                "disposition": "REQUIRED_CHANGE",
                "finding": "The ETL producer-consumer edge needs an explicit physical binding and enforcement point.",
                "evidence_refs": ["fixture://etl/wiring"],
            }
        )
etl["closure_proof"]["materiality"].append(
    {
        "signal": "CROSS_OPERATION",
        "material": True,
        "rationale": "Producer and consumer belong to distinct governed execution boundaries.",
        "obligation_ids": ["PO-CROSS-WIRE"],
    }
)
for row in etl["closure_proof"]["materiality"]:
    if row["signal"] == "WIRING":
        row.update(
            {
                "material": True,
                "rationale": "A material cross-component edge must be physically bound.",
                "obligation_ids": ["PO-CROSS-WIRE"],
            }
        )
etl["closure_proof"]["proof_obligations"].append(
    {
        "obligation_id": "PO-CROSS-WIRE",
        "obligation_type": "WIRING_PHYSICALITY",
        "derived_from": ["CROSS_OPERATION", "WIRING"],
        "status": "CLOSED",
        "evidence_ids": ["EV-CLOSURE"],
        "decision_refs": ["$.implementation_package.wiring"],
        "missing_requirements": [],
        "closure_basis": "Producer, contract, consumer, enforcement and physical binding are explicit.",
    }
)
etl["closure_proof"]["wiring_proofs"] = [
    {
        "edge_id": "ETL-EDGE-1",
        "producer_ref": "fixture://etl/extractor",
        "data_contract_ref": "fixture://etl/normalized-record-v1",
        "consumer_ref": "fixture://etl/loader",
        "enforcement_point_ref": "fixture://etl/loader/input-gate",
        "failure_behavior": "Reject the batch before load when the transport contract cannot be proven.",
        "binding_kind": "EXISTING_REUSABLE_CAPABILITY",
        "binding_ref": "fixture://etl/queue-binding",
        "evidence_ids": ["EV-CLOSURE"],
    }
]
etl["closure_proof"]["derived_decision_closure"]["required_obligation_ids"].append("PO-CROSS-WIRE")
etl["closure_proof"]["derived_decision_closure"]["closed_obligation_ids"].append("PO-CROSS-WIRE")
etl, etl_manifest = rebind(etl, etl_manifest)
assert schema_valid(etl), "complete ETL wiring schema"
assert runtime_pass(etl, etl_manifest), "complete ETL wiring runtime"

etl_missing = copy.deepcopy(etl)
etl_missing["closure_proof"]["wiring_proofs"] = []
etl_missing, etl_missing_manifest = rebind(etl_missing, copy.deepcopy(etl_manifest))
assert not schema_valid(etl_missing), "material wiring missing schema proof"
assert_runtime_code(etl_missing, etl_missing_manifest, "SRCR_MATERIAL_WIRING_UNDERCLOSED", "material wiring missing runtime proof")


# 5. Metamorphic closure: every required obligation is necessary.
base, base_manifest = valid_pair()
required_ids = list(base["closure_proof"]["derived_decision_closure"]["required_obligation_ids"])
for obligation_id in required_ids:
    mutant = copy.deepcopy(base)
    mutant["closure_proof"]["proof_obligations"] = [
        row for row in mutant["closure_proof"]["proof_obligations"] if row["obligation_id"] != obligation_id
    ]
    mutant, mutant_manifest = rebind(mutant, copy.deepcopy(base_manifest))
    result = runtime_validate.validate(mutant, mutant_manifest)
    assert result["status"] == "FAIL", ("removed required proof accepted", obligation_id, result)

for obligation_id in required_ids:
    mutant = copy.deepcopy(base)
    for row in mutant["closure_proof"]["proof_obligations"]:
        if row["obligation_id"] == obligation_id:
            row["status"] = "OPEN"
            row["missing_requirements"] = ["One material proof remains unresolved."]
            row["closure_basis"] = None
    mutant, mutant_manifest = rebind(mutant, copy.deepcopy(base_manifest))
    result = runtime_validate.validate(mutant, mutant_manifest)
    assert result["status"] == "FAIL", ("open required proof accepted", obligation_id, result)
    assert result["closure_summary"]["computed_handoff_ready"] is False


# 6. Evidence currentness is monotonic: CURRENT may pass, SUPERSEDED must not.
current, current_manifest = valid_pair()
assert runtime_pass(current, current_manifest), "current evidence should pass"
superseded = copy.deepcopy(current)
superseded_manifest = copy.deepcopy(current_manifest)
for row in superseded_manifest["evidence"]:
    if row["evidence_id"] == "EV-ASSET":
        row["state"] = "SUPERSEDED"
superseded, superseded_manifest = rebind(superseded, superseded_manifest)
assert_runtime_code(
    superseded,
    superseded_manifest,
    "SRCR_EXISTING_AUTHORITY_EVIDENCE_STALE",
    "superseded authority evidence",
)

print(
    "PASS_SRCR_V03_GENERALIZATION_PROPERTY="
    f"domains=4,behavior_mutations=4,closure_mutations={len(required_ids) * 2},currentness=2"
)
