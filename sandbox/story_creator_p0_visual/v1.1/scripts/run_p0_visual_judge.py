#!/usr/bin/env python3
"""Independent J00 visual audit for a consolidated P0 reading."""
from __future__ import annotations
import argparse, difflib, json, re, unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from consolidate_p0_visual_reading import Box, canonical_sha, detect_geometry, group_lines, iou, run_tesseract_tsv, sha256_bytes, evidence_ref, expanded_background_green
CONTROL_TYPES={"INPUT","SELECT","BUTTON"}
GEOMETRY_TYPES=CONTROL_TYPES|{"CHECKBOX","PROGRESS_INDICATOR","SECURITY_INDICATOR"}
def box_of(e:dict[str,Any])->Box:
    r=e["region"]; return Box(int(r["x"]),int(r["y"]),int(r["width"]),int(r["height"]))
def norm(s:str|None)->str:
    if not s:return ""
    s=unicodedata.normalize("NFKD",s.casefold());s="".join(ch for ch in s if not unicodedata.combining(ch));s=re.sub(r"[^\w¿?]+"," ",s,flags=re.UNICODE);return " ".join(s.split())
def sim(a:str|None,b:str|None)->float:
    aa,bb=norm(a),norm(b)
    if not aa or not bb:return 0.0
    if aa in bb or bb in aa:return min(len(aa),len(bb))/max(len(aa),len(bb)) if max(len(aa),len(bb)) else 1.0
    return difflib.SequenceMatcher(None,aa,bb).ratio()
def _match_boxes(a:list[Box],b:list[Box],thr:float)->tuple[list[tuple[int,int]],list[int],list[int]]:
    pairs=[]; used_b=set()
    for i,x in enumerate(a):
        scored=[(iou(x,y),j) for j,y in enumerate(b) if j not in used_b]
        if scored:
            score,j=max(scored)
            if score>=thr:pairs.append((i,j));used_b.add(j)
    ma={i for i,_ in pairs};mb={j for _,j in pairs};return pairs,[i for i in range(len(a)) if i not in ma],[j for j in range(len(b)) if j not in mb]
def contains_like(a:Box,b:Box,tol:int=4)->bool:
    return (b.x>=a.x-tol and b.y>=a.y-tol and b.right<=a.right+tol and b.bottom<=a.bottom+tol) or (a.x>=b.x-tol and a.y>=b.y-tol and a.right<=b.right+tol and a.bottom<=b.bottom+tol)
