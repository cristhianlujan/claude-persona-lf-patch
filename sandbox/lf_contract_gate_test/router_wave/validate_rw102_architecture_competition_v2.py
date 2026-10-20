#!/usr/bin/env python3
"""RW1-02 architecture competition validator V2.

Repairs C3 findings by:
- deriving candidate capabilities and structural metrics from structured design contracts;
- treating free-text descriptions as display-only;
- enforcing exact schema / no authority-bearing unknown fields;
- removing any hardcoded expected winner or hard-pass set;
- accepting valid sensitivity variants even when the recomputed winner changes.

Scope remains architecture-design evidence only, not Router runtime or production.
"""
from __future__ import annotations
import copy, json, sys
from pathlib import Path

SCHEMA="RW102_ARCHITECTURE_COMPETITION_V2"
RESULT_SCHEMA="RW102_ARCHITECTURE_COMPETITION_RESULT_V2"
A="A_MIN_ROUTER_SEMANTIC_SPECIALIST"
B="B_MIN_CLASSIFIER_COMPOSITE_DERIVATION"
C="C_BOUNDED_SEMANTIC_ROUTER"
D="D_CURRENT_HYBRID_BASELINE"
EXPECTED_CANDIDATES={A,B,C,D}
ELIGIBLE=[A,B,C]
EXPECTED_NEEDS={f"N{i:02d}" for i in range(1,13)}
NOT_MEASURED="NOT_MEASURED_NO_EQUIVALENT_IMPLEMENTATIONS"
CAPABILITIES={
 "preserve_literal","discover_registered_responsibility","semantic_normalization",
 "preserve_negation","multi_goal_composition","context_resolution",
 "material_clarification_only","future_capability_gap","role_separation",
 "no_effect_authority","safe_readonly_continuity","deterministic_authority",
 "simulation_no_effect","typed_hint_non_authority",
 "train_technical_route_separation","stale_currentness_fail_closed",
}
CAPABILITY_BASIS={
 "preserve_literal":"transport.literal",
 "discover_registered_responsibility":"routing.discovery_owner",
 "semantic_normalization":"semantics.normalization_provider",
 "preserve_negation":"semantics.negation_handling",
 "multi_goal_composition":"composition.multi_goal",
 "context_resolution":"context.resolution",
 "material_clarification_only":"clarification.material_only",
 "future_capability_gap":"currentness.future_gap",
 "role_separation":"roles.separated",
 "no_effect_authority":"authority.effect_owner",
 "safe_readonly_continuity":"continuity.readonly",
 "deterministic_authority":"currentness.revision_pinned",
 "simulation_no_effect":"simulation.effect_mode",
 "typed_hint_non_authority":"authority.typed_hint",
 "train_technical_route_separation":"routing.train_lane",
 "stale_currentness_fail_closed":"currentness.stale_policy",
}
TOP_KEYS={
 "schema_version","plan_code","unit_code","checkpoint_code","scope","source_c1_blob",
 "requirements_expected","candidates","cases","selection_policy","hard_invariants",
 "description_authority","candidate_contract_mode","literal_request_authority",
}
CANDIDATE_KEYS={
 "eligible","description","description_authoritative","capability_evidence_mode",
 "capability_evidence","design_contract","capabilities","structural_metrics",
}
CASE_KEYS={"id","family","literal_request","required_capabilities","semantic_complex","extensibility_case","needs"}
DESIGN_KEYS={
 "architecture_kind","transport","routing","semantics","composition","context",
 "clarification","currentness","roles","authority","continuity","simulation",
 "specialist","core_router_semantic_rule_families","router_control_responsibilities",
 "new_shared_runtime_components","base_control_path","semantic_control_path",
 "design_basis_refs","runtime_evidence_claimed",
}
POLICY_KEYS={
 "hard_rule","baseline_eligible","eligible_candidates","lexicographic_tiebreak",
 "weights_forbidden","actual_latency","actual_cost",
}
INVARIANT_KEYS={
 "router_owns_discovery_and_derivation","semantic_specialist_is_not_router",
 "semantic_specialist_cannot_discover_workers","semantic_specialist_cannot_route",
 "semantic_specialist_cannot_authorize_effect","effect_authority_outside_router",
 "current_baseline_not_oracle","no_production_mutation",
}
EXPECTED_KIND={
 A:"MIN_ROUTER_SEMANTIC_SPECIALIST",
 B:"MIN_CLASSIFIER_COMPOSITE_DERIVATION",
 C:"BOUNDED_SEMANTIC_ROUTER",
 D:"CURRENT_HYBRID_BASELINE",
}
ALLOWED_RESPONSIBILITIES={
 "DISCOVERY","DERIVATION","CURRENTNESS","COMPOSITION","GOAL_NORMALIZATION",
 "NEGATION","CONTEXT","LEXICAL_MATCH","REGISTRY_HINT","ROLE_HINT","TARGET_HINT",
 "TRAIN_SEPARATION",
}
ALLOWED_RULE_FAMILIES={"MINIMAL_CLASSIFICATION","BOUNDED_SEMANTIC_NORMALIZATION","LEXICAL_HYBRID","HINT_ROUTING"}
ALLOWED_COMPONENTS={"SEMANTIC_SPECIALIST"}
ALLOWED_PATH_STAGES={"ROUTER","SEMANTIC_SPECIALIST","RESPONSIBLE_OWNER"}

