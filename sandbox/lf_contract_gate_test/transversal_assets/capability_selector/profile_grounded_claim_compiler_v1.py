"""Profile Evolution: independently reconstructed, source-grounded causal explanation.

A method's own 'VERIFIED' claim is NOT trusted. The judge reconstructs
each proposition from raw observations, literal predictions and receipt refs.
Supports only a restricted fact language; free-text causal inferences remain
unqualified. TEST_NON_AUTHORITY exclusively.
"""
from __future__ import annotations
import hashlib
import json
from typing import Any, Callable

def _sha(x: Any) -> str:
    return hashlib.sha256(json.dumps(x, ensure_ascii=False,sort_keys=True,
             separators=(",",":"),allow_nan=False).encode("utf-8")).hexdigest()

def _good_obs(case_id: str, e: dict[str, Any]) -> bool:
    if not isinstance(e,dict) or type(e.get("observed")) is not bool:
        return False
    proof={"case_id":case_id,"probe_id":e.get("probe_id"),
           "observed":e["observed"],"source":"fixture-primary-readback"}
    return e.get("evidence_ref")=="fixture-verified://"+_sha(proof)

def _block(code: str):
    return {"schema":"PE_EVIDENCE_GROUNDED_EXPLANATION_V1","status":"BLOCKED",
            "blocking_code":code,"claims":[],"final_text":None,
            "causality_proven":False,"production_authorized":False,
            "cutover_eligible":False}