def audit_candidate(image_path:Path,candidate:dict[str,Any],*,execution_id:str,identity:str,reader_execution_id:str,config:dict[str,Any],created_at:str|None=None)->dict[str,Any]:
    source_sha=sha256_bytes(image_path.read_bytes());findings=[];remediation=[];contradictions=[];unsupported=[];audit_only=[];reader_only=[]
    if candidate.get("source_sha256")!=source_sha:findings.append({"code":"SOURCE_SHA_MISMATCH","blocking":True})
    if execution_id==reader_execution_id:findings.append({"code":"J00_EXECUTION_REUSE","blocking":True})
    if identity in {"P0_VISUAL_READER","reader",""}:findings.append({"code":"J00_IDENTITY_REUSE","blocking":True})
    geo=detect_geometry(image_path,canny_low=30,canny_high=95);elements=candidate.get("elements",[]) if isinstance(candidate.get("elements"),list) else [];by_id={e.get("element_id"):e for e in elements if isinstance(e,dict)}
    for e in elements:
        b=box_of(e);expected=evidence_ref(source_sha,b);refs=e.get("evidence_refs") or []
        if expected not in refs:unsupported.append({"element_id":e.get("element_id"),"reason":"EVIDENCE_REF_NOT_REPRODUCIBLE"})
    screen=next((e for e in elements if e.get("element_type")=="SCREEN"),None);screen_w=float(screen.get("region",{}).get("width",0)) if isinstance(screen,dict) else 0.0
    if screen_w<=0:findings.append({"code":"SOURCE_GEOMETRY_WIDTH_INVALID","blocking":True});screen_w=max((b.right for b in geo["all"]),default=1)
    card_candidates=[b for b in geo["large_cards"] if b.cx>screen_w*.55 and b.x>screen_w*.25]
    if card_candidates:card=max(card_candidates,key=lambda b:b.area)
    else:card=Box(0,0,1,1);findings.append({"code":"AUDIT_FORM_CARD_NOT_DETECTED","blocking":True})
    audit_controls=[b for b in geo["controls"] if (b.x>=card.x and b.right<=card.right and b.y>=card.y and b.bottom<=card.bottom) and (b.h<=65 or b.y<card.y+card.h*.58 or b.y>card.y+card.h*.80)]
    cand_control_elems_for_match=[e for e in elements if e.get("element_type") in CONTROL_TYPES];cand_controls=[box_of(e) for e in cand_control_elems_for_match]
    pairs,cand_un,audit_un=_match_boxes(cand_controls,audit_controls,float(config["quality"]["geometry_iou_threshold"]))
    for idx in audit_un:
        b=audit_controls[idx];audit_only.append({"element_type":"FORM_CONTROL","region":b.as_region(),"material":True});remediation.append({"code":"AUDIT_ONLY_CONTROL","region":b.as_region()})
    for idx in cand_un:
        b=cand_controls[idx];eid=cand_control_elems_for_match[idx].get("element_id");reader_only.append({"element_id":eid,"element_type":"FORM_CONTROL","region":b.as_region()});unsupported.append({"element_id":eid,"region":b.as_region(),"reason":"CONTROL_NOT_REDETECTED_BY_J00"})
    for e in elements:
        if e.get("element_type") not in CONTROL_TYPES:continue
        eb=box_of(e);green=expanded_background_green(image_path,eb)
        if e.get("element_type")=="BUTTON" and green<=.25:
            contradictions.append({"element_id":e.get("element_id"),"reason":"CONTROL_SEMANTIC_TYPE_MISMATCH","claimed_type":"BUTTON","green_background_ratio":round(green,4)});remediation.append({"code":"CONTROL_SEMANTIC_TYPE_MISMATCH","element_id":e.get("element_id"),"region":eb.as_region()})
        elif e.get("element_type") in {"INPUT","SELECT"} and green>.25:
            contradictions.append({"element_id":e.get("element_id"),"reason":"CONTROL_SEMANTIC_TYPE_MISMATCH","claimed_type":e.get("element_type"),"green_background_ratio":round(green,4)});remediation.append({"code":"CONTROL_SEMANTIC_TYPE_MISMATCH","element_id":e.get("element_id"),"region":eb.as_region()})
    for e in elements:
        if e.get("element_type") not in {"ICON","SECURITY_INDICATOR"}:continue
        eb=box_of(e);local=[q for q in geo["all"] if q.w<=80 and q.h<=80 and (iou(eb,q)>=.12 or contains_like(eb,q))]
        if not local:unsupported.append({"element_id":e.get("element_id"),"region":eb.as_region(),"reason":"ICON_CROP_GEOMETRY_NOT_REDETECTED_BY_J00"})
    audit_progress=[b for b in geo["progress"] if b.y<card.y+card.h*.25 and b.x>=card.x];cand_progress_elems=[e for e in elements if e.get("element_type")=="PROGRESS_INDICATOR"];cand_progress=[box_of(e) for e in cand_progress_elems];_,cp,ap=_match_boxes(cand_progress,audit_progress,.45)
    for idx in ap:
        b=audit_progress[idx];audit_only.append({"element_type":"PROGRESS_INDICATOR","region":b.as_region(),"material":True});remediation.append({"code":"AUDIT_ONLY_PROGRESS","region":b.as_region()})
    for idx in cp:
        b=cand_progress[idx];unsupported.append({"element_id":cand_progress_elems[idx].get("element_id"),"region":b.as_region(),"reason":"PROGRESS_NOT_REDETECTED_BY_J00"})
    audit_cb=[];form_left=min((b.x for b in audit_controls),default=card.x);upper_controls=[b for b in audit_controls if b.y<card.y+card.h*.70];consent_start=max((b.bottom for b in upper_controls),default=card.y+card.h*.45)
    for b in geo["small_squares"]:
        if 18<=b.w<=27 and 18<=b.h<=27 and form_left<=b.x<form_left+85 and b.y>consent_start:
            if not any(abs(b.cy-q.cy)<8 for q in audit_cb):audit_cb.append(b)
    cand_cb_elems=[e for e in elements if e.get("element_type")=="CHECKBOX"];cand_cb=[box_of(e) for e in cand_cb_elems];_,cc,ac=_match_boxes(cand_cb,audit_cb,.40)
    for idx in ac:
        b=audit_cb[idx];audit_only.append({"element_type":"CHECKBOX","region":b.as_region(),"material":True});remediation.append({"code":"AUDIT_ONLY_CHECKBOX","region":b.as_region()})
    for idx in cc:unsupported.append({"element_id":cand_cb_elems[idx].get("element_id"),"region":cand_cb[idx].as_region(),"reason":"CHECKBOX_NOT_REDETECTED_BY_J00"})
    for e in elements:
        txt=norm(e.get("visible_text"))
        if e.get("element_type") not in {"TEXT","HEADING","PARAGRAPH","LABEL"} or txt not in {"o","0"}:continue
        eb=box_of(e)
        if eb.w>40 or eb.h>40:continue
        if any((iou(eb,b)>.10 or (abs(eb.cx-b.cx)<14 and abs(eb.cy-b.cy)<14)) for b in audit_cb):
            contradictions.append({"element_id":e.get("element_id"),"candidate_text":e.get("visible_text"),"reason":"CHECKBOX_TEXT_CONFUSION"});remediation.append({"code":"CHECKBOX_TEXT_CONFUSION","element_id":e.get("element_id"),"region":eb.as_region()})
    cand_control_elems=[e for e in elements if e.get("element_type") in CONTROL_TYPES]
    for ce in cand_control_elems:
        cbx=box_of(ce);compact=[q for q in geo["all"] if q.x>cbx.x+3 and q.right<cbx.right-3 and q.y>cbx.y+3 and q.bottom<cbx.bottom-3 and 7<=q.w<=38 and 7<=q.h<=38 and q.area>=45 and (q.cx<=cbx.x+58 or q.cx>=cbx.right-58)]
        if compact:
            children=[e for e in elements if e.get("parent_id")==ce.get("element_id") and e.get("element_type")=="ICON"]
            if not children:remediation.append({"code":"CONTROL_ICON_CHILD_MISSING","parent_id":ce.get("element_id"),"region":compact[0].as_region()});audit_only.append({"element_type":"ICON","parent_id":ce.get("element_id"),"region":compact[0].as_region(),"material":True})
    audit_words=run_tesseract_tsv(image_path,languages=config["ocr"]["languages"],psm=int(config["ocr"]["judge_psm"]),scale=1.0);audit_lines=group_lines(audit_words);critical_types={"LABEL","LINK","HEADING"}
    for e in elements:
        if not e.get("visible_text") or e.get("element_type") not in critical_types:continue
        eb=box_of(e);candidates=[]
        for ln in audit_lines:
            lb=ln["box"];vertical=abs(lb.cy-eb.cy)<=max(18,eb.h*1.5);horizontal=(max(0,min(lb.right,eb.right)-max(lb.x,eb.x))>0) or abs(lb.cx-eb.cx)<160
            if vertical and horizontal:candidates.append(ln)
        best=max(((sim(e.get("visible_text"),ln["text"]),ln) for ln in candidates),default=(0.0,None),key=lambda z:z[0]);threshold=float(config["quality"]["critical_text_similarity"])
        if e.get("element_type")=="LABEL" and len(norm(e.get("visible_text")))<=18:threshold=max(threshold,.90)
        if best[0]<threshold:
            full=" ".join(ln["text"] for ln in audit_lines);global_sim=1.0 if norm(e.get("visible_text")) in norm(full) else 0.0
            if max(best[0],global_sim)<threshold:
                contradictions.append({"element_id":e.get("element_id"),"candidate_text":e.get("visible_text"),"audit_text":best[1]["text"] if best[1] else None,"similarity":round(best[0],4)});remediation.append({"code":"TEXT_DISAGREEMENT","element_id":e.get("element_id"),"region":eb.as_region()})
    for e in elements:
        txt=(e.get("visible_text") or "").strip()
        if e.get("element_type") in {"TEXT","HEADING","PARAGRAPH","LABEL"} and re.match(r"^[©®()□◇◆⚠]+\s+\w",txt):
            contradictions.append({"element_id":e.get("element_id"),"candidate_text":txt,"audit_text":None,"similarity":0.0,"reason":"ICON_TEXT_CONFUSION"});remediation.append({"code":"ICON_TEXT_CONFUSION","element_id":e.get("element_id"),"region":box_of(e).as_region()})
    for e in elements:
        if e.get("machine_resolution_status")=="REMEDIATION_REQUIRED":remediation.append({"code":"READER_UNCERTAINTY","element_id":e.get("element_id"),"region":box_of(e).as_region(),"uncertainty_codes":e.get("uncertainty_codes",[])})
    roots=[e for e in elements if e.get("parent_id") is None]
    if len(roots)!=1 or roots[0].get("element_type")!="SCREEN":findings.append({"code":"VISUAL_STRUCTURE_ROOT_INVALID","blocking":True});remediation.append({"code":"STRUCTURE_REBUILD_REQUIRED"})
    for e in elements:
        pid=e.get("parent_id")
        if pid is not None and pid not in by_id:findings.append({"code":"VISUAL_STRUCTURE_PARENT_MISSING","blocking":True,"element_id":e.get("element_id")});remediation.append({"code":"STRUCTURE_REBUILD_REQUIRED"})
    parents={e.get("parent_id") for e in elements if e.get("parent_id") is not None}
    if len(elements)>8 and len(parents)<=1:findings.append({"code":"VISUAL_STRUCTURE_DEGENERATE","blocking":True});remediation.append({"code":"STRUCTURE_REBUILD_REQUIRED"})
    for e in elements:
        seen=set();cur=e
        while cur.get("parent_id") is not None:
            pid=cur.get("parent_id")
            if pid in seen:findings.append({"code":"VISUAL_STRUCTURE_CYCLE","blocking":True,"element_id":e.get("element_id")});remediation.append({"code":"STRUCTURE_REBUILD_REQUIRED"});break
            seen.add(pid);cur=by_id.get(pid,{})
    for u in unsupported:remediation.append({"code":"UNSUPPORTED_CLAIM_RECONCILE","element_id":u.get("element_id"),"region":u.get("region"),"reason":u.get("reason")})
    uniq=[];seen=set()
    for r in remediation:
        key=json.dumps(r,sort_keys=True)
        if key not in seen:seen.add(key);uniq.append(r)
    remediation=uniq;blocking=bool(findings or contradictions or unsupported or any(x.get("material") for x in audit_only) or remediation)
    return {"schema_version":"p0-j00-visual-audit/v1","execution_id":execution_id,"identity":identity,"reader_execution_id":reader_execution_id,"source_sha256":source_sha,"candidate_sha256":canonical_sha(candidate),"audit_observation_counts":{"ocr_words":len(audit_words),"ocr_lines":len(audit_lines),"controls":len(audit_controls),"progress":len(audit_progress),"checkboxes":len(audit_cb)},"findings":findings,"audit_only":audit_only,"reader_only":reader_only,"contradictions":contradictions,"unsupported_claims":unsupported,"blocking_findings":len(findings)+len(contradictions)+len(unsupported)+sum(1 for x in audit_only if x.get("material")),"remediation_targets":remediation,"judgment":"BLOCKED" if blocking else "PASS","created_at":created_at or datetime.now(timezone.utc).isoformat()}
def main()->int:
    ap=argparse.ArgumentParser();ap.add_argument("--image",type=Path,required=True);ap.add_argument("--candidate",type=Path,required=True);ap.add_argument("--config",type=Path,required=True);ap.add_argument("--execution-id",required=True);ap.add_argument("--identity",default="P0_VISUAL_JUDGE");ap.add_argument("--reader-execution-id",required=True);ap.add_argument("--output",type=Path,required=True)
    a=ap.parse_args();result=audit_candidate(a.image,json.loads(a.candidate.read_text()),execution_id=a.execution_id,identity=a.identity,reader_execution_id=a.reader_execution_id,config=json.loads(a.config.read_text()));a.output.write_text(json.dumps(result,sort_keys=True,separators=(",",":"),ensure_ascii=False));print(json.dumps({"judgment":result["judgment"],"blocking_findings":result["blocking_findings"],"remediation_targets":len(result["remediation_targets"]),"candidate_sha256":result["candidate_sha256"]},sort_keys=True));return 0 if result["judgment"]=="PASS" else 2
if __name__=="__main__":raise SystemExit(main())
