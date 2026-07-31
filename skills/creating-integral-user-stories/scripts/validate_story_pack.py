#!/usr/bin/env python3
"""Semantic validator for J03_STORY_CORE v0.7 (A-B stage only)."""
from __future__ import annotations
import argparse, copy, hashlib, json, os, re, sys
from pathlib import Path
from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object, sha256_file

JUDGE="J03_STORY_CORE"; VERSION="v0.7"
REG="supabase://private.lf_skill_artifacts/ART_SCRIPT_VALIDATE_STORY_PACK"
SHA_RE=re.compile(r"^[0-9a-f]{64}$")
TOP={"target_functional_unit","story_core","source_snapshot","j02_evidence"}
ASSERTIONS=("input_envelope_valid","identity_schema_valid","core_schema_valid","target_functional_unit_matches","source_decision_matches","source_snapshot_matches","actor_missing","need_missing","benefit_missing","preconditions_missing","trigger_missing","main_flow_missing","postconditions_missing","acceptance_criteria_missing","criteria_without_given_when_then","criteria_without_source_ref","duplicate_criterion_codes","out_of_scope_missing","multiple_independent_results","blocking_pending_decisions")

def canonical_sha(v): return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()).hexdigest()
def obj(v,n):
    if not isinstance(v,dict): raise ValidationInputError(f"{n}_must_be_object")
    return v
def runtime_meta():
    p=Path(__file__).resolve(); b=p.read_bytes()
    return {"semantic_validator_path":str(p),"semantic_validator_sha256":hashlib.sha256(b).hexdigest(),"semantic_validator_git_blob_sha1":hashlib.sha1(f"blob {len(b)}\0".encode()+b).hexdigest(),"semantic_validator_bytes":len(b),"semantic_validator_registration_ref":REG}
def sp_schema(): return Path(os.getenv("LF_STORY_PACK_SCHEMA") or Path(__file__).resolve().parent.parent/"schemas/story-pack.schema.json")
def jr_schema(): return Path(os.getenv("LF_JUDGE_RESULT_SCHEMA") or Path(__file__).resolve().parent.parent/"schemas/judge-result.schema.json")
def schema_errors(v,prop):
    try: import jsonschema
    except ImportError as e: raise ValidationInputError("jsonschema_not_available") from e
    p=sp_schema(); root=obj(load_json(p),"story_pack_schema"); jsonschema.Draft7Validator.check_schema(root)
    sub=dict(obj(obj(root.get("properties"),"properties").get(prop),f"{prop}_schema")); sub["$schema"]=root.get("$schema","http://json-schema.org/draft-07/schema#"); sub["definitions"]=root.get("definitions",{})
    errs=sorted(f"{'/'.join(map(str,e.absolute_path)) or '$'}:{e.message}" for e in jsonschema.Draft7Validator(sub,format_checker=jsonschema.FormatChecker()).iter_errors(v))
    return errs,sha256_file(p)
def result_schema_errors(v):
    try: import jsonschema
    except ImportError as e: raise ValidationInputError("jsonschema_not_available") from e
    s=obj(load_json(jr_schema()),"judge_result_schema"); jsonschema.Draft7Validator.check_schema(s)
    return sorted(f"{'/'.join(map(str,e.absolute_path)) or '$'}:{e.message}" for e in jsonschema.Draft7Validator(s).iter_errors(v))
def missing_s(v,n=1): return 0 if isinstance(v,str) and len(v.strip())>=n else 1
def missing_a(v): return 0 if isinstance(v,list) and v else 1

def runtime_blockers(executor,version,expected,registration,meta):
    b=[]; executor=str(executor or "").strip(); version=str(version or "").strip(); expected=str(expected or "").strip()
    if not executor: b.append("executor_identity_missing")
    if version!=VERSION: b.append("judge_version_missing_or_mismatch")
    if not expected: b.append("validator_unavailable")
    elif not SHA_RE.fullmatch(expected): b.append("validator_sha_expected_invalid")
    elif expected!=meta["semantic_validator_sha256"]: b.append("validator_sha_unreconciled")
    if str(registration or "").strip()!=REG: b.append("validator_unregistered")
    return b

