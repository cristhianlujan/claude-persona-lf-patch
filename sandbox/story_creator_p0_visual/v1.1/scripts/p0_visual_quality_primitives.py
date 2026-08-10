#!/usr/bin/env python3
"""Closed-loop P0 visual quality orchestration primitives."""
from __future__ import annotations
import argparse,copy,hashlib,json,re,struct,subprocess,tempfile,unicodedata
from datetime import datetime,timezone
from pathlib import Path
from typing import Any
from consolidate_p0_visual_reading import Box,build_consolidated,canonical_bytes,canonical_sha,runtime_versions,sha256_bytes,evidence_ref,expanded_background_green
from run_p0_visual_judge import audit_candidate,sim
def now_iso()->str:return datetime.now(timezone.utc).isoformat()
def norm(value:str|None)->str:
    if not value:return ""
    s=unicodedata.normalize("NFKD",value.casefold());s="".join(ch for ch in s if not unicodedata.combining(ch));return " ".join(re.sub(r"[^\w]+"," ",s).split())
def validate_admission(image_path:Path,admission_path:Path,processing_manifest_path:Path|None)->dict[str,Any]:
    from PIL import Image,ImageOps
    raw=image_path.read_bytes();admission=json.loads(admission_path.read_text(encoding="utf-8"));source_sha=sha256_bytes(raw);image=ImageOps.exif_transpose(Image.open(image_path)).convert("RGBA");normalized=hashlib.sha256(struct.pack(">II",image.width,image.height)+image.tobytes()).hexdigest();checks={"raw_bytes_sha256":admission.get("raw_bytes_sha256")==source_sha,"normalized_pixel_sha256":admission.get("normalized_pixel_sha256")==normalized,"width":admission.get("width")==image.width,"height":admission.get("height")==image.height,"decoder":admission.get("decoder_name")=="Pillow"};processing_sha=None
    if processing_manifest_path is not None:processing_sha=sha256_bytes(processing_manifest_path.read_bytes());checks["processing_manifest_sha256"]=admission.get("processing_manifest_sha256")==processing_sha
    checks["source_quality_minimum"]=image.width>=320 and image.height>=240
    return {"source_sha256":source_sha,"normalized_pixel_sha256":normalized,"processing_manifest_sha256":processing_sha,"width":image.width,"height":image.height,"checks":checks,"pass":all(checks.values())}
def empirical_p0_5_eligible(config:dict[str,Any],evidence_kind:str)->bool:
    synthetic=evidence_kind.upper().startswith("SYNTHETIC");calibration=config.get("calibration",{});return not synthetic and calibration.get("empirical_benchmark_acceptance") is True and calibration.get("p0_5_denominator_eligible") is True
def idempotency_key(config:dict[str,Any],source_sha256:str)->str:
    namespace=config.get("execution_controls",{}).get("namespace","P0");config_sha=canonical_sha(config);return hashlib.sha256(f"{namespace}|{source_sha256}|{config_sha}".encode()).hexdigest()
def runtime_config_check(config:dict[str,Any])->dict[str,Any]:
    actual=runtime_versions();expected=config.get("dependencies",{});matched={key:actual.get(key)==value for key,value in expected.items()};return {"configuration_id":config.get("configuration_id"),"config_sha256":canonical_sha(config),"actual":actual,"expected":expected,"dependency_match":matched,"registered":bool(config.get("configuration_id")) and bool(matched) and all(matched.values()),"calibration_current":config.get("calibration",{}).get("status")=="GOVERNED_OPERATIONAL_CALIBRATION","p0_5_denominator_eligible":bool(config.get("calibration",{}).get("p0_5_denominator_eligible",False))}
def _crop_reread(image_path:Path,region:dict[str,Any],config:dict[str,Any],*,tight:bool=False)->dict[str,Any]:
    import cv2
    image=cv2.imread(str(image_path),cv2.IMREAD_COLOR)
    if image is None:raise ValueError("source_decode_failed")
    h,w=image.shape[:2];b=Box(int(region["x"]),int(region["y"]),int(region["width"]),int(region["height"]))
    if tight:margin_x=max(4,min(12,int(max(4,b.h)*.35)));margin_y=max(3,min(8,int(max(4,b.h)*.25)))
    else:margin_x=margin_y=max(16,min(48,int(max(b.w,b.h)*.75)))
    x1,y1=max(0,b.x-margin_x),max(0,b.y-margin_y);x2,y2=min(w,b.right+margin_x),min(h,b.bottom+margin_y);crop=image[y1:y2,x1:x2];scale=float(config["ocr"]["adaptive_crop_scale"]);enlarged=cv2.resize(crop,None,fx=scale,fy=scale,interpolation=cv2.INTER_CUBIC)
    with tempfile.NamedTemporaryFile(suffix=".png",delete=False) as tmp:tmp_path=Path(tmp.name)
    cv2.imwrite(str(tmp_path),enlarged);readings=[]
    try:
        for psm in (6,7,11,13):
            proc=subprocess.run(["tesseract",str(tmp_path),"stdout","-l",config["ocr"]["languages"],"--psm",str(psm)],text=True,capture_output=True,check=False);readings.append({"psm":psm,"text":proc.stdout.strip(),"returncode":proc.returncode})
    finally:tmp_path.unlink(missing_ok=True)
    transform={"source_region":b.as_region(),"expanded_source_crop":{"x":x1,"y":y1,"width":x2-x1,"height":y2-y1},"scale":scale,"forward":"crop_x=(source_x-expanded_x)*scale; crop_y=(source_y-expanded_y)*scale","inverse":"source_x=crop_x/scale+expanded_x; source_y=crop_y/scale+expanded_y"};return {"readings":readings,"transform":transform}
