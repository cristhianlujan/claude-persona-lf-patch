#!/usr/bin/env python3
from __future__ import annotations
import json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SHA40=re.compile(r"^[0-9a-f]{40}$")
class ContractError(ValueError): pass
def load(n): return json.loads((ROOT/n).read_text(encoding="utf-8"))

def validate_request_context(o):
    req={"schema_version","request_identity","objective","target_hints","source_refs","provided_facts","constraints","ambiguities","no_solution_inferred"}
    if set(o)!=req: raise ContractError("REQUEST_CONTEXT_KEYS_MISMATCH")
    if o["schema_version"]!="REQUEST_CONTEXT_V1": raise ContractError("REQUEST_CONTEXT_VERSION")
    if o["no_solution_inferred"] is not True: raise ContractError("REQUEST_CONTEXT_SOLUTION_INFERENCE")
    if set(o["request_identity"])!={"request_ref","request_kind"}: raise ContractError("REQUEST_IDENTITY_KEYS")
    if len(o["request_identity"]["request_ref"].strip())<3: raise ContractError("REQUEST_REF")
    if o["request_identity"]["request_kind"] not in {"USER_REQUEST","SYSTEM_REQUEST","ISSUE","HANDOFF","FILE","EVENT","OTHER"}: raise ContractError("REQUEST_KIND")
    if set(o["objective"])!={"problem_statement","desired_outcome"}: raise ContractError("OBJECTIVE_KEYS")
    if not all(isinstance(o["objective"][k],str) and o["objective"][k].strip() for k in o["objective"]): raise ContractError("OBJECTIVE_EMPTY")
    if not isinstance(o["ambiguities"],list): raise ContractError("AMBIGUITIES_TYPE")
    for a in o["ambiguities"]:
        if set(a)!={"code","statement","materiality","resolution_state"}: raise ContractError("AMBIGUITY_KEYS")
        if a["materiality"] not in {"MATERIAL","NON_MATERIAL","UNKNOWN"}: raise ContractError("AMBIGUITY_MATERIALITY")
        if a["resolution_state"] not in {"OPEN","RESOLVED_FROM_SOURCE"}: raise ContractError("AMBIGUITY_STATE")

def validate_programming_entry(o):
    if o.get("schema_version")!="PROGRAMMING_ENTRY_CONTRACT_V1": raise ContractError("PROGRAMMING_ENTRY_VERSION")
    if o.get("canonical_upstream")!="ANALYSIS_IMPLEMENTATION_PACKAGE_V1": raise ContractError("PROGRAMMING_UPSTREAM")
    expected={"required_analysis_verdict":"READY","analysis_package_digest_required":True,"source_currentness_required":True,"exact_target_identity_required":True,"lossless_projection_required":True,"story_identity_required":False,"functional_version_required":False,"agent_task_required_at_upstream_admission":False}
    for k,v in expected.items():
        if o.get("admission",{}).get(k)!=v: raise ContractError("PROGRAMMING_ADMISSION_"+k)
    c=o.get("compatibility",{})
    if c.get("action")!="EXTEND_ENTRY_BOUNDARY_DO_NOT_DUPLICATE_RUNTIME" or c.get("new_runtime_created") is not False: raise ContractError("PROGRAMMING_PARALLEL_RUNTIME")
    if c.get("story_direct_consumption_after_cutover") is not False: raise ContractError("PROGRAMMING_STORY_CUTOVER")

def validate_testing_admission(o):
    if o.get("schema_version")!="TESTING_ADMISSION_CONTRACT_V1": raise ContractError("TESTING_ADMISSION_VERSION")
    m=o.get("modes",{})
    if set(m)!={"DESIGN_ONLY","EXECUTION"}: raise ContractError("TESTING_MODES")
    for mode in m.values():
        if mode.get("agent_task_required") is not False or mode.get("story_required") is not False: raise ContractError("TESTING_STAGE_COUPLING")
    if "frozen_candidate_ref" in m["DESIGN_ONLY"].get("requires",[]): raise ContractError("DESIGN_MODE_CANDIDATE_REQUIRED")
    if set(m["DESIGN_ONLY"].get("forbids",[]))!={"frozen_candidate_ref","frozen_candidate_sha256"}: raise ContractError("DESIGN_MODE_FORBIDS")
    for k in ("frozen_candidate_ref","frozen_candidate_sha256"):
        if k not in m["EXECUTION"].get("requires",[]): raise ContractError("EXECUTION_MODE_CANDIDATE_MISSING")
    if o.get("no_parallel_engine") is not True: raise ContractError("TESTING_PARALLEL_ENGINE")

