#!/usr/bin/env python3
"""Deterministic hardening controls for Creating Integral User Stories v1.

Candidate-only controls. They fail closed on malformed evidence, never mutate
classifications, never remove graders automatically, and never authorize P0-5
or production.
"""
from __future__ import annotations
import hashlib
import json
import math
import re
from difflib import SequenceMatcher
from itertools import product
from typing import Any

SHA256_RE=re.compile(r"^[0-9a-f]{64}$")
EKB_RELATIONS={
    "EKB-P0-003":"BLOCKED",
    "EKB-P0-014":"BLOCKED_OR_REVIEW",
    "EKB-P0-016":"BLOCKED",
    "EKB-P0-017":"BLOCKED",
    "EKB-P0-020":"BLOCKED",
    "EKB-P0-021":"BLOCKED",
    "EKB-P0-022":"BLOCKED",
    "AUD-020":"BLOCKED",
    "AUD-030":"BLOCKED",
}

def canonical_sha(value:Any)->str:
    raw=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()

def ekb_gate(results:Any)->dict[str,Any]:
    if not isinstance(results,dict):
        return {"result":"BLOCKED","blocking_assertions":["EKB_RESULTS_NOT_OBJECT"],"auto_acceptance_allowed":False}
    allowed={"BLOCKED":{"BLOCKED","FAIL"},"BLOCKED_OR_REVIEW":{"BLOCKED","FAIL","HUMAN_REVIEW_REQUIRED"}}
    missing=sorted(code for code in EKB_RELATIONS if code not in results)
    incompatible=sorted(code for code,expected in EKB_RELATIONS.items() if code in results and results[code] not in allowed[expected])
    return {
        "result":"PASS_WITH_EVIDENCE" if not missing and not incompatible else "BLOCKED",
        "missing":missing,
        "incompatible":incompatible,
        "registry_sha256":canonical_sha(EKB_RELATIONS),
        "auto_acceptance_allowed":False,
    }

def _phi(left:list[int],right:list[int])->float|None:
    if len(left)!=len(right) or not left:
        return None
    if left==right and len(set(left))==1:
        return 1.0
    ml=sum(left)/len(left); mr=sum(right)/len(right)
    vl=sum((x-ml)**2 for x in left); vr=sum((x-mr)**2 for x in right)
    if not vl or not vr:
        return 0.0
    return sum((x-ml)*(y-mr) for x,y in zip(left,right))/math.sqrt(vl*vr)

def grader_audit(payload:Any)->dict[str,Any]:
    failures=[]
    if not isinstance(payload,dict):
        return {"result":"BLOCKED","blocking_assertions":["GRADER_PAYLOAD_NOT_OBJECT"],"automatic_grader_removal_allowed":False}
    cases=payload.get("cases") if isinstance(payload.get("cases"),list) else []
    graders=payload.get("graders") if isinstance(payload.get("graders"),list) else []
    ids=[str(c.get("case_id") or "") for c in cases if isinstance(c,dict)]
    if len(cases)<3 or len(ids)!=len(cases) or any(not x for x in ids) or len(set(ids))!=len(ids):
        failures.append("CASE_UNIVERSE_INVALID")
    if len(graders)<2:
        failures.append("INSUFFICIENT_GRADERS")
    expected={str(c.get("case_id")):c.get("expected") for c in cases if isinstance(c,dict) and c.get("case_id")}
    vectors={}; families={}; metadata={}
    for grader in graders:
        if not isinstance(grader,dict):
            failures.append("GRADER_RECORD_INVALID"); continue
        gid=str(grader.get("grader_id") or "")
        family=str(grader.get("family") or "")
        model_id=str(grader.get("model_id") or "")
        model_version=str(grader.get("model_version") or "")
        prompt_sha=str(grader.get("prompt_sha256") or "")
        config_sha=str(grader.get("configuration_sha256") or "")
        decisions=grader.get("decisions") if isinstance(grader.get("decisions"),dict) else {}
        if not gid or not family or not model_id or not model_version or not SHA256_RE.fullmatch(prompt_sha) or not SHA256_RE.fullmatch(config_sha):
            failures.append(f"GRADER_IDENTITY_INCOMPLETE:{gid or 'UNKNOWN'}"); continue
        if gid in vectors or any(case_id not in decisions for case_id in ids):
            failures.append(f"GRADER_DECISIONS_INCOMPLETE:{gid}"); continue
        vectors[gid]=[int(decisions[case_id]!=expected[case_id]) for case_id in ids]
        families[gid]=family
        metadata[gid]={"family":family,"model_id":model_id,"model_version":model_version,"prompt_sha256":prompt_sha,"configuration_sha256":config_sha}
    if failures:
        return {"result":"BLOCKED","blocking_assertions":sorted(set(failures)),"automatic_grader_removal_allowed":False}
    pairwise=[]; positive=[]; gids=sorted(vectors)
    for index,left in enumerate(gids):
        for right in gids[index+1:]:
            corr=_phi(vectors[left],vectors[right])
            if corr is not None:
                positive.append(max(0.0,corr))
            pairwise.append({
                "left":left,"right":right,
                "same_family":families[left]==families[right],
                "same_error_vector":vectors[left]==vectors[right],
                "error_phi":None if corr is None else round(corr,6),
            })
    mean=sum(positive)/len(positive) if positive else 0.0
    n=len(gids); effective=n/(1+(n-1)*mean) if n else 0.0
    redundant=sorted({pair[key] for pair in pairwise if pair["same_family"] and pair["same_error_vector"] for key in ("left","right")})
    return {
        "result":"MEASURED_NO_AUTO_REMOVAL",
        "case_count":len(ids),"grader_count":n,
        "mean_positive_error_correlation":round(mean,6),
        "effective_vote_proxy":round(effective,6),
        "grader_metadata":metadata,
        "redundancy_review_candidates":redundant,
        "pairwise":pairwise,
        "automatic_grader_removal_allowed":False,
    }

