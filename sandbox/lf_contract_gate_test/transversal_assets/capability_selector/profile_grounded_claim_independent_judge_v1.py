"""Second-pass, producer-independent semantic judge for restricted causal claims.

Recomputes literal propositions from raw frozen observations and hypothesis
predictions. Does not import or trust the method-result compiler. Does not
qualify unrestricted natural-language explanations or full independent assurance.
"""
from __future__ import annotations
import hashlib,json
from typing import Any

def digest(x: Any) -> str:
    return hashlib.sha256(json.dumps(x,sort_keys=True,ensure_ascii=False,
       separators=(",",":"),allow_nan=False).encode("utf-8")).hexdigest()

def audit_grounded_rationale(case: dict[str,Any], answer: dict[str,Any]) -> dict[str,Any]:
    fail={"schema":"PE_INDEPENDENT_CONSTRAINED_SEMANTIC_AUDIT_V1","status":"BLOCKED",
          "publication_authorized":False,"cutover_eligible":False}
    if not isinstance(case,dict) or not isinstance(answer,dict):
        return {**fail,"reason":"BAD_REQUEST"}
    cid=case.get("case_id")
    if answer.get("case_id")!=cid or answer.get("status")!="TEST_ONLY_EVIDENCE_COMPILED":
        return {**fail,"reason":"WRONG_SUBJECT_OR_UNVERIFIED_COMPILATION"}
    if answer.get("causality_proven") is not False:
        return {**fail,"reason":"CAUSALITY_OVERCLAIM"}
    hs=case.get("hypotheses");observations=case.get("observations")
    if not isinstance(hs,list) or not isinstance(observations,list):
        return {**fail,"reason":"BAD_SOURCE_SCHEMA"}
    trusted={};untrusted={}
    for obs in observations:
        if not isinstance(obs,dict) or type(obs.get("observed")) is not bool:
            return {**fail,"reason":"OBSERVATION_SCHEMA_INVALID"}
        probe=obs.get("probe_id")
        if not isinstance(probe,str) or probe in trusted or probe in untrusted:
            return {**fail,"reason":"DUPLICATE_PROBE"}
        authority={"case_id":cid,"probe_id":probe,"observed":obs["observed"],"source":"fixture-primary-readback"}
        if obs.get("evidence_ref")=="fixture-verified://"+digest(authority):
            trusted[probe]=obs
        else:
            untrusted[probe]=obs
    hypothesis={}
    for h in hs:
        hid=h.get("id");pr=h.get("predictions")
        if not isinstance(hid,str) or not isinstance(pr,dict) or hid in hypothesis:
            return {**fail,"reason":"BAD_HYPOTHESIS"}
        hypothesis[hid]=pr
    falsified={}
    for hid,pr in hypothesis.items():
        falsified[hid]=sorted(k for k,v in pr.items() if k in trusted and trusted[k]["observed"]!=v)
    rejects=sorted(h for h,v in falsified.items() if v)
    survivors=sorted(set(hypothesis)-set(rejects))
    missing={h:sorted(k for k in hypothesis[h] if k not in trusted) for h in survivors}
    action=("COLLECT_MORE_EVIDENCE" if len(survivors)!=1 or any(missing.values())
            else "INVESTIGATE_"+survivors[0])
    if (answer.get("recommended_action")!=action
       or answer.get("falsified_hypotheses")!=rejects):
        return {**fail,"reason":"DECISION_OR_FALSIFICATION_CONTRADICTION"}
    permitted={}
    for p,e in trusted.items():
        permitted["OBS:"+p]={
            "claim_id":"OBS:"+p,"type":"OBSERVATION","probe_id":p,"observed":e["observed"],
            "text":f"Verificación {p} = {str(e['observed']).lower()}",
            "evidence_refs":[e["evidence_ref"]]}
    for hid,probes in falsified.items():
        for p in probes:
            e=trusted[p]
            permitted["REFUTE:"+hid+":"+p]={
               "claim_id":"REFUTE:"+hid+":"+p,"type":"FALSIFICATION",
               "hypothesis_id":hid,"probe_id":p,
               "text":f"{hid} queda contradicha por {p} = {str(e['observed']).lower()}",
               "evidence_refs":[e["evidence_ref"]]}
    for hid in survivors:
        for p in missing[hid]:
            permitted["MISSING:"+hid+":"+p]={
                "claim_id":"MISSING:"+hid+":"+p,"type":"EVIDENCE_GAP",
                "hypothesis_id":hid,"probe_id":p,
                "text":f"Falta evidencia verificable de {p} para {hid}",
                "evidence_refs":["verifier://"+digest({
                    "case_id":cid,"hypothesis_id":hid,"probe_id":p,
                    "available_ref":untrusted.get(p,{}).get("evidence_ref"),
                    "verified":False})]}
    chosen=answer.get("claims")
    if not isinstance(chosen,list) or not chosen:
        return {**fail,"reason":"CLAIM_LIST_EMPTY"}
    ids=[]
    for c in chosen:
        if not isinstance(c,dict) or c.get("claim_id") not in permitted:
            return {**fail,"reason":"UNKNOWN_CLAIM"}
        ids.append(c["claim_id"])
        if c!=permitted[c["claim_id"]]:
            return {**fail,"reason":"PROPOSITION_OR_REFERENCE_MISMATCH"}
    if len(set(ids))!=len(ids):
        return {**fail,"reason":"DUPLICATED_CLAIM"}
    mandatory={k for k,v in permitted.items() if v["type"] in ("FALSIFICATION","EVIDENCE_GAP")}
    if not mandatory.issubset(set(ids)):
        return {**fail,"reason":"MISSING_DECISIVE_COUNTEREVIDENCE_OR_GAP"}
    text="; ".join(c["text"]+" ["+", ".join(c["evidence_refs"])+"]" for c in chosen)
    text+=". "+("Se requiere más evidencia." if action=="COLLECT_MORE_EVIDENCE"
                else "Priorizar investigación de "+survivors[0]+".")
    text+=" No se ha demostrado causalidad."
    if text!=answer.get("final_text"):
        return {**fail,"reason":"NARRATIVE_NOT_ENTAILED_BY_STRUCTURED_CLAIMS"}
    return {**fail,"status":"TEST_ONLY_CONSTRAINED_SEMANTIC_PASS",
            "reason":"ALL_RESTRICTED_CLAIMS_ENTAILED_BY_SEPARATELY_READ_EVIDENCE",
            "claim_count":len(chosen),"external_independent_assurance":"NOT_EXECUTED"}
