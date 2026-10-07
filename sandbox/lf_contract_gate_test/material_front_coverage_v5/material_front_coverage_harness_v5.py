from __future__ import annotations
import copy, hashlib, json
from typing import Any

PASS="MATERIAL_FRONT_COVERAGE_PASS"
BLOCK="MATERIAL_FRONT_COVERAGE_BLOCKED"
RETURN="RETURN_TO_EVIDENCE_ACQUISITION"
SIX_AXES=("root_cause","repair_topology","blast_radius","acceptance_criteria","rollback_recovery","terminality_lifecycle")
MANDATORY={
    "write_capable":"AGENT_ACTION_SIDE_EFFECT",
    "ai_terminal_claim":"AGENT_EVAL_INTEGRITY",
    "identity_change":"AGENT_IDENTITY_PRIVILEGE",
}
def canon_sha(v:Any)->str:
    raw=json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()
    return hashlib.sha256(raw).hexdigest()
def _walk_no_expected(v:Any,path="$"):
    if isinstance(v,dict):
        for k,x in v.items():
            kl=str(k).lower()
            if kl.startswith("expected") or kl in {"reason","reason_code","terminal_status","pass"}:
                raise ValueError(f"INJECTED_EXPECTATION_FIELD:{path}.{k}")
            _walk_no_expected(x,f"{path}.{k}")
    elif isinstance(v,list):
        for i,x in enumerate(v): _walk_no_expected(x,f"{path}[{i}]")
def group_id(s:dict)->str:
    vals=[s.get("provider"),s.get("authority_ref"),s.get("source_subject_digest")]
    if not all(isinstance(x,str) and x for x in vals): return ""
    return canon_sha(vals)
def select_modules(signals:list[dict], required_flags:set[str]):
    scores={}; groups={}
    for s in signals:
        if not s.get("current",False) or not s.get("subject_bound",False) or not s.get("evidence_ref"):
            return None, ["TRIGGER_STRENGTH_UNRESOLVED"]
        module=s.get("module")
        if not isinstance(module,str) or not module: continue
        direct=s.get("directness")
        if direct=="DIRECT":
            scores[module]=scores.get(module,0)+2
        elif direct=="INDIRECT":
            g=group_id(s)
            if not g: return None,["TRIGGER_STRENGTH_UNRESOLVED"]
            groups.setdefault(module,set()).add(g)
        else:
            return None,["TRIGGER_STRENGTH_UNRESOLVED"]
    for m,gs in groups.items(): scores[m]=scores.get(m,0)+len(gs)
    selected={m for m,score in scores.items() if score>=2}
    for f in required_flags:
        m=MANDATORY.get(f)
        if m: selected.add(m)
    return selected,[]
def provider_ok(module:str, receipt:dict|None, subject_revision:str):
    if not isinstance(receipt,dict): return False,"REQUIRED_PROVIDER_RECEIPT_MISSING"
    if receipt.get("verification_state")!="VERIFIED": return False,"PROVIDER_RECEIPT_NOT_VERIFIED"
    if receipt.get("subject_revision")!=subject_revision: return False,"PROVIDER_SUBJECT_REVISION_MISMATCH"
    if receipt.get("scope_supported") is not True: return False,"PROVIDER_SCOPE_UNPROVEN"
    if not receipt.get("evidence_refs"): return False,"PROVIDER_EVIDENCE_MISSING"
    if not receipt.get("capability_code"): return False,"PROVIDER_IDENTITY_MISSING"
    return True,None
def classify_front(front:dict):
    if front.get("applicable") is False:
        if front.get("na_proof_ref") and front.get("evidence_refs"): return "N_A_PROVED",None
        return None,"N_A_WITHOUT_EVIDENCE"
    refs=front.get("evidence_refs")
    if not isinstance(refs,list) or not refs: return None,"FRONT_EVIDENCE_REFS_MISSING"
    axes=front.get("low_risk_axes")
    if isinstance(axes,dict):
        vals=[axes.get(a) for a in SIX_AXES]
        if "CAN_CHANGE" in vals: return "MATERIAL",None
        if "UNRESOLVED" in vals: return None,"LOW_RISK_AXIS_UNRESOLVED"
        if vals==["NO_CHANGE_PROVEN"]*6: return "LOW_RISK_CLOSED",None
    if front.get("material_signal") is True: return "MATERIAL",None
    if front.get("na_proof_ref"): return "N_A_PROVED",None
    return None,"FRONT_CLASSIFICATION_UNRESOLVED"