def _inside(region:dict[str,Any],container:dict[str,Any],tol:int=3)->bool:return region["x"]>=container["x"]-tol and region["y"]>=container["y"]-tol and region["x"]+region["width"]<=container["x"]+container["width"]+tol and region["y"]+region["height"]<=container["y"]+container["height"]+tol
def remove_element(candidate:dict[str,Any],element_id:str)->None:
    candidate["elements"]=[e for e in candidate["elements"] if e.get("element_id")!=element_id];tree=candidate["ui_structure"]["visual_containment_tree"];tree["edges"]=[e for e in tree.get("edges",[]) if e.get("child")!=element_id and e.get("parent")!=element_id];candidate["ui_structure"]["candidate_reading_orders"]=[[eid for eid in order if eid!=element_id] for order in candidate["ui_structure"].get("candidate_reading_orders",[])]
def _region_box(region:dict[str,Any])->Box:return Box(int(region["x"]),int(region["y"]),int(region["width"]),int(region["height"]))
def _contains_box(outer:Box,inner:Box,tol:int=3)->bool:return inner.x>=outer.x-tol and inner.y>=outer.y-tol and inner.right<=outer.right+tol and inner.bottom<=outer.bottom+tol
def _next_element_id(candidate:dict[str,Any])->str:
    used={e.get("element_id") for e in candidate.get("elements",[])};n=1
    while True:
        eid=f"EL-R{n:04d}"
        if eid not in used:return eid
        n+=1
def add_source_grounded_element(candidate:dict[str,Any],*,region:dict[str,Any],element_type:str,parent_id:str|None,source_image_ref:str,role:str,source_observation_ref:str)->str:
    b=_region_box(region);eid=_next_element_id(candidate);item={"element_id":eid,"source_image_ref":source_image_ref,"parent_id":parent_id,"region":b.as_region(),"element_type":element_type,"visible_text":None,"semantic_role":role,"visual_state":"STATIC_VISIBLE","classification":"CONFIRMED","confidence":.90,"evidence_refs":[evidence_ref(candidate["source_sha256"],b)],"source_observation_refs":[source_observation_ref],"uncertainty_codes":[],"machine_resolution_status":"RESOLVED"};candidate["elements"].append(item)
    if parent_id is not None:candidate["ui_structure"]["visual_containment_tree"].setdefault("edges",[]).append({"parent":parent_id,"child":eid})
    return eid
def rebuild_hierarchy(candidate:dict[str,Any])->None:
    elements=candidate.get("elements",[]);screens=[e for e in elements if e.get("element_type")=="SCREEN"]
    if not screens:return
    root=max(screens,key=lambda e:_region_box(e["region"]).area);root_id=root["element_id"]
    for e in screens:e["parent_id"]=None if e is root else root_id
    for e in elements:
        if e.get("element_id")==root_id:continue
        eb=_region_box(e["region"]);allowed=[]
        for p in elements:
            if p.get("element_id")==e.get("element_id"):continue
            pt=p.get("element_type")
            if pt not in {"SCREEN","REGION","CONTAINER","INPUT","SELECT","BUTTON","CHECKBOX","RADIO"}:continue
            pb=_region_box(p["region"])
            if not _contains_box(pb,eb,5):continue
            if e.get("element_type") in {"REGION","CONTAINER"} and pt in {"INPUT","SELECT","BUTTON","CHECKBOX","RADIO"}:continue
            if e.get("element_type")=="REGION" and pt!="SCREEN":continue
            allowed.append(p)
        if allowed:
            parent=min(allowed,key=lambda p:_region_box(p["region"]).area)
            if _region_box(parent["region"]).area<=eb.area and parent.get("element_type")!="SCREEN":
                larger=[p for p in allowed if _region_box(p["region"]).area>eb.area or p.get("element_type")=="SCREEN"];parent=min(larger,key=lambda p:_region_box(p["region"]).area) if larger else root
            e["parent_id"]=parent["element_id"]
        else:e["parent_id"]=root_id
    candidate["ui_structure"]["visual_containment_tree"]={"roots":[root_id],"edges":[{"parent":e["parent_id"],"child":e["element_id"]} for e in elements if e.get("parent_id") is not None]};region_ids=[e["element_id"] for e in elements if e.get("element_type") in {"REGION","CONTAINER"}];orders=[]
    for pid in region_ids:
        children=sorted([e for e in elements if e.get("parent_id")==pid],key=lambda e:(e["region"]["y"],e["region"]["x"]))
        if children:orders.append([e["element_id"] for e in children])
    candidate["ui_structure"]["candidate_reading_orders"]=orders
