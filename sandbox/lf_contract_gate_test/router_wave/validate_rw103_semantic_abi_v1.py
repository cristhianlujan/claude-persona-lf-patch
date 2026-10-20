#!/usr/bin/env python3
import copy, hashlib, json, sys
from pathlib import Path

EXPECTED_TOP = {
  "schema_version","plan_code","unit_code","checkpoint_code","selected_architecture",
  "evidence_scope","authority_boundaries","request_abi","response_abi",
  "clarification_contract","resume_contract","compatibility_contract",
  "transition_contract","acl_contract","acceptance_cases","forbidden_claims"
}
FORBIDDEN_RESPONSE_KEYS={"operation_code","executor","downstream_execution_allowed","effect_authority"}
EXPECTED_CASES={f"C{i:02d}" for i in range(1,15)}

def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def exact_keys(obj, keys, label, errors):
    if not isinstance(obj,dict):
        errors.append(f"{label}:NOT_OBJECT"); return
    extra=set(obj)-set(keys); missing=set(keys)-set(obj)
    if extra: errors.append(f"{label}:EXTRA:{','.join(sorted(extra))}")
    if missing: errors.append(f"{label}:MISSING:{','.join(sorted(missing))}")

def validate(doc):
    e=[]
    exact_keys(doc,EXPECTED_TOP,"TOP",e)
    if doc.get("schema_version")!="RW103_C2_SEMANTIC_ABI_V1": e.append("SCHEMA")
    if doc.get("plan_code")!="LF_ROUTER_ARCHITECTURE_WAVE_V1": e.append("PLAN")
    if doc.get("unit_code")!="RW1-03" or doc.get("checkpoint_code")!="RW1-03_C2": e.append("CHECKPOINT")
    if doc.get("selected_architecture")!="A_MIN_ROUTER_SEMANTIC_SPECIALIST": e.append("ARCH")
    if doc.get("evidence_scope")!="CONTRACT_AND_TRANSITION_ONLY_NOT_ROUTER_RUNTIME_OR_PRODUCTION": e.append("SCOPE")

    ab=doc.get("authority_boundaries",{})
    if "DISCOVERY" not in ab.get("router_owns",[]) or "EFFECT_AUTHORITY_BINDING" not in ab.get("router_owns",[]): e.append("ROUTER_AUTHORITY_INCOMPLETE")
    if any(x not in ab.get("specialist_forbidden",[]) for x in ["SELECT_ROUTE","SELECT_OPERATION","SELECT_EXECUTOR","AUTHORIZE_EFFECT","WIDEN_SCOPE","MINT_TARGET_AUTHORITY"]): e.append("SPECIALIST_FORBIDDEN_INCOMPLETE")

    req=doc.get("request_abi",{})
    res=doc.get("response_abi",{})
    if req.get("schema_version")!="LF_ROUTER_SEMANTIC_REQUEST_V1": e.append("REQUEST_SCHEMA")
    if res.get("schema_version")!="LF_ROUTER_SEMANTIC_RESULT_V1": e.append("RESULT_SCHEMA")
    ri=req.get("invariants",{})
    if ri.get("router_must_equal")!="ACT-0001" or ri.get("no_operation_code") is not True or ri.get("no_executor") is not True or ri.get("no_effect_authority") is not True: e.append("REQUEST_AUTHORITY")
    si=res.get("invariants",{})
    for k in ["request_sha256_must_match","positive_targets_subset_of_candidates","exclusions_must_be_preserved_or_strengthened","allowed_scope_may_only_narrow","forbidden_scope_may_only_expand","operation_code_forbidden","executor_forbidden","downstream_execution_allowed_forbidden","effect_authority_forbidden"]:
        if si.get(k) is not True: e.append(f"RESULT_INVARIANT:{k}")
    if set(res.get("decision_enum",[]))!={"RESOLVED","CLARIFICATION_REQUIRED","BLOCKED"}: e.append("DECISIONS")

    cc=doc.get("clarification_contract",{})
    if cc.get("owner")!="CALLER_INTERACTION_LAYER" or cc.get("specialist_role")!="PROPOSE_ONLY" or cc.get("max_question_count_per_round")!=1: e.append("CLARIFICATION_OWNER")
    if cc.get("clarification_never_authorizes_effect") is not True: e.append("CLARIFICATION_EFFECT")

    rc=doc.get("resume_contract",{})
    required={"REQUEST_HASH_MATCH","SOURCE_CURRENTNESS_CURRENT","CANDIDATE_SUBSET_ONLY","NO_SCOPE_WIDENING","EXCLUSIONS_PRESERVED","NO_OPERATION_OR_EXECUTOR_FROM_SPECIALIST"}
    if set(rc.get("required_checks",[]))!=required: e.append("RESUME_CHECKS")
    if rc.get("owner")!="ACT-0001" or rc.get("on_success")!="ROUTER_REDERIVES_ROUTE_AND_AUTHORITY" or rc.get("specialist_result_is_not_route_authority") is not True: e.append("RESUME_AUTHORITY")

    compat=doc.get("compatibility_contract",{})
    if compat.get("legacy_entrypoint")!="public.lf_router_resolve_v1": e.append("LEGACY_ENTRYPOINT")
    if compat.get("current_handoff")!="public.lf_router_intent_handoff_v1": e.append("HANDOFF_REUSE")
    if compat.get("migration_rule")!="EVOLVE_HANDOFF_WITHOUT_SECOND_ROUTER": e.append("SECOND_ROUTER")
    if compat.get("legacy_consumers_must_not_receive_new_effect_authority") is not True: e.append("LEGACY_EFFECT")

    tr=doc.get("transition_contract",{})
    if tr.get("no_circular_train_dependency") is not True or tr.get("no_double_router") is not True: e.append("TRANSITION_SAFETY")
    if tr.get("train_bootstrap_rule")!="INSTALLATION_USES_PREEXISTING_ACT0001_AND_MERGE_TRAIN_AUTHORITY": e.append("TRAIN_BOOTSTRAP")
    phases=tr.get("phases",[])
    if [p.get("phase") for p in phases]!=["T0","T1","T2","T3","T4"]: e.append("PHASES")

    acl=doc.get("acl_contract",{})
    for k in ["new_semantic_runtime_public_execute","new_resume_validator_public_execute","anon_allowed","authenticated_allowed","current_v1_handoff_acl_change_in_c2"]:
        if acl.get(k) is not False: e.append(f"ACL_FORBIDDEN:{k}")
    for k in ["service_role_allowed","postgres_allowed","no_acl_widening"]:
        if acl.get(k) is not True: e.append(f"ACL_REQUIRED:{k}")

    cases=doc.get("acceptance_cases",[])
    ids={x.get("id") for x in cases if isinstance(x,dict)}
    if len(cases)!=14 or ids!=EXPECTED_CASES: e.append("CASES")
    if any(set(x)!={"id","family","expect"} for x in cases if isinstance(x,dict)): e.append("CASE_SCHEMA")

    claims=set(doc.get("forbidden_claims",[]))
    for c in ["ROUTER_RUNTIME_PASS","PRODUCTION_PASS","E2E_PASS","SEMANTIC_SPECIALIST_CAN_AUTHORIZE_EFFECT"]:
        if c not in claims: e.append(f"FORBIDDEN_CLAIM_MISSING:{c}")
    return e

