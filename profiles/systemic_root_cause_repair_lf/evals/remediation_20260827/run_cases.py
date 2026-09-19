#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
GOOD = json.loads((ROOT / "examples/good_output.json").read_text())
SCHEMA = json.loads((ROOT / "schemas/output.schema.json").read_text())


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


validator = load_module("validator", ROOT / "validators/runtime_validate.py")
utility = load_module("utility", ROOT / "validators/runtime_semantic_utility.py")


def contract_gate():
    return {"status": "PASS"}


def schema_pass(value):
    try:
        jsonschema.validate(value, SCHEMA)
        return True
    except Exception:
        return False


def has_code(result, code):
    return code in (result.get("blocking_codes") or [])


def claim_hypothesis(statement, refs, missing):
    return {
        "statement": statement,
        "status": "HYPOTHESIS",
        "evidence_refs": refs,
        "missing_evidence": missing,
    }


def unresolved_authority(label):
    return {
        "status": "UNRESOLVED",
        "code": None,
        "evidence_ref": None,
        "missing_evidence": [label],
    }


def make_needs_more():
    o = copy.deepcopy(GOOD)
    o["status"] = "NEEDS_MORE_EVIDENCE"
    o["systemic_root_cause"] = claim_hypothesis(
        "The failure class may originate at one of two materially different enforcement boundaries.",
        ["runtime://effect/current"],
        ["exact boundary evidence that distinguishes the two repair designs"],
    )
    o["immediate_cause"] = claim_hypothesis(
        "A material effect can occur before the responsible execution boundary is established.",
        ["runtime://effect/current"],
        ["pre-effect trace for the unresolved boundary"],
    )
    o["first_bad_control"] = claim_hypothesis(
        "Admission may fail to bind the correct enforcement boundary before effect.",
        ["contract://operation/admission"],
        ["exact boundary selected by the live caller"],
    )
    o["escape_control"] = claim_hypothesis(
        "Post-effect evidence detects the result after the unresolved boundary has already been crossed.",
        ["runtime://effect/current"],
        ["current escape-path identity"],
    )
    o["repair_level"] = "UNDETERMINED"
    o["live_authority_packet"]["status"] = "PARTIAL"
    o["live_authority_packet"]["unavailable_sources"] = ["CURRENT_EXECUTION_BOUNDARY_IDENTITY"]
    o["live_authority_packet"]["unavailable_source_assessments"] = [{
        "source": "CURRENT_EXECUTION_BOUNDARY_IDENTITY",
        "impact": "DESIGN_BLOCKING",
        "rationale": "The missing source determines which of two materially different enforcement points is correct.",
        "containment_ref": None,
    }]
    rec = o["execution_effect_reconciliation"][0]
    rec["reconciliation_status"] = "UNRESOLVED_PRODUCER"
    rec["observed_producer_refs"] = []
    rec["impact"] = "DESIGN_BLOCKING"
    rec["blocking"] = True
    rec["containment_ref"] = None
    o["selected_alternative"] = None
    o["rejected_alternatives"] = []
    o["origin_asset"] = unresolved_authority("systemic origin asset")
    o["origin_operation"] = unresolved_authority("systemic origin operation")
    o["owner"] = unresolved_authority("systemic owner")
    o["invariant"] = {
        "statement": "The exact boundary must be resolved before a final invariant is accepted.",
        "validation_state": "PROPOSED",
        "evidence_refs": ["contract://operation/admission"],
        "missing_evidence": ["exact live enforcement boundary"],
    }
    o["hard_guard"] = {
        "validation_state": "PROPOSED",
        "control": "Block at the unresolved common boundary.",
        "enforcement_point_ref": None,
        "fail_closed_condition": "Block if the required boundary cannot be resolved.",
        "blocking_code": None,
        "observable_result": "No material effect is accepted before boundary resolution.",
        "evidence_refs": ["contract://operation/admission"],
        "missing_evidence": ["exact enforcement point and blocking code"],
    }
    o["should_exist_assessment"] = {
        "verdict": "INSUFFICIENT_EVIDENCE",
        "subject": "candidate enforcement boundary",
        "real_consumers": [],
        "elimination_impact": "Cannot be determined until the live boundary is identified.",
        "native_or_existing_alternative": "One of two existing boundaries may be sufficient.",
        "evidence_refs": [],
        "missing_evidence": ["exact live consumer/boundary mapping"],
    }
    for item in o["falsification_results"]:
        item["result"] = "NOT_COVERED"
        item["evidence_ref"] = "missing:" + item["case"]
        item["evidence_class"] = "MISSING"
    o["implementation_delta"] = []
    o["transition_plan"] = None
    o["rollback_plan"] = None
    o["current_uncertainties"] = [{
        "uncertainty": "The live execution boundary identity can change the selected repair design.",
        "impact": "DESIGN_BLOCKING",
        "evidence_needed": ["exact current producer-to-boundary trace"],
        "design_consequence": "Different evidence selects a different enforcement point and implementation delta.",
        "containment_ref": None,
    }]
    o["residual_risks"] = []
    o["blocking_codes"] = [
        "LIVE_AUTHORITY_EVIDENCE_INCOMPLETE",
        "EXECUTION_EFFECT_PRODUCER_UNRESOLVED",
    ]
    o["evidence_map"] = [
        {"claim_path": "$.symptom", "evidence_refs": ["run://migration-parity/failure-1"]},
        {"claim_path": "$.immediate_cause", "evidence_refs": ["runtime://effect/current"]},
        {"claim_path": "$.systemic_root_cause", "evidence_refs": ["runtime://effect/current"]},
        {"claim_path": "$.first_bad_control", "evidence_refs": ["contract://operation/admission"]},
        {"claim_path": "$.escape_control", "evidence_refs": ["runtime://effect/current"]},
        {"claim_path": "$.origin_asset", "evidence_refs": ["missing://systemic-origin-asset"]},
        {"claim_path": "$.origin_operation", "evidence_refs": ["missing://systemic-origin-operation"]},
        {"claim_path": "$.owner", "evidence_refs": ["missing://systemic-owner"]},
    ]
    o["next_gate"] = {
        "gate": "RESOLVE_DESIGN_BOUNDARY",
        "entry_condition": "A DESIGN_BLOCKING boundary uncertainty remains.",
        "exit_condition": "Exact evidence selects one repair boundary and removes the design blocker.",
    }
    return o