def load(path:str)->dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))

def exact_keys(obj,expected,label,errors):
    if not isinstance(obj,dict):
        errors.append(f"{label}:NOT_OBJECT"); return
    extra=sorted(set(obj)-set(expected)); missing=sorted(set(expected)-set(obj))
    if extra: errors.append(f"{label}:UNKNOWN_KEYS:{','.join(extra)}")
    if missing: errors.append(f"{label}:MISSING_KEYS:{','.join(missing)}")

def derive_capabilities(dc:dict)->dict:
    return {
      "preserve_literal":dc["transport"]["literal"] is True,
      "discover_registered_responsibility":dc["routing"]["discovery_owner"]=="ROUTER",
      "semantic_normalization":dc["semantics"]["normalization_provider"] in ("EXTERNAL_SPECIALIST","ROUTER_BOUNDED"),
      "preserve_negation":dc["semantics"]["negation_handling"]=="STRUCTURED",
      "multi_goal_composition":dc["composition"]["multi_goal"] is True,
      "context_resolution":dc["context"]["resolution"] is True,
      "material_clarification_only":dc["clarification"]["material_only"] is True,
      "future_capability_gap":dc["currentness"]["future_gap"] is True,
      "role_separation":dc["roles"]["separated"] is True,
      "no_effect_authority":dc["authority"]["effect_owner"]=="EXTERNAL_OPERATION",
      "safe_readonly_continuity":dc["continuity"]["readonly"] is True,
      "deterministic_authority":dc["currentness"]["revision_pinned"] is True,
      "simulation_no_effect":dc["simulation"]["effect_mode"]=="NO_EFFECT",
      "typed_hint_non_authority":dc["authority"]["typed_hint"]=="NON_AUTHORITY",
      "train_technical_route_separation":dc["routing"]["train_lane"]=="SEPARATE",
      "stale_currentness_fail_closed":dc["currentness"]["stale_policy"]=="FAIL_CLOSED",
    }

def derive_metrics(dc:dict)->dict:
    return {
      "core_router_semantic_rule_change_touches":len(dc["core_router_semantic_rule_families"]),
      "router_authority_decision_responsibilities":len(dc["router_control_responsibilities"]),
      "new_shared_runtime_components":len(dc["new_shared_runtime_components"]),
      "base_control_hops":len(dc["base_control_path"]),
      "semantic_extra_hops":max(0,len(dc["semantic_control_path"])-len(dc["base_control_path"])),
      "router_internal_semantic_engine":dc["semantics"]["normalization_provider"]=="ROUTER_BOUNDED",
      "specialist_can_discover_workers":dc["specialist"]["can_discover_workers"],
      "specialist_can_authorize_effect":dc["specialist"]["can_authorize_effect"],
      "specialist_can_route":dc["specialist"]["can_route"],
    }