def validate_semantic_response(doc, request, response):
    errors=[]
    if response.get("request_sha256") != request.get("request_sha256"):
        errors.append("REQUEST_HASH_MISMATCH")
    candidate_ids={x.get("asset_code") for x in request.get("candidate_subjects",[]) if isinstance(x,dict)}
    if any(x not in candidate_ids for x in response.get("positive_target_refs",[])):
        errors.append("CANDIDATE_WIDENING")
    req_ex=set(request.get("excluded_target_refs",[])); out_ex=set(response.get("excluded_target_refs",[]))
    if not req_ex.issubset(out_ex): errors.append("EXCLUSION_DROPPED")
    if any(k in response for k in FORBIDDEN_RESPONSE_KEYS): errors.append("FORBIDDEN_AUTHORITY_FIELD")
    return errors

def self_test(doc):
    failures=[]
    def must_reject(name, mut):
        d=copy.deepcopy(doc); mut(d)
        if not validate(d): failures.append("FALSE_ACCEPT:"+name)

    must_reject("specialist_authorizes_effect", lambda d:d["authority_boundaries"]["specialist_forbidden"].remove("AUTHORIZE_EFFECT"))
    must_reject("second_router", lambda d:d["compatibility_contract"].__setitem__("migration_rule","CREATE_SECOND_ROUTER"))
    must_reject("public_execute", lambda d:d["acl_contract"].__setitem__("new_semantic_runtime_public_execute",True))
    must_reject("train_circular", lambda d:d["transition_contract"].__setitem__("no_circular_train_dependency",False))
    must_reject("clarification_owner", lambda d:d["clarification_contract"].__setitem__("owner","SEMANTIC_SPECIALIST"))
    must_reject("resume_owner", lambda d:d["resume_contract"].__setitem__("owner","SEMANTIC_SPECIALIST"))
    must_reject("operation_allowed", lambda d:d["response_abi"]["invariants"].__setitem__("operation_code_forbidden",False))
    must_reject("legacy_effect", lambda d:d["compatibility_contract"].__setitem__("legacy_consumers_must_not_receive_new_effect_authority",False))

    literal="Actualizar A pero no B, solo si current."
    h=hashlib.sha256(literal.encode("utf-8")).hexdigest()
    request={
      "request_sha256":h,
      "candidate_subjects":[{"asset_code":"A"},{"asset_code":"B"}],
      "excluded_target_refs":["B"]
    }
    good={"request_sha256":h,"positive_target_refs":["A"],"excluded_target_refs":["B"]}
    if validate_semantic_response(doc,request,good): failures.append("FALSE_REJECT:GOOD_RESPONSE")
    for name,bad in [
      ("hash",dict(good,request_sha256="0"*64)),
      ("candidate",dict(good,positive_target_refs=["C"])),
      ("exclusion",dict(good,excluded_target_refs=[])),
      ("operation",dict(good,operation_code="ACTUALIZACION_DB_LF")),
      ("effect",dict(good,effect_authority=True)),
    ]:
      if not validate_semantic_response(doc,request,bad): failures.append("FALSE_ACCEPT_RESPONSE:"+name)

    if failures:
      print(json.dumps({"status":"RW103_C2_SELF_TEST_FAIL","failures":failures},sort_keys=True)); return 2
    print(json.dumps({"status":"RW103_C2_SELF_TEST_PASS","negative_contract_mutations":8,"negative_response_probes":5,"positive_response_probe":1},sort_keys=True)); return 0

def main():
    if len(sys.argv)<2:
      print("usage: validate_rw103_semantic_abi_v1.py CONTRACT [--self-test]",file=sys.stderr); return 2
    doc=load(sys.argv[1]); errors=validate(doc)
    if errors:
      print(json.dumps({"status":"FAIL","errors":errors},sort_keys=True)); return 1
    if "--self-test" in sys.argv[2:]: return self_test(doc)
    print(json.dumps({
      "status":"RW103_C2_SEMANTIC_ABI_PASS",
      "acceptance_cases":len(doc["acceptance_cases"]),
      "selected_architecture":doc["selected_architecture"],
      "no_second_router":doc["transition_contract"]["no_double_router"],
      "no_acl_widening":doc["acl_contract"]["no_acl_widening"],
      "no_runtime_claim":True,
      "no_production_mutation":True
    },sort_keys=True)); return 0

if __name__=="__main__":
    raise SystemExit(main())