def validate_analysis_change_classification(o):
    if o.get("schema_version")!="ANALYSIS_CHANGE_CLASSIFICATION_CONTRACT_V1" or o.get("unit")!="A2": raise ContractError("A2_IDENTITY")
    c=o.get("classification",{})
    if c.get("depth_levels")!=["L1","L2","L3"]: raise ContractError("A2_DEPTH_LEVELS")
    if c.get("change_type_required") is not True or c.get("change_type_policy")!="EVIDENCE_DERIVED_OPEN_CATALOG": raise ContractError("A2_CHANGE_TYPE")
    if c.get("depth_reason_required") is not True or c.get("evidence_refs_required") is not True: raise ContractError("A2_REPRODUCIBILITY")
    s=o.get("specialist_resolution",{})
    expected={"cardinality":"0..N","selector_capability":"CAPABILITY_SELECTOR","selector_version_policy":"CURRENT","currentness_required":True,"release_state_required":"RELEASED","hardcoded_specialist_identity_forbidden":True,"hardcoded_story_creator_forbidden":True,"selection_is_execution_permission":False}
    for k,v in expected.items():
        if s.get(k)!=v: raise ContractError("A2_SPECIALIST_"+k)
    if s.get("catalog_source")!="CURRENT_RELEASED_CAPABILITY_MANIFESTS_WITH_SPECIALIST_DECLARATION": raise ContractError("A2_SPECIALIST_CATALOG")
    if o.get("no_parallel_engine") is not True: raise ContractError("A2_PARALLEL_ENGINE")

def validate_analysis_targeted_evidence(o):
    if o.get("schema_version")!="ANALYSIS_TARGETED_EVIDENCE_CONTRACT_V1" or o.get("unit")!="A3": raise ContractError("A3_IDENTITY")
    a=o.get("acquisition",{})
    expected={"capability":"TARGETED_EVIDENCE_ACQUISITION","source_resolution":"SOURCE_RESOLUTION_POLICY","data_access":"TYPED_DATA_ACCESS","query_only_missing_or_material_evidence":True,"reuse_current_evidence_before_fetch":True,"duplicate_read_forbidden":True,"full_repository_search_without_trigger_forbidden":True,"stop_when":"MINIMUM_SUFFICIENT_CONTEXT_REACHED"}
    for k,v in expected.items():
        if a.get(k)!=v: raise ContractError("A3_ACQUISITION_"+k)
    allowed={"REQUIRED_EVIDENCE_MISSING","MATERIAL_CONTRADICTION","CURRENTNESS_UNPROVEN","SOURCE_DRIFT"}
    if set(a.get("continue_only_if",[]))!=allowed: raise ContractError("A3_CONTINUE_GATES")
    if o.get("no_over_search") is not True or o.get("no_parallel_engine") is not True: raise ContractError("A3_SEARCH_GOVERNANCE")
    if set(o.get("sufficiency_verdicts",[]))!={"SUFFICIENT","NEED_MORE_EVIDENCE","REQUIRES_DECISION","BLOCKED"}: raise ContractError("A3_VERDICTS")

