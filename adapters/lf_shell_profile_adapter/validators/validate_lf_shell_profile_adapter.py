#!/usr/bin/env python3
import json, sys

ADAPTER="ADAPTER_LF_SHELL_PROFILE"
MAX_CAPSULE_CHARS=1800
ALLOWED_STATES={"BOUND","BOUND_CANDIDATE_ONLY","RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY","RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED","BLOCKED_SOURCE_CONFLICT","BLOCKED_SCREEN_UNRESOLVED"}

def err(errors, code, path, message):
    errors.append({"code":code,"path":path,"message":message})

def text(v):
    return isinstance(v,str) and bool(v.strip())

def validate(payload):
    errors=[]
    if not isinstance(payload,dict):
        err(errors,"NOT_OBJECT","$","payload must be object")
        return {"valid":False,"errors":errors}

    applicable=payload.get("applicable")
    if not isinstance(applicable,bool): err(errors,"APPLICABLE_REQUIRED","applicable","boolean required")

    invs=payload.get("lf_adapter_invocations")
    if not isinstance(invs,list):
        err(errors,"INVOCATIONS_REQUIRED","lf_adapter_invocations","array required")
        invs=[]

    if applicable is True and len(invs)==0:
        err(errors,"BLOCK_MISSING_ADAPTER_INVOCATION","lf_adapter_invocations","applicable adapter requires exactly one invocation")
    if len(invs)>1:
        err(errors,"BLOCK_DUPLICATE_ADAPTER_INVOCATION","lf_adapter_invocations","at most one invocation is allowed for one adapter/target")

    if invs:
        inv=invs[0]
        if not isinstance(inv,dict):
            err(errors,"INVOCATION_NOT_OBJECT","lf_adapter_invocations[0]","object required")
        else:
            required=["invocation_id","adapter_code","assurance_revision","activation_source","binding_ref","profile_id","target_ref","capsule_ref","capsule_char_count","source_refs","verdict"]
            for f in required:
                if f not in inv: err(errors,"INVOCATION_FIELD_MISSING",f"lf_adapter_invocations[0].{f}","required")
            if inv.get("adapter_code")!=ADAPTER: err(errors,"ADAPTER_CODE_MISMATCH","lf_adapter_invocations[0].adapter_code","unexpected adapter")
            if inv.get("assurance_revision")!="v2": err(errors,"ASSURANCE_REVISION_MISMATCH","lf_adapter_invocations[0].assurance_revision","must be v2")
            if inv.get("activation_source")!="ROUTER": err(errors,"BLOCK_UNBOUND_ADAPTER_INVOCATION","lf_adapter_invocations[0].activation_source","only ROUTER is valid")
            if not text(inv.get("binding_ref")): err(errors,"BLOCK_UNBOUND_ADAPTER_INVOCATION","lf_adapter_invocations[0].binding_ref","Router binding_ref required")
            for f in ["invocation_id","profile_id","target_ref"]:
                if not text(inv.get(f)): err(errors,"INVOCATION_FIELD_INVALID",f"lf_adapter_invocations[0].{f}","non-empty string required")
            if inv.get("capsule_ref")!="runtime/runtime_capsule.yaml": err(errors,"CAPSULE_REF_INVALID","lf_adapter_invocations[0].capsule_ref","unexpected capsule")
            cc=inv.get("capsule_char_count")
            if not isinstance(cc,int) or isinstance(cc,bool) or cc<1 or cc>MAX_CAPSULE_CHARS:
                err(errors,"BLOCK_CONTEXT_BUDGET_EXCEEDED","lf_adapter_invocations[0].capsule_char_count",f"must be 1..{MAX_CAPSULE_CHARS}")
            refs=inv.get("source_refs")
            if not isinstance(refs,list) or not refs or len(refs)>8 or len(refs)!=len(set(refs)) or not all(text(x) for x in refs):
                err(errors,"SOURCE_REFS_INVALID","lf_adapter_invocations[0].source_refs","1..8 unique non-empty refs required")
            if inv.get("verdict") not in {"APPLIED","BLOCKED"}: err(errors,"INVOCATION_VERDICT_INVALID","lf_adapter_invocations[0].verdict","APPLIED or BLOCKED required")

    binding=payload.get("shell_binding")
    if applicable is True and not isinstance(binding,dict):
        err(errors,"SHELL_BINDING_REQUIRED","shell_binding","binding required when applicable")
    if isinstance(binding,dict):
        state=binding.get("binding_state")
        if state not in ALLOWED_STATES: err(errors,"BINDING_STATE_INVALID","shell_binding.binding_state","unsupported state")
        protected={x.get("target_id") for x in binding.get("protected_targets",[]) if isinstance(x,dict) and x.get("classification")=="SHELL_LOCKED"}
        for i,d in enumerate(binding.get("profile_delta",[]) if isinstance(binding.get("profile_delta"),list) else []):
            if isinstance(d,dict) and d.get("target_id") in protected and d.get("execution_allowed") is True:
                err(errors,"SHELL_LOCKED_EXECUTION","shell_binding.profile_delta[%d].execution_allowed"%i,"SHELL_LOCKED target cannot execute")

    if payload.get("adapter_llm_call_count") not in {None,0}:
        err(errors,"SECOND_LLM_CALL_FORBIDDEN","adapter_llm_call_count","adapter must not perform a separate LLM call")

    return {"valid":not errors,"errors":errors,"blocking_codes":sorted({e["code"] for e in errors if e["code"].startswith("BLOCK_") or e["code"] in {"SHELL_LOCKED_EXECUTION","SECOND_LLM_CALL_FORBIDDEN"}})}

if __name__=="__main__":
    try:
        print(json.dumps(validate(json.load(sys.stdin)),ensure_ascii=False,indent=2))
    except Exception as ex:
        print(json.dumps({"valid":False,"errors":[{"code":"MALFORMED_INPUT","path":"$","message":str(ex)}],"blocking_codes":["MALFORMED_INPUT"]},ensure_ascii=False,indent=2))
        sys.exit(1)