def validate_design(name:str,dc:dict,errors:list[str])->None:
    exact_keys(dc,DESIGN_KEYS,f"{name}:DESIGN",errors)
    if set(dc) != DESIGN_KEYS: return
    if dc.get("architecture_kind")!=EXPECTED_KIND[name]:
        errors.append(f"{name}:ARCHITECTURE_KIND_DRIFT")
    if dc.get("runtime_evidence_claimed") is not False:
        errors.append(f"{name}:RUNTIME_EVIDENCE_CLAIM_FORBIDDEN")
    refs=dc.get("design_basis_refs")
    if not isinstance(refs,list) or not refs or any(not isinstance(x,str) or not x for x in refs):
        errors.append(f"{name}:DESIGN_BASIS_REFS_REQUIRED")
    sp=dc.get("specialist")
    exact_keys(sp,{"present","can_discover_workers","can_route","can_authorize_effect"},f"{name}:SPECIALIST",errors)
    if isinstance(sp,dict):
        if any(type(sp.get(k)) is not bool for k in ("present","can_discover_workers","can_route","can_authorize_effect")):
            errors.append(f"{name}:SPECIALIST_FIELDS_NOT_BOOLEAN")
    sem=dc.get("semantics",{})
    exact_keys(sem,{"normalization_provider","negation_handling"},f"{name}:SEMANTICS",errors)
    provider=sem.get("normalization_provider") if isinstance(sem,dict) else None
    if name==A:
        if provider!="EXTERNAL_SPECIALIST" or sp.get("present") is not True:
            errors.append("A:EXTERNAL_SPECIALIST_CONTRACT_REQUIRED")
    elif name==C:
        if provider!="ROUTER_BOUNDED" or sp.get("present") is not False:
            errors.append("C:BOUNDED_ROUTER_CONTRACT_REQUIRED")
    else:
        if provider!="NONE" or sp.get("present") is not False:
            errors.append(f"{name}:NO_SEMANTIC_SPECIALIST_CONTRACT_REQUIRED")
    if name==A and any(sp.get(k) is not False for k in ("can_discover_workers","can_route","can_authorize_effect")):
        errors.append("A:SPECIALIST_BOUNDARY_VIOLATION")
    for key,allowed in (
      ("core_router_semantic_rule_families",ALLOWED_RULE_FAMILIES),
      ("router_control_responsibilities",ALLOWED_RESPONSIBILITIES),
      ("new_shared_runtime_components",ALLOWED_COMPONENTS),
      ("base_control_path",ALLOWED_PATH_STAGES),
      ("semantic_control_path",ALLOWED_PATH_STAGES),
    ):
        val=dc.get(key)
        if not isinstance(val,list) or len(val)!=len(set(val)) or any(x not in allowed for x in val):
            errors.append(f"{name}:BAD_DESIGN_LIST:{key}")
    if not dc.get("base_control_path") or not dc.get("semantic_control_path"):
        errors.append(f"{name}:CONTROL_PATH_EMPTY")
    # Exact nested schemas; values are subsequently interpreted by derivation.
    nested={
      "transport":{"literal"},
      "routing":{"discovery_owner","train_lane"},
      "composition":{"multi_goal"},
      "context":{"resolution"},
      "clarification":{"material_only"},
      "currentness":{"future_gap","revision_pinned","stale_policy"},
      "roles":{"separated"},
      "authority":{"effect_owner","typed_hint"},
      "continuity":{"readonly"},
      "simulation":{"effect_mode"},
    }
    for key,keys in nested.items():
        exact_keys(dc.get(key),keys,f"{name}:{key.upper()}",errors)

def evaluate_candidate(cand:dict,cases:list[dict])->dict:
    failures=[]; hops=0.0; continuity=0; extensibility=0
    for case in cases:
        missing=[cap for cap in case["required_capabilities"] if cand["capabilities"].get(cap) is not True]
        if missing: failures.append({"case_id":case["id"],"missing_capabilities":missing})
        passed=not missing
        if passed and "safe_readonly_continuity" in case["required_capabilities"]: continuity+=1
        if passed and case["extensibility_case"] is True: extensibility+=1
        m=cand["structural_metrics"]; hops+=m["base_control_hops"]
        if case["semantic_complex"] is True: hops+=m["semantic_extra_hops"]
    return {
      "cases_total":len(cases),"cases_passed":len(cases)-len(failures),
      "hard_failures":len(failures),"failed_cases":[x["case_id"] for x in failures],
      "missing_capabilities":sorted({c for x in failures for c in x["missing_capabilities"]}),
      "continuity_cases_passed":continuity,"extensibility_cases_passed":extensibility,
      "avg_control_hops":round(hops/len(cases),3),
    }

def rank_key(name:str,doc:dict,scoreboard:dict)->tuple:
    m=doc["candidates"][name]["structural_metrics"]
    return (
      scoreboard[name]["hard_failures"],
      m["core_router_semantic_rule_change_touches"],
      m["router_authority_decision_responsibilities"],
      m["new_shared_runtime_components"],
      scoreboard[name]["avg_control_hops"],
      name,
    )