def validate_shared_impact(o):
    if o.get("schema_version")!="SHARED_CHANGE_IMPACT_ANALYSIS_CONTRACT_V1": raise ContractError("IMPACT_VERSION")
    if set(o.get("units",[]))!={"A4","TST-05"}: raise ContractError("IMPACT_UNITS")
    if o.get("provider")!="SHARED_CHANGE_IMPACT_ANALYSIS" or o.get("transformation_action")!="TRANSVERSALIZE_EXISTING_CORE": raise ContractError("IMPACT_PROVIDER")
    required_sources={"LF_GLOBAL_TECHNICAL_INVENTORY_V1","inventory.fn_impact_analysis_v1","inventory.fn_dependencies_v1","IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.11"}
    if set(o.get("sources",[]))!=required_sources: raise ContractError("IMPACT_SOURCES")
    required_outputs={"direct_impacts[]","indirect_impacts[]","consumers[]","dependency_paths[]","evidence_refs[]","unresolved_material_impacts[]"}
    if set(o.get("core_output_requirements",[]))!=required_outputs: raise ContractError("IMPACT_OUTPUTS")
    tp=o.get("testing_projection",{})
    if tp.get("consumes_same_core") is not True or tp.get("parallel_impact_engine_forbidden") is not True: raise ContractError("IMPACT_TESTING_REUSE")
    if o.get("consumer_migration_policy")!="KEEP_EXISTING_CONSUMERS_AS_ADAPTERS_UNTIL_QUALIFIED_CUTOVER": raise ContractError("IMPACT_CUTOVER")
    if o.get("runtime_activation") is not False or o.get("production_activation") is not False or o.get("no_parallel_engine") is not True: raise ContractError("IMPACT_ACTIVATION")

def validate_testing_pipeline(o):
    if o.get("schema_version")!="TESTING_WAVE1_DESIGN_PIPELINE_CONTRACT_V1": raise ContractError("TEST_PIPELINE_VERSION")
    if set(o.get("units",[]))!={"TST-02","TST-03","TST-04"} or o.get("sequence")!=["TST-02","TST-03","TST-04"]: raise ContractError("TEST_PIPELINE_SEQUENCE")
    if o.get("story_required") is not False or o.get("agent_task_required") is not False: raise ContractError("TEST_PIPELINE_STAGE_COUPLING")
    steps=o.get("steps",{})
    if set(steps)!={"TST-02","TST-03","TST-04"}: raise ContractError("TEST_PIPELINE_STEPS")
    if steps["TST-02"].get("output_contract")!="TEST_CHANGE_SIGNALS_V1": raise ContractError("TST02_OUTPUT")
    if steps["TST-03"].get("input_contracts")!=["TEST_CHANGE_SIGNALS_V1"] or steps["TST-03"].get("output_contract")!="TEST_RISK_ASSESSMENT_V1": raise ContractError("TST03_CHAIN")
    if steps["TST-04"].get("input_contracts")!=["TEST_RISK_ASSESSMENT_V1"] or steps["TST-04"].get("output_contract")!="TEST_QUALITY_OBJECTIVES_V1": raise ContractError("TST04_CHAIN")
    for u in ("TST-02","TST-03","TST-04"):
        if "public.lf_strategy_test_characteristic_catalog" not in steps[u].get("mapped_assets",[]): raise ContractError(u+"_QUALITY_CATALOG")
    if o.get("no_parallel_engine") is not True: raise ContractError("TEST_PIPELINE_PARALLEL_ENGINE")

def validate_manifest(o):
    if o.get("schema_version")!="PROGRAMMING_AGENT_WAVE1_BOUNDARY_MANIFEST_V1": raise ContractError("MANIFEST_VERSION")
    if o.get("state")!="SOURCE_ONLY_CANDIDATE": raise ContractError("MANIFEST_STATE")
    if not SHA40.fullmatch(o.get("base_main_sha","")): raise ContractError("MANIFEST_BASE_SHA")
    scope={"A1","A2","A3","A4","PG-01","TST-01","TST-02","TST-03","TST-04","TST-05"}
    if set(o.get("scope",[]))!=scope: raise ContractError("MANIFEST_SCOPE")
    contracts=o.get("contracts",{})
    if set(contracts)!=scope: raise ContractError("MANIFEST_CONTRACT_MAP")
    if contracts.get("A4")!=contracts.get("TST-05"): raise ContractError("MANIFEST_SHARED_IMPACT_SPLIT")
    if len({contracts.get("TST-02"),contracts.get("TST-03"),contracts.get("TST-04")})!=1: raise ContractError("MANIFEST_TEST_PIPELINE_SPLIT")

