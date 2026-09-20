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
etl_manifest["evidence"].append(
    {
        "evidence_id": "EV-WIRING",
        "subject": "ETL-WIRING-READBACK",
        "evidence_class": "OBSERVED_READBACK",
        "source_locator": "fixture://etl/wiring/readback",
        "revision_or_observed_at": "etl-rev-1",
        "digest": "sha256:etl-wiring",
        "state": "CURRENT",
    }
)
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
        "obligation_ids": ["PO-CROSS-WIRE"],
        "binding_state": "OBSERVED_WIRED",
        "producer_ref": "fixture://etl/extractor",
        "data_contract_ref": "fixture://etl/normalized-record-v1",
        "consumer_ref": "fixture://etl/loader",
        "enforcement_point_ref": "fixture://etl/loader/input-gate",
        "failure_behavior": "Reject the batch before load when the transport contract cannot be proven.",
        "binding_kind": "EXISTING_REUSABLE_CAPABILITY",
        "binding_ref": "fixture://etl/queue-binding",
        "evidence_ids": ["EV-WIRING"],
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

etl_proposed = copy.deepcopy(etl)
etl_proposed["closure_proof"]["wiring_proofs"][0].update(
    {
        "binding_state": "PROPOSED_WIRING",
        "binding_kind": "PROPOSED_DELIVERABLE",
        "binding_ref": "fixture://etl/future-queue-binding",
        "evidence_ids": [],
    }
)
etl_proposed, etl_proposed_manifest = rebind(etl_proposed, copy.deepcopy(etl_manifest))
assert schema_valid(etl_proposed), "proposed ETL wiring is valid future design"
assert_runtime_code(
    etl_proposed,
    etl_proposed_manifest,
    "SRCR_CLOSED_WIRING_NOT_OBSERVED",
    "proposed wiring cannot close current obligation",
)

etl_source_only = copy.deepcopy(etl)
etl_source_only_manifest = copy.deepcopy(etl_manifest)
for row in etl_source_only_manifest["evidence"]:
    if row["evidence_id"] == "EV-WIRING":
        row["evidence_class"] = "SOURCE_PROVENANCE"
etl_source_only, etl_source_only_manifest = rebind(etl_source_only, etl_source_only_manifest)
assert_runtime_code(
    etl_source_only,
    etl_source_only_manifest,
    "SRCR_WIRING_EVIDENCE_CLASS_INSUFFICIENT",
    "source existence does not prove observed wiring",
)


# 5. Context transport domain: existing capabilities must be proven on the actual path.
ctx, ctx_manifest = valid_pair()
ctx["symptom"]["statement"] = "A context pipeline selects bounded facts and may hydrate additional evidence by reference before a model consumer."
ctx["solution_depth"]["complexity_signals"] = ["CONTEXT_TRANSPORT"]
ctx_manifest["evidence"].append(
    {
        "evidence_id": "EV-TRANSPORT",
        "subject": "CONTEXT-PIPELINE-READBACK",
        "evidence_class": "OBSERVED_READBACK",
        "source_locator": "fixture://context/readback/current",
        "revision_or_observed_at": "ctx-rev-1",
        "digest": "sha256:context-readback",
        "state": "CURRENT",
    }
)
ctx["closure_proof"]["materiality"].append(
    {
        "signal": "CONTEXT_TRANSPORT",
        "material": True,
        "rationale": "Selection, transport, bounded hydration and consumption materially affect the model input.",
        "obligation_ids": ["PO-CONTEXT", "PO-CONTEXT-WIRE"],
    }
)
ctx["closure_proof"]["proof_obligations"].extend(
    [
        {
            "obligation_id": "PO-CONTEXT",
            "obligation_type": "CONTEXT_TRANSPORT",
            "derived_from": ["CONTEXT_TRANSPORT"],
            "status": "CLOSED",
            "evidence_ids": ["EV-TRANSPORT"],
            "decision_refs": ["$.implementation_package.wiring"],
            "missing_requirements": [],
            "closure_basis": "Selection, budget, hydration, enforcement and readback are physically proven.",
        },
        {
            "obligation_id": "PO-CONTEXT-WIRE",
            "obligation_type": "WIRING_PHYSICALITY",
            "derived_from": ["CONTEXT_TRANSPORT"],
            "status": "CLOSED",
            "evidence_ids": ["EV-TRANSPORT"],
            "decision_refs": ["$.implementation_package.wiring"],
            "missing_requirements": [],
            "closure_basis": "The context producer-to-consumer binding is observed on the actual path.",
        },
    ]
)
ctx["closure_proof"]["wiring_proofs"] = [
    {
        "edge_id": "CTX-EDGE-1",
        "obligation_ids": ["PO-CONTEXT-WIRE"],
        "binding_state": "OBSERVED_WIRED",
        "producer_ref": "fixture://context/selector",
        "data_contract_ref": "fixture://context/capsule-v1",
        "consumer_ref": "fixture://context/model-consumer",
        "enforcement_point_ref": "fixture://context/pre-model-gate",
        "failure_behavior": "Block model dispatch when admitted context cannot be proven.",
        "binding_kind": "EXISTING_REUSABLE_CAPABILITY",
        "binding_ref": "fixture://context/live-binding",
        "evidence_ids": ["EV-TRANSPORT"],
    }
]
ctx["closure_proof"]["context_transport_proofs"] = [
    {
        "transport_id": "CTX-TRANSPORT-1",
        "obligation_ids": ["PO-CONTEXT"],
        "selection_ref": "fixture://context/admission",
        "transport_contract_ref": "fixture://context/capsule-v1",
        "consumer_ref": "fixture://context/model-consumer",
        "enforcement_point_ref": "fixture://context/pre-model-gate",
        "budget_guard_ref": "fixture://context/total-prompt-budget",
        "hydration_mode": "JIT_BY_REF",
        "hydration_resolver_ref": "fixture://context/evidence-resolver",
        "failure_behavior": "Fail closed when a required reference cannot be hydrated or budgeted.",
        "wiring_edge_ids": ["CTX-EDGE-1"],
        "readback_evidence_ids": ["EV-TRANSPORT"],
    }
]
for oid in ("PO-CONTEXT", "PO-CONTEXT-WIRE"):
    ctx["closure_proof"]["derived_decision_closure"]["required_obligation_ids"].append(oid)
    ctx["closure_proof"]["derived_decision_closure"]["closed_obligation_ids"].append(oid)