def _iou(left:Any,right:Any)->float:
    if not isinstance(left,(list,tuple)) or not isinstance(right,(list,tuple)) or len(left)!=4 or len(right)!=4:
        return 0.0
    try:
        ax,ay,aw,ah=(float(x) for x in left); bx,by,bw,bh=(float(x) for x in right)
    except (TypeError,ValueError):
        return 0.0
    if aw<=0 or ah<=0 or bw<=0 or bh<=0:
        return 0.0
    width=max(0.0,min(ax+aw,bx+bw)-max(ax,bx)); height=max(0.0,min(ay+ah,by+bh)-max(ay,by))
    inter=width*height; union=aw*ah+bw*bh-inter
    return inter/union if union>0 else 0.0

def _engine_failures(record:Any,prefix:str)->list[str]:
    if not isinstance(record,dict): return [f"{prefix}_NOT_OBJECT"]
    failures=[]
    for field in ("engine_family","engine_version","execution_id"):
        if not str(record.get(field) or "").strip(): failures.append(f"{prefix}_{field.upper()}_MISSING")
    if not SHA256_RE.fullmatch(str(record.get("configuration_sha256") or "")):
        failures.append(f"{prefix}_CONFIGURATION_SHA_INVALID")
    if not isinstance(record.get("observations"),list) or not record.get("observations"):
        failures.append(f"{prefix}_OBSERVATIONS_MISSING")
    return failures