def compute_result(doc:dict)->dict:
    cases=doc["cases"]
    board={n:evaluate_candidate(c,cases) for n,c in doc["candidates"].items()}
    hard=[n for n in doc["selection_policy"]["eligible_candidates"] if board[n]["hard_failures"]==0]
    hard=sorted(hard,key=lambda n:rank_key(n,doc,board))
    return {
      "schema_version":RESULT_SCHEMA,
      "checkpoint_code":"RW1-02_C2",
      "scope":"EXECUTABLE_DESIGN_CONTRACT_BENCHMARK_NOT_ROUTER_RUNTIME",
      "corpus_cases":len(cases),
      "requirements_covered":sorted({need for case in cases for need in case["needs"]}),
      "candidate_count":len(doc["candidates"]),
      "eligible_candidate_count":len(doc["selection_policy"]["eligible_candidates"]),
      "hard_pass_candidates":hard,
      "scoreboard":board,
      "provisional_selection":hard[0] if hard else None,
      "selection_status":"PROVISIONAL_PENDING_INDEPENDENT_C3_V2",
      "selection_reason":"Exact recomputation from structured candidate design contracts; no hardcoded winner assertion. Zero hard failures first, then declared lexicographic structural simplicity derived from topology; no runtime latency/cost claims.",
      "actual_latency":NOT_MEASURED,"actual_cost":NOT_MEASURED,
      "no_router_runtime_claim":True,"no_production_mutation":True,
      "baseline_not_eligible":True,
    }

