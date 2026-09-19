#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROFILE = HERE.parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


validator = load_module("srcr_runtime_validate", PROFILE / "validators/runtime_validate.py")
utility = load_module("srcr_runtime_semantic", PROFILE / "validators/runtime_semantic_utility.py")
GOOD = json.loads((PROFILE / "examples/good_output.json").read_text(encoding="utf-8"))


def contract_gate():
    return {"status": "PASS"}


def has_code(result, code):
    return code in result.get("blocking_codes", [])


def make_needs_more():
    value = copy.deepcopy(GOOD)
    value["status"] = "NEEDS_MORE_EVIDENCE"
    value["immediate_cause"] = {
        "statement": "The observed effect suggests a caller-provenance gap, but the executing identity is not fully recoverable.",
        "status": "HYPOTHESIS",
        "evidence_refs": ["runtime://effect/current"],
        "missing_evidence": ["historical caller identity"],
    }
    value["systemic_root_cause"] = {
        "statement": "A shared lifecycle boundary may be missing producer provenance enforcement.",
        "status": "HYPOTHESIS",
        "evidence_refs": ["runtime://effect/current", "contract://lifecycle/current"],
        "missing_evidence": ["complete live authority", "producer identity for every material effect"],
    }
    value["first_bad_control"] = {
        "statement": "The admission boundary may not bind caller provenance before the material effect.",
        "status": "HYPOTHESIS",
        "evidence_refs": ["contract://lifecycle/current"],
        "missing_evidence": ["observed pre-effect execution trace"],
    }
    value["escape_control"] = {
        "statement": "Post-effect telemetry reveals the effect but may not prove the originating caller.",
        "status": "HYPOTHESIS",
        "evidence_refs": ["runtime://effect/current"],
        "missing_evidence": ["complete producer trace"],
    }
    value["causal_chain"][1] = {
        "statement": "The effect may cross a boundary without complete producer provenance.",
        "status": "HYPOTHESIS",
        "evidence_refs": ["runtime://effect/current"],
        "missing_evidence": ["historical caller identity"],
    }
    value["live_authority_packet"]["status"] = "PARTIAL"
    value["live_authority_packet"]["inspected_surfaces"] = ["SQL_FUNCTIONS", "REPOSITORY"]
    value["live_authority_packet"]["unavailable_sources"] = ["AGENT_CONNECTOR_IDENTITY"]
    value["execution_effect_reconciliation"][0]["observed_producer_refs"] = []
    value["execution_effect_reconciliation"][0]["reconciliation_status"] = "UNRESOLVED_PRODUCER"
    value["execution_effect_reconciliation"][0]["blocking"] = True
    value["repair_level"] = "UNDETERMINED"
    value["should_exist_assessment"] = {
        "verdict": "INSUFFICIENT_EVIDENCE",
        "subject": "shared lifecycle provenance boundary",
        "real_consumers": [],
        "elimination_impact": "Cannot be concluded until actual consumers and producer identity are reconciled.",
        "native_or_existing_alternative": "Reuse the existing lifecycle policy and reliability primitives if the missing boundary is confirmed.",
        "evidence_refs": ["contract://lifecycle/current"],
        "missing_evidence": ["actual consumer inventory", "complete producer provenance"],
    }
    value["preferred_alternative"] = "B"
    value["selected_alternative"] = None
    value["rejected_alternatives"] = []
    for row in value["falsification_results"]:
        row["result"] = "NOT_COVERED"
        row["evidence_ref"] = f"missing:{row['case']}"
        row["evidence_class"] = "MISSING"
    unresolved = {
        "status": "UNRESOLVED",
        "code": None,
        "evidence_ref": None,
        "missing_evidence": ["exact governed identity"],
    }
    value["origin_asset"] = copy.deepcopy(unresolved)
    value["origin_operation"] = copy.deepcopy(unresolved)
    value["owner"] = copy.deepcopy(unresolved)
    value["invariant"] = {
        "statement": "Every material effect should be attributable to a governed producer before closure.",
        "validation_state": "PROPOSED",
        "evidence_refs": ["contract://lifecycle/current"],
        "missing_evidence": ["observed falsification of the proposed invariant"],
    }
    value["hard_guard"] = {
        "validation_state": "PROPOSED",
        "control": "Bind producer provenance before material effect.",
        "enforcement_point_ref": None,
        "fail_closed_condition": "Block when the producer cannot be verified.",
        "blocking_code": None,
        "observable_result": "No new material effect is committed.",
        "evidence_refs": ["contract://lifecycle/current"],
        "missing_evidence": ["exact enforcement point", "observed blocking code", "falsification evidence"],
    }
    value["current_uncertainties"] = [{
        "uncertainty": "The historical agent/connector identity that produced every observed effect is not recoverable from current evidence.",
        "blocking": True,
        "evidence_needed": ["historical caller identity", "producer-to-effect reconciliation"],
    }]
    value["residual_risks"] = []
    value["blocking_codes"] = [
        "LIVE_AUTHORITY_EVIDENCE_INCOMPLETE",
        "EXECUTION_EFFECT_PRODUCER_UNRESOLVED",
    ]
    value["evidence_map"] = [
        {"claim_path": "$.symptom", "evidence_refs": ["run://migration-parity/failure-1"]},
        {"claim_path": "$.immediate_cause", "evidence_refs": ["runtime://effect/current"]},
        {"claim_path": "$.systemic_root_cause", "evidence_refs": ["runtime://effect/current", "contract://lifecycle/current"]},
        {"claim_path": "$.first_bad_control", "evidence_refs": ["contract://lifecycle/current"]},
        {"claim_path": "$.escape_control", "evidence_refs": ["runtime://effect/current"]},
        {"claim_path": "$.origin_asset", "evidence_refs": ["missing://origin-asset-identity"]},
        {"claim_path": "$.origin_operation", "evidence_refs": ["missing://origin-operation-identity"]},
        {"claim_path": "$.owner", "evidence_refs": ["missing://owner-identity"]},
    ]
    value["next_gate"] = {
        "gate": "RESOLVE_LIVE_PRODUCER_PROVENANCE",
        "entry_condition": "Current live-authority packet remains partial or an effect producer is unresolved.",
        "exit_condition": "All applicable execution surfaces are inspected and every material effect producer is reconciled.",
    }
    return value