def preflight(p,executor):
    b=[]
    if not isinstance(p,dict): return ["required_input_missing"]
    if set(p)!=TOP: b.append("required_input_missing")
    t=p.get("target_functional_unit"); sc=p.get("story_core"); ss=p.get("source_snapshot"); j=p.get("j02_evidence")
    if not all(isinstance(x,dict) for x in (t,sc,ss,j)): return sorted(set(b+["required_input_missing"]))
    if set(sc)!={"identity","core"} or not all(isinstance(sc.get(k),dict) for k in ("identity","core")): b.append("required_input_missing")
    if t.get("decision")!="CREATE_STORY": b.append("target_decision_not_CREATE_STORY")
    if j.get("judge_result")!="PASS_WITH_EVIDENCE" or not isinstance(j.get("evidence_refs"),list) or not j.get("evidence_refs"): b.append("j02_not_passed_with_evidence")
    if not isinstance(ss.get("sha256"),str) or not SHA_RE.fullmatch(ss["sha256"]): b.append("source_hash_missing")
    if not str(ss.get("source_version") or "").strip(): b.append("source_snapshot_unavailable")
    rr=t.get("source_refs"); resolved=ss.get("resolved_refs")
    if not isinstance(rr,list) or not rr or not isinstance(resolved,list) or any(x not in resolved for x in rr): b.append("source_ref_unresolvable")
    worker=str(t.get("worker_identity") or "").strip(); executor=str(executor or "").strip()
    if not worker or not executor or worker==executor: b.append("worker_judge_independence_broken")
    if not str(t.get("functional_unit_code") or "").strip(): b.append("approved_functional_unit_missing_or_ambiguous")
    return sorted(set(b))

def semantic(p):
    t=obj(p["target_functional_unit"],"target_functional_unit"); sc=obj(p["story_core"],"story_core"); ss=obj(p["source_snapshot"],"source_snapshot"); i=obj(sc.get("identity"),"identity"); c=obj(sc.get("core"),"core")
    ie,sh=schema_errors(i,"identity"); ce,_=schema_errors(c,"core"); crit=c.get("acceptance_criteria") if isinstance(c.get("acceptance_criteria"),list) else []
    bad_gwt=bad_ref=0; codes=[]
    for x in crit:
        if not isinstance(x,dict): bad_gwt+=1; bad_ref+=1; continue
        bad_gwt+=int(any(missing_s(x.get(k),5) for k in ("given","when","then"))); bad_ref+=missing_s(x.get("source_ref"),3)
        if isinstance(x.get("criterion_code"),str) and x["criterion_code"].strip(): codes.append(x["criterion_code"].strip())
    dup=sorted({x for x in codes if codes.count(x)>1}); results=t.get("business_results") if isinstance(t.get("business_results"),list) else []; pending=t.get("pending_decisions") if isinstance(t.get("pending_decisions"),list) else []
    blocking=sum(1 for x in pending if isinstance(x,dict) and x.get("blocking") is True and x.get("status")=="OPEN")
    checks={
      "input_envelope_valid":0 if set(p)==TOP else 1,"identity_schema_valid":len(ie),"core_schema_valid":len(ce),
      "target_functional_unit_matches":0 if i.get("functional_unit_code")==t.get("functional_unit_code") else 1,
      "source_decision_matches":0 if i.get("source_decision_id")==t.get("source_decision_id") else 1,
      "source_snapshot_matches":0 if i.get("source_version")==t.get("source_version")==ss.get("source_version") and i.get("source_snapshot_sha")==t.get("source_snapshot_sha")==ss.get("sha256") else 1,
      "actor_missing":missing_s(c.get("actor"),3),"need_missing":missing_s(c.get("need"),8),"benefit_missing":missing_s(c.get("benefit"),8),"preconditions_missing":missing_a(c.get("preconditions")),"trigger_missing":missing_s(c.get("trigger"),5),"main_flow_missing":missing_a(c.get("main_flow")),"postconditions_missing":missing_a(c.get("postconditions")),"acceptance_criteria_missing":missing_a(c.get("acceptance_criteria")),"criteria_without_given_when_then":bad_gwt,"criteria_without_source_ref":bad_ref,"duplicate_criterion_codes":len(dup),"out_of_scope_missing":missing_a(c.get("out_of_scope")),"multiple_independent_results":0 if len(results)==1 else max(len(results)-1,1),"blocking_pending_decisions":blocking}
    checks={k:int(checks.get(k,1)) for k in ASSERTIONS}
    ev={"checks":checks,"input_envelope_ref":"inline:story-core-envelope","identity_schema_ref":"schemas/story-pack.schema.json#properties/identity","core_schema_ref":"schemas/story-pack.schema.json#properties/core","story_pack_schema_sha256":sh,"identity_schema_errors":ie,"core_schema_errors":ce,"target_functional_unit_code":t.get("functional_unit_code"),"source_decision_id":t.get("source_decision_id"),"source_snapshot_sha256":ss.get("sha256"),"source_version":ss.get("source_version"),"j02_result":p["j02_evidence"].get("judge_result"),"j02_evidence_refs":p["j02_evidence"].get("evidence_refs"),"acceptance_criteria_count":len(crit),"duplicate_criterion_codes":dup,"atomicity_boundaries":{k:t.get(k) for k in ("actor","trigger","business_results","permission_boundary","resource_boundary","state_boundary")},"blocking_pending_decisions_count":blocking}
    return checks,ev