def visual_challenger(primary:Any,challenger:Any)->dict[str,Any]:
    blockers=_engine_failures(primary,"PRIMARY")+_engine_failures(challenger,"CHALLENGER")
    psha=str(primary.get("source_sha256") or "") if isinstance(primary,dict) else ""
    csha=str(challenger.get("source_sha256") or "") if isinstance(challenger,dict) else ""
    if not SHA256_RE.fullmatch(psha) or psha!=csha: blockers.append("SOURCE_HASH_MISMATCH")
    if isinstance(primary,dict) and isinstance(challenger,dict):
        if primary.get("engine_family")==challenger.get("engine_family"): blockers.append("ENGINE_FAMILY_NOT_INDEPENDENT")
        if primary.get("execution_id")==challenger.get("execution_id"): blockers.append("EXECUTION_ID_NOT_INDEPENDENT")
        if challenger.get("primary_output_visible_to_challenger") is not False: blockers.append("CHALLENGER_NOT_BLIND_TO_PRIMARY")
    if blockers:
        return {"result":"BLOCKED","blocking_assertions":sorted(set(blockers)),"auto_confirm_allowed":False,"classification_mutation":None}
    used=set(); disagreements=[]; matches=[]
    for observation in primary["observations"]:
        if not isinstance(observation,dict) or not observation.get("observation_id"):
            disagreements.append({"type":"PRIMARY_INVALID_OBSERVATION"}); continue
        candidates=[]
        for index,candidate in enumerate(challenger["observations"]):
            if index in used or not isinstance(candidate,dict) or candidate.get("kind")!=observation.get("kind"): continue
            overlap=_iou(observation.get("region"),candidate.get("region"))
            if overlap>=0.5: candidates.append((overlap,index,candidate))
        if not candidates:
            disagreements.append({"type":"PRIMARY_ONLY","id":observation.get("observation_id")}); continue
        overlap,index,candidate=max(candidates,key=lambda row:row[0]); used.add(index)
        left=" ".join(str(observation.get("text") or "").casefold().split()); right=" ".join(str(candidate.get("text") or "").casefold().split())
        similarity=1.0 if not left and not right else SequenceMatcher(None,left,right).ratio()
        matches.append({"primary_id":observation.get("observation_id"),"challenger_id":candidate.get("observation_id"),"iou":round(overlap,6),"text_similarity":round(similarity,6)})
        if (left or right) and similarity<0.85:
            disagreements.append({"type":"TEXT_DISAGREEMENT","primary_id":observation.get("observation_id"),"challenger_id":candidate.get("observation_id"),"text_similarity":round(similarity,6)})
    for index,candidate in enumerate(challenger["observations"]):
        if index not in used:
            disagreements.append({"type":"CHALLENGER_ONLY","id":candidate.get("observation_id") if isinstance(candidate,dict) else None})
    return {
        "result":"HUMAN_REVIEW_REQUIRED" if disagreements else "ORTHOGONAL_SUPPORT_OBSERVED",
        "source_sha256":psha,
        "primary_engine_family":primary["engine_family"],
        "challenger_engine_family":challenger["engine_family"],
        "matches":matches,"disagreements":disagreements,
        "auto_confirm_allowed":False,"classification_mutation":None,
    }

def _literal(value:Any)->tuple[str,bool]:
    text=str(value or "").strip()
    if not text: raise ValueError("empty literal")
    return (text[1:] if text.startswith("!") else text,not text.startswith("!"))

def formal_rule_gate(payload:Any)->dict[str,Any]:
    if not isinstance(payload,dict) or not isinstance(payload.get("rules"),list):
        return {"result":"BLOCKED","failures":["RULE_PAYLOAD_INVALID"],"semantic_truth_claimed":False,"production_authorized":False}
    compiled=[]; skipped=[]; variables=set(); failures=[]
    for rule in payload["rules"]:
        if not isinstance(rule,dict): failures.append("RULE_RECORD_INVALID"); continue
        rid=str(rule.get("rule_id") or "")
        if not rid: failures.append("RULE_ID_MISSING"); continue
        if rule.get("formalizable") is not True: skipped.append(rid); continue
        if len(str(rule.get("source_ref") or "").strip())<3: failures.append("SOURCE_REF_MISSING:"+rid); continue
        try:
            antecedent=[_literal(item) for item in rule.get("antecedent",[])]; consequent=_literal(rule.get("consequent"))
        except ValueError:
            failures.append("FORMALIZATION_INVALID:"+rid); continue
        compiled.append((rid,antecedent,consequent)); variables.update(name for name,_ in antecedent); variables.add(consequent[0])
    if failures:
        return {"result":"BLOCKED","failures":sorted(set(failures)),"semantic_truth_claimed":False,"production_authorized":False}
    if not compiled:
        return {"result":"NOT_FORMALIZABLE","not_formalizable":sorted(skipped),"semantic_truth_claimed":False,"source_translation_verified":False,"production_authorized":False}
    if len(variables)>16:
        return {"result":"BLOCKED_FORMAL_SOLVER_LIMIT","failures":["VARIABLE_LIMIT_EXCEEDED"],"semantic_truth_claimed":False,"production_authorized":False}
    names=sorted(variables); witness=None
    for bits in product((False,True),repeat=len(names)):
        env=dict(zip(names,bits))
        if all(not all(env[name] is polarity for name,polarity in antecedent) or env[consequent[0]] is consequent[1] for _,antecedent,consequent in compiled):
            witness=env; break
    return {
        "result":"SAT_FORMALIZATION" if witness is not None else "UNSAT_FORMALIZATION",
        "formalization_sha256":canonical_sha(payload["rules"]),
        "formalizable_rule_count":len(compiled),"not_formalizable":sorted(skipped),"witness":witness,
        "semantic_truth_claimed":False,"source_translation_verified":False,"production_authorized":False,
    }

