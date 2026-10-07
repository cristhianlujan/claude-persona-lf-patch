#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
class CaseBatchError(ValueError): pass

def load():
    return json.loads((ROOT/"analysis_evaluation_cases_batch01_v1.json").read_text(encoding="utf-8"))

def validate(o):
    if o.get("schema_version")!="ANALYSIS_EVALUATION_CASE_BATCH_V1": raise CaseBatchError("BATCH_VERSION")
    if o.get("batch_id")!="A10-HIST-BATCH-01" or o.get("state")!="REGISTERED_SOURCE_BOUND_NOT_SCORED": raise CaseBatchError("BATCH_IDENTITY")
    if o.get("campaign_contract")!="ANALYSIS_EVALUATION_CAMPAIGN_CONTRACT_V1": raise CaseBatchError("BATCH_CAMPAIGN")
    if o.get("holdout_role")!="A10_HISTORICAL_ONLY" or o.get("excluded_from_A14_fresh_holdout") is not True: raise CaseBatchError("BATCH_HOLDOUT_SEPARATION")
    cases=o.get("cases",[])
    if len(cases)!=5 or len({c.get("case_id") for c in cases})!=5: raise CaseBatchError("BATCH_CASE_COUNT")
    required_families={"FEATURE","MIGRATION","RUNTIME","CONCURRENCY_IDEMPOTENCY","MODEL_OR_INTELLIGENCE"}
    if {c.get("change_family") for c in cases}!=required_families: raise CaseBatchError("BATCH_FAMILIES")
    for c in cases:
        if not c.get("source_refs") or not all(isinstance(x,str) and x for x in c["source_refs"]): raise CaseBatchError("CASE_SOURCE_REF")
        if not c.get("material_signals_expected") or not c.get("critical_omission_if_missing"): raise CaseBatchError("CASE_EXPECTATIONS")
        if c.get("depth_oracle")!="PENDING_INDEPENDENT_LABEL": raise CaseBatchError("CASE_DEPTH_NOT_SEALED")
    g=o.get("batch_guards",{})
    for k in ("every_case_has_canonical_source_ref","case_specific_solution_hardcoding_forbidden","depth_scoring_forbidden_until_independent_label","A14_holdout_contamination_forbidden"):
        if g.get(k) is not True: raise CaseBatchError("BATCH_GUARD_"+k)
    if g.get("runtime_activation") is not False or g.get("production_activation") is not False: raise CaseBatchError("BATCH_ACTIVATION")

def expect_error(o,code):
    try: validate(o)
    except CaseBatchError as e: assert str(e)==code,(str(e),code)
    else: raise AssertionError("Expected "+code)

def self_test():
    import copy
    o=load(); validate(o)
    x=copy.deepcopy(o); x["excluded_from_A14_fresh_holdout"]=False; expect_error(x,"BATCH_HOLDOUT_SEPARATION")
    x=copy.deepcopy(o); x["cases"]=x["cases"][:4]; expect_error(x,"BATCH_CASE_COUNT")
    x=copy.deepcopy(o); x["cases"][0]["source_refs"]=[]; expect_error(x,"CASE_SOURCE_REF")
    x=copy.deepcopy(o); x["cases"][0]["critical_omission_if_missing"]=[]; expect_error(x,"CASE_EXPECTATIONS")
    x=copy.deepcopy(o); x["cases"][0]["depth_oracle"]="L2"; expect_error(x,"CASE_DEPTH_NOT_SEALED")
    x=copy.deepcopy(o); x["batch_guards"]["depth_scoring_forbidden_until_independent_label"]=False; expect_error(x,"BATCH_GUARD_depth_scoring_forbidden_until_independent_label")
    x=copy.deepcopy(o); x["batch_guards"]["runtime_activation"]=True; expect_error(x,"BATCH_ACTIVATION")
    print("PASS_ANALYSIS_EVALUATION_CASE_BATCH01_V1 negatives=7")

if __name__=="__main__":
    if "--self-test" not in sys.argv: raise SystemExit("usage: validate_analysis_evaluation_case_batch01_v1.py --self-test")
    self_test()
