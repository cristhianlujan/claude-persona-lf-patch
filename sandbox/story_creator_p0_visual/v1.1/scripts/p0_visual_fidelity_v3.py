#!/usr/bin/env python3
"""P0 V3 visual fidelity primitives.

Additive layer over the V2 semantic reader. It never overwrites the locked blind
artifact: callers pass the legacy/consolidated payload and receive a new v2 payload.
"""
from __future__ import annotations
import base64, copy, hashlib, html, json, math, re
from pathlib import Path
from statistics import median
from typing import Any, Iterable

PROVENANCE_KINDS={
    "OBSERVED_PIXEL_GEOMETRY","OBSERVED_PIXEL_COLOR","OBSERVED_PIXEL_STYLE",
    "ESTIMATED_VISUAL_STYLE","DECLARED_DOM_COMPUTED_STYLE","DECLARED_CSS_STYLESHEET",
    "DECLARED_FIGMA_NODE","DECLARED_DESIGN_TOKEN","RECONCILED","NOT_OBSERVABLE","NOT_APPLICABLE",
    "NOT_AVAILABLE_LEGACY",
}
RESOLUTION_STATES={
    "RESOLVED_OBSERVED","RESOLVED_ESTIMATED","RESOLVED_DECLARED","NOT_OBSERVABLE",
    "NOT_APPLICABLE","REMEDIATION_REQUIRED","NOT_AVAILABLE_LEGACY",
}
RELATION_TYPES={
    "CONTAINS","INSIDE","LEFT_OF","RIGHT_OF","ABOVE","BELOW","ALIGNED_LEFT","ALIGNED_RIGHT",
    "ALIGNED_CENTER_X","ALIGNED_CENTER_Y","SAME_ROW","SAME_COLUMN","ADJACENT","OVERLAPS",
    "VISUALLY_GROUPED_WITH","REPEATED_WITH",
}
MATERIAL_TYPES={"SCREEN","REGION","CONTAINER","INPUT","SELECT","BUTTON","CHECKBOX","PROGRESS_INDICATOR","TEXT","LABEL","HEADING","PARAGRAPH","LINK","ICON","SECURITY_INDICATOR","BRAND_MARK","ILLUSTRATION"}
TEXT_TYPES={"TEXT","LABEL","HEADING","PARAGRAPH","LINK"}
CONTROL_TYPES={"INPUT","SELECT","BUTTON","CHECKBOX"}
CONTAINER_TYPES={"SCREEN","REGION","CONTAINER"}
GRAPHIC_TYPES={"ICON","SECURITY_INDICATOR","BRAND_MARK","ILLUSTRATION"}