REPAIR={
"input_envelope_valid":("$","Provide exactly the four J03 envelope inputs."),"identity_schema_valid":("story_core.identity","Repair identity against the canonical A subschema."),"core_schema_valid":("story_core.core","Repair core against the canonical B subschema."),"target_functional_unit_matches":("story_core.identity.functional_unit_code","Match the approved target functional unit."),"source_decision_matches":("story_core.identity.source_decision_id","Match the J02 source decision."),"source_snapshot_matches":("story_core.identity","Reconcile source version and SHA with the snapshot."),"actor_missing":("story_core.core.actor","Provide the source-backed actor."),"need_missing":("story_core.core.need","Provide the source-backed need."),"benefit_missing":("story_core.core.benefit","Provide the observable business benefit."),"preconditions_missing":("story_core.core.preconditions","Provide at least one verifiable precondition."),"trigger_missing":("story_core.core.trigger","Provide one source-backed trigger."),"main_flow_missing":("story_core.core.main_flow","Provide the ordered main flow."),"postconditions_missing":("story_core.core.postconditions","Provide observable postconditions."),"acceptance_criteria_missing":("story_core.core.acceptance_criteria","Provide at least one acceptance criterion."),"criteria_without_given_when_then":("story_core.core.acceptance_criteria","Complete given, when and then."),"criteria_without_source_ref":("story_core.core.acceptance_criteria","Attach a resolvable source_ref."),"duplicate_criterion_codes":("story_core.core.acceptance_criteria","Assign unique criterion codes."),"out_of_scope_missing":("story_core.core.out_of_scope","Declare at least one boundary."),"multiple_independent_results":("target_functional_unit.business_results","Return to J02 and separate independent results."),"blocking_pending_decisions":("target_functional_unit.pending_decisions","Resolve from source or remain BLOCKED.")}

def build(p,refs,retry,executor,version,expected,registration,input_sha,input_path,command):
    meta=runtime_meta(); blockers=runtime_blockers(executor,version,expected,registration,meta)+preflight(p,executor); checks={}; ev={**meta,"semantic_validator_expected_sha256":expected,"input_sha256":input_sha,"input_path":input_path,"checks":checks}
    if isinstance(p,dict) and all(isinstance(p.get(k),dict) for k in TOP):
        try: checks,extra=semantic(p); ev.update(extra)
        except ValidationInputError as e: blockers.append(str(e))
    if checks.get("blocking_pending_decisions",0): blockers.append("blocking_pending_decisions")
    blockers=sorted(set(blockers)); failed=[k for k,v in checks.items() if v]; repairs=[failure(k,*REPAIR[k]) for k in failed]
    return result_object(JUDGE,failed,ev,refs,repairs,blockers,retry_count=retry,judge_version=version,executor_identity=executor,command=command)

