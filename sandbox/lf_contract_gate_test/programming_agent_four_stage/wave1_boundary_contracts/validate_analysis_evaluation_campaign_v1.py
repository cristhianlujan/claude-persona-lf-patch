#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
class ContractError(ValueError): pass

def load():
    return json.loads((ROOT/"analysis_evaluation_campaign_contract_v1.json").read_text(encoding="utf-8"))

def validate(o):
    if o.get("schema_version")!="ANALYSIS_EVALUATION_CAMPAIGN_CONTRACT_V1": raise ContractError("EVAL_VERSION")
    if o.get("units")!=["A10","A11","A12","A13","A14"] or o.get("sequence")!=["A10","A11","A12","A13","A14"]: raise ContractError("EVAL_SEQUENCE")
    cp=o.get("case_policy",{})
    if cp.get("historical_case_target")!="APPROX_30_HETEROGENEOUS": raise ContractError("EVAL_CASE_TARGET")
    families={"BUG","FEATURE","MIGRATION","RUNTIME","CONCURRENCY_IDEMPOTENCY","GOVERNANCE","MODEL_OR_INTELLIGENCE"}
    if set(cp.get("required_change_families",[]))!=families: raise ContractError("EVAL_CASE_FAMILIES")
    if not all(cp.get(k) is True for k in ("same_case_set_for_baseline_and_candidate_in_A12","fresh_holdout_for_A14","A14_cases_or_variants_must_not_be_used_for_A13_tuning","case_specific_hardcoding_forbidden")): raise ContractError("EVAL_CASE_GOVERNANCE")
    dims={"CRITICAL_IMPACT_RECALL","MATERIAL_FRONT_COVERAGE","MISSING_FRONT_FALSE_READY","TARGET_AND_DEPTH_CLASSIFICATION","IMPLEMENTABILITY_WITHOUT_REINTERPRETATION","A9_PG01_HANDOFF_PARITY","SCOPE_FRONT_CONSISTENCY","CURRENTNESS_BEHAVIOR","DEPENDENCY_AND_BLAST_RADIUS","FALSE_READY_FALSE_PASS","SECOND_ORDER_HIDDEN_FAILURE","SELECTOR_OR_MODULE_APPROPRIATENESS","OVERANALYSIS","SOURCE_READ_EFFICIENCY","LATENCY","TOKEN_USAGE_WHEN_LIVE_MEASURED"}
    if set(o.get("evaluation_dimensions",[]))!=dims: raise ContractError("EVAL_DIMENSIONS")
    t=o.get("telemetry",{})
    case_fields={"case_id","candidate_ref","source_snapshot_ref","verdict","critical_impacts_expected[]","critical_impacts_observed[]","material_fronts_expected[]","material_fronts_observed[]","false_ready_count","reinterpretation_required","handoff_parity_verdict","scope_front_consistency_verdict","currentness_verdict","source_read_count","duplicate_read_count","retry_count","elapsed_ms"}
    if set(t.get("required_per_case",[]))!=case_fields: raise ContractError("EVAL_TELEMETRY_FIELDS")
    if set(t.get("live_provider_fields_when_model_executed",[]))!={"provider_response_id","exact_model_or_profile","input_tokens","output_tokens"}: raise ContractError("EVAL_LIVE_FIELDS")
    if t.get("token_estimation_forbidden") is not True or t.get("missing_live_usage_must_remain_null") is not True: raise ContractError("EVAL_LIVE_TELEMETRY")
    a11=o.get("A11_adversarial",{})
    adv={"STALE_AUTHORITY","HIDDEN_INDIRECT_IMPACT","INCOMPLETE_CONTEXT","CONTRADICTORY_CONTEXT","OMITTED_MATERIAL_FRONT","READY_SCOPE_WITH_BLOCKING_FRONT","HANDOFF_SCHEMA_DRIFT","LOSSY_WORKER_PROJECTION","CURRENTNESS_FALSE_INVALIDATION","CURRENTNESS_FALSE_REUSE","SECOND_ORDER_CONSUMER_FAILURE"}
    if set(a11.get("must_include",[]))!=adv or a11.get("critical_false_ready_tolerance")!=0: raise ContractError("EVAL_ADVERSARIAL")
    a12=o.get("A12_benchmark",{})
    if a12.get("baseline_and_candidate_same_cases") is not True or a12.get("no_quality_promotion_from_missing_live_telemetry") is not True: raise ContractError("EVAL_BENCHMARK")
    a13=o.get("A13_remediation",{})
    if not all(a13.get(k) is True for k in ("finding_must_be_reproducible","generalizable_rule_required","case_specific_patch_forbidden","must_rerun_affected_regression_set")): raise ContractError("EVAL_REMEDIATION")
    a14=o.get("A14_fresh_validation_gates",{})
    if a14.get("critical_impacts_omitted")!=0 or a14.get("critical_false_ready")!=0: raise ContractError("EVAL_CRITICAL_GATES")
    if a14.get("material_front_accounting_rate")!=1.0 or a14.get("handoff_material_parity_rate")!=1.0 or a14.get("lossy_material_projection_count")!=0: raise ContractError("EVAL_MATERIAL_GATES")
    if a14.get("classification_accuracy_min")!=0.95 or a14.get("usable_without_material_reinterpretation_min")!=0.95 or a14.get("fresh_or_unseen_variants_required") is not True: raise ContractError("EVAL_QUALITY_GATES")
    fb=o.get("freeze_boundary",{})
    if fb.get("A15_owns_freeze") is not True or fb.get("this_contract_does_not_freeze") is not True or fb.get("runtime_activation") is not False or fb.get("production_activation") is not False: raise ContractError("EVAL_FREEZE_BOUNDARY")
    if o.get("no_parallel_evaluation_engine") is not True: raise ContractError("EVAL_PARALLEL_ENGINE")