def canonical_bytes(obj:Any)->bytes:
    return json.dumps(obj,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode("utf-8")

def canonical_sha(obj:Any)->str:
    return hashlib.sha256(canonical_bytes(obj)).hexdigest()

def sha256_file(path:Path)->str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
    return h.hexdigest()

def clamp(v:float,lo:float,hi:float)->float:return max(lo,min(hi,v))

def _r(e:dict[str,Any])->dict[str,float]:
    r=e.get("region") or {}
    return {k:float(r.get(k,0) or 0) for k in ("x","y","width","height")}

def _edges(r:dict[str,float])->tuple[float,float,float,float]:
    return r["x"],r["y"],r["x"]+r["width"],r["y"]+r["height"]

def _intersection(a:dict[str,float],b:dict[str,float])->float:
    ax,ay,ar,ab=_edges(a); bx,by,br,bb=_edges(b)
    return max(0,min(ar,br)-max(ax,bx))*max(0,min(ab,bb)-max(ay,by))

def _contains(parent:dict[str,float],child:dict[str,float],tol:float=0.0)->bool:
    px,py,pr,pb=_edges(parent); cx,cy,cr,cb=_edges(child)
    return cx>=px-tol and cy>=py-tol and cr<=pr+tol and cb<=pb+tol

def _norm_box(r:dict[str,float],w:float,h:float)->dict[str,float]:
    return {"x":round(r["x"]/w,8),"y":round(r["y"]/h,8),"width":round(r["width"]/w,8),"height":round(r["height"]/h,8)}

def _relative_box(r:dict[str,float],p:dict[str,float]|None)->dict[str,float]:
    if not p or p["width"]<=0 or p["height"]<=0:
        return {"x":0.0,"y":0.0,"width":1.0,"height":1.0}
    return {"x":round((r["x"]-p["x"])/p["width"],8),"y":round((r["y"]-p["y"])/p["height"],8),"width":round(r["width"]/p["width"],8),"height":round(r["height"]/p["height"],8)}

def _viewport_size(candidate:dict[str,Any])->tuple[int,int]:
    screens=[e for e in candidate.get("elements",[]) if e.get("element_type")=="SCREEN"]
    if screens:
        r=_r(screens[0]);return max(1,int(round(r["width"]))),max(1,int(round(r["height"])))
    rs=[_r(e) for e in candidate.get("elements",[])]
    if not rs:return 1,1
    return max(1,int(max(x["x"]+x["width"] for x in rs))),max(1,int(max(x["y"]+x["height"] for x in rs)))

def geometry_profile(e:dict[str,Any],parent:dict[str,Any]|None,vw:int,vh:int)->dict[str,Any]:
    r=_r(e); pr=_r(parent) if parent else None
    vp={k:int(round(v)) for k,v in r.items()}
    inter=_intersection(r,{"x":0,"y":0,"width":vw,"height":vh})
    area=max(1.0,r["width"]*r["height"])
    return {
        "viewport_box_px":vp,
        "viewport_box_normalized":_norm_box(r,float(vw),float(vh)),
        "parent_box_relative":_relative_box(r,pr),
        "center_px":{"x":round(r["x"]+r["width"]/2,4),"y":round(r["y"]+r["height"]/2,4)},
        "aspect_ratio":round(r["width"]/r["height"],8) if r["height"]>0 else None,
        "visible_fraction":round(clamp(inter/area,0,1),8),
        "clipping":"VISIBLE_CLIPPED" if inter+1e-6<area else "NOT_CLIPPED",
        "measurement_kind":"OBSERVED_PIXEL_GEOMETRY",
        "resolution_status":"RESOLVED_OBSERVED" if r["width"]>0 and r["height"]>0 else "REMEDIATION_REQUIRED",
        "confidence":round(float(e.get("confidence",1.0)),6),
        "evidence_refs":list(e.get("evidence_refs",[])),
    }

def _load_image(path:Path|None):
    if not path:return None,None,None
    try:
        import cv2, numpy as np
    except Exception:return None,None,None
    img=cv2.imread(str(path))
    if img is None:return None,None,None
    return cv2,np,img

def _crop(img,r:dict[str,float]):
    if img is None:return None
    h,w=img.shape[:2];x=max(0,int(r["x"]));y=max(0,int(r["y"]));x2=min(w,int(math.ceil(r["x"]+r["width"])));y2=min(h,int(math.ceil(r["y"]+r["height"])))
    if x2<=x or y2<=y:return None
    return img[y:y2,x:x2]

def _rgb_from_bgr(v:Iterable[float])->list[int]:
    z=list(v);return [int(round(clamp(z[2],0,255))),int(round(clamp(z[1],0,255))),int(round(clamp(z[0],0,255)))]

def _hex(rgb:list[int])->str:return "#"+"".join(f"{x:02X}" for x in rgb)

def _robust_color_profiles(img,r:dict[str,float])->tuple[dict[str,Any],dict[str,Any]]:
    """Estimate crop background from border median and foreground as pixels far from it."""
    if img is None:
        na={"rgb":None,"hex":None,"kind":"NOT_OBSERVABLE","sampling_method":"NO_BITMAP","sample_count":0,"antialiasing_contamination":None,"confidence":0.0,"resolution_status":"NOT_OBSERVABLE"}
        return copy.deepcopy(na),copy.deepcopy(na)
    try:import numpy as np
    except Exception: return _robust_color_profiles(None,r)
    c=_crop(img,r)
    if c is None or c.size==0:return _robust_color_profiles(None,r)
    hh,ww=c.shape[:2]
    border=np.concatenate([c[0,:,:],c[-1,:,:],c[:,0,:],c[:,-1,:]],axis=0).astype(float)
    bg_bgr=np.median(border,axis=0)
    flat=c.reshape(-1,3).astype(float)
    dist=np.linalg.norm(flat-bg_bgr,axis=1)
    threshold=max(18.0,float(np.percentile(dist,55)))
    fg=flat[dist>threshold]
    if len(fg)<max(3,int(len(flat)*.01)):
        fg=flat[np.argsort(dist)[-max(3,int(len(flat)*.08)):]]
    fg_bgr=np.median(fg,axis=0) if len(fg) else bg_bgr
    bg=_rgb_from_bgr(bg_bgr);fgc=_rgb_from_bgr(fg_bgr)
    contaminated=float(np.mean((dist>5)&(dist<threshold)))
    return (
      {"rgb":fgc,"hex":_hex(fgc),"kind":"OBSERVED_PIXEL_COLOR","sampling_method":"ROBUST_FOREGROUND_MEDIAN","sample_count":int(len(fg)),"antialiasing_contamination":round(contaminated,6),"confidence":round(clamp(.90-contaminated*.35,.5,.98),6),"resolution_status":"RESOLVED_OBSERVED"},
      {"rgb":bg,"hex":_hex(bg),"kind":"OBSERVED_PIXEL_COLOR","sampling_method":"BORDER_MEDIAN","sample_count":int(len(border)),"antialiasing_contamination":round(contaminated,6),"confidence":round(clamp(.94-contaminated*.2,.6,.99),6),"resolution_status":"RESOLVED_OBSERVED"},
    )

def _underline_candidate(img,r:dict[str,float],bg_rgb:list[int]|None)->tuple[bool,float]:
    if img is None or not bg_rgb:return False,0.0
    try:import numpy as np
    except Exception:return False,0.0
    c=_crop(img,r)
    if c is None or c.shape[0]<4 or c.shape[1]<8:return False,0.0
    bg_bgr=np.array(bg_rgb[::-1],float)
    dist=np.linalg.norm(c.astype(float)-bg_bgr,axis=2)
    lower=dist[max(0,int(c.shape[0]*.68)):,:]
    if lower.size==0:return False,0.0
    row_cov=(lower>35).mean(axis=1)
    score=float(row_cov.max()) if len(row_cov) else 0
    return score>.62,round(clamp(score,0,1),6)

def _weight_class(img,r:dict[str,float],bg_rgb:list[int]|None)->tuple[str,float]:
    if img is None or not bg_rgb:return "UNKNOWN",0.0
    try:import numpy as np
    except Exception:return "UNKNOWN",0.0
    c=_crop(img,r)
    if c is None or c.size==0:return "UNKNOWN",0.0
    bg=np.array(bg_rgb[::-1],float);d=np.linalg.norm(c.astype(float)-bg,axis=2)
    density=float((d>40).mean())
    if density>=.24:return "BOLD",round(clamp(.55+density,.6,.9),6)
    if density>=.16:return "SEMIBOLD",round(clamp(.55+density,.58,.86),6)
    if density>=.10:return "MEDIUM",round(clamp(.55+density,.56,.82),6)
    return "REGULAR",round(clamp(.62-density,.5,.78),6)

def typography_profile(e:dict[str,Any],img)->dict[str,Any]:
    r=_r(e); fg,bg=_robust_color_profiles(img,r); underline,uscore=_underline_candidate(img,r,bg.get("rgb")); weight,wconf=_weight_class(img,r,bg.get("rgb"))
    text=str(e.get("visible_text") or "")
    h=r["height"] if r["height"]>0 else None
    est=round(h*1.16,2) if h else None
    case="MIXED"
    letters="".join(ch for ch in text if ch.isalpha())
    if letters:
        if letters.upper()==letters:case="UPPER"
        elif letters.lower()==letters:case="LOWER"
        elif text[:1].isupper():case="TITLE"
    return {
      "visual_text_height_px":round(h,2) if h else None,
      "visual_text_height_kind":"OBSERVED_PIXEL_STYLE" if h else "NOT_OBSERVABLE",
      "estimated_font_size_px":est,
      "font_size_kind":"ESTIMATED_VISUAL_STYLE" if est else "NOT_OBSERVABLE",
      "font_weight_class":weight,
      "font_weight_kind":"ESTIMATED_VISUAL_STYLE" if weight!="UNKNOWN" else "NOT_OBSERVABLE",
      "font_style":"UNKNOWN","font_style_kind":"NOT_OBSERVABLE",
      "text_decoration":["UNDERLINE"] if underline else ["NONE"],
      "text_decoration_kind":"ESTIMATED_VISUAL_STYLE" if img is not None else "NOT_OBSERVABLE",
      "estimated_line_height_px":None,"line_height_kind":"NOT_OBSERVABLE",
      "estimated_letter_spacing_px":None,"letter_spacing_kind":"NOT_OBSERVABLE",
      "font_family":None,"font_family_kind":"NOT_OBSERVABLE",
      "text_align":"UNKNOWN","text_align_kind":"ESTIMATED_VISUAL_STYLE",
      "case_style":case,
      "confidence":round(max(.45,wconf,uscore*.7),6),
      "evidence_refs":list(e.get("evidence_refs",[])),
      "resolution_status":"RESOLVED_ESTIMATED" if h else "NOT_OBSERVABLE",
      "text_color":fg,
    }

def _edge_profile(img,r:dict[str,float])->tuple[dict[str,Any],dict[str,Any],dict[str,Any]]:
    if img is None:
        na={"present":None,"kind":"NOT_OBSERVABLE","resolution_status":"NOT_OBSERVABLE","confidence":0.0}
        return copy.deepcopy(na),copy.deepcopy(na),copy.deepcopy(na)
    try:import cv2, numpy as np
    except Exception:return _edge_profile(None,r)
    c=_crop(img,r)
    if c is None or min(c.shape[:2])<4:return _edge_profile(None,r)
    gray=cv2.cvtColor(c,cv2.COLOR_BGR2GRAY);edges=cv2.Canny(gray,60,150)
    h,w=edges.shape
    perimeter=np.concatenate([edges[:2,:].ravel(),edges[-2:,:].ravel(),edges[:,:2].ravel(),edges[:,-2:].ravel()])
    edge_ratio=float((perimeter>0).mean())
    present=edge_ratio>.08
    k=max(2,min(h,w)//8)
    corners=np.concatenate([edges[:k,:k].ravel(),edges[:k,-k:].ravel(),edges[-k:,:k].ravel(),edges[-k:,-k:].ravel()])
    corner_ink=float((corners>0).mean())
    radius_est=round(clamp((1-corner_ink)*min(h,w)*.18,0,min(h,w)/2),2) if present else 0.0
    border={"present":present,"estimated_width_px":1.0 if present else 0.0,"color":None,"style_candidate":"SOLID" if present else "NONE","kind":"ESTIMATED_VISUAL_STYLE","resolution_status":"RESOLVED_ESTIMATED","confidence":round(clamp(.55+edge_ratio,.55,.9),6)}
    radius={"present":radius_est>1.0,"estimated_radius_px":radius_est,"uniform_candidate":True,"kind":"ESTIMATED_VISUAL_STYLE","resolution_status":"RESOLVED_ESTIMATED","confidence":round(clamp(.5+edge_ratio*.8,.5,.85),6)}
    shadow={"present":None,"offset_px":None,"blur_spread":"UNKNOWN","color":None,"kind":"NOT_OBSERVABLE","resolution_status":"NOT_OBSERVABLE","confidence":0.0}
    return border,radius,shadow

def visual_style_profile(e:dict[str,Any],img)->dict[str,Any]:
    r=_r(e); fg,bg=_robust_color_profiles(img,r); border,radius,shadow=_edge_profile(img,r)
    et=e.get("element_type")
    typ=typography_profile(e,img) if et in TEXT_TYPES or e.get("visible_text") else {"resolution_status":"NOT_APPLICABLE","font_family":None,"font_family_kind":"NOT_APPLICABLE"}
    return {
      "typography":typ,
      "foreground":fg if (et in TEXT_TYPES or et in GRAPHIC_TYPES or e.get("visible_text")) else {"kind":"NOT_APPLICABLE","resolution_status":"NOT_APPLICABLE"},
      "background":bg,
      "border":border if et in CONTROL_TYPES|CONTAINER_TYPES else {"present":None,"kind":"NOT_APPLICABLE","resolution_status":"NOT_APPLICABLE"},
      "radius":radius if et in CONTROL_TYPES|CONTAINER_TYPES else {"present":None,"kind":"NOT_APPLICABLE","resolution_status":"NOT_APPLICABLE"},
      "shadow":shadow if et in CONTROL_TYPES|CONTAINER_TYPES else {"present":None,"kind":"NOT_APPLICABLE","resolution_status":"NOT_APPLICABLE"},
      "opacity":{"value":None,"kind":"NOT_OBSERVABLE","resolution_status":"NOT_OBSERVABLE"},
      "profile_resolution":"RESOLVED_ESTIMATED" if img is not None else "NOT_OBSERVABLE",
    }

def _union_region(elements:list[dict[str,Any]])->dict[str,int]:
    rs=[_r(e) for e in elements]
    x=min(r["x"] for r in rs);y=min(r["y"] for r in rs);rr=max(r["x"]+r["width"] for r in rs);bb=max(r["y"]+r["height"] for r in rs)
    return {"x":int(round(x)),"y":int(round(y)),"width":int(round(rr-x)),"height":int(round(bb-y))}

def build_text_groups(elements:list[dict[str,Any]],config:dict[str,Any]|None=None)->list[dict[str,Any]]:
    cfg=(config or {}).get("text_grouping",{}); max_gap=float(cfg.get("max_horizontal_gap_px",24)); baseline_tol=float(cfg.get("baseline_tolerance_px",10)); height_ratio=float(cfg.get("text_height_ratio_tolerance",.45))
    texts=[e for e in elements if e.get("visible_text")]
    texts=sorted(texts,key=lambda e:(str(e.get("parent_id")),_r(e)["y"],_r(e)["x"]))
    groups:list[list[dict[str,Any]]]=[]
    for e in texts:
        r=_r(e);placed=False
        for g in reversed(groups[-8:]):
            last=g[-1];lr=_r(last)
            if last.get("parent_id")!=e.get("parent_id"):continue
            if last.get("element_type") in CONTROL_TYPES or e.get("element_type") in CONTROL_TYPES:continue
            if last.get("element_type")=="LABEL" or e.get("element_type")=="LABEL":continue
            ymid=r["y"]+r["height"]/2;lmid=lr["y"]+lr["height"]/2
            gap=r["x"]-(lr["x"]+lr["width"])
            hratio=abs(r["height"]-lr["height"])/max(1,r["height"],lr["height"])
            if abs(ymid-lmid)<=baseline_tol and -2<=gap<=max_gap and hratio<=height_ratio:
                g.append(e);placed=True;break
        if not placed:groups.append([e])
    out=[]
    for i,g in enumerate(groups,1):
        members=[e["element_id"] for e in g]
        words=[];ev=[]
        for e in g:
            words.extend([x for x in e.get("source_observation_refs",[]) if x and x not in words])
            ev.extend([x for x in e.get("evidence_refs",[]) if x and x not in ev])
        out.append({
          "text_group_id":f"TG-{i:04d}","group_text":" ".join(str(e.get("visible_text") or "").strip() for e in g).strip(),
          "member_element_ids":members,"word_observation_refs":words,"region":_union_region(g),
          "grouping_basis":["SAME_PARENT","BASELINE_COMPATIBLE","LOCAL_HORIZONTAL_CONTINUITY"] if len(g)>1 else ["STANDALONE_SEMANTIC_UNIT"],
          "classification":"CONFIRMED" if all(e.get("classification")=="CONFIRMED" for e in g) else "INFERRED",
          "confidence":round(min(float(e.get("confidence",.5)) for e in g),6),"evidence_refs":ev,
          "machine_resolution_status":"RESOLVED",
        })
    return out

def build_spatial_relations(elements:list[dict[str,Any]],config:dict[str,Any]|None=None)->list[dict[str,Any]]:
    cfg=(config or {}).get("geometry",{});align_tol=float(cfg.get("alignment_tolerance_px",8));adj=float(cfg.get("adjacency_distance_px",32))
    byid={e["element_id"]:e for e in elements};out=[];seen=set()
    def add(a,b,t,d=None,conf=.95):
        key=(a,b,t)
        if key in seen:return
        seen.add(key);out.append({"source_element_id":a,"target_element_id":b,"relation_type":t,"measured_distance_px":None if d is None else round(float(d),3),"tolerance_px":round(align_tol,3),"confidence":round(conf,6),"evidence_refs":list(dict.fromkeys(byid[a].get("evidence_refs",[])+byid[b].get("evidence_refs",[])))})
    for e in elements:
        p=e.get("parent_id")
        if p and p in byid:add(p,e["element_id"],"CONTAINS",0,.99);add(e["element_id"],p,"INSIDE",0,.99)
    mats=[e for e in elements if e.get("element_type") in MATERIAL_TYPES]
    for i,a in enumerate(mats):
        ar=_r(a);acx=ar["x"]+ar["width"]/2;acy=ar["y"]+ar["height"]/2
        for b in mats[i+1:i+25]:
            if a.get("parent_id")!=b.get("parent_id") or not a.get("parent_id"):continue
            br=_r(b);bcx=br["x"]+br["width"]/2;bcy=br["y"]+br["height"]/2
            inter=_intersection(ar,br)
            if inter>0:add(a["element_id"],b["element_id"],"OVERLAPS",0,.9);continue
            hgap=max(0,br["x"]-(ar["x"]+ar["width"]),ar["x"]-(br["x"]+br["width"]))
            vgap=max(0,br["y"]-(ar["y"]+ar["height"]),ar["y"]-(br["y"]+br["height"]))
            if abs(acy-bcy)<=align_tol:
                add(a["element_id"],b["element_id"],"SAME_ROW",abs(acy-bcy),.93);add(a["element_id"],b["element_id"],"ALIGNED_CENTER_Y",abs(acy-bcy),.93)
                if ar["x"]+ar["width"]<=br["x"]:add(a["element_id"],b["element_id"],"LEFT_OF",hgap,.94)
                elif br["x"]+br["width"]<=ar["x"]:add(a["element_id"],b["element_id"],"RIGHT_OF",hgap,.94)
            if abs(acx-bcx)<=align_tol:
                add(a["element_id"],b["element_id"],"SAME_COLUMN",abs(acx-bcx),.93);add(a["element_id"],b["element_id"],"ALIGNED_CENTER_X",abs(acx-bcx),.93)
                if ar["y"]+ar["height"]<=br["y"]:add(a["element_id"],b["element_id"],"ABOVE",vgap,.94)
                elif br["y"]+br["height"]<=ar["y"]:add(a["element_id"],b["element_id"],"BELOW",vgap,.94)
            if min(hgap,vgap)<=adj and (abs(acy-bcy)<=max(ar["height"],br["height"]) or abs(acx-bcx)<=max(ar["width"],br["width"])):add(a["element_id"],b["element_id"],"ADJACENT",min(hgap,vgap),.82)
            if abs(ar["x"]-br["x"])<=align_tol:add(a["element_id"],b["element_id"],"ALIGNED_LEFT",abs(ar["x"]-br["x"]),.9)
            if abs((ar["x"]+ar["width"])-(br["x"]+br["width"]))<=align_tol:add(a["element_id"],b["element_id"],"ALIGNED_RIGHT",abs((ar["x"]+ar["width"])-(br["x"]+br["width"])),.9)
    return out

def _padding_estimate(parent:dict[str,Any],children:list[dict[str,Any]])->dict[str,Any]:
    if not children:return {"top":None,"right":None,"bottom":None,"left":None,"kind":"NOT_OBSERVABLE","resolution_status":"NOT_OBSERVABLE"}
    p=_r(parent);rs=[_r(c) for c in children]
    vals={"top":min(r["y"] for r in rs)-p["y"],"left":min(r["x"] for r in rs)-p["x"],"right":p["x"]+p["width"]-max(r["x"]+r["width"] for r in rs),"bottom":p["y"]+p["height"]-max(r["y"]+r["height"] for r in rs)}
    return {k:round(max(0,float(v)),2) for k,v in vals.items()}|{"kind":"ESTIMATED_VISUAL_STYLE","resolution_status":"RESOLVED_ESTIMATED"}

def _layout_regions(elements:list[dict[str,Any]],vw:int,vh:int)->list[dict[str,Any]]:
    byparent:dict[str,list[dict[str,Any]]]={}
    for e in elements:
        if e.get("parent_id"):byparent.setdefault(e["parent_id"],[]).append(e)
    out=[]
    for e in elements:
        if e.get("element_type") not in CONTAINER_TYPES:continue
        r=_r(e);children=byparent.get(e["element_id"],[])
        out.append({"layout_region_id":"LR-"+e["element_id"],"element_id":e["element_id"],"semantic_role":e.get("semantic_role"),"viewport_box_px":{k:int(round(v)) for k,v in r.items()},"viewport_fraction":round((r["width"]*r["height"])/(vw*vh),8),"estimated_padding_px":_padding_estimate(e,children),"child_count":len(children),"alignment_model":"OBSERVED_FREEFORM","clipping":e.get("geometry",{}).get("clipping","UNKNOWN"),"confidence":round(float(e.get("confidence",.5)),6)})
    return out

def _style_signature(e:dict[str,Any])->tuple:
    s=e.get("visual_style",{});t=s.get("typography",{});fg=s.get("foreground",{});bg=s.get("background",{});rad=s.get("radius",{})
    def q(h):
        if not isinstance(h,str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}",h):return h
        rgb=[int(h[i:i+2],16) for i in (1,3,5)];return tuple(int(round(x/16))*16 for x in rgb)
    return (e.get("element_type"),t.get("font_weight_class"),round(float(t.get("estimated_font_size_px") or 0)/2)*2,q(fg.get("hex")),q(bg.get("hex")),round(float(rad.get("estimated_radius_px") or 0)/2)*2)

def observed_style_clusters(elements:list[dict[str,Any]])->list[dict[str,Any]]:
    buckets:dict[tuple,list[str]]={}
    for e in elements:
        if e.get("element_type") not in MATERIAL_TYPES:continue
        buckets.setdefault(_style_signature(e),[]).append(e["element_id"])
    out=[];idx=1
    for sig,members in buckets.items():
        if len(members)<2:continue
        out.append({"observed_style_cluster_id":f"OSC-{idx:03d}","signature":{"element_type":sig[0],"weight":sig[1],"font_size_bucket_px":sig[2],"foreground_hex":sig[3],"background_hex":sig[4],"radius_bucket_px":sig[5]},"member_element_ids":members,"classification":"OBSERVED_STYLE_CLUSTER_NOT_OFFICIAL_TOKEN"});idx+=1
    return out

def _required_style_status(e:dict[str,Any])->dict[str,str]:
    et=e.get("element_type");s=e.get("visual_style",{});req={"geometry":e.get("geometry",{}).get("resolution_status","REMEDIATION_REQUIRED")}
    if et in TEXT_TYPES or e.get("visible_text"):
        t=s.get("typography",{});req|={"text_group":"REMEDIATION_REQUIRED","text_color":t.get("text_color",{}).get("resolution_status",s.get("foreground",{}).get("resolution_status","REMEDIATION_REQUIRED")),"visual_text_height":"RESOLVED_OBSERVED" if t.get("visual_text_height_px") is not None else "NOT_OBSERVABLE","font_size":t.get("resolution_status","NOT_OBSERVABLE"),"weight":"RESOLVED_ESTIMATED" if t.get("font_weight_class") not in (None,"UNKNOWN") else "NOT_OBSERVABLE","style":"NOT_OBSERVABLE" if t.get("font_style")=="UNKNOWN" else "RESOLVED_ESTIMATED","decoration":"RESOLVED_ESTIMATED" if t.get("text_decoration") else "NOT_OBSERVABLE","alignment":"RESOLVED_ESTIMATED","line_height":t.get("line_height_kind","NOT_OBSERVABLE").replace("ESTIMATED_VISUAL_STYLE","RESOLVED_ESTIMATED") if isinstance(t.get("line_height_kind"),str) else "NOT_OBSERVABLE"}
    if et in CONTROL_TYPES:req|={"background":s.get("background",{}).get("resolution_status","REMEDIATION_REQUIRED"),"border":s.get("border",{}).get("resolution_status","NOT_OBSERVABLE"),"radius":s.get("radius",{}).get("resolution_status","NOT_OBSERVABLE"),"padding":"RESOLVED_ESTIMATED"}
    if et in CONTAINER_TYPES:req|={"background":s.get("background",{}).get("resolution_status","NOT_OBSERVABLE"),"border":s.get("border",{}).get("resolution_status","NOT_OBSERVABLE"),"radius":s.get("radius",{}).get("resolution_status","NOT_OBSERVABLE"),"shadow":s.get("shadow",{}).get("resolution_status","NOT_OBSERVABLE"),"padding":"RESOLVED_ESTIMATED"}
    if et in GRAPHIC_TYPES:req|={"foreground":s.get("foreground",{}).get("resolution_status","NOT_OBSERVABLE"),"background":s.get("background",{}).get("resolution_status","NOT_OBSERVABLE")}
    return req

def visual_fidelity_summary(candidate:dict[str,Any],aux_reconciliation:dict[str,Any]|None=None)->dict[str,Any]:
    els=candidate.get("elements",[]);m=[e for e in els if e.get("element_type") in MATERIAL_TYPES];containers=[e for e in m if e.get("element_type") in CONTAINER_TYPES];texts=[e for e in m if e.get("visible_text")];controls=[e for e in m if e.get("element_type") in CONTROL_TYPES]
    groups=candidate.get("text_groups",[]);member_ids={x for g in groups for x in g.get("member_element_ids",[])}
    def cov(items,pred):return round(sum(1 for x in items if pred(x))/len(items),6) if items else 1.0
    geom=cov(m,lambda e:e.get("geometry",{}).get("resolution_status") in {"RESOLVED_OBSERVED","RESOLVED_ESTIMATED"})
    cgeom=cov(containers,lambda e:e.get("geometry",{}).get("viewport_box_px",{}).get("width",0)>0 and e.get("geometry",{}).get("viewport_box_px",{}).get("height",0)>0)
    tg=cov(texts,lambda e:e["element_id"] in member_ids)
    ts=cov(texts,lambda e:e.get("visual_style",{}).get("typography",{}).get("visual_text_height_px") is not None)
    color=cov(m,lambda e:e.get("visual_style",{}).get("background",{}).get("resolution_status") in {"RESOLVED_OBSERVED","RESOLVED_ESTIMATED","NOT_APPLICABLE"})
    ctrl=cov(controls,lambda e:all(e.get("visual_style",{}).get(k,{}).get("resolution_status") in RESOLUTION_STATES for k in ("background","border","radius")))
    unsupported=0;style_missing=0;geom_missing=0
    for e in m:
        g=e.get("geometry",{})
        if g.get("resolution_status")=="REMEDIATION_REQUIRED":geom_missing+=1
        t=e.get("visual_style",{}).get("typography",{})
        if t.get("font_family") and t.get("font_family_kind") not in {"DECLARED_DOM_COMPUTED_STYLE","DECLARED_FIGMA_NODE","DECLARED_DESIGN_TOKEN","RECONCILED"}:unsupported+=1
        if t.get("estimated_font_size_px") is not None and t.get("font_size_kind") not in {"ESTIMATED_VISUAL_STYLE","DECLARED_DOM_COMPUTED_STYLE","DECLARED_FIGMA_NODE","DECLARED_DESIGN_TOKEN","RECONCILED"}:unsupported+=1
        if any(v=="REMEDIATION_REQUIRED" for v in e.get("fidelity_property_status",{}).values()):style_missing+=1
    aux=aux_reconciliation or {};mism=aux.get("summary",{}).get("mismatches_total",0);crit=aux.get("summary",{}).get("mismatches_critical",0)
    rels=candidate.get("spatial_relations",[]);rel_ok=1.0 if all(r.get("relation_type") in RELATION_TYPES for r in rels) else 0.0
    result="PASS_VISUAL_FIDELITY" if min(geom,cgeom,tg)>=1 and unsupported==0 and geom_missing==0 and style_missing==0 and crit==0 else "BLOCKED_VISUAL_FIDELITY"
    return {"material_geometry_coverage":geom,"material_container_geometry_coverage":cgeom,"text_grouping_coverage":tg,"text_style_coverage":ts,"color_profile_coverage":color,"control_style_coverage":ctrl,"spatial_relation_consistency":rel_ok,"unsupported_exact_style_claims":unsupported,"grouping_conflicts":0 if tg==1 else len(texts)-len(member_ids&{e['element_id'] for e in texts}),"layout_conflicts":geom_missing,"style_conflicts":style_missing,"auxiliary_mismatches_total":mism,"auxiliary_mismatches_critical":crit,"visual_fidelity_remediations_before":int(candidate.get("visual_fidelity_remediations_before",0)),"visual_fidelity_remediations_after":int(candidate.get("visual_fidelity_remediations_after",0)),"final_visual_fidelity_result":result}

def enrich_candidate(legacy:dict[str,Any],image_path:Path|None=None,config:dict[str,Any]|None=None)->dict[str,Any]:
    """Create p0-consolidated-visual-reading/v2 from a V1/legacy payload without mutating it."""
    before=canonical_sha(legacy);out=copy.deepcopy(legacy);vw,vh=_viewport_size(out);byid={e["element_id"]:e for e in out.get("elements",[])};_,_,img=_load_image(image_path)
    for e in out.get("elements",[]):
        e["geometry"]=geometry_profile(e,byid.get(e.get("parent_id")),vw,vh)
        e["visual_style"]=visual_style_profile(e,img)
    out["text_groups"]=build_text_groups(out.get("elements",[]),config)
    group_members={x for g in out["text_groups"] for x in g.get("member_element_ids",[])}
    for e in out.get("elements",[]):
        e["fidelity_property_status"]=_required_style_status(e)
        if e.get("visible_text") and e["element_id"] in group_members:e["fidelity_property_status"]["text_group"]="RESOLVED_OBSERVED"
    out["spatial_relations"]=build_spatial_relations(out.get("elements",[]),config)
    out["layout_regions"]=_layout_regions(out.get("elements",[]),vw,vh)
    out["observed_style_clusters"]=observed_style_clusters(out.get("elements",[]))
    out["visual_fidelity_summary"]={}
    out["legacy_semantic_sha256"]=before
    out["schema_version"]="p0-consolidated-visual-reading/v2"
    out["visual_fidelity_summary"]=visual_fidelity_summary(out)
    out["blind_lock"]={"input_sha256":before,"output_sha256":canonical_sha(out),"auxiliary_context_before_lock":False,"blind_output_mutated":False}
    if canonical_sha(legacy)!=before:raise RuntimeError("blind_input_mutated")
    return out

def remediate_visual_fidelity(candidate:dict[str,Any],image_path:Path|None=None,config:dict[str,Any]|None=None,max_cycles:int=3)->tuple[dict[str,Any],list[dict[str,Any]]]:
    c=copy.deepcopy(candidate);history=[]
    semantic_anchor=canonical_sha({"elements":[{k:e.get(k) for k in ("element_id","element_type","visible_text","semantic_role","classification")} for e in c.get("elements",[])]})
    for cycle in range(1,max_cycles+1):
        findings=[]
        groups=build_text_groups(c.get("elements",[]),config);members={x for g in groups for x in g.get("member_element_ids",[])};texts=[e for e in c.get("elements",[]) if e.get("visible_text")]
        if any(e["element_id"] not in members for e in texts) or c.get("text_groups")!=groups:
            findings.append("TEXT_GROUP_REBUILD");c["text_groups"]=groups
        vw,vh=_viewport_size(c);byid={e["element_id"]:e for e in c.get("elements",[])};_,_,img=_load_image(image_path)
        for e in c.get("elements",[]):
            if not e.get("geometry") or e.get("geometry",{}).get("resolution_status")=="REMEDIATION_REQUIRED":e["geometry"]=geometry_profile(e,byid.get(e.get("parent_id")),vw,vh);findings.append("GEOMETRY_RECOMPUTE")
            if not e.get("visual_style"):
                e["visual_style"]=visual_style_profile(e,img);findings.append("STYLE_RECOMPUTE")
        c["spatial_relations"]=build_spatial_relations(c.get("elements",[]),config);c["layout_regions"]=_layout_regions(c.get("elements",[]),vw,vh);c["observed_style_clusters"]=observed_style_clusters(c.get("elements",[]))
        members={x for g in c.get("text_groups",[]) for x in g.get("member_element_ids",[])}
        for e in c.get("elements",[]):
            e["fidelity_property_status"]=_required_style_status(e)
            if e.get("visible_text") and e["element_id"] in members:e["fidelity_property_status"]["text_group"]="RESOLVED_OBSERVED"
        c["visual_fidelity_remediations_before"]=len(findings);c["visual_fidelity_remediations_after"]=0;c["visual_fidelity_summary"]=visual_fidelity_summary(c)
        history.append({"cycle":cycle,"strategies":sorted(set(findings)),"result":c["visual_fidelity_summary"]["final_visual_fidelity_result"]})
        if not findings or c["visual_fidelity_summary"]["final_visual_fidelity_result"]=="PASS_VISUAL_FIDELITY":break
    if canonical_sha({"elements":[{k:e.get(k) for k in ("element_id","element_type","visible_text","semantic_role","classification")} for e in c.get("elements",[])]})!=semantic_anchor:raise RuntimeError("semantic_v2_output_degraded_by_fidelity_remediation")
    return c,history

def validate_visual_fidelity(candidate:dict[str,Any],aux_reconciliation:dict[str,Any]|None=None,config:dict[str,Any]|None=None)->dict[str,Any]:
    cfg=config or {};vw,vh=_viewport_size(candidate);errors=[];warnings=[];els=candidate.get("elements",[]);byid={e.get("element_id"):e for e in els}
    if candidate.get("schema_version")!="p0-consolidated-visual-reading/v2":errors.append("WRONG_SCHEMA_VERSION")
    for e in els:
        eid=e.get("element_id","?");g=e.get("geometry")
        if not g:errors.append(f"MISSING_GEOMETRY:{eid}");continue
        b=g.get("viewport_box_px") or {};x=b.get("x");y=b.get("y");w=b.get("width");h=b.get("height")
        if any(v is None for v in (x,y,w,h)) or w<=0 or h<=0:errors.append(f"IMPOSSIBLE_GEOMETRY:{eid}")
        elif (x<0 or y<0 or x+w>vw or y+h>vh) and g.get("clipping")!="VISIBLE_CLIPPED":errors.append(f"OUT_OF_VIEWPORT_WITHOUT_CLIPPING:{eid}")
        p=byid.get(e.get("parent_id"))
        if p and e.get("element_type")!="SCREEN":
            tol=float(cfg.get("geometry",{}).get("parent_containment_tolerance_px",10))
            if not _contains(_r(p),_r(e),tol) and g.get("clipping")!="VISIBLE_CLIPPED":errors.append(f"PARENT_CHILD_GEOMETRY_CONFLICT:{eid}")
        t=e.get("visual_style",{}).get("typography",{})
        if t.get("font_family") and t.get("font_family_kind") not in {"DECLARED_DOM_COMPUTED_STYLE","DECLARED_FIGMA_NODE","DECLARED_DESIGN_TOKEN","RECONCILED"}:errors.append(f"UNSUPPORTED_EXACT_FONT_FAMILY:{eid}")
        if t.get("estimated_font_size_px") is not None and t.get("font_size_kind")=="OBSERVED_PIXEL_STYLE":errors.append(f"UNSUPPORTED_EXACT_CSS_FONT_SIZE:{eid}")
        for color_role in ("foreground","background"):
            cp=e.get("visual_style",{}).get(color_role,{})
            rgb=cp.get("rgb");hx=cp.get("hex")
            if rgb and hx and _hex([int(x) for x in rgb]).upper()!=str(hx).upper():errors.append(f"COLOR_HEX_RGB_INCONSISTENT:{eid}:{color_role}")
        if e.get("element_type") in MATERIAL_TYPES:
            statuses=e.get("fidelity_property_status")
            if not statuses:errors.append(f"MISSING_FIDELITY_PROPERTY_MATRIX:{eid}")
            elif set(_required_style_status(e))-set(statuses):errors.append(f"SILENT_STYLE_PROPERTY_MISSING:{eid}")
            elif any(v not in RESOLUTION_STATES for v in statuses.values()):errors.append(f"SILENT_OR_INVALID_STYLE_STATUS:{eid}")
            elif any(v=="REMEDIATION_REQUIRED" for v in statuses.values()):errors.append(f"PENDING_MACHINE_REMEDIATION:{eid}")
    groups=candidate.get("text_groups")
    if groups is None:errors.append("MISSING_TEXT_GROUPS")
    else:
        seen={}
        for g in groups:
            if not g.get("group_text"):errors.append("EMPTY_TEXT_GROUP")
            members=g.get("member_element_ids",[])
            if not members:errors.append("TEXT_GROUP_WITHOUT_MEMBERS")
            parents={byid.get(x,{}).get("parent_id") for x in members}
            if len(parents)>1:errors.append(f"TEXT_GROUP_OVERMERGE:{g.get('text_group_id')}")
            if len(members)>1 and any(byid.get(x,{}).get("element_type") in CONTROL_TYPES for x in members):errors.append(f"TEXT_GROUP_CONTROL_OVERMERGE:{g.get('text_group_id')}")
            for x in members:
                if x in seen:errors.append(f"ELEMENT_IN_MULTIPLE_TEXT_GROUPS:{x}")
                seen[x]=g.get("text_group_id")
        required=[e["element_id"] for e in els if e.get("visible_text")]
        for x in required:
            if x not in seen:errors.append(f"SPLIT_OR_UNGROUPED_TEXT:{x}")
    for rel in candidate.get("spatial_relations",[]):
        if rel.get("relation_type") not in RELATION_TYPES:errors.append("INVALID_SPATIAL_RELATION")
        if rel.get("source_element_id") not in byid or rel.get("target_element_id") not in byid:errors.append("DANGLING_SPATIAL_RELATION")
    if aux_reconciliation:
        if aux_reconciliation.get("blind_output_sha256")!=canonical_sha({k:v for k,v in candidate.items() if k!="_transient"}):errors.append("AUXILIARY_BLIND_SHA_MISMATCH")
        if aux_reconciliation.get("blind_output_mutated") is True:errors.append("AUXILIARY_MUTATED_BLIND_OUTPUT")
        if aux_reconciliation.get("summary",{}).get("mismatches_critical",0)>0:errors.append("CRITICAL_AUXILIARY_MISMATCH")
        for rc in aux_reconciliation.get("reconciliations",[]):
            if rc.get("critical") and rc.get("reconciliation",{}).get("status")=="MATCH" and rc.get("observed",{}).get("value")!=rc.get("declared",{}).get("value"):errors.append("HIDDEN_CRITICAL_AUXILIARY_MISMATCH")
    summary=visual_fidelity_summary(candidate,aux_reconciliation)
    if errors:summary["final_visual_fidelity_result"]="BLOCKED_VISUAL_FIDELITY"
    return {"schema_version":"p0-visual-fidelity-report/v1","candidate_sha256":canonical_sha(candidate),"checks":{"semantic_completeness_preserved":bool(candidate.get("legacy_semantic_sha256")),"geometry_valid":not any("GEOMETRY" in x or "VIEWPORT" in x for x in errors),"text_grouping_valid":not any("TEXT_GROUP" in x or "UNGROUPED" in x for x in errors),"unsupported_exact_style_claims_zero":not any("UNSUPPORTED_EXACT" in x for x in errors),"blind_enriched_provenance_integrity":not any("AUXILIARY" in x for x in errors)},"metrics":summary,"errors":errors,"warnings":warnings,"result":"PASS_VISUAL_FIDELITY" if not errors and summary["final_visual_fidelity_result"]=="PASS_VISUAL_FIDELITY" else "BLOCKED_VISUAL_FIDELITY"}

def _get_path(obj:dict[str,Any],path:str):
    cur:Any=obj
    for part in path.split("."):
        if isinstance(cur,dict):cur=cur.get(part)
        else:return None
    return cur

def reconcile_auxiliary(blind:dict[str,Any],aux:dict[str,Any],config:dict[str,Any]|None=None)->dict[str,Any]:
    """P0X: create a separate reconciliation artifact; never mutate blind."""
    before=canonical_sha(blind);cfg=config or {};errors=[]
    required=("source_type","source_version","source_sha256","captured_at","screen_mapping","provenance","trust_level","authorization")
    for k in required:
        if not aux.get(k):errors.append(f"AUX_SOURCE_MISSING_{k.upper()}")
    if aux.get("source_sha256") and not re.fullmatch(r"[0-9a-fA-F]{64}",str(aux.get("source_sha256"))):errors.append("AUX_SOURCE_SHA_INVALID")
    if aux.get("screen_mapping") and blind.get("source_image_ref") and blind.get("source_image_ref") not in json.dumps(aux.get("screen_mapping"),ensure_ascii=False):errors.append("STALE_OR_WRONG_SCREEN_MAPPING")
    reconciliations=[];critical=0;mism=0
    for claim in aux.get("claims",[]):
        eid=claim.get("element_id");prop=claim.get("property");decl=claim.get("value");kind=claim.get("kind")
        e=next((x for x in blind.get("elements",[]) if x.get("element_id")==eid),None)
        obs=_get_path(e or {},prop or "")
        if e is None or not prop:status="NOT_COMPARABLE";delta=None
        elif obs is None:status="DECLARED_ONLY";delta=None
        elif isinstance(obs,(int,float)) and isinstance(decl,(int,float)):
            delta=abs(float(obs)-float(decl));tol=float(cfg.get("reconciliation",{}).get("numeric_match_tolerance",1.0));approx=float(cfg.get("reconciliation",{}).get("numeric_approx_tolerance",3.0));status="MATCH" if delta<=tol else "APPROX_MATCH" if delta<=approx else "MISMATCH"
        elif isinstance(obs,str) and isinstance(decl,str):
            delta=None;status="MATCH" if obs.casefold()==decl.casefold() else "MISMATCH"
        else:delta=None;status="NOT_COMPARABLE"
        if status=="MISMATCH":mism+=1
        iscrit=bool(claim.get("critical")) and status=="MISMATCH";critical+=int(iscrit)
        reconciliations.append({"element_id":eid,"property":prop,"observed":{"value":obs,"kind":"OBSERVED_OR_ESTIMATED_BLIND"},"declared":{"value":decl,"kind":kind},"reconciliation":{"status":status,"delta":delta,"threshold_ref":"config://p0-visual-fidelity-v3/reconciliation","confidence":.98 if status in {"MATCH","MISMATCH"} else .8},"critical":bool(claim.get("critical"))})
    after=canonical_sha(blind)
    if after!=before:errors.append("BLIND_OUTPUT_MUTATED_DURING_P0X")
    return {"schema_version":"p0-enriched-design-reconciliation/v1","blind_output_sha256":before,"auxiliary_source_sha256":aux.get("source_sha256"),"auxiliary_source_type":aux.get("source_type"),"reconciliations":reconciliations,"summary":{"mismatches_total":mism,"mismatches_critical":critical,"source_errors":errors},"blind_output_mutated":after!=before,"result":"BLOCKED_AUXILIARY_CONFLICT" if errors or critical else "PASS_RECONCILIATION"}

def human_review_packet(candidate:dict[str,Any],report:dict[str,Any],reconciliation:dict[str,Any]|None=None,remediation_history:list[dict[str,Any]]|None=None)->dict[str,Any]:
    exceptions=[]
    for e in candidate.get("elements",[]):
        if e.get("classification")=="INFERRED" or any(v=="REMEDIATION_REQUIRED" for v in e.get("fidelity_property_status",{}).values()):exceptions.append({"element_id":e.get("element_id"),"reason":"INFERRED_OR_REMEDIATION","confidence":e.get("confidence")})
    for x in (reconciliation or {}).get("reconciliations",[]):
        if x.get("reconciliation",{}).get("status")=="MISMATCH":exceptions.append({"element_id":x.get("element_id"),"reason":"AUXILIARY_MISMATCH","property":x.get("property"),"critical":x.get("critical",False)})
    resolved=max(0,len(candidate.get("elements",[]))-len({x.get("element_id") for x in exceptions}))
    return {"schema_version":"p0-human-review-packet-v4/v1","candidate_sha256":canonical_sha(candidate),"fidelity_report_sha256":canonical_sha(report),"human_review_ready":report.get("result")=="PASS_VISUAL_FIDELITY","screen_summary":{"material_elements":len(candidate.get("elements",[])),"automatically_resolved":resolved,"human_attention_required":len(exceptions),"visual_fidelity_result":report.get("result")},"layout_regions":candidate.get("layout_regions",[]),"typography_summary":_typography_summary(candidate),"color_summary":_color_summary(candidate),"text_groups":candidate.get("text_groups",[]),"human_attention_required":exceptions,"automatically_resolved_count":resolved,"remediation_history":remediation_history or [],"reconciliation":reconciliation,"technical_appendix":{"elements":candidate.get("elements",[]),"spatial_relations":candidate.get("spatial_relations",[]),"observed_style_clusters":candidate.get("observed_style_clusters",[])}}

def _typography_summary(candidate:dict[str,Any])->list[dict[str,Any]]:
    buckets={}
    for e in candidate.get("elements",[]):
        if not e.get("visible_text"):continue
        t=e.get("visual_style",{}).get("typography",{});key=(round(float(t.get("estimated_font_size_px") or 0),1),t.get("font_weight_class"),e.get("visual_style",{}).get("foreground",{}).get("hex"),tuple(t.get("text_decoration",[])))
        b=buckets.setdefault(key,{"use":e.get("semantic_role"),"estimated_font_size_px":key[0],"weight":key[1],"color":key[2],"decoration":list(key[3]),"element_ids":[]});b["element_ids"].append(e["element_id"])
    return [{"group":f"TYPE-{i:02d}",**b,"element_count":len(b["element_ids"])} for i,b in enumerate(buckets.values(),1)]

def _color_summary(candidate:dict[str,Any])->list[dict[str,Any]]:
    buckets={}
    for e in candidate.get("elements",[]):
        for role in ("foreground","background"):
            p=e.get("visual_style",{}).get(role,{})
            hx=p.get("hex")
            if not hx:continue
            b=buckets.setdefault((hx,role),{"hex":hx,"rgb":p.get("rgb"),"role":role,"appearances":0,"confidence":[]});b["appearances"]+=1;b["confidence"].append(float(p.get("confidence",0)))
    return [{**b,"confidence":round(sum(b.pop("confidence"))/max(1,b["appearances"]),6)} for b in buckets.values()]

def build_human_html(packet:dict[str,Any],candidate:dict[str,Any],image_path:Path|None=None)->str:
    img_html="<div class='placeholder'>Screenshot privada no embebida en este artefacto.</div>"
    if image_path and image_path.exists():
        mime="image/png" if image_path.suffix.lower()==".png" else "image/jpeg";b64=base64.b64encode(image_path.read_bytes()).decode();img_html=f"<div class='shotwrap'><img id='shot' src='data:{mime};base64,{b64}'/><svg id='overlay' viewBox='0 0 100 100' preserveAspectRatio='none'></svg></div>"
    def rows(items,cols):
        return "".join("<tr>"+"".join(f"<td>{html.escape(str(it.get(c,'')))}</td>" for c in cols)+"</tr>" for it in items)
    layout=packet.get("layout_regions",[]);types=packet.get("typography_summary",[]);colors=packet.get("color_summary",[]);groups=packet.get("text_groups",[]);exceptions=packet.get("human_attention_required",[])
    swatches="".join(f"<div class='sw'><i style='background:{html.escape(str(c.get('hex')))}'></i><b>{html.escape(str(c.get('hex')))}</b> · {html.escape(str(c.get('role')))} · {c.get('appearances')}</div>" for c in colors)
    element_details="".join(f"<details><summary>{html.escape(str(e.get('element_id')))} · {html.escape(str(e.get('element_type')))} · {html.escape(str(e.get('visible_text') or ''))}</summary><pre>{html.escape(json.dumps(e,ensure_ascii=False,indent=2))}</pre></details>" for e in candidate.get("elements",[]))
    boxes=json.dumps([{"id":e.get("element_id"),"r":e.get("geometry",{}).get("viewport_box_normalized",{})} for e in candidate.get("elements",[]) if e.get("geometry")])
    return f"""<!doctype html><html><head><meta charset='utf-8'><title>P0 V3 Human Review</title><style>body{{font:14px system-ui;margin:24px;color:#202124}}h1,h2{{margin-top:28px}}.grid{{display:grid;grid-template-columns:1.3fr 1fr;gap:18px}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #ddd;padding:6px;vertical-align:top}}.sw{{display:flex;align-items:center;gap:8px;margin:5px 0}}.sw i{{width:32px;height:22px;border:1px solid #aaa;display:inline-block}}.shotwrap{{position:relative;max-width:100%;display:inline-block}}#shot{{max-width:100%;display:block}}#overlay{{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}}.exc{{border-left:4px solid #b3261e;padding:8px;background:#fff4f2}}.ok{{border-left:4px solid #137333;padding:8px;background:#f2fff5}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;background:#f6f8fa;padding:10px}}details{{margin:5px 0}}.placeholder{{padding:40px;background:#f6f8fa}}</style></head><body><h1>P0 V3 · Revisión humana por excepción</h1><section><h2>1. Resumen ejecutivo</h2><div class='ok'>Resultado máquina: <b>{html.escape(str(packet.get('screen_summary',{}).get('visual_fidelity_result')))}</b> · resueltos automáticamente: {packet.get('automatically_resolved_count',0)} · excepciones: {len(exceptions)}</div></section><section><h2>2. Screenshot + overlay</h2>{img_html}</section><section><h2>3. Excepciones que requieren humano</h2><div class='exc'><pre>{html.escape(json.dumps(exceptions,ensure_ascii=False,indent=2))}</pre></div></section><section><h2>4. Layout principal</h2><table><tr><th>Región</th><th>Rol</th><th>Box</th><th>% viewport</th><th>Padding est.</th><th>Hijos</th></tr>{rows(layout,['layout_region_id','semantic_role','viewport_box_px','viewport_fraction','estimated_padding_px','child_count'])}</table></section><section><h2>5. Jerarquía tipográfica</h2><table><tr><th>Grupo</th><th>Uso</th><th>Tamaño estimado</th><th>Peso</th><th>Color</th><th>Decoración</th><th>N</th></tr>{rows(types,['group','use','estimated_font_size_px','weight','color','decoration','element_count'])}</table></section><section><h2>6. Paleta observada</h2>{swatches or '<p>Sin colores resueltos.</p>'}</section><section><h2>7. Borders / radius / shadows</h2><p>Disponibles al expandir cada elemento; valores screenshot-only permanecen observados/estimados, no tokens oficiales.</p></section><section><h2>8. Text groups</h2><table><tr><th>ID</th><th>Texto</th><th>Miembros</th><th>Basis</th><th>Conf.</th></tr>{rows(groups,['text_group_id','group_text','member_element_ids','grouping_basis','confidence'])}</table></section><section><h2>9. Reconciliación observed vs declared</h2><pre>{html.escape(json.dumps(packet.get('reconciliation'),ensure_ascii=False,indent=2))}</pre></section><section><h2>10. Remediaciones automáticas</h2><pre>{html.escape(json.dumps(packet.get('remediation_history',[]),ensure_ascii=False,indent=2))}</pre></section><section><h2>11. Anexo técnico</h2>{element_details}</section><script>const boxes={boxes};const svg=document.getElementById('overlay');if(svg){{for(const b of boxes){{const r=b.r;if(!r||r.width===undefined)continue;const x=r.x*100,y=r.y*100,w=r.width*100,h=r.height*100;const q=document.createElementNS('http://www.w3.org/2000/svg','rect');q.setAttribute('x',x);q.setAttribute('y',y);q.setAttribute('width',w);q.setAttribute('height',h);q.setAttribute('fill','none');q.setAttribute('stroke','rgba(220,30,30,.45)');q.setAttribute('stroke-width','.15');svg.appendChild(q);}}}}</script></body></html>"""


def compare_viewports(candidates:list[dict[str,Any]],config:dict[str,Any]|None=None)->dict[str,Any]:
    """Compare source-bound viewports. A single screenshot never yields breakpoint claims."""
    if len(candidates)<2:return {"viewport_count":len(candidates),"breakpoints":[],"responsive_claims":[],"status":"NOT_OBSERVABLE_SINGLE_VIEWPORT"}
    claims=[]
    bysets=[]
    for c in candidates:
        vw,vh=_viewport_size(c);bysets.append((vw,vh,{e.get("semantic_role") or e.get("element_id"):e for e in c.get("elements",[]) if e.get("element_type") in MATERIAL_TYPES}))
    a=bysets[0]
    for b in bysets[1:]:
        common=set(a[2])&set(b[2])
        for k in sorted(common):
            ra=_r(a[2][k]);rb=_r(b[2][k]);na=_norm_box(ra,a[0],a[1]);nb=_norm_box(rb,b[0],b[1])
            dx=abs(na['x']-nb['x']);dy=abs(na['y']-nb['y']);dw=abs(na['width']-nb['width'])
            if max(dx,dy,dw)>.08:claims.append({'element_key':k,'relation':'OBSERVED_REFLOW_OR_RESIZE','from_viewport':[a[0],a[1]],'to_viewport':[b[0],b[1]],'normalized_delta':round(max(dx,dy,dw),6),'kind':'OBSERVED_MULTI_VIEWPORT'})
    return {'viewport_count':len(candidates),'breakpoints':[],'responsive_claims':claims,'status':'OBSERVED_MULTI_VIEWPORT_COMPARISON'}

def validate_packet_v4(packet:dict[str,Any],report:dict[str,Any],candidate:dict[str,Any])->dict[str,Any]:
    errors=[]
    if packet.get('schema_version')!='p0-human-review-packet-v4/v1':errors.append('WRONG_PACKET_SCHEMA')
    if packet.get('candidate_sha256')!=canonical_sha(candidate):errors.append('PACKET_CANDIDATE_SHA_MISMATCH')
    if packet.get('fidelity_report_sha256')!=canonical_sha(report):errors.append('PACKET_REPORT_SHA_MISMATCH')
    if report.get('result')=='PASS_VISUAL_FIDELITY' and packet.get('human_review_ready') is not True:errors.append('PASS_NOT_HUMAN_READY')
    exc=packet.get('human_attention_required',[]);total=len(candidate.get('elements',[]))
    if report.get('result')=='PASS_VISUAL_FIDELITY' and total and len(exc)>=total:errors.append('MASS_MANUAL_REVIEW_OF_RESOLVED_ELEMENTS')
    if packet.get('automatically_resolved_count',-1)+len({x.get('element_id') for x in exc})<0:errors.append('INVALID_RESOLVED_COUNT')
    return {'pass':not errors,'errors':errors}

def validate_html_v4(doc:str)->dict[str,Any]:
    required=['Resumen ejecutivo','Screenshot + overlay','Excepciones que requieren humano','Layout principal','Jerarquía tipográfica','Paleta observada','Text groups','Reconciliación observed vs declared','Remediaciones automáticas','Anexo técnico','viewport_box_px','estimated_font_size_px']
    missing=[x for x in required if x not in doc]
    if "class='sw'" not in doc and 'Sin colores resueltos' not in doc:missing.append('COLOR_SWATCH_SECTION')
    return {'pass':not missing,'missing':missing}

def validate_observed_style_against_bitmap(candidate:dict[str,Any],image_path:Path,config:dict[str,Any]|None=None)->dict[str,Any]:
    """Independent pixel re-read for tamper/mismatch tests used by J00 V3."""
    _,_,img=_load_image(image_path);errors=[];tol=float((config or {}).get('style',{}).get('color_rgb_max_delta',45))
    if img is None:return {'pass':False,'errors':['BITMAP_UNAVAILABLE']}
    for e in candidate.get('elements',[]):
        eid=e.get('element_id');r=_r(e);s=e.get('visual_style',{});fg,bg=_robust_color_profiles(img,r)
        for role,actual in [('foreground',fg),('background',bg)]:
            claim=s.get(role,{})
            if claim.get('kind')!='OBSERVED_PIXEL_COLOR' or not claim.get('rgb') or not actual.get('rgb'):continue
            delta=max(abs(int(a)-int(b)) for a,b in zip(claim['rgb'],actual['rgb']))
            if delta>tol:errors.append(f'PIXEL_COLOR_MISMATCH:{eid}:{role}')
        if e.get('visible_text'):
            tp=s.get('typography',{});u,_=_underline_candidate(img,r,bg.get('rgb'));claimed='UNDERLINE' in tp.get('text_decoration',[])
            if tp.get('text_decoration_kind')=='ESTIMATED_VISUAL_STYLE' and claimed!=u:errors.append(f'TEXT_DECORATION_PIXEL_MISMATCH:{eid}')
        if e.get('element_type') in CONTROL_TYPES|CONTAINER_TYPES:
            br,rad,_=_edge_profile(img,r);cb=s.get('border',{});cr=s.get('radius',{})
            if cb.get('kind')=='ESTIMATED_VISUAL_STYLE' and cb.get('present') is not None and cb.get('present')!=br.get('present'):errors.append(f'BORDER_PIXEL_MISMATCH:{eid}')
            if cr.get('kind')=='ESTIMATED_VISUAL_STYLE' and cr.get('estimated_radius_px') is not None and rad.get('estimated_radius_px') is not None and abs(float(cr['estimated_radius_px'])-float(rad['estimated_radius_px']))>max(4,float(rad['estimated_radius_px'])*.8):errors.append(f'RADIUS_PIXEL_MISMATCH:{eid}')
    return {'pass':not errors,'errors':errors}