def self_test()->dict[str,Any]:
    ekb=ekb_gate({code:("HUMAN_REVIEW_REQUIRED" if expected=="BLOCKED_OR_REVIEW" else "BLOCKED") for code,expected in EKB_RELATIONS.items()})
    sha="a"*64; prompt="b"*64; config_a="c"*64; config_b="d"*64
    cases=[{"case_id":"1","expected":"FAIL"},{"case_id":"2","expected":"FAIL"},{"case_id":"3","expected":"PASS"},{"case_id":"4","expected":"PASS"}]
    graders=grader_audit({"cases":cases,"graders":[
        {"grader_id":"G1","family":"LLM-A","model_id":"M1","model_version":"v1","prompt_sha256":prompt,"configuration_sha256":config_a,"decisions":{"1":"PASS","2":"FAIL","3":"PASS","4":"PASS"}},
        {"grader_id":"G2","family":"LLM-A","model_id":"M1","model_version":"v1","prompt_sha256":prompt,"configuration_sha256":config_a,"decisions":{"1":"PASS","2":"FAIL","3":"PASS","4":"PASS"}},
        {"grader_id":"G3","family":"DET-B","model_id":"M2","model_version":"v2","prompt_sha256":prompt,"configuration_sha256":config_b,"decisions":{"1":"FAIL","2":"PASS","3":"PASS","4":"PASS"}},
    ]})
    constant=_phi([0,0,0],[0,0,0])
    primary={"source_sha256":sha,"engine_family":"OCR","engine_version":"v1","execution_id":"EXEC-P","configuration_sha256":config_a,"observations":[{"observation_id":"P","kind":"TEXT","region":[0,0,10,10],"text":"Ej. 123"}]}
    challenger={"source_sha256":sha,"engine_family":"SCREEN_PARSER","engine_version":"v2","execution_id":"EXEC-C","configuration_sha256":config_b,"primary_output_visible_to_challenger":False,"observations":[{"observation_id":"C","kind":"TEXT","region":[0,0,10,10],"text":"Ej. 123"}]}
    divergent=json.loads(json.dumps(challenger)); divergent["observations"][0]["text"]="55 123"
    sat=formal_rule_gate({"rules":[{"rule_id":"R","source_ref":"SRC","formalizable":True,"antecedent":["A"],"consequent":"B"}]})
    unsat=formal_rule_gate({"rules":[{"rule_id":"R1","source_ref":"SRC","formalizable":True,"antecedent":[],"consequent":"A"},{"rule_id":"R2","source_ref":"SRC","formalizable":True,"antecedent":[],"consequent":"!A"}]})
    abstain=formal_rule_gate({"rules":[{"rule_id":"R3","source_ref":"SRC","formalizable":False}]})
    checks={
        "ekb":ekb["result"]=="PASS_WITH_EVIDENCE",
        "grader":graders["result"]=="MEASURED_NO_AUTO_REMOVAL" and set(graders["redundancy_review_candidates"])>={"G1","G2"} and graders["automatic_grader_removal_allowed"] is False,
        "grader_constant_vector_correlation":constant==1.0,
        "grader_malformed_blocks":grader_audit({"cases":[],"graders":[]})["result"]=="BLOCKED",
        "visual_support":visual_challenger(primary,challenger)["result"]=="ORTHOGONAL_SUPPORT_OBSERVED",
        "visual_disagreement":visual_challenger(primary,divergent)["result"]=="HUMAN_REVIEW_REQUIRED",
        "visual_same_family":visual_challenger(primary,{**challenger,"engine_family":"OCR"})["result"]=="BLOCKED",
        "visual_missing_config":visual_challenger(primary,{**challenger,"configuration_sha256":""})["result"]=="BLOCKED",
        "formal_sat":sat["result"]=="SAT_FORMALIZATION" and sat["semantic_truth_claimed"] is False,
        "formal_unsat":unsat["result"]=="UNSAT_FORMALIZATION",
        "formal_abstention":abstain["result"]=="NOT_FORMALIZABLE",
    }
    return {"schema_version":"story-creator-architecture-hardening-self-test/v2","result":"PASS" if all(checks.values()) else "FAIL","checks":checks,"production_authorized":False}

if __name__=="__main__":
    result=self_test(); print(json.dumps(result,ensure_ascii=False,sort_keys=True)); raise SystemExit(0 if result["result"]=="PASS" else 1)