ctx, ctx_manifest = rebind(ctx, ctx_manifest)
assert schema_valid(ctx), "complete context transport schema"
assert runtime_pass(ctx, ctx_manifest), "complete context transport runtime"

ctx_no_wire = copy.deepcopy(ctx)
ctx_no_wire["closure_proof"]["wiring_proofs"] = []
ctx_no_wire, ctx_no_wire_manifest = rebind(ctx_no_wire, copy.deepcopy(ctx_manifest))
assert_runtime_code(
    ctx_no_wire,
    ctx_no_wire_manifest,
    "SRCR_MATERIAL_WIRING_UNDERCLOSED",
    "context transport without physical wiring",
)

ctx_proposed_wire = copy.deepcopy(ctx)
ctx_proposed_wire["closure_proof"]["wiring_proofs"][0].update(
    {
        "binding_state": "PROPOSED_WIRING",
        "binding_kind": "PROPOSED_DELIVERABLE",
        "binding_ref": "fixture://context/future-binding",
        "evidence_ids": [],
    }
)
ctx_proposed_wire, ctx_proposed_manifest = rebind(ctx_proposed_wire, copy.deepcopy(ctx_manifest))
assert_runtime_code(
    ctx_proposed_wire,
    ctx_proposed_manifest,
    "SRCR_CLOSED_WIRING_NOT_OBSERVED",
    "existing capability without observed consumption",
)

ctx_no_budget = copy.deepcopy(ctx)
ctx_no_budget["closure_proof"]["context_transport_proofs"][0]["budget_guard_ref"] = ""
ctx_no_budget, ctx_no_budget_manifest = rebind(ctx_no_budget, copy.deepcopy(ctx_manifest))
assert not schema_valid(ctx_no_budget), "context transport budget guard required"
assert_runtime_code(
    ctx_no_budget,
    ctx_no_budget_manifest,
    "SRCR_CONTEXT_TRANSPORT_FIELD_REQUIRED",
    "context transport budget guard runtime",
)

ctx_no_jit = copy.deepcopy(ctx)
ctx_no_jit["closure_proof"]["context_transport_proofs"][0]["hydration_resolver_ref"] = None
ctx_no_jit, ctx_no_jit_manifest = rebind(ctx_no_jit, copy.deepcopy(ctx_manifest))
assert not schema_valid(ctx_no_jit), "JIT resolver required"
assert_runtime_code(
    ctx_no_jit,
    ctx_no_jit_manifest,
    "SRCR_CONTEXT_JIT_RESOLVER_MISSING",
    "JIT resolver runtime",
)

ctx_stale = copy.deepcopy(ctx)
ctx_stale_manifest = copy.deepcopy(ctx_manifest)
for row in ctx_stale_manifest["evidence"]:
    if row["evidence_id"] == "EV-TRANSPORT":
        row["state"] = "SUPERSEDED"
ctx_stale, ctx_stale_manifest = rebind(ctx_stale, ctx_stale_manifest)
assert_runtime_code(
    ctx_stale,
    ctx_stale_manifest,
    "SRCR_CONTEXT_READBACK_EVIDENCE_STALE",
    "context readback currentness",
)

ctx_wrong_link = copy.deepcopy(ctx)
ctx_wrong_link["closure_proof"]["context_transport_proofs"][0]["obligation_ids"] = ["PO-CONTEXT-WIRE"]
ctx_wrong_link, ctx_wrong_link_manifest = rebind(ctx_wrong_link, copy.deepcopy(ctx_manifest))
assert_runtime_code(
    ctx_wrong_link,
    ctx_wrong_link_manifest,
    "SRCR_CONTEXT_OBLIGATION_TYPE_MISMATCH",
    "context proof wrong obligation link",
)


# 6. Metamorphic closure: every required obligation is necessary.
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


# 7. Evidence currentness is monotonic: CURRENT may pass, SUPERSEDED must not.
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
    f"domains=5,behavior_mutations=4,closure_mutations={len(required_ids) * 2},"
    "wiring_observed_vs_proposed=3,context_transport_mutations=5,currentness=2"
)