def expect_error(o,code):
    try: validate(o)
    except ContractError as e: assert str(e)==code,(str(e),code)
    else: raise AssertionError("Expected "+code)

def self_test():
    import copy
    o=load()
    validate(o)
    x=copy.deepcopy(o); x["sequence"]=["A10","A12","A11","A13","A14"]; expect_error(x,"EVAL_SEQUENCE")
    x=copy.deepcopy(o); x["evaluation_dimensions"].remove("MATERIAL_FRONT_COVERAGE"); expect_error(x,"EVAL_DIMENSIONS")
    x=copy.deepcopy(o); x["telemetry"]["token_estimation_forbidden"]=False; expect_error(x,"EVAL_LIVE_TELEMETRY")
    x=copy.deepcopy(o); x["A11_adversarial"]["must_include"].remove("OMITTED_MATERIAL_FRONT"); expect_error(x,"EVAL_ADVERSARIAL")
    x=copy.deepcopy(o); x["A11_adversarial"]["critical_false_ready_tolerance"]=1; expect_error(x,"EVAL_ADVERSARIAL")
    x=copy.deepcopy(o); x["A12_benchmark"]["baseline_and_candidate_same_cases"]=False; expect_error(x,"EVAL_BENCHMARK")
    x=copy.deepcopy(o); x["A13_remediation"]["case_specific_patch_forbidden"]=False; expect_error(x,"EVAL_REMEDIATION")
    x=copy.deepcopy(o); x["A14_fresh_validation_gates"]["handoff_material_parity_rate"]=0.95; expect_error(x,"EVAL_MATERIAL_GATES")
    x=copy.deepcopy(o); x["freeze_boundary"]["this_contract_does_not_freeze"]=False; expect_error(x,"EVAL_FREEZE_BOUNDARY")
    print("PASS_ANALYSIS_EVALUATION_CAMPAIGN_V1 negatives=9")

if __name__=="__main__":
    if "--self-test" not in sys.argv: raise SystemExit("usage: validate_analysis_evaluation_campaign_v1.py --self-test")
    self_test()
