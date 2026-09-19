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


def run():
    cases = []

    result = validator.validate(copy.deepcopy(GOOD))
    sem = utility.evaluate(copy.deepcopy(GOOD), contract_gate())
    cases.append(("positive_structural_candidate", result["valid"] and sem["status"] == "PASS"))

    legacy_run1 = copy.deepcopy(GOOD)
    legacy_run1.pop("live_authority_packet")
    legacy_run1.pop("execution_effect_reconciliation")
    r = validator.validate(legacy_run1)
    cases.append(("mr02_run1_shape_without_live_reconciliation_blocks", has_code(r, "LIVE_AUTHORITY_PACKET_MISSING") and has_code(r, "EXECUTION_EFFECT_RECONCILIATION_MISSING")))

    legacy_run2 = copy.deepcopy(GOOD)
    legacy_run2["status"] = "NEEDS_MORE_EVIDENCE"
    legacy_run2["blocking_codes"] = ["FALSIFICATION_BYPASS_NOT_COVERED"]
    legacy_run2.pop("live_authority_packet")
    legacy_run2.pop("execution_effect_reconciliation")
    r = validator.validate(legacy_run2)
    cases.append(("mr02_run2_shape_without_live_packet_blocks", has_code(r, "LIVE_AUTHORITY_PACKET_MISSING") and has_code(r, "EXECUTION_EFFECT_RECONCILIATION_MISSING")))

    unresolved = copy.deepcopy(GOOD)
    unresolved["execution_effect_reconciliation"][0] = {
        "effect": "lease fence increment",
        "observed_ref": "supabase://public.lf_operation_execution/lease_fence_gt0",
        "declared_producer": "fn_lf_operation_acquire_lease_v1",
        "observed_producer_refs": [],
        "reconciliation_status": "UNRESOLVED_PRODUCER",
        "blocking": True,
    }
    unresolved["blocking_codes"] = ["EXECUTION_EFFECT_PRODUCER_UNRESOLVED"]
    r = validator.validate(unresolved)
    cases.append(("ready_spec_with_unresolved_producer_rejected", has_code(r, "SYSTEMIC_SPEC_WITH_UNRESOLVED_EFFECT_RECONCILIATION") and has_code(r, "SYSTEMIC_SPEC_WITH_BLOCKERS")))

    partial = copy.deepcopy(GOOD)
    partial["status"] = "NEEDS_MORE_EVIDENCE"
    partial["live_authority_packet"]["status"] = "PARTIAL"
    partial["live_authority_packet"]["inspected_surfaces"] = ["SQL_FUNCTIONS"]
    partial["live_authority_packet"]["unavailable_sources"] = ["EXTERNAL_WORKERS"]
    partial["execution_effect_reconciliation"][0]["observed_producer_refs"] = []
    partial["execution_effect_reconciliation"][0]["reconciliation_status"] = "UNRESOLVED_PRODUCER"
    partial["execution_effect_reconciliation"][0]["blocking"] = True
    partial["blocking_codes"] = ["LIVE_AUTHORITY_EVIDENCE_INCOMPLETE", "EXECUTION_EFFECT_PRODUCER_UNRESOLVED"]
    r = validator.validate(partial)
    cases.append(("honest_partial_live_authority_can_return_needs_more_evidence", r["valid"]))

    partial_without_code = copy.deepcopy(partial)
    partial_without_code["blocking_codes"] = ["EXECUTION_EFFECT_PRODUCER_UNRESOLVED"]
    r = validator.validate(partial_without_code)
    cases.append(("partial_live_authority_requires_explicit_blocker", has_code(r, "LIVE_AUTHORITY_PARTIAL_WITHOUT_BLOCKER")))

    contradiction = copy.deepcopy(GOOD)
    contradiction["authority_contradictions"] = [{
        "classification": "SOURCE_LIVE_DIVERGENCE",
        "declared": "declared owner",
        "observed": "different live executor",
        "blocking": True,
        "evidence_ref": "run://external/1",
    }]
    contradiction["execution_effect_reconciliation"][0]["reconciliation_status"] = "SOURCE_LIVE_DIVERGENCE"
    contradiction["execution_effect_reconciliation"][0]["blocking"] = True
    contradiction["blocking_codes"] = ["SOURCE_LIVE_DIVERGENCE"]
    r = validator.validate(contradiction)
    cases.append(("declared_live_contradiction_blocks_spec", has_code(r, "UNRESOLVED_AUTHORITY_CONTRADICTION") and has_code(r, "SYSTEMIC_SPEC_WITH_UNRESOLVED_EFFECT_RECONCILIATION")))

    design_pass = copy.deepcopy(GOOD)
    design_pass["falsification_results"][0]["evidence_class"] = "DESIGN_ONLY"
    design_pass["falsification_results"][0]["evidence_ref"] = "design://preferred-alternative"
    r = validator.validate(design_pass)
    cases.append(("design_only_falsification_cannot_pass", has_code(r, "FALSIFICATION_PASS_NOT_OBSERVED")))

    nonpass_ready = copy.deepcopy(GOOD)
    nonpass_ready["falsification_results"][0]["result"] = "NOT_COVERED"
    nonpass_ready["falsification_results"][0]["evidence_class"] = "MISSING"
    r = validator.validate(nonpass_ready)
    cases.append(("ready_spec_requires_all_falsification_families_observed_pass", has_code(r, "SYSTEMIC_SPEC_FALSIFICATION_NOT_PASS")))

    complete_with_unavailable = copy.deepcopy(GOOD)
    complete_with_unavailable["live_authority_packet"]["unavailable_sources"] = ["EXTERNAL_WORKERS"]
    r = validator.validate(complete_with_unavailable)
    cases.append(("complete_live_authority_cannot_hide_unavailable_surface", has_code(r, "LIVE_AUTHORITY_COMPLETE_WITH_UNAVAILABLE_SOURCE")))

    match_without_producer = copy.deepcopy(GOOD)
    match_without_producer["execution_effect_reconciliation"][0]["observed_producer_refs"] = []
    r = validator.validate(match_without_producer)
    cases.append(("match_requires_observed_producer_reference", has_code(r, "MATCH_REQUIRES_OBSERVED_PRODUCER")))

    non_mr02_holdout = copy.deepcopy(GOOD)
    non_mr02_holdout["status"] = "NEEDS_MORE_EVIDENCE"
    non_mr02_holdout["symptom"] = "A scheduled notification effect exists but its executing worker cannot be reconciled."
    non_mr02_holdout["execution_effect_reconciliation"] = [{
        "effect": "notification dispatch",
        "observed_ref": "runtime://notification-ledger/effect-42",
        "declared_producer": "notification scheduler",
        "observed_producer_refs": [],
        "reconciliation_status": "UNRESOLVED_PRODUCER",
        "blocking": True,
    }]
    non_mr02_holdout["blocking_codes"] = ["EXECUTION_EFFECT_PRODUCER_UNRESOLVED"]
    r = validator.validate(non_mr02_holdout)
    cases.append(("non_mr02_holdout_unresolved_producer_is_generic_and_blocking", r["valid"]))

    existence = copy.deepcopy(GOOD)
    existence["should_exist_assessment"]["verdict"] = "INSUFFICIENT_EVIDENCE"
    r = validator.validate(existence)
    cases.append(("should_exist_insufficient_blocks_spec", has_code(r, "SHOULD_EXIST_ASSESSMENT_UNRESOLVED")))

    unknown_selected = copy.deepcopy(GOOD)
    unknown_selected["selected_alternative"] = "NOT_DECLARED"
    r = utility.evaluate(unknown_selected, contract_gate())
    cases.append(("selected_alternative_must_exist", has_code(r, "SELECTED_ALTERNATIVE_NOT_DECLARED")))

    malformed = [None, [], {}, {"status": "SYSTEMIC_REPAIR_SPEC"}]
    cases.append(("malformed_fail_closed_no_crash", all(validator.validate(item)["valid"] is False for item in malformed)))

    ok = all(value for _, value in cases)
    print(json.dumps({
        "suite": "SYSTEMIC_ROOT_CAUSE_REPAIR_LIVE_AUTHORITY_RECONCILIATION_20260919",
        "evidence_class": "STRUCTURAL_VALIDATOR_REGRESSION_NOT_LIVE_PROFILE_EXECUTION",
        "passed": sum(1 for _, value in cases if value),
        "total": len(cases),
        "cases": [{"case": name, "ok": value} for name, value in cases],
    }, ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(run())
