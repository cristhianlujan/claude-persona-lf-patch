#!/usr/bin/env python3
"""Transversal V0.3/V2 closure semantics and vocabulary parity.

These cases are deliberately domain-neutral. They prove that a repair
specification can describe a missing current binding, fully specify the future
binding, and keep post-implementation observation pending without pretending
that the repair is already deployed.
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

import closure_proof
import runtime_validate

fixture = runpy.run_path(str(ROOT / "evals" / "v03_deterministic_floor_cases.py"))
valid_pair = fixture["valid_pair"]
rebind = fixture["rebind"]

VOCAB = json.loads((ROOT / "contracts" / "closure_vocabulary.v2.json").read_text())
SCHEMA = json.loads((ROOT / "schemas" / "output.schema.json").read_text())
RUNTIME_SCHEMA = json.loads((ROOT / "schemas" / "runtime_output.schema.json").read_text())
schema_validator = Draft7Validator(SCHEMA)
runtime_schema_validator = Draft7Validator(RUNTIME_SCHEMA)


def schema_errors(value):
    return list(schema_validator.iter_errors(value))


def assert_code(result, code, label):
    assert result["status"] == "FAIL", (label, result)
    assert code in result["blocking_codes"], (label, code, result["blocking_codes"])


def to_v2(candidate, manifest):
    candidate = copy.deepcopy(candidate)
    manifest = copy.deepcopy(manifest)
    proof = candidate["closure_proof"]
    proof["contract_version"] = closure_proof.CLOSURE_V2
    for row in proof["proof_obligations"]:
        if row["obligation_type"] == "DECISION_CLOSURE":
            row["proof_phase"] = "REPAIR_DESIGN"
        else:
            row["proof_phase"] = "CURRENT_STATE"
    proof["derived_decision_closure"]["post_implementation_obligation_ids"] = []
    return rebind(candidate, manifest)


def with_missing_then_proposed_wiring(candidate, manifest):
    candidate, manifest = to_v2(candidate, manifest)
    proof = candidate["closure_proof"]

    for row in candidate["omission_discovery"]:
        if row["dimension"] == "WIRING":
            row["disposition"] = "REQUIRED_CHANGE"
            row["finding"] = (
                "The current producer-to-consumer binding is absent and an exact "
                "future binding must be specified before implementation."
            )
            row["evidence_refs"] = ["fixture://generic/current-binding-absence"]

    for row in proof["materiality"]:
        if row["signal"] == "WIRING":
            row.update(
                {
                    "material": True,
                    "rationale": "A missing current edge and its replacement are material.",
                    "obligation_ids": ["PO-WIRE-CURRENT", "PO-WIRE-DESIGN", "PO-WIRE-POST"],
                }
            )
            break

    manifest["evidence"].append(
        {
            "evidence_id": "EV-WIRE-ABSENCE",
            "subject": "GENERIC-BINDING-ABSENCE",
            "evidence_class": "SOURCE_PROVENANCE",
            "source_locator": "fixture://generic/current-binding-absence",
            "revision_or_observed_at": "rev-current",
            "digest": "sha256:generic-binding-absence",
            "state": "CURRENT",
        }
    )

    proof["proof_obligations"].extend(
        [
            {
                "obligation_id": "PO-WIRE-CURRENT",
                "obligation_type": "WIRING_PHYSICALITY",
                "proof_phase": "CURRENT_STATE",
                "derived_from": ["WIRING"],
                "status": "CLOSED",
                "evidence_ids": ["EV-WIRE-ABSENCE"],
                "decision_refs": ["$.closure_proof.wiring_proofs"],
                "missing_requirements": [],
                "closure_basis": "Current absence is explicitly observed and evidence-bound.",
            },
            {
                "obligation_id": "PO-WIRE-DESIGN",
                "obligation_type": "WIRING_PHYSICALITY",
                "proof_phase": "REPAIR_DESIGN",
                "derived_from": ["WIRING"],
                "status": "CLOSED",
                "evidence_ids": ["EV-CLOSURE"],
                "decision_refs": ["$.implementation_package.wiring"],
                "missing_requirements": [],
                "closure_basis": "The replacement producer-contract-consumer edge is fully specified.",
            },
            {
                "obligation_id": "PO-WIRE-POST",
                "obligation_type": "WIRING_PHYSICALITY",
                "proof_phase": "POST_IMPLEMENTATION",
                "derived_from": ["WIRING"],
                "status": "OPEN",
                "evidence_ids": [],
                "decision_refs": ["$.acceptance_criteria"],
                "missing_requirements": ["Observed post-implementation binding readback."],
                "closure_basis": None,
            },
        ]
    )

    proof["wiring_proofs"].extend(
        [
            {
                "edge_id": "EDGE-CURRENT-ABSENCE",
                "producer_ref": "fixture://generic/producer",
                "data_contract_ref": "fixture://generic/contract-v1",
                "consumer_ref": "fixture://generic/consumer",
                "enforcement_point_ref": "fixture://generic/consumer/input-gate",
                "failure_behavior": "Block use of the unproven current edge.",
                "binding_kind": "NO_BINDING",
                "binding_ref": "fixture://generic/current-binding-absence",
                "evidence_ids": ["EV-WIRE-ABSENCE"],
                "obligation_ids": ["PO-WIRE-CURRENT"],
                "binding_state": "OBSERVED_NOT_WIRED",
            },
            {
                "edge_id": "EDGE-REPAIR-DESIGN",
                "producer_ref": "fixture://generic/producer",
                "data_contract_ref": "fixture://generic/contract-v2",
                "consumer_ref": "fixture://generic/consumer",
                "enforcement_point_ref": "fixture://generic/consumer/input-gate",
                "failure_behavior": "Fail closed when the replacement contract is not consumed.",
                "binding_kind": "PROPOSED_DELIVERABLE",
                "binding_ref": "fixture://generic/proposed-binding",
                "evidence_ids": [],
                "obligation_ids": ["PO-WIRE-DESIGN"],
                "binding_state": "PROPOSED_WIRING",
            },
        ]
    )

    derived = proof["derived_decision_closure"]
    derived["required_obligation_ids"].extend(["PO-WIRE-CURRENT", "PO-WIRE-DESIGN"])
    derived["closed_obligation_ids"].extend(["PO-WIRE-CURRENT", "PO-WIRE-DESIGN"])
    derived["post_implementation_obligation_ids"] = ["PO-WIRE-POST"]
    derived["open_obligation_ids"] = []
    derived["handoff_ready"] = True
    candidate["implementation_package"]["decision_closure"]["handoff_ready"] = True

    return rebind(candidate, manifest)


# 1. V1 remains compatible for historical replays.
v1, v1_manifest = valid_pair()
assert runtime_validate.validate(v1, v1_manifest)["status"] == "PASS"

# 2. Fresh V2 lightweight case is valid.
v2, v2_manifest = to_v2(*valid_pair())
assert not schema_errors(v2)
v2_result = runtime_validate.validate(v2, v2_manifest)
assert v2_result["status"] == "PASS", v2_result
assert v2_result["closure_summary"]["closure_contract_version"] == closure_proof.CLOSURE_V2
assert v2_result["closure_summary"]["post_implementation_obligation_ids"] == []

# 3. Current observed absence + exact proposed repair + open post proof is handoff-ready.
wired, wired_manifest = with_missing_then_proposed_wiring(*valid_pair())
assert not schema_errors(wired), [e.message for e in schema_errors(wired)]
wired_result = runtime_validate.validate(wired, wired_manifest)
assert wired_result["status"] == "PASS", wired_result
assert wired_result["closure_summary"]["computed_handoff_ready"] is True
assert wired_result["closure_summary"]["post_implementation_obligation_ids"] == ["PO-WIRE-POST"]

# 4. Proposed wiring may not masquerade as CURRENT_STATE evidence.
bad_current = copy.deepcopy(wired)
row = next(x for x in bad_current["closure_proof"]["wiring_proofs"] if x["edge_id"] == "EDGE-CURRENT-ABSENCE")
row.update(
    {
        "binding_state": "PROPOSED_WIRING",
        "binding_kind": "PROPOSED_DELIVERABLE",
        "binding_ref": "fixture://generic/not-current",
        "evidence_ids": [],
    }
)
bad_current, bad_current_manifest = rebind(bad_current, copy.deepcopy(wired_manifest))
assert_code(
    runtime_validate.validate(bad_current, bad_current_manifest),
    "SRCR_CURRENT_STATE_WIRING_NOT_PROVEN",
    "proposed_cannot_prove_current_state",
)

# 5. A POST_IMPLEMENTATION claim marked CLOSED must have observed wired readback.
bad_post = copy.deepcopy(wired)
post = next(x for x in bad_post["closure_proof"]["proof_obligations"] if x["obligation_id"] == "PO-WIRE-POST")
post.update(
    {
        "status": "CLOSED",
        "evidence_ids": ["EV-WIRE-ABSENCE"],
        "missing_requirements": [],
        "closure_basis": "Incorrectly claims the future edge is already observed.",
    }
)
bad_post, bad_post_manifest = rebind(bad_post, copy.deepcopy(wired_manifest))
assert_code(
    runtime_validate.validate(bad_post, bad_post_manifest),
    "SRCR_POST_IMPLEMENTATION_WIRING_NOT_OBSERVED",
    "post_close_requires_observed_readback",
)

# 6. Vocabulary parity: canonical and provider-side schemas use the same generic enums.
assert set(
    SCHEMA["properties"]["solution_depth"]["properties"]["complexity_signals"]["items"]["enum"]
) == set(VOCAB["solution_depth_signals"])
assert set(
    SCHEMA["properties"]["recurrence_evidence"]["items"]["properties"]["evidence_class"]["enum"]
) == set(VOCAB["recurrence_evidence_classes"])
assert set(
    RUNTIME_SCHEMA["properties"]["solution_depth"]["properties"]["complexity_signals"]["items"]["enum"]
) == set(VOCAB["solution_depth_signals"])
assert set(
    RUNTIME_SCHEMA["properties"]["closure_proof"]["properties"]["materiality"]["items"]["properties"]["signal"]["enum"]
) == set(VOCAB["closure_materiality_signals"])

# 7. Omission dimensions are not smuggled into solution-depth enums.
depth_mutant = copy.deepcopy(v2)
depth_mutant["solution_depth"]["complexity_signals"] = ["WIRING"]
assert schema_errors(depth_mutant)

# 8. Source provenance is a valid typed recurrence observation.
source_recurrence = copy.deepcopy(v2)
source_recurrence["recurrence_evidence"][0]["evidence_class"] = "OBSERVED_SOURCE"
assert not schema_errors(source_recurrence)

# 9. Compact runtime constraint accepts canonical vocabulary and rejects near-synonyms.
assert not list(runtime_schema_validator.iter_errors(source_recurrence))
runtime_mutant = copy.deepcopy(source_recurrence)
runtime_mutant["closure_proof"]["wiring_proofs"] = [
    {
        "binding_state": "PARTIALLY_WIRED",
        "binding_kind": "EXISTING_REUSABLE_CAPABILITY",
    }
]
assert list(runtime_schema_validator.iter_errors(runtime_mutant))

# 10. Transversal core contains no incident/domain-specific exception literals.
forbidden = ("S30", "CI_FAST_DEEP", "apply_migration", "BASE_MAIN_SHA", "HOLDOUT-CI")
for rel in (
    "contracts/closure_vocabulary.v2.json",
    "schemas/runtime_output.schema.json",
    "validators/closure_proof.py",
):
    text = (ROOT / rel).read_text(encoding="utf-8")
    assert not any(token in text for token in forbidden), (rel, forbidden)

# 11. Provider-side constraint blocks invalid solution-depth mode before canonical validation.
invalid_mode = copy.deepcopy(source_recurrence)
invalid_mode["solution_depth"]["mode"] = "SYSTEMIC"
assert list(runtime_schema_validator.iter_errors(invalid_mode))

# 12. A reusable capability cannot self-promote into an authority slot at provider boundary.
invalid_authority = copy.deepcopy(source_recurrence)
invalid_authority["closure_proof"]["authority_bindings"] = [
    {"authority_kind": "EXISTING_REUSABLE_CAPABILITY", "used_as_existing_authority": True}
]
assert list(runtime_schema_validator.iter_errors(invalid_authority))

# 13. V0.3 origin authority slots cannot be filled by a reusable capability.
invalid_origin = copy.deepcopy(source_recurrence)
invalid_origin["origin_asset"]["authority_kind"] = "EXISTING_REUSABLE_CAPABILITY"
assert schema_errors(invalid_origin)
assert list(runtime_schema_validator.iter_errors(invalid_origin))

# 14. Provider constraint rejects noncanonical deliverable change types.
invalid_change = copy.deepcopy(source_recurrence)
invalid_change["implementation_package"]["deliverables"][0]["change_type"] = "PROMOTE_OR_BIND"
assert list(runtime_schema_validator.iter_errors(invalid_change))

# 15. Provider constraint rejects free-text implementation preconditions.
invalid_precondition = copy.deepcopy(source_recurrence)
invalid_precondition["implementation_package"]["decision_closure"]["implementation_preconditions"] = [
    "Resolve current authority before implementation."
]
assert list(runtime_schema_validator.iter_errors(invalid_precondition))

# 16. MATCH reconciliation is neutral in both canonical and provider schemas.
invalid_match = copy.deepcopy(source_recurrence)
invalid_match["execution_effect_reconciliation"] = [{
    "effect": "Observed effect matches declared producer.",
    "observed_ref": "fixture://effect/readback",
    "declared_producer": "fixture-producer",
    "declared_producer_ref": "fixture://producer/current",
    "observed_producer_refs": ["fixture://producer/current"],
    "reconciliation_status": "MATCH",
    "blocking": False,
    "impact": "NON_BLOCKING_HISTORICAL",
    "containment_ref": "fixture://containment"
}]
assert schema_errors(invalid_match)
assert list(runtime_schema_validator.iter_errors(invalid_match))

# 17. Provider constraint mirrors canonical minimum authority revision shape.
invalid_revision = copy.deepcopy(source_recurrence)
invalid_revision["origin_asset"]["observed_revision"] = "v1"
assert schema_errors(invalid_revision)
assert list(runtime_schema_validator.iter_errors(invalid_revision))

# 18. Every non-NONE depth signal is provider-constrained to matching materiality and obligation types.
invalid_depth_closure = copy.deepcopy(source_recurrence)
invalid_depth_closure["solution_depth"]["complexity_signals"] = ["CONCURRENCY", "COST_SCALE"]
assert list(runtime_schema_validator.iter_errors(invalid_depth_closure))

# 19. Origin authority subject must match the evidence-manifest subject exactly.
subject_candidate, subject_manifest = to_v2(*valid_pair())
subject_candidate["origin_asset"]["subject"] = "RELATED-BUT-DIFFERENT-SUBJECT"
subject_candidate, subject_manifest = rebind(subject_candidate, subject_manifest)
subject_result = runtime_validate.validate(subject_candidate, subject_manifest)
assert_code(subject_result, "SRCR_EXISTING_AUTHORITY_SUBJECT_MISMATCH", "authority_subject_exact_match")


# 20. Recurrence provenance cannot borrow falsification execution classes.
invalid_recurrence_namespace = copy.deepcopy(source_recurrence)
invalid_recurrence_namespace["recurrence_evidence"][0]["evidence_class"] = "OBSERVED_TEST"
assert schema_errors(invalid_recurrence_namespace)
assert list(runtime_schema_validator.iter_errors(invalid_recurrence_namespace))
namespace_result = runtime_validate.validate(invalid_recurrence_namespace, subject_manifest)
assert_code(namespace_result, "RECURRENCE_EVIDENCE_NOT_TYPED", "recurrence_falsification_namespace_cross_use")

# 21. Falsification execution state cannot borrow recurrence provenance classes.
invalid_falsification_namespace = copy.deepcopy(source_recurrence)
invalid_falsification_namespace["falsification_results"][0]["evidence_class"] = "OBSERVED_HISTORY"
assert schema_errors(invalid_falsification_namespace)
assert list(runtime_schema_validator.iter_errors(invalid_falsification_namespace))

# 22. Canonical, provider and validator vocabulary all share both field-specific namespaces.
assert set(
    SCHEMA["properties"]["falsification_results"]["items"]["properties"]["evidence_class"]["enum"]
) == set(VOCAB["falsification_evidence_classes"])
assert set(
    RUNTIME_SCHEMA["properties"]["falsification_results"]["items"]["properties"]["evidence_class"]["enum"]
) == set(VOCAB["falsification_evidence_classes"])
assert set(closure_proof.FALSIFICATION_EVIDENCE_CLASSES) == set(VOCAB["falsification_evidence_classes"])


# 23. V0.2 remains validator-readable for history but cannot be newly generated by the current provider boundary.
legacy_v02 = copy.deepcopy(fixture["BASE"])
assert not schema_errors(legacy_v02)
assert runtime_validate.validate(legacy_v02)["status"] == "PASS"
assert list(runtime_schema_validator.iter_errors(legacy_v02))

print("PASS_SRCR_V03_TRANSVERSAL_CONTRACT=23/23")