def independently_compile_grounded_answer(
    case: dict[str, Any], method_plan: dict[str, Any],
    *,
    proposed_claim_ids: list[str] | None = None,
    verify_method_receipt: Callable[[dict[str, Any]], bool] | None = None,
) -> dict[str, Any]:
    """Build attestable claims directly from evidence; never from model prose.

    No claim can cite a matching-looking but unauthenticated source. A
    falsified hypothesis is not equivalent to proof the survivor caused it.
    """
    if not isinstance(case,dict) or not isinstance(method_plan,dict):
        return _block("INPUT_INVALID")
    cid=case.get("case_id")
    hs=case.get("hypotheses");obs=case.get("observations")
    if not isinstance(cid,str) or not cid or not isinstance(hs,list) or not 2<=len(hs)<=8 or not isinstance(obs,list):
        return _block("CASE_CONTRACT_INVALID")
    if method_plan.get("status")!="TEST_ONLY_RECONCILED" or method_plan.get("causality_proven") is not False:
        return _block("METHOD_PLAN_NOT_GOVERNED")
    if not isinstance(method_plan.get("method_receipt_sha256"),str) or len(method_plan["method_receipt_sha256"])!=64:
        return _block("METHOD_RECEIPT_MISSING")
    if not callable(verify_method_receipt):
        return _block("EXTERNAL_METHOD_RECEIPT_VERIFIER_REQUIRED")
    try:
        if verify_method_receipt(method_plan) is not True:
            return _block("METHOD_RECEIPT_NOT_INDEPENDENTLY_VERIFIED")
    except Exception:
        return _block("METHOD_RECEIPT_NOT_INDEPENDENTLY_VERIFIED")
    if not isinstance(method_plan.get("falsified_hypotheses"),list):
        return _block("METHOD_VERDICT_INVALID")
    ids=set();pred={}
    for h in hs:
        if not isinstance(h,dict) or not isinstance(h.get("id"),str) or h["id"] in ids or not isinstance(h.get("predictions"),dict):
            return _block("HYPOTHESES_INVALID")
        if not h["predictions"] or any(type(v) is not bool or not isinstance(k,str) for k,v in h["predictions"].items()):
            return _block("PREDICTION_INVALID")
        ids.add(h["id"]);pred[h["id"]]=h["predictions"]
    byprobe={};verified={}
    for e in obs:
        if not isinstance(e,dict) or not isinstance(e.get("probe_id"),str) or e["probe_id"] in byprobe:
            return _block("PROBE_INVALID_OR_DUPLICATED")
        byprobe[e["probe_id"]]=e
        if _good_obs(cid,e):verified[e["probe_id"]]=e
    if not verified:return _block("NO_VERIFIED_OBSERVATIONS")
    falsified={}
    for hid,pr in pred.items():
        falsified[hid]=sorted(k for k,v in pr.items() if k in verified and verified[k]["observed"]!=v)
    rejected=sorted(x for x,v in falsified.items() if v)
    survivors=[hid for hid in sorted(ids) if hid not in rejected]
    missing={hid:sorted(k for k in pred[hid] if k not in verified) for hid in survivors}
    action=("COLLECT_MORE_EVIDENCE" if len(survivors)!=1 or any(missing.values())
            else "INVESTIGATE_"+survivors[0])
    if (sorted(method_plan["falsified_hypotheses"])!=rejected
        or method_plan.get("recommended_action")!=action):
        return _block("METHOD_RESULT_CONTRADICTS_INDEPENDENT_READBACK")
    claims=[]
    for probe in sorted(verified):
        e=verified[probe]
        claims.append({"claim_id":"OBS:"+probe,"type":"OBSERVATION",
            "probe_id":probe,"observed":e["observed"],
            "text":f"Verificación {probe} = {str(e['observed']).lower()}",
            "evidence_refs":[e["evidence_ref"]]})
    for hid in sorted(falsified):
        for probe in falsified[hid]:
            e=verified[probe]
            claims.append({"claim_id":"REFUTE:"+hid+":"+probe,"type":"FALSIFICATION",
                "hypothesis_id":hid,"probe_id":probe,
                "text":f"{hid} queda contradicha por {probe} = {str(e['observed']).lower()}",
                "evidence_refs":[e["evidence_ref"]]})
    for hid in survivors:
        for probe in missing[hid]:
            claims.append({"claim_id":"MISSING:"+hid+":"+probe,"type":"EVIDENCE_GAP",
                "hypothesis_id":hid,"probe_id":probe,
                "text":f"Falta evidencia verificable de {probe} para {hid}",
                "evidence_refs":["verifier://"+_sha({
                    "case_id":cid,"hypothesis_id":hid,"probe_id":probe,
                    "available_ref":byprobe.get(probe,{}).get("evidence_ref"),
                    "verified":False
                })]})
    required_ids=set(x["claim_id"] for x in claims)
    if proposed_claim_ids is not None:
        if not isinstance(proposed_claim_ids,list) or len(set(proposed_claim_ids))!=len(proposed_claim_ids):
            return _block("MODEL_CLAIMS_INVALID")
        if not set(proposed_claim_ids).issubset(required_ids):
            return _block("MODEL_REFERENCES_UNSUPPORTED_CLAIMS")
        # A model may choose relevant claims, but may not omit the decisive
        # counterevidence/gap and still get a "verified" explanation.
        decisive={x["claim_id"] for x in claims if x["type"] in ("FALSIFICATION","EVIDENCE_GAP")}
        if not decisive.issubset(set(proposed_claim_ids)):
            return _block("MODEL_OMITS_DECISIVE_EVIDENCE")
        selected=[x for x in claims if x["claim_id"] in set(proposed_claim_ids)]
    else:
        selected=claims
    if not selected:return _block("NO_EVIDENCE_CLAIMS")
    narrative="; ".join(c["text"]+" ["+", ".join(c["evidence_refs"])+"]" for c in selected)
    narrative+=". "+("Se requiere más evidencia." if action=="COLLECT_MORE_EVIDENCE"
                     else "Priorizar investigación de "+survivors[0]+".")
    narrative+=" No se ha demostrado causalidad."
    return {"schema":"PE_EVIDENCE_GROUNDED_EXPLANATION_V1",
        "status":"TEST_ONLY_EVIDENCE_COMPILED",
        "case_id":cid,"method_receipt_sha256":method_plan["method_receipt_sha256"],
        "recommended_action":action,"falsified_hypotheses":rejected,
        "claims":selected,"final_text":narrative,
        "causality_proven":False,"source_verifier_kind":"INDEPENDENT_DETERMINISTIC_FIXTURE_HASH_READBACK",
        "independent_semantic_assurance":"NOT_EXECUTED",
        "production_authorized":False,"cutover_eligible":False}
