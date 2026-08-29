#!/usr/bin/env python3
import json, re, sys

ADAPTER="ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF"
MAX_CAPSULE_CHARS=1600
ALLOWED_STATES={"BOUND","BOUND_WITH_APPROVED_FALLBACK","RETURN_TO_ORCHESTRATOR_MISSING_SOURCE","BLOCKED_SOURCE_CONFLICT","BLOCKED_PROJECT_UNRESOLVED"}
GOV_SECTIONS={"APPLICABILITY_READINESS","SOURCE_AUTHORITY_PROVENANCE","FRESHNESS_INVALIDATION","NEGATIVE_REQUIREMENTS","CONFLICT_PRECEDENCE"}
GOV_DECISIONS={"PASS","PARTIAL","NEGATIVE_CONFIRMED","N/A"}
SHA256=re.compile(r"^[0-9a-f]{64}$")

def err(e,c,p,m): e.append({"code":c,"path":p,"message":m})
def text(v): return isinstance(v,str) and bool(v.strip())
def result(e): return {"valid":not e,"errors":e,"blocking_codes":sorted({x["code"] for x in e if x["code"].startswith("BLOCK_") or x["code"] in {"CROSS_PROJECT_TOKEN_CONTAMINATION","CANONICAL_FALLBACK_FORBIDDEN","SECOND_LLM_CALL_FORBIDDEN"}})}

def validate_governance(payload,e,applicable,invocation_verdict):
    if applicable is not True: return
    gov_app=payload.get("input_governance_applicable")
    if not isinstance(gov_app,bool): err(e,"BLOCK_INPUT_GOVERNANCE_APPLICABILITY","input_governance_applicable","boolean required when adapter applies"); return
    r=payload.get("governance_receipt")
    if not isinstance(r,dict): err(e,"BLOCK_INPUT_GOVERNANCE_RECEIPT","governance_receipt","governance receipt required"); return
    for f in ["governance_agent_used","governance_version","sections_consumed","source_refs","snapshot_hash","decision","gap_or_na","timestamp"]:
        if f not in r: err(e,"BLOCK_INPUT_GOVERNANCE_RECEIPT",f"governance_receipt.{f}","required")
    used=r.get("governance_agent_used"); sections=r.get("sections_consumed"); refs=r.get("source_refs"); decision=r.get("decision"); snapshot=r.get("snapshot_hash")
    if not isinstance(used,bool): err(e,"BLOCK_INPUT_GOVERNANCE_RECEIPT","governance_receipt.governance_agent_used","boolean required")
    if not isinstance(sections,list) or len(sections)!=len(set(sections)) or any(x not in GOV_SECTIONS for x in sections): err(e,"BLOCK_INPUT_GOVERNANCE_SECTIONS","governance_receipt.sections_consumed","unique allowlisted sections required")
    if decision not in GOV_DECISIONS: err(e,"BLOCK_INPUT_GOVERNANCE_DECISION","governance_receipt.decision","unsupported decision")
    if not text(r.get("gap_or_na")) or not text(r.get("timestamp")): err(e,"BLOCK_INPUT_GOVERNANCE_RECEIPT","governance_receipt","gap_or_na and timestamp required")
    if gov_app:
        if used is not True: err(e,"BLOCK_INPUT_GOVERNANCE_AGENT","governance_receipt.governance_agent_used","must be true when governance applies")
        if not text(r.get("governance_version")) or r.get("governance_version")=="N/A": err(e,"BLOCK_INPUT_GOVERNANCE_VERSION","governance_receipt.governance_version","resolved live revision required")
        if not isinstance(sections,list) or not sections: err(e,"BLOCK_INPUT_GOVERNANCE_SECTIONS","governance_receipt.sections_consumed","at least one section required")
        if not isinstance(refs,list) or not refs or len(refs)!=len(set(refs)) or not all(text(x) for x in refs): err(e,"BLOCK_INPUT_GOVERNANCE_SOURCE_REFS","governance_receipt.source_refs","governed source refs required")
        if not text(snapshot) or not SHA256.fullmatch(snapshot): err(e,"BLOCK_INPUT_GOVERNANCE_SNAPSHOT","governance_receipt.snapshot_hash","64-char lowercase sha256 required")
        if invocation_verdict=="APPLIED" and decision!="PASS": err(e,"BLOCK_INPUT_GOVERNANCE_DECISION","governance_receipt.decision","APPLIED requires PASS")
    else:
        if used is not False or decision!="N/A": err(e,"BLOCK_INPUT_GOVERNANCE_NA","governance_receipt","N/A requires agent_used=false and decision=N/A")
        if sections not in ([],None) or refs not in ([],None) or snapshot!="N/A": err(e,"BLOCK_INPUT_GOVERNANCE_NA","governance_receipt","N/A receipt must not claim sections/sources/snapshot")

