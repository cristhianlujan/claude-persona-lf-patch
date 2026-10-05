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
def validate_manifest(o):
    if o.get("schema_version")!="PROGRAMMING_AGENT_WAVE1_BOUNDARY_MANIFEST_V1": raise ContractError("MANIFEST_VERSION")
    if o.get("state")!="SOURCE_ONLY_CANDIDATE": raise ContractError("MANIFEST_STATE")
    if not SHA40.fullmatch(o.get("base_main_sha","")): raise ContractError("MANIFEST_BASE_SHA")
    if set(o.get("scope",[]))!={"A1","PG-01","TST-01"}: raise ContractError("MANIFEST_SCOPE")
def positive_request():
    return {"schema_version":"REQUEST_CONTEXT_V1","request_identity":{"request_ref":"chat://request/1","request_kind":"USER_REQUEST"},"objective":{"problem_statement":"The requested change needs analysis.","desired_outcome":"Produce a source-bound implementation analysis."},"target_hints":["repo://example"],"source_refs":["source://request/1"],"provided_facts":[{"fact_code":"F1","value":"known","source_ref":"source://request/1"}],"constraints":["NO_PRODUCTION_ACTIVATION"],"ambiguities":[{"code":"A1","statement":"Exact implementation target is not yet authoritative.","materiality":"UNKNOWN","resolution_state":"OPEN"}],"no_solution_inferred":True}
def self_test():
    schema=load("analysis_request_context_v1.schema.json"); p=load("programming_entry_contract_v1.json"); t=load("testing_admission_contract_v1.json"); m=load("manifest_v1.json")
    assert schema["properties"]["no_solution_inferred"]["const"] is True
    assert {"story_code","agent_task_id","functional_version_id","proposed_solution"}.isdisjoint(schema["properties"])
    validate_programming_entry(p); validate_testing_admission(t); validate_manifest(m); validate_request_context(positive_request())
    x=positive_request(); x["story_code"]="LEGACY-STORY"
    try: validate_request_context(x)
    except ContractError as e: assert str(e)=="REQUEST_CONTEXT_KEYS_MISMATCH"
    else: raise AssertionError("Story-coupled Analysis accepted")
    x=positive_request(); x["no_solution_inferred"]=False
    try: validate_request_context(x)
    except ContractError as e: assert str(e)=="REQUEST_CONTEXT_SOLUTION_INFERENCE"
    else: raise AssertionError("Solution inference accepted")
    x=json.loads(json.dumps(p)); x["admission"]["story_identity_required"]=True
    try: validate_programming_entry(x)
    except ContractError as e: assert str(e)=="PROGRAMMING_ADMISSION_story_identity_required"
    else: raise AssertionError("Story requirement accepted")
    x=json.loads(json.dumps(t)); x["modes"]["DESIGN_ONLY"]["requires"].append("frozen_candidate_ref")
    try: validate_testing_admission(x)
    except ContractError as e: assert str(e)=="DESIGN_MODE_CANDIDATE_REQUIRED"
    else: raise AssertionError("Candidate-coupled DESIGN_ONLY accepted")
    x=json.loads(json.dumps(t)); x["modes"]["EXECUTION"]["agent_task_required"]=True
    try: validate_testing_admission(x)
    except ContractError as e: assert str(e)=="TESTING_STAGE_COUPLING"
    else: raise AssertionError("Agent-Task-coupled Testing accepted")
    print("PASS_WAVE1_BOUNDARY_CONTRACTS checks=11 negatives=5")
if __name__=="__main__":
    if "--self-test" not in sys.argv: raise SystemExit("usage: validate_wave1_boundary_contracts_v1.py --self-test")
    self_test()