def challenger_ok(ch:dict|None, fixture:dict):
    if not isinstance(ch,dict): return False,"HOSTILE_CHALLENGER_NOT_RUN"
    if ch.get("execution_id")==fixture.get("producer_execution_id"): return False,"HOSTILE_CHALLENGER_NOT_INDEPENDENT"
    if ch.get("executor_identity")==fixture.get("producer_identity"): return False,"HOSTILE_CHALLENGER_NOT_INDEPENDENT"
    if ch.get("subject_revision")!=fixture.get("subject_revision"): return False,"CHALLENGER_SUBJECT_REVISION_MISMATCH"
    receipt=ch.get("independence_receipt")
    if not isinstance(receipt,dict) or receipt.get("verification_state")!="VERIFIED": return False,"INDEPENDENT_ASSURANCE_CHAIN_INCOMPLETE"
    measurement=receipt.get("measurement")
    if not isinstance(measurement,dict) or measurement.get("state")!="INDEPENDENT": return False,"HOSTILE_CHALLENGER_NOT_INDEPENDENT"
    if receipt.get("measurement_digest")!=canon_sha(measurement): return False,"INDEPENDENT_ASSURANCE_RECEIPT_DIGEST_INVALID"
    if receipt.get("provider_bound") is not True: return False,"INDEPENDENT_ASSURANCE_PROVIDER_UNBOUND"
    return True,None
def evaluate(fixture:dict)->dict:
    try: _walk_no_expected(fixture)
    except ValueError as e: return {"status":BLOCK,"reasons":[str(e)]}
    revision=fixture.get("subject_revision")
    if not revision or not fixture.get("front_catalog_version") or not fixture.get("selection_policy_version"):
        return {"status":BLOCK,"reasons":["STRUCTURAL_INPUT_MISSING"]}
    structural=list(fixture.get("structural_failures") or [])
    if structural: return {"status":BLOCK,"reasons":sorted(set(structural))}
    evidence_state=fixture.get("evidence_state","CURRENT")
    if evidence_state in {"MISSING","UNRESOLVED","STALE","CONTRADICTED"}:
        return {"status":RETURN,"reasons":["EVIDENCE_STATE_"+evidence_state]}
    rounds=fixture.get("signal_rounds")
    if not isinstance(rounds,list) or not rounds: return {"status":BLOCK,"reasons":["SIGNAL_ROUNDS_MISSING"]}
    max_rounds=fixture.get("max_reselection_rounds")
    if not isinstance(max_rounds,int) or max_rounds<1: return {"status":BLOCK,"reasons":["SEARCH_BUDGET_MISSING"]}
    reselection_count=len(rounds)
    selected,reasons=select_modules(rounds[-1],set(fixture.get("required_flags") or []))
    if reasons: return {"status":RETURN,"reasons":reasons,"reselection_count":reselection_count}
    if fixture.get("needs_another_reselection") is True and reselection_count>=max_rounds:
        return {"status":BLOCK,"reasons":["NON_CONVERGENT_COVERAGE_BUDGET_EXHAUSTED"],"reselection_count":reselection_count}
    if fixture.get("converged") is not True and reselection_count>=max_rounds:
        return {"status":BLOCK,"reasons":["NON_CONVERGENT_COVERAGE_BUDGET_EXHAUSTED"],"reselection_count":reselection_count}
    receipts=fixture.get("module_receipts") or {}
    for m in sorted(selected):
        ok,why=provider_ok(m,receipts.get(m),revision)
        if not ok: return {"status":BLOCK,"reasons":[why+":"+m],"selected_modules":sorted(selected),"reselection_count":reselection_count}
    fronts=fixture.get("fronts")
    if not isinstance(fronts,list) or not fronts: return {"status":BLOCK,"reasons":["FRONT_LEDGER_INCOMPLETE"]}
    classifications={}
    for f in fronts:
        code=f.get("code")
        if not code: return {"status":BLOCK,"reasons":["FRONT_ID_MISSING"]}
        cls,why=classify_front(f)
        if why=="LOW_RISK_AXIS_UNRESOLVED": return {"status":RETURN,"reasons":[why+":"+code]}
        if why: return {"status":BLOCK,"reasons":[why+":"+code]}
        if cls=="MATERIAL" and f.get("deep_inspection_complete") is not True:
            return {"status":BLOCK,"reasons":["MATERIAL_FRONT_NOT_DEEP_INSPECTED:"+code]}
        if f.get("orphan_required") is True:
            return {"status":BLOCK,"reasons":["ORPHAN_METHOD_UNPROVEN:"+code]}
        classifications[code]=cls
    if fixture.get("closure_claim_requested",True):
        ok,why=challenger_ok(fixture.get("challenger"),fixture)
        if not ok: return {"status":BLOCK,"reasons":[why],"classifications":classifications}
    if fixture.get("unconsumed_reinspection_triggers"):
        return {"status":BLOCK,"reasons":["REINSPECTION_TRIGGER_NOT_CONSUMED"],"classifications":classifications}
    return {"status":PASS,"reasons":[],"classifications":classifications,
            "selected_modules":sorted(selected),"reselection_count":reselection_count,"closure_allowed":True}