def positive_request():
    return {"schema_version":"REQUEST_CONTEXT_V1","request_identity":{"request_ref":"chat://request/1","request_kind":"USER_REQUEST"},"objective":{"problem_statement":"The requested change needs analysis.","desired_outcome":"Produce a source-bound implementation analysis."},"target_hints":["repo://example"],"source_refs":["source://request/1"],"provided_facts":[{"fact_code":"F1","value":"known","source_ref":"source://request/1"}],"constraints":["NO_PRODUCTION_ACTIVATION"],"ambiguities":[{"code":"A1","statement":"Exact implementation target is not yet authoritative.","materiality":"UNKNOWN","resolution_state":"OPEN"}],"no_solution_inferred":True}

def expect_error(fn,obj,code):
    try: fn(obj)
    except ContractError as e: assert str(e)==code,(str(e),code)
    else: raise AssertionError("Expected "+code)

def self_test():
    schema=load("analysis_request_context_v1.schema.json")
    p=load("programming_entry_contract_v1.json")
    ta=load("testing_admission_contract_v1.json")
    a2=load("analysis_change_classification_contract_v1.json")
    a3=load("analysis_targeted_evidence_contract_v1.json")
    impact=load("shared_change_impact_contract_v1.json")
    tp=load("testing_wave1_design_pipeline_contract_v1.json")
    m=load("manifest_v1.json")
    assert schema["properties"]["no_solution_inferred"]["const"] is True
    assert {"story_code","agent_task_id","functional_version_id","proposed_solution"}.isdisjoint(schema["properties"])
    validate_programming_entry(p); validate_testing_admission(ta)
    validate_analysis_change_classification(a2); validate_analysis_targeted_evidence(a3)
    validate_shared_impact(impact); validate_testing_pipeline(tp); validate_manifest(m)
    validate_request_context(positive_request())

    x=positive_request(); x["story_code"]="LEGACY-STORY"; expect_error(validate_request_context,x,"REQUEST_CONTEXT_KEYS_MISMATCH")
    x=positive_request(); x["no_solution_inferred"]=False; expect_error(validate_request_context,x,"REQUEST_CONTEXT_SOLUTION_INFERENCE")
    x=json.loads(json.dumps(p)); x["admission"]["story_identity_required"]=True; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_story_identity_required")
    x=json.loads(json.dumps(ta)); x["modes"]["DESIGN_ONLY"]["requires"].append("frozen_candidate_ref"); expect_error(validate_testing_admission,x,"DESIGN_MODE_CANDIDATE_REQUIRED")
    x=json.loads(json.dumps(ta)); x["modes"]["EXECUTION"]["agent_task_required"]=True; expect_error(validate_testing_admission,x,"TESTING_STAGE_COUPLING")
    x=json.loads(json.dumps(a2)); x["specialist_resolution"]["hardcoded_specialist_identity_forbidden"]=False; expect_error(validate_analysis_change_classification,x,"A2_SPECIALIST_hardcoded_specialist_identity_forbidden")
    x=json.loads(json.dumps(a2)); x["specialist_resolution"]["selection_is_execution_permission"]=True; expect_error(validate_analysis_change_classification,x,"A2_SPECIALIST_selection_is_execution_permission")
    x=json.loads(json.dumps(a3)); x["acquisition"]["full_repository_search_without_trigger_forbidden"]=False; expect_error(validate_analysis_targeted_evidence,x,"A3_ACQUISITION_full_repository_search_without_trigger_forbidden")
    x=json.loads(json.dumps(impact)); x["testing_projection"]["consumes_same_core"]=False; expect_error(validate_shared_impact,x,"IMPACT_TESTING_REUSE")
    x=json.loads(json.dumps(tp)); x["story_required"]=True; expect_error(validate_testing_pipeline,x,"TEST_PIPELINE_STAGE_COUPLING")
    x=json.loads(json.dumps(m)); x["contracts"]["TST-05"]="testing_private_impact_engine.json"; expect_error(validate_manifest,x,"MANIFEST_SHARED_IMPACT_SPLIT")
    print("PASS_WAVE1_BOUNDARY_CONTRACTS checks=28 negatives=11")

if __name__=="__main__":
    if "--self-test" not in sys.argv: raise SystemExit("usage: validate_wave1_boundary_contracts_v1.py --self-test")
    self_test()