def validate_corpus(doc:dict)->list[str]:
    e=[]
    exact_keys(doc,TOP_KEYS,"TOP",e)
    if doc.get("schema_version")!=SCHEMA:e.append("WRONG_SCHEMA")
    if doc.get("plan_code")!="LF_ROUTER_ARCHITECTURE_WAVE_V1":e.append("WRONG_PLAN")
    if doc.get("unit_code")!="RW1-02" or doc.get("checkpoint_code")!="RW1-02_C2":e.append("WRONG_CHECKPOINT")
    if doc.get("scope")!="EXECUTABLE_DESIGN_CONTRACT_BENCHMARK_NOT_ROUTER_RUNTIME":e.append("WRONG_SCOPE")
    if doc.get("source_c1_blob")!="470979c9b9a0dd9a728601b6ec5f577d7445f8b5":e.append("C1_SOURCE_BLOB_DRIFT")
    if doc.get("description_authority")!="DISPLAY_ONLY_NOT_SELECTION_AUTHORITY":e.append("DESCRIPTION_AUTHORITY_DRIFT")
    if doc.get("candidate_contract_mode")!="STRUCTURED_DESIGN_CONTRACT_NOT_RUNTIME_EVIDENCE":e.append("CANDIDATE_CONTRACT_MODE_DRIFT")
    if doc.get("literal_request_authority")!="TRACEABILITY_ONLY_STRUCTURED_CASE_FIELDS_DRIVE_BENCHMARK":e.append("LITERAL_AUTHORITY_DRIFT")
    cases=doc.get("cases")
    if not isinstance(cases,list) or len(cases)!=36:e.append("CASE_COUNT_NOT_36"); cases=cases if isinstance(cases,list) else []
    ids=[c.get("id") for c in cases if isinstance(c,dict)]
    if len(ids)!=len(set(ids)):e.append("DUPLICATE_CASE_ID")
    if set(doc.get("requirements_expected",[]))!=EXPECTED_NEEDS:e.append("EXPECTED_NEEDS_NOT_N01_N12")
    covered={n for c in cases if isinstance(c,dict) for n in c.get("needs",[])}
    if covered!=EXPECTED_NEEDS:e.append("ACTUAL_NEED_COVERAGE_NOT_N01_N12")
    cands=doc.get("candidates")
    if not isinstance(cands,dict) or set(cands)!=EXPECTED_CANDIDATES:e.append("CANDIDATE_SET_WRONG"); cands=cands if isinstance(cands,dict) else {}
    for name,cand in cands.items():
        exact_keys(cand,CANDIDATE_KEYS,name,e)
        if not isinstance(cand,dict):continue
        if cand.get("eligible") is not (name!=D):e.append(f"{name}:ELIGIBILITY_WRONG")
        if cand.get("description_authoritative") is not False:e.append(f"{name}:DESCRIPTION_MUST_BE_DISPLAY_ONLY")
        if cand.get("capability_evidence_mode")!="DERIVED_FROM_STRUCTURED_DESIGN_CONTRACT":e.append(f"{name}:CAPABILITY_EVIDENCE_MODE_WRONG")
        ce=cand.get("capability_evidence")
        exact_keys(ce,CAPABILITIES,f"{name}:CAPABILITY_EVIDENCE",e)
        if isinstance(ce,dict):
            for cap in CAPABILITIES:
                row=ce.get(cap)
                exact_keys(row,{"basis_type","basis_ref"},f"{name}:CAPABILITY_EVIDENCE:{cap}",e)
                if isinstance(row,dict) and (row.get("basis_type")!="DESIGN_CONTRACT" or row.get("basis_ref")!=CAPABILITY_BASIS[cap]):
                    e.append(f"{name}:CAPABILITY_BASIS_WRONG:{cap}")
        dc=cand.get("design_contract")
        validate_design(name,dc,e)
        if isinstance(dc,dict) and set(dc)==DESIGN_KEYS:
            try:
                if cand.get("capabilities")!=derive_capabilities(dc):e.append(f"{name}:CAPABILITIES_NOT_DERIVED")
                if cand.get("structural_metrics")!=derive_metrics(dc):e.append(f"{name}:METRICS_NOT_DERIVED")
            except Exception as ex:e.append(f"{name}:DERIVATION_ERROR:{type(ex).__name__}")
    p=doc.get("selection_policy",{})
    exact_keys(p,POLICY_KEYS,"SELECTION_POLICY",e)
    if p.get("eligible_candidates")!=ELIGIBLE:e.append("ELIGIBLE_CANDIDATES_DRIFT")
    if p.get("baseline_eligible") is not False:e.append("BASELINE_MUST_BE_INELIGIBLE")
    if p.get("hard_rule")!="ANY_MISSING_REQUIRED_CAPABILITY_ELIMINATES_ELIGIBLE_CANDIDATE":e.append("HARD_RULE_DRIFT")
    if p.get("weights_forbidden") is not True:e.append("WEIGHTS_FORBIDDEN")
    if p.get("actual_latency")!=NOT_MEASURED:e.append("LATENCY_MUST_BE_NOT_MEASURED")
    if p.get("actual_cost")!=NOT_MEASURED:e.append("COST_MUST_BE_NOT_MEASURED")
    if p.get("lexicographic_tiebreak")!=["hard_failures_asc","core_router_semantic_rule_change_touches_asc","router_authority_decision_responsibilities_asc","new_shared_runtime_components_asc","avg_control_hops_asc"]:e.append("TIEBREAK_DRIFT")
    inv=doc.get("hard_invariants",{})
    exact_keys(inv,INVARIANT_KEYS,"HARD_INVARIANTS",e)
    if isinstance(inv,dict) and any(inv.get(k) is not True for k in INVARIANT_KEYS):e.append("HARD_INVARIANT_FALSE")
    for case in cases:
        if not isinstance(case,dict):e.append("CASE_NOT_OBJECT");continue
        exact_keys(case,CASE_KEYS,f"CASE:{case.get('id')}",e)
        if not isinstance(case.get("literal_request"),str) or not case["literal_request"].strip():e.append(f"{case.get('id')}:EMPTY_LITERAL")
        req=case.get("required_capabilities")
        if not isinstance(req,list) or not req or len(req)!=len(set(req)):e.append(f"{case.get('id')}:BAD_REQUIRED_CAPABILITIES")
        elif any(x not in CAPABILITIES for x in req):e.append(f"{case.get('id')}:UNKNOWN_CAPABILITY")
        needs=case.get("needs")
        if not isinstance(needs,list) or not needs or any(n not in EXPECTED_NEEDS for n in needs):e.append(f"{case.get('id')}:BAD_NEEDS")
        if type(case.get("semantic_complex")) is not bool:e.append(f"{case.get('id')}:SEMANTIC_COMPLEX_NOT_BOOL")
        if type(case.get("extensibility_case")) is not bool:e.append(f"{case.get('id')}:EXTENSIBILITY_NOT_BOOL")
    return e

def validate_package(doc:dict,result:dict)->tuple[list[str],dict]:
    e=validate_corpus(doc)
    if e:return e,{}
    computed=compute_result(doc)
    if result!=computed:e.append("RESULT_NOT_EXACT_RECOMPUTATION")
    return e,computed