def positive_payload():
    sha="a"*64; ref="SRC-CORE-001"; t={"functional_unit_code":"FU-CUSTOMER-SEARCH","decision":"CREATE_STORY","source_decision_id":"DEC-J02-001","source_version":"v1.0","source_snapshot_sha":sha,"source_refs":[ref],"actor":"Authorized operator","trigger":"Submit customer search","business_results":["Display the matching authorized customer"],"permission_boundary":"PERM-CUSTOMER-SEARCH","resource_boundary":"CUSTOMER-READ-MODEL","state_boundary":"IDLE_TO_RESULTS","worker_identity":"PERFIL_STORY_CORE_AUTHOR_LF","pending_decisions":[]}
    i={"story_code":"US-CUSTOMER-SEARCH-001","title":"Search an authorized customer","epic_code":"EP-CUSTOMERS","module_code":"MOD-CUSTOMERS","screen_code":"SCR-CUSTOMER-SEARCH","functional_unit_code":t["functional_unit_code"],"source_decision_id":t["source_decision_id"],"source_version":"v1.0","source_snapshot_sha":sha,"status":"CANDIDATO_READ_ONLY","priority":"P1"}
    c={"actor":"Authorized operator","need":"search for an authorized customer","benefit":"review the matching customer before continuing","preconditions":["The operator is authenticated"],"trigger":"Submit the customer search","main_flow":["The operator submits the search","The system displays the matching customer"],"alternative_flows":[],"postconditions":["The matching customer is visible"],"acceptance_criteria":[{"criterion_code":"AC-001","given":"An authenticated authorized operator","when":"The operator submits a valid search","then":"The matching authorized customer is displayed","source_ref":ref}],"out_of_scope":["Editing customer data"]}
    return {"target_functional_unit":t,"story_core":{"identity":i,"core":c},"source_snapshot":{"source_version":"v1.0","sha256":sha,"content_ref":"snapshot://customer-search/v1.0","resolved_refs":[ref]},"j02_evidence":{"judge_result":"PASS_WITH_EVIDENCE","evidence_refs":["evidence://j02/customer-search"]}}

def cases():
    return [
("missing_j02_evidence","BLOCKED","j02_not_passed_with_evidence",lambda p:p.update({"j02_evidence":{}})),("target_decision_not_create_story","BLOCKED","target_decision_not_CREATE_STORY",lambda p:p["target_functional_unit"].update({"decision":"MERGE_WITH"})),("functional_unit_mismatch","RETURN_TO_WORKER","target_functional_unit_matches",lambda p:p["story_core"]["identity"].update({"functional_unit_code":"FU-OTHER"})),("source_decision_mismatch","RETURN_TO_WORKER","source_decision_matches",lambda p:p["story_core"]["identity"].update({"source_decision_id":"DEC-OTHER"})),("snapshot_sha_mismatch","RETURN_TO_WORKER","source_snapshot_matches",lambda p:p["story_core"]["identity"].update({"source_snapshot_sha":"b"*64})),("missing_actor","RETURN_TO_WORKER","actor_missing",lambda p:p["story_core"]["core"].update({"actor":""})),("missing_trigger","RETURN_TO_WORKER","trigger_missing",lambda p:p["story_core"]["core"].update({"trigger":""})),("empty_main_flow","RETURN_TO_WORKER","main_flow_missing",lambda p:p["story_core"]["core"].update({"main_flow":[]})),("criterion_missing_given","RETURN_TO_WORKER","criteria_without_given_when_then",lambda p:p["story_core"]["core"]["acceptance_criteria"][0].update({"given":""})),("criterion_missing_source_ref","RETURN_TO_WORKER","criteria_without_source_ref",lambda p:p["story_core"]["core"]["acceptance_criteria"][0].update({"source_ref":""})),("duplicate_criterion_code","RETURN_TO_WORKER","duplicate_criterion_codes",lambda p:p["story_core"]["core"]["acceptance_criteria"].append(copy.deepcopy(p["story_core"]["core"]["acceptance_criteria"][0]))),("missing_out_of_scope","RETURN_TO_WORKER","out_of_scope_missing",lambda p:p["story_core"]["core"].update({"out_of_scope":[]})),("multiple_independent_results","RETURN_TO_WORKER","multiple_independent_results",lambda p:p["target_functional_unit"]["business_results"].append("Export a separate customer report")),("blocking_pending_decision","BLOCKED","blocking_pending_decisions",lambda p:p["target_functional_unit"]["pending_decisions"].append({"decision_code":"PD-001","blocking":True,"status":"OPEN"})),("missing_executor_identity","BLOCKED","executor_identity_missing",None),("validator_sha_mismatch","BLOCKED","validator_sha_unreconciled",None)]

