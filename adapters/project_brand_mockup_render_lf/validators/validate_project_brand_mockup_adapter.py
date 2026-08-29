#!/usr/bin/env python3
import json, sys

ADAPTER="ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF"
MAX_CAPSULE_CHARS=1600
ALLOWED_STATES={"BOUND","BOUND_WITH_APPROVED_FALLBACK","RETURN_TO_ORCHESTRATOR_MISSING_SOURCE","BLOCKED_SOURCE_CONFLICT","BLOCKED_PROJECT_UNRESOLVED"}

def err(e,c,p,m): e.append({"code":c,"path":p,"message":m})
def text(v): return isinstance(v,str) and bool(v.strip())
def result(e): return {"valid":not e,"errors":e,"blocking_codes":sorted({x["code"] for x in e if x["code"].startswith("BLOCK_") or x["code"] in {"CROSS_PROJECT_TOKEN_CONTAMINATION","CANONICAL_FALLBACK_FORBIDDEN","SECOND_LLM_CALL_FORBIDDEN"}})}

def validate(payload):
    e=[]
    if not isinstance(payload,dict): err(e,"NOT_OBJECT","$","payload must be object"); return result(e)
    applicable=payload.get("applicable")
    if not isinstance(applicable,bool): err(e,"APPLICABLE_REQUIRED","applicable","boolean required")
    invs=payload.get("lf_adapter_invocations")
    if not isinstance(invs,list): err(e,"INVOCATIONS_REQUIRED","lf_adapter_invocations","array required"); invs=[]
    if applicable is True and len(invs)==0: err(e,"BLOCK_MISSING_ADAPTER_INVOCATION","lf_adapter_invocations","applicable adapter requires exactly one invocation")
    if len(invs)>1: err(e,"BLOCK_DUPLICATE_ADAPTER_INVOCATION","lf_adapter_invocations","duplicate invocation")
    if invs:
        inv=invs[0]
        if not isinstance(inv,dict): err(e,"INVOCATION_NOT_OBJECT","lf_adapter_invocations[0]","object required")
        else:
            for f in ["invocation_id","adapter_code","assurance_revision","activation_source","binding_ref","project_code","target_ref","capsule_char_count","source_refs","verdict"]:
                if f not in inv: err(e,"INVOCATION_FIELD_MISSING",f"lf_adapter_invocations[0].{f}","required")
            if inv.get("adapter_code")!=ADAPTER: err(e,"ADAPTER_CODE_MISMATCH","lf_adapter_invocations[0].adapter_code","unexpected adapter")
            if inv.get("assurance_revision")!="v2": err(e,"ASSURANCE_REVISION_MISMATCH","lf_adapter_invocations[0].assurance_revision","must be v2")
            if inv.get("activation_source")!="ROUTER" or not text(inv.get("binding_ref")): err(e,"BLOCK_UNBOUND_ADAPTER_INVOCATION","lf_adapter_invocations[0]","Router activation + binding_ref required")
            cc=inv.get("capsule_char_count")
            if not isinstance(cc,int) or isinstance(cc,bool) or not 1<=cc<=MAX_CAPSULE_CHARS: err(e,"BLOCK_CONTEXT_BUDGET_EXCEEDED","lf_adapter_invocations[0].capsule_char_count",f"must be 1..{MAX_CAPSULE_CHARS}")
            refs=inv.get("source_refs")
            if not isinstance(refs,list) or not refs or len(refs)>10 or len(refs)!=len(set(refs)) or not all(text(x) for x in refs): err(e,"SOURCE_REFS_INVALID","lf_adapter_invocations[0].source_refs","1..10 unique refs required")
            if inv.get("verdict") not in {"APPLIED","BLOCKED"}: err(e,"INVOCATION_VERDICT_INVALID","lf_adapter_invocations[0].verdict","APPLIED or BLOCKED")

    b=payload.get("project_brand_mockup_binding")
    if applicable is True and not isinstance(b,dict): err(e,"BINDING_REQUIRED","project_brand_mockup_binding","binding required when applicable")
    if isinstance(b,dict):
        if b.get("binding_state") not in ALLOWED_STATES: err(e,"BINDING_STATE_INVALID","project_brand_mockup_binding.binding_state","unsupported state")
        project=b.get("project")
        project_code=project.get("project_code") if isinstance(project,dict) else None
        if not text(project_code): err(e,"PROJECT_UNRESOLVED","project_brand_mockup_binding.project.project_code","project required")
        refs=b.get("source_refs")
        if not isinstance(refs,list) or not refs or len(refs)!=len(set(refs)): err(e,"SOURCE_REFS_INVALID","project_brand_mockup_binding.source_refs","unique source refs required")
        token_projects=payload.get("token_project_codes",[])
        if token_projects and (not isinstance(token_projects,list) or any(x!=project_code for x in token_projects)):
            err(e,"CROSS_PROJECT_TOKEN_CONTAMINATION","token_project_codes","all tokens must belong to resolved project")
        fallback=b.get("fallback_mode")
        if fallback not in {"NONE","APPROVED_FALLBACK","PROPOSED_NOT_CANONICAL"}: err(e,"FALLBACK_MODE_INVALID","project_brand_mockup_binding.fallback_mode","unsupported fallback")
        if fallback!="NONE" and payload.get("fallback_presented_as_canonical") is True:
            err(e,"CANONICAL_FALLBACK_FORBIDDEN","fallback_presented_as_canonical","fallback cannot be canonical")
        screen_id=project.get("screen_id") if isinstance(project,dict) else None
        if text(screen_id) and not b.get("screen_spec_refs") and b.get("binding_state") in {"BOUND","BOUND_WITH_APPROVED_FALLBACK"}:
            err(e,"SCREEN_SPEC_REQUIRED","project_brand_mockup_binding.screen_spec_refs","screen-based binding requires screen spec refs")
        qa=b.get("qa_requirements")
        if not isinstance(qa,list) or not qa: err(e,"QA_REQUIRED","project_brand_mockup_binding.qa_requirements","QA requirements required")

    if payload.get("adapter_llm_call_count") not in {None,0}: err(e,"SECOND_LLM_CALL_FORBIDDEN","adapter_llm_call_count","adapter must not perform separate LLM call")
    return result(e)

if __name__=="__main__":
    try: print(json.dumps(validate(json.load(sys.stdin)),ensure_ascii=False,indent=2))
    except Exception as ex:
        print(json.dumps({"valid":False,"errors":[{"code":"MALFORMED_INPUT","path":"$","message":str(ex)}],"blocking_codes":["MALFORMED_INPUT"]},ensure_ascii=False,indent=2)); sys.exit(1)