def validate(payload):
    e=[]
    if not isinstance(payload,dict): err(e,"NOT_OBJECT","$","payload must be object"); return result(e)
    applicable=payload.get("applicable")
    if not isinstance(applicable,bool): err(e,"APPLICABLE_REQUIRED","applicable","boolean required")
    invs=payload.get("lf_adapter_invocations")
    if not isinstance(invs,list): err(e,"INVOCATIONS_REQUIRED","lf_adapter_invocations","array required"); invs=[]
    if applicable is True and len(invs)==0: err(e,"BLOCK_MISSING_ADAPTER_INVOCATION","lf_adapter_invocations","applicable adapter requires exactly one invocation")
    if len(invs)>1: err(e,"BLOCK_DUPLICATE_ADAPTER_INVOCATION","lf_adapter_invocations","duplicate invocation")
    invocation_verdict=None
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
            invocation_verdict=inv.get("verdict")
            if invocation_verdict not in {"APPLIED","BLOCKED"}: err(e,"INVOCATION_VERDICT_INVALID","lf_adapter_invocations[0].verdict","APPLIED or BLOCKED")
    validate_governance(payload,e,applicable,invocation_verdict)
    b=payload.get("project_brand_mockup_binding")
    if applicable is True and not isinstance(b,dict): err(e,"BINDING_REQUIRED","project_brand_mockup_binding","binding required when applicable")
    if isinstance(b,dict):
        if b.get("binding_state") not in ALLOWED_STATES: err(e,"BINDING_STATE_INVALID","project_brand_mockup_binding.binding_state","unsupported state")
        project=b.get("project"); project_code=project.get("project_code") if isinstance(project,dict) else None
        if not text(project_code): err(e,"PROJECT_UNRESOLVED","project_brand_mockup_binding.project.project_code","project required")
        refs=b.get("source_refs")
        if not isinstance(refs,list) or not refs or len(refs)!=len(set(refs)): err(e,"SOURCE_REFS_INVALID","project_brand_mockup_binding.source_refs","unique source refs required")
        token_projects=payload.get("token_project_codes",[])
        if token_projects and (not isinstance(token_projects,list) or any(x!=project_code for x in token_projects)): err(e,"CROSS_PROJECT_TOKEN_CONTAMINATION","token_project_codes","all tokens must belong to resolved project")
        fallback=b.get("fallback_mode")
        if fallback not in {"NONE","APPROVED_FALLBACK","PROPOSED_NOT_CANONICAL"}: err(e,"FALLBACK_MODE_INVALID","project_brand_mockup_binding.fallback_mode","unsupported fallback")
        if fallback!="NONE" and payload.get("fallback_presented_as_canonical") is True: err(e,"CANONICAL_FALLBACK_FORBIDDEN","fallback_presented_as_canonical","fallback cannot be canonical")
        screen_id=project.get("screen_id") if isinstance(project,dict) else None
        if text(screen_id) and not b.get("screen_spec_refs") and b.get("binding_state") in {"BOUND","BOUND_WITH_APPROVED_FALLBACK"}: err(e,"SCREEN_SPEC_REQUIRED","project_brand_mockup_binding.screen_spec_refs","screen-based binding requires screen spec refs")
        qa=b.get("qa_requirements")
        if not isinstance(qa,list) or not qa: err(e,"QA_REQUIRED","project_brand_mockup_binding.qa_requirements","QA requirements required")
    if payload.get("adapter_llm_call_count") not in {None,0}: err(e,"SECOND_LLM_CALL_FORBIDDEN","adapter_llm_call_count","adapter must not perform separate LLM call")
    return result(e)

if __name__=="__main__":
    try: print(json.dumps(validate(json.load(sys.stdin)),ensure_ascii=False,indent=2))
    except Exception as ex:
        print(json.dumps({"valid":False,"errors":[{"code":"MALFORMED_INPUT","path":"$","message":str(ex)}],"blocking_codes":["MALFORMED_INPUT"]},ensure_ascii=False,indent=2)); sys.exit(1)