def self_test():
    meta=runtime_meta(); p=positive_payload(); pos=build(p,["evidence:self-test-positive"],0,"LF_SELF_TEST",VERSION,meta["semantic_validator_sha256"],REG,canonical_sha(p),None,"self-test:positive"); out=[]
    for cid,er,ea,mut in cases():
        q=copy.deepcopy(p); mut(q) if mut else None; ex=None if cid=="missing_executor_identity" else "LF_SELF_TEST"; sh="b"*64 if cid=="validator_sha_mismatch" else meta["semantic_validator_sha256"]
        r=build(q,[f"evidence:self-test:{cid}"],0,ex,VERSION,sh,REG,canonical_sha(q),None,f"self-test:{cid}"); assertions=set(r["failed_assertions"])|set(r["blocking_assertions"]); out.append({"case_id":cid,"expected_result":er,"actual_result":r["result"],"expected_assertion":ea,"matched":r["result"]==er and ea in assertions})
    pe=result_schema_errors(pos); passed=pos["result"]=="PASS_WITH_EVIDENCE" and pos["assertions_passed"]==20 and pos["assertions_total"]==20 and not pe and all(x["matched"] for x in out)
    ev=dict(pos["evidence"]); ev.update({"self_test":{"positive_pass":pos["result"]=="PASS_WITH_EVIDENCE","positive_assertions":f"{pos['assertions_passed']}/{pos['assertions_total']}","positive_result_schema_errors":pe,"negative_cases_total":len(out),"negative_cases_passed":sum(x["matched"] for x in out),"negative_cases":out},"checks":pos["evidence"]["checks"],"input_sha256":canonical_sha(p)})
    r=result_object(JUDGE,[] if passed else ["self_test_failed"],ev,["evidence:self-test"],[] if passed else [failure("self_test_failed","$","Repair runtime behavior.")],[],retry_count=0,judge_version=VERSION,executor_identity="LF_SELF_TEST",command="python scripts/validate_story_pack.py --self-test")
    if result_schema_errors(r): raise ValidationInputError("self_test_result_schema_invalid")
    return emit(r)

def run():
    c=argparse.ArgumentParser(description=__doc__); c.add_argument("input",type=Path,nargs="?"); c.add_argument("--self-test",action="store_true"); c.add_argument("--evidence-ref",action="append",default=[]); c.add_argument("--retry-count",type=int,default=0); c.add_argument("--expected-validator-sha256"); c.add_argument("--registration-ref"); a=c.parse_args()
    if a.self_test:return self_test()
    if a.input is None: raise ValidationInputError("story_core_envelope_input_required")
    p=load_json(a.input); r=build(p,a.evidence_ref or [f"file:{a.input}"],a.retry_count,os.getenv("LF_EXECUTOR_IDENTITY"),os.getenv("LF_JUDGE_VERSION"),a.expected_validator_sha256,a.registration_ref,sha256_file(a.input),str(a.input)," ".join(sys.argv))
    if result_schema_errors(r): raise ValidationInputError("judge_result_schema_invalid")
    return emit(r)
if __name__=="__main__": raise SystemExit(main_guard(JUDGE,run))