def run():
    cases = []

    ready = copy.deepcopy(GOOD)
    structural = validator.validate(ready)
    semantic = utility.evaluate(ready, contract_gate())
    cases.append(("ready_spec_positive", structural["valid"] and semantic["status"] == "PASS"))

    needs_more = make_needs_more()
    structural = validator.validate(needs_more)
    semantic = utility.evaluate(needs_more, contract_gate())
    cases.append(("honest_needs_more_positive", structural["valid"] and semantic["status"] == "PASS"))

    partial_without_blocker = make_needs_more()
    partial_without_blocker["blocking_codes"] = ["EXECUTION_EFFECT_PRODUCER_UNRESOLVED"]
    r = validator.validate(partial_without_blocker)
    cases.append(("partial_authority_requires_explicit_blocker", has_code(r, "LIVE_AUTHORITY_PARTIAL_WITHOUT_BLOCKER")))

    premature_root = make_needs_more()
    premature_root["systemic_root_cause"] = copy.deepcopy(GOOD["systemic_root_cause"])
    r = validator.validate(premature_root)
    s = utility.evaluate(premature_root, contract_gate())
    cases.append(("incomplete_authority_cannot_establish_root_cause", has_code(r, "PREMATURE_SYSTEMIC_ROOT_CAUSE") and has_code(s, "PREMATURE_SYSTEMIC_ROOT_CAUSE")))

    premature_repair = make_needs_more()
    premature_repair["repair_level"] = "ARCHITECTURAL"
    r = validator.validate(premature_repair)
    cases.append(("unresolved_root_cause_forces_undetermined_repair_level", has_code(r, "REPAIR_LEVEL_PREMATURE") or has_code(r, "PREMATURE_REPAIR_LEVEL")))

    premature_selection = make_needs_more()
    premature_selection["selected_alternative"] = "B"
    r = validator.validate(premature_selection)
    s = utility.evaluate(premature_selection, contract_gate())
    cases.append(("nonready_status_cannot_finalize_selected_alternative", has_code(r, "FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS") and has_code(s, "FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS")))

    premature_rejection = make_needs_more()
    premature_rejection["rejected_alternatives"] = [{
        "id": "A",
        "reason": "Prematurely rejected before authority closure.",
        "evidence_refs": ["design://comparison-only"],
    }]
    r = validator.validate(premature_rejection)
    cases.append(("incomplete_authority_cannot_finalize_rejected_alternatives", has_code(r, "PREMATURE_REJECTED_ALTERNATIVES")))

    residual_before_ready = make_needs_more()
    residual_before_ready["residual_risks"] = [{
        "risk": "This is still a current uncertainty, not a residual risk.",
        "evidence_refs": ["runtime://effect/current"],
    }]
    r = validator.validate(residual_before_ready)
    s = utility.evaluate(residual_before_ready, contract_gate())
    cases.append(("nonready_status_cannot_use_residual_risk_bucket", has_code(r, "RESIDUAL_RISK_BEFORE_READY_SPEC") and has_code(s, "RESIDUAL_RISK_BEFORE_READY_SPEC")))

    preferred_candidate = make_needs_more()
    r = validator.validate(preferred_candidate)
    cases.append(("nonready_status_can_keep_preferred_candidate", r["valid"] and preferred_candidate["preferred_alternative"] == "B" and preferred_candidate["selected_alternative"] is None))

    old_historical_shape = make_needs_more()
    old_historical_shape["historical_regressions"] = ["retry should not duplicate effect"]
    r = validator.validate(old_historical_shape)
    s = utility.evaluate(old_historical_shape, contract_gate())
    cases.append(("planned_scenario_cannot_masquerade_as_historical_occurrence", has_code(r, "HISTORICAL_REGRESSION_REQUIRES_OBSERVED_OCCURRENCE") and has_code(s, "HISTORICAL_REGRESSION_NOT_OBSERVED")))

    old_evidence_map = make_needs_more()
    old_evidence_map["evidence_map"] = ["runtime://effect/current", "contract://lifecycle/current"]
    r = validator.validate(old_evidence_map)
    s = utility.evaluate(old_evidence_map, contract_gate())
    cases.append(("global_reference_bag_is_not_claim_evidence_map", has_code(r, "EVIDENCE_MAP_ENTRY_INVALID") and has_code(s, "CLAIM_EVIDENCE_MAP_INVALID")))

    established_without_refs = copy.deepcopy(GOOD)
    established_without_refs["systemic_root_cause"]["evidence_refs"] = []
    r = validator.validate(established_without_refs)
    cases.append(("established_root_cause_requires_exact_evidence", has_code(r, "SUPPORTED_CLAIM_EVIDENCE_REQUIRED")))

    resolved_owner_without_ref = copy.deepcopy(GOOD)
    resolved_owner_without_ref["owner"]["evidence_ref"] = None
    r = validator.validate(resolved_owner_without_ref)
    cases.append(("resolved_owner_requires_authority_evidence", has_code(r, "RESOLVED_AUTHORITY_EVIDENCE_REQUIRED")))

    unknown_preferred = make_needs_more()
    unknown_preferred["preferred_alternative"] = "NOT_DECLARED"
    r = validator.validate(unknown_preferred)
    s = utility.evaluate(unknown_preferred, contract_gate())
    cases.append(("preferred_alternative_must_exist", has_code(r, "PREFERRED_ALTERNATIVE_NOT_DECLARED") and has_code(s, "PREFERRED_ALTERNATIVE_NOT_DECLARED")))

    design_pass = copy.deepcopy(GOOD)
    design_pass["falsification_results"][0]["evidence_class"] = "DESIGN_ONLY"
    design_pass["falsification_results"][0]["evidence_ref"] = "design://preferred-alternative"
    r = validator.validate(design_pass)
    s = utility.evaluate(design_pass, contract_gate())
    cases.append(("design_only_falsification_cannot_pass", has_code(r, "FALSIFICATION_PASS_NOT_OBSERVED") and has_code(s, "FALSIFICATION_PASS_NOT_OBSERVED")))

    unresolved_ready = copy.deepcopy(GOOD)
    unresolved_ready["execution_effect_reconciliation"][0]["observed_producer_refs"] = []
    unresolved_ready["execution_effect_reconciliation"][0]["reconciliation_status"] = "UNRESOLVED_PRODUCER"
    unresolved_ready["execution_effect_reconciliation"][0]["blocking"] = True
    unresolved_ready["blocking_codes"] = ["EXECUTION_EFFECT_PRODUCER_UNRESOLVED"]
    r = validator.validate(unresolved_ready)
    cases.append(("ready_spec_with_unresolved_producer_rejected", has_code(r, "SYSTEMIC_SPEC_WITH_UNRESOLVED_EFFECT_RECONCILIATION")))

    ready_with_uncertainty = copy.deepcopy(GOOD)
    ready_with_uncertainty["current_uncertainties"] = [{
        "uncertainty": "A material gap remains.",
        "blocking": True,
        "evidence_needed": ["missing evidence"],
    }]
    r = validator.validate(ready_with_uncertainty)
    s = utility.evaluate(ready_with_uncertainty, contract_gate())
    cases.append(("ready_spec_cannot_hide_current_uncertainty", has_code(r, "SYSTEMIC_SPEC_WITH_CURRENT_UNCERTAINTIES") and has_code(s, "SYSTEMIC_SPEC_WITH_CURRENT_UNCERTAINTIES")))

    non_mr02_holdout = make_needs_more()
    non_mr02_holdout["symptom"] = {
        "statement": "A scheduled notification was emitted but its executing worker cannot be identified.",
        "status": "OBSERVED",
        "evidence_refs": ["runtime://notification-ledger/effect-42"],
        "missing_evidence": [],
    }
    non_mr02_holdout["execution_effect_reconciliation"] = [{
        "effect": "notification dispatch",
        "observed_ref": "runtime://notification-ledger/effect-42",
        "declared_producer": "notification scheduler",
        "declared_producer_ref": "contract://notification/scheduler",
        "observed_producer_refs": [],
        "reconciliation_status": "UNRESOLVED_PRODUCER",
        "blocking": True,
    }]
    r = validator.validate(non_mr02_holdout)
    s = utility.evaluate(non_mr02_holdout, contract_gate())
    cases.append(("non_mr02_holdout_remains_honest_without_final_decision", r["valid"] and s["status"] == "PASS"))

    legacy_mr02_semantics = make_needs_more()
    legacy_mr02_semantics["systemic_root_cause"] = copy.deepcopy(GOOD["systemic_root_cause"])
    legacy_mr02_semantics["repair_level"] = "ARCHITECTURAL"
    legacy_mr02_semantics["selected_alternative"] = "B"
    legacy_mr02_semantics["rejected_alternatives"] = copy.deepcopy(GOOD["rejected_alternatives"])
    r = validator.validate(legacy_mr02_semantics)
    cases.append((
        "mr02_postfix_definitive_semantics_now_rejected",
        has_code(r, "PREMATURE_SYSTEMIC_ROOT_CAUSE")
        and (has_code(r, "PREMATURE_REPAIR_LEVEL") or has_code(r, "REPAIR_LEVEL_PREMATURE"))
        and has_code(r, "FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS")
        and has_code(r, "PREMATURE_REJECTED_ALTERNATIVES"),
    ))

    malformed = [None, [], {}, {"status": "SYSTEMIC_REPAIR_SPEC"}]
    cases.append(("malformed_fail_closed_no_crash", all(validator.validate(item)["valid"] is False for item in malformed)))

    ok = all(value for _, value in cases)
    print(json.dumps({
        "suite": "SYSTEMIC_ROOT_CAUSE_REPAIR_STATUS_CONDITIONAL_SEMANTICS_20260919",
        "evidence_class": "STRUCTURAL_AND_SEMANTIC_REGRESSION_NOT_LIVE_PROFILE_EXECUTION",
        "passed": sum(1 for _, value in cases if value),
        "total": len(cases),
        "cases": [{"case": name, "ok": value} for name, value in cases],
    }, ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(run())