def self_test(doc:dict,result:dict)->int:
    failures=[]
    def must_reject(name,mut_doc=None,mut_res=None):
        d=copy.deepcopy(doc);r=copy.deepcopy(result)
        if mut_doc:mut_doc(d)
        if mut_res:mut_res(r)
        errs,_=validate_package(d,r)
        if not errs:failures.append(f"FALSE_ACCEPT:{name}")
    must_reject("unknown_candidate_field",lambda d:d["candidates"][A].__setitem__("effect_authority_mode","ROUTER"))
    must_reject("unknown_case_field",lambda d:d["cases"][0].__setitem__("effect_authority","ALLOW"))
    must_reject("hard_rule_drift",lambda d:d["selection_policy"].__setitem__("hard_rule","RANDOM_WINNER"))
    must_reject("weights_enabled",lambda d:d["selection_policy"].__setitem__("weights_forbidden",False))
    must_reject("A_specialist_authorizes",lambda d:d["candidates"][A]["design_contract"]["specialist"].__setitem__("can_authorize_effect",True))
    must_reject("C_not_bounded_router",lambda d:d["candidates"][C]["design_contract"]["semantics"].__setitem__("normalization_provider","EXTERNAL_SPECIALIST"))
    must_reject("metric_tamper",lambda d:d["candidates"][A]["structural_metrics"].__setitem__("core_router_semantic_rule_change_touches",99))
    must_reject("capability_tamper",lambda d:d["candidates"][B]["capabilities"].__setitem__("semantic_normalization",True))
    must_reject("capability_basis_tamper",lambda d:d["candidates"][A]["capability_evidence"]["no_effect_authority"].__setitem__("basis_ref","description"))
    must_reject("source_drift",lambda d:d.__setitem__("source_c1_blob","0"*40))
    must_reject("result_tamper",mut_res=lambda r:r.__setitem__("provisional_selection",C))
    must_reject("runtime_claim",mut_res=lambda r:r.__setitem__("no_router_runtime_claim",False))
    must_reject("baseline_eligible",lambda d:d["selection_policy"].__setitem__("baseline_eligible",True))
    must_reject("description_authoritative",lambda d:d["candidates"][A].__setitem__("description_authoritative",True))
    # Neutrality positive control: a valid structured sensitivity variant can elect C.
    d=copy.deepcopy(doc)
    d["candidates"][A]["design_contract"]["router_control_responsibilities"].extend(["COMPOSITION","GOAL_NORMALIZATION"])
    d["candidates"][A]["structural_metrics"]=derive_metrics(d["candidates"][A]["design_contract"])
    r=compute_result(d)
    errs,_=validate_package(d,r)
    if errs:failures.append("FALSE_REJECT:valid_sensitivity_C_can_win:"+",".join(errs[:3]))
    if r.get("provisional_selection")!=C:failures.append("SENSITIVITY_DID_NOT_ELECT_C")
    if failures:
        print(json.dumps({"status":"SELF_TEST_V2_FAILED","failures":failures},ensure_ascii=False));return 2
    print(json.dumps({"status":"RW102_C2_V2_SELF_TEST_PASS","negative_probes":14,"neutrality_positive_controls":1,"C_can_win_valid_variant":True},ensure_ascii=False));return 0

def main()->int:
    if len(sys.argv)<3:
        print("usage: validate_rw102_architecture_competition_v2.py CORPUS RESULT [--self-test]",file=sys.stderr);return 2
    doc=load(sys.argv[1]);result=load(sys.argv[2])
    errs,computed=validate_package(doc,result)
    if errs:
        print(json.dumps({"status":"FAIL","errors":errs},ensure_ascii=False));return 1
    if "--self-test" in sys.argv[3:]:return self_test(doc,result)
    print(json.dumps({
      "status":"RW102_C2_COMPETITION_V2_PASS","corpus_cases":computed["corpus_cases"],
      "requirements_covered":len(computed["requirements_covered"]),
      "candidate_count":computed["candidate_count"],"eligible_candidate_count":computed["eligible_candidate_count"],
      "hard_pass_candidates":computed["hard_pass_candidates"],"provisional_selection":computed["provisional_selection"],
      "winner_hardcoded":False,"capabilities_derived":True,"metrics_derived":True,
      "no_router_runtime_claim":True,"no_production_mutation":True
    },ensure_ascii=False,sort_keys=True));return 0

if __name__=="__main__":
    raise SystemExit(main())