def evaluate_case(name, payload, expected_valid=True, expected_codes=()):
    r = validator.validate(payload)
    s = utility.evaluate(payload, contract_gate())
    schema_ok = schema_pass(payload)
    codes = set(r.get("blocking_codes") or []) | set(s.get("blocking_codes") or [])
    ok = (r["valid"] is expected_valid) and ((s["status"] == "PASS") is expected_valid)
    if expected_valid:
        ok = ok and schema_ok
    else:
        ok = ok and all(code in codes for code in expected_codes)
    return name, ok, {
        "schema": schema_ok,
        "validator": r["status"],
        "semantic": s["status"],
        "codes": sorted(codes),
    }


def run():
    cases = []

    cases.append(evaluate_case("ready_spec_with_contained_historical_unknown_passes", copy.deepcopy(GOOD), True))

    nme = make_needs_more()
    cases.append(evaluate_case("design_blocker_needs_more_passes", nme, True))

    x = copy.deepcopy(GOOD)
    x["current_uncertainties"][0]["impact"] = "DESIGN_BLOCKING"
    x["current_uncertainties"][0]["containment_ref"] = None
    cases.append(evaluate_case(
        "ready_spec_rejects_design_blocking_uncertainty", x, False,
        ["SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_UNCERTAINTY"],
    ))

    x = copy.deepcopy(GOOD)
    x["live_authority_packet"]["unavailable_source_assessments"][0]["impact"] = "DESIGN_BLOCKING"
    x["live_authority_packet"]["unavailable_source_assessments"][0]["containment_ref"] = None
    cases.append(evaluate_case(
        "ready_spec_rejects_design_blocking_authority_gap", x, False,
        ["SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_LIVE_AUTHORITY_GAP"],
    ))

    x = copy.deepcopy(GOOD)
    x["execution_effect_reconciliation"][0]["impact"] = "DESIGN_BLOCKING"
    x["execution_effect_reconciliation"][0]["blocking"] = True
    x["execution_effect_reconciliation"][0]["containment_ref"] = None
    x["blocking_codes"] = ["EXECUTION_EFFECT_PRODUCER_UNRESOLVED"]
    cases.append(evaluate_case(
        "ready_spec_rejects_design_blocking_unresolved_producer", x, False,
        ["SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_UNRESOLVED_PRODUCER"],
    ))

    x = copy.deepcopy(GOOD)
    x["execution_effect_reconciliation"][0]["containment_ref"] = None
    cases.append(evaluate_case(
        "contained_unresolved_producer_requires_containment", x, False,
        ["CONTAINED_UNRESOLVED_PRODUCER_REQUIRES_CONTAINMENT"],
    ))

    x = copy.deepcopy(GOOD)
    x["implementation_delta"] = []
    cases.append(evaluate_case(
        "ready_spec_requires_implementation_delta", x, False,
        ["SYSTEMIC_SPEC_IMPLEMENTATION_DELTA_REQUIRED"],
    ))

    x = copy.deepcopy(GOOD)
    x["transition_plan"] = None
    cases.append(evaluate_case(
        "ready_spec_requires_transition_plan", x, False,
        ["SYSTEMIC_SPEC_TRANSITION_PLAN_REQUIRED"],
    ))

    x = copy.deepcopy(GOOD)
    x["rollback_plan"] = None
    cases.append(evaluate_case(
        "ready_spec_requires_rollback_plan", x, False,
        ["SYSTEMIC_SPEC_ROLLBACK_PLAN_REQUIRED"],
    ))

    x = copy.deepcopy(GOOD)
    x["invariant"]["validation_state"] = "PROPOSED"
    x["invariant"]["missing_evidence"] = ["implementation not yet observed"]
    cases.append(evaluate_case(
        "ready_spec_requires_specified_invariant", x, False,
        ["SYSTEMIC_SPEC_INVARIANT_NOT_SPECIFIED"],
    ))

    x = copy.deepcopy(GOOD)
    x["falsification_results"][0]["result"] = "PASS"
    x["falsification_results"][0]["evidence_class"] = "DESIGN_ONLY"
    cases.append(evaluate_case(
        "design_only_falsification_cannot_pass", x, False,
        ["FALSIFICATION_PASS_NOT_OBSERVED"],
    ))

    x = copy.deepcopy(GOOD)
    x["falsification_results"][0]["evidence_class"] = "OBSERVED_TEST"
    cases.append(evaluate_case(
        "planned_falsification_must_remain_design_only", x, False,
        ["FALSIFICATION_PLANNED_MUST_BE_DESIGN_ONLY"],
    ))

    x = make_needs_more()
    x["selected_alternative"] = "B"
    cases.append(evaluate_case(
        "nonready_final_selection_rejected", x, False,
        ["FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS"],
    ))

    x = make_needs_more()
    x["residual_risks"] = [{"risk": "premature risk", "evidence_refs": ["runtime://effect/current"]}]
    cases.append(evaluate_case(
        "nonready_residual_risk_rejected", x, False,
        ["RESIDUAL_RISK_BEFORE_READY_SPEC"],
    ))

    x = make_needs_more()
    x["current_uncertainties"][0]["impact"] = "NON_BLOCKING_HISTORICAL"
    x["current_uncertainties"][0]["containment_ref"] = "$.hard_guard"
    cases.append(evaluate_case(
        "needs_more_requires_design_blocker", x, False,
        ["NEEDS_MORE_EVIDENCE_WITHOUT_DESIGN_BLOCKER"],
    ))

    x = copy.deepcopy(GOOD)
    x["live_authority_packet"]["unavailable_source_assessments"][0]["source"] = "DIFFERENT_SOURCE"
    cases.append(evaluate_case(
        "unavailable_source_assessments_must_match", x, False,
        ["LIVE_AUTHORITY_UNAVAILABLE_ASSESSMENT_MISMATCH"],
    ))

    x = copy.deepcopy(GOOD)
    x["execution_effect_reconciliation"][0]["reconciliation_status"] = "SOURCE_LIVE_DIVERGENCE"
    x["execution_effect_reconciliation"][0]["impact"] = "DESIGN_BLOCKING"
    x["execution_effect_reconciliation"][0]["blocking"] = True
    x["authority_contradictions"] = [{"kind": "SOURCE_LIVE_DIVERGENCE"}]
    cases.append(evaluate_case(
        "current_authority_contradiction_blocks_ready_spec", x, False,
        ["SYSTEMIC_SPEC_WITH_EXECUTION_CONTRADICTION"],
    ))

    x = copy.deepcopy(GOOD)
    x["systemic_root_cause"] = claim_hypothesis(
        "The systemic boundary may still differ.",
        ["runtime://effect/current"],
        ["exact root boundary"],
    )
    x["repair_level"] = "SYSTEMIC_ORIGIN"
    cases.append(evaluate_case(
        "unestablished_root_cannot_have_final_repair_level", x, False,
        ["REPAIR_LEVEL_PREMATURE"],
    ))

    holdout = make_needs_more()
    holdout["symptom"] = {
        "statement": "A scheduled notification was emitted but the current worker path cannot be resolved.",
        "status": "OBSERVED",
        "evidence_refs": ["runtime://notification-ledger/effect-42"],
        "missing_evidence": [],
    }
    cases.append(evaluate_case("non_mr02_design_blocking_holdout_stays_needs_more", holdout, True))

    x = copy.deepcopy(GOOD)
    x["current_uncertainties"][0]["impact"] = "IMPLEMENTATION_PRECONDITION"
    x["current_uncertainties"][0]["design_consequence"] = "No architecture change; exact inventory is required before activating the bounded stage."
    x["current_uncertainties"][0]["containment_ref"] = "$.implementation_package.decision_closure.implementation_preconditions[0]"
    x["execution_effect_reconciliation"][0]["impact"] = "IMPLEMENTATION_PRECONDITION"
    x["live_authority_packet"]["unavailable_source_assessments"][0]["impact"] = "IMPLEMENTATION_PRECONDITION"
    x["implementation_package"]["decision_closure"]["implementation_preconditions"] = [{
        "name": "exact implementation-stage inventory",
        "resolver_ref": "resolver://exact-stage-inventory",
        "expected_shape": "array<canonical_identity>",
        "decision_rule": "Apply the already-selected bounded stage to every returned identity; unresolved currentness blocks the stage without selecting a different architecture.",
        "stage": "ADOPT",
        "design_effect": "NONE",
    }]
    cases.append(evaluate_case("ready_spec_allows_implementation_precondition", x, True))


    x = copy.deepcopy(GOOD)
    x["implementation_package"]["decision_closure"]["open_design_decisions"] = ["Choose whether enforcement belongs in the recorder or wrapper."]
    x["implementation_package"]["decision_closure"]["handoff_ready"] = False
    cases.append(evaluate_case(
        "ready_spec_rejects_open_design_decision", x, False,
        ["SYSTEMIC_SPEC_OPEN_DESIGN_DECISIONS"],
    ))

    x = copy.deepcopy(GOOD)
    x["implementation_package"]["context_transport"]["compiler_ref"] = None
    cases.append(evaluate_case(
        "ready_spec_requires_closed_context_transport", x, False,
        ["CONTEXT_TRANSPORT_NOT_CLOSED"],
    ))

    x = copy.deepcopy(GOOD)
    x["solution_depth"]["mode"] = "DEEP_ARCHITECTURE_RESEARCH"
    x["challenger_review"] = x["challenger_review"][:1]
    cases.append(evaluate_case(
        "deep_architecture_requires_real_challenger", x, False,
        ["CHALLENGER_REVIEW_INSUFFICIENT"],
    ))

    x = copy.deepcopy(GOOD)
    x["omission_discovery"] = [d for d in x["omission_discovery"] if d["dimension"] != "COST_PERFORMANCE"]
    cases.append(evaluate_case(
        "ready_spec_requires_omission_discovery", x, False,
        ["SYSTEMIC_SPEC_OMISSION_DIMENSIONS_MISSING"],
    ))

    x = copy.deepcopy(GOOD)
    x["current_uncertainties"][0]["impact"] = "IMPLEMENTATION_PRECONDITION"
    x["current_uncertainties"][0]["containment_ref"] = "$.implementation_package.decision_closure.implementation_preconditions[0]"
    x["implementation_package"]["decision_closure"]["implementation_preconditions"] = [{
        "name": "fresh caller inventory",
        "resolver_ref": "resolver://exact-current-callers",
        "expected_shape": "array<caller_identity>",
        "decision_rule": "Apply the already-selected repair to every returned caller; empty inventory blocks that stage without changing architecture.",
        "stage": "ADOPT",
        "design_effect": "NONE",
    }]
    cases.append(evaluate_case("ready_spec_allows_mechanical_implementation_precondition", x, True))

    x = copy.deepcopy(GOOD)
    x["current_uncertainties"][0]["impact"] = "IMPLEMENTATION_PRECONDITION"
    x["current_uncertainties"][0]["containment_ref"] = "$.implementation_package.decision_closure.implementation_preconditions[0]"
    x["implementation_package"]["decision_closure"]["implementation_preconditions"] = [{
        "name": "choose enforcement point",
        "resolver_ref": "",
        "expected_shape": "",
        "decision_rule": "Decide what is best.",
        "stage": "ADOPT",
        "design_effect": "MAY_CHANGE",
    }]
    cases.append(evaluate_case(
        "implementation_precondition_cannot_hide_design_work", x, False,
        ["IMPLEMENTATION_PRECONDITION_NOT_MECHANICAL"],
    ))

    x = copy.deepcopy(GOOD)
    x["falsification_results"][0]["test_protocol"]["action"] = []
    cases.append(evaluate_case(
        "falsification_requires_executable_protocol", x, False,
        ["EXECUTABLE_TEST_PROTOCOL_INCOMPLETE"],
    ))

    x = copy.deepcopy(GOOD)
    x["solution_depth"] = {
        "mode": "LIGHTWEIGHT",
        "rationale": "The defect is deterministic and already classified by a current canonical rule.",
        "complexity_signals": ["NONE"],
    }
    x["research_assurance"]["current_practice_research_required"] = False
    x["research_assurance"]["external_research_rationale"] = "External technique research cannot change this already-classified deterministic repair."
    x["research_assurance"]["external_evidence_refs"] = []
    x["research_assurance"]["patterns_compared"] = [{
        "pattern": "existing canonical deterministic repair",
        "fit": "Exact match to the classified defect.",
        "tradeoff": "No new architecture is introduced.",
        "source_refs": ["ekb://deterministic-rule"],
    }]
    x["challenger_review"] = [x["challenger_review"][0]]
    cases.append(evaluate_case("lightweight_mode_does_not_require_external_research", x, True))

    malformed = [None, [], {}, {"status": "SYSTEMIC_REPAIR_SPEC"}]
    ok = all(validator.validate(item)["valid"] is False for item in malformed)
    cases.append(("malformed_fail_closed_no_crash", ok, {}))

    passed = sum(1 for _, ok, _ in cases if ok)
    print(json.dumps({
        "suite": "SYSTEMIC_ROOT_CAUSE_REPAIR_IMPLEMENTATION_CLOSURE_20260919",
        "evidence_class": "STRUCTURAL_AND_SEMANTIC_REGRESSION_NOT_LIVE_PROFILE_EXECUTION",
        "passed": passed,
        "total": len(cases),
        "cases": [{"case": n, "ok": ok, "details": d} for n, ok, d in cases],
    }, ensure_ascii=False, indent=2))
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    raise SystemExit(run())
