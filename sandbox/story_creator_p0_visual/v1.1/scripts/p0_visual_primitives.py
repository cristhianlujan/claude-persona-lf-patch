#!/usr/bin/env python3
"""P0B-P0E consolidated visual reader from admitted screenshot bytes.

The reader intentionally separates raw OCR from geometry and semantics. OCR is
one evidence source; geometry comes from independent CV contours. Image text is
untrusted and never interpreted as an instruction.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import re
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

ELEMENT_TYPES = {
    "SCREEN","REGION","CONTAINER","BRAND_MARK","TEXT","HEADING","PARAGRAPH","LABEL","INPUT","SELECT","CHECKBOX","RADIO","BUTTON","LINK","ICON","PROGRESS_INDICATOR","BADGE","ILLUSTRATION","DIVIDER","SECURITY_INDICATOR","LEGAL_DISCLOSURE","UNKNOWN_VISUAL_ELEMENT"
}

@dataclass(frozen=True)
class Box:
    x: int; y: int; w: int; h: int
    @property
    def right(self)->int: return self.x+self.w
    @property
    def bottom(self)->int: return self.y+self.h
    @property
    def area(self)->int: return self.w*self.h
    @property
    def cx(self)->float: return self.x+self.w/2
    @property
    def cy(self)->float: return self.y+self.h/2
    def as_region(self)->dict[str,int]: return {"x":self.x,"y":self.y,"width":self.w,"height":self.h}

def iou(a:Box,b:Box)->float:
    x1=max(a.x,b.x); y1=max(a.y,b.y); x2=min(a.right,b.right); y2=min(a.bottom,b.bottom)
    if x2<=x1 or y2<=y1:return 0.0
    inter=(x2-x1)*(y2-y1); return inter/(a.area+b.area-inter)

def contains(outer:Box,inner:Box,tol:int=3)->bool:
    return inner.x>=outer.x-tol and inner.y>=outer.y-tol and inner.right<=outer.right+tol and inner.bottom<=outer.bottom+tol

def sha256_bytes(raw:bytes)->str: return hashlib.sha256(raw).hexdigest()
def canonical_bytes(v:Any)->bytes: return json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()
def canonical_sha(v:Any)->str: return sha256_bytes(canonical_bytes(v))

def _imports():
    import cv2
    import numpy as np
    from PIL import Image
    return cv2,np,Image

def _version(name:str)->str:
    import importlib.metadata as md
    return md.version(name)

def runtime_versions()->dict[str,str]:
    cv2,np,Image=_imports()
    try:
        tv=subprocess.run(["tesseract","--version"],text=True,capture_output=True,check=True).stdout.splitlines()[0].split()[1]
    except Exception:
        tv="UNAVAILABLE"
    return {"tesseract":tv,"Pillow":_version("Pillow"),"numpy":np.__version__,"opencv-python-headless":_version("opencv-python-headless")}

def run_tesseract_tsv(image_path:Path,*,languages:str="spa+eng",psm:int=11,scale:float=1.0)->list[dict[str,Any]]:
    cv2,np,Image=_imports()
    src=cv2.imread(str(image_path),cv2.IMREAD_COLOR)
    if src is None: raise ValueError("source_decode_failed")
    work=src
    if scale!=1.0:
        work=cv2.resize(src,None,fx=scale,fy=scale,interpolation=cv2.INTER_CUBIC)
    with tempfile.NamedTemporaryFile(suffix=".png",delete=False) as tmp:
        tmp_path=Path(tmp.name)
    try:
        cv2.imwrite(str(tmp_path),work)
        proc=subprocess.run(["tesseract",str(tmp_path),"stdout","-l",languages,"--psm",str(psm),"tsv"],text=True,capture_output=True,check=False)
        if proc.returncode!=0: raise RuntimeError("tesseract_failed:"+proc.stderr[-300:])
        rows=[]
        reader=csv.DictReader(io.StringIO(proc.stdout),delimiter="\t")
        for row in reader:
            if row.get("level")!="5" or not (row.get("text") or "").strip(): continue
            try: conf=float(row.get("conf","-1"))
            except ValueError: conf=-1
            x=int(round(int(row["left"])/scale)); y=int(round(int(row["top"])/scale)); w=max(1,int(round(int(row["width"])/scale))); h=max(1,int(round(int(row["height"])/scale)))
            rows.append({"text":row["text"].strip(),"confidence":max(0.0,min(1.0,conf/100.0)),"box":Box(x,y,w,h),
                         "block":row.get("block_num"),"par":row.get("par_num"),"line":row.get("line_num")})
        return rows
    finally:
        tmp_path.unlink(missing_ok=True)

def group_lines(words:list[dict[str,Any]])->list[dict[str,Any]]:
    groups:dict[tuple[str,str,str],list[dict[str,Any]]]={}
    for w in words: groups.setdefault((w["block"],w["par"],w["line"]),[]).append(w)
    out=[]
    for key,items in groups.items():
        items=sorted(items,key=lambda z:z["box"].x)
        x=min(z["box"].x for z in items); y=min(z["box"].y for z in items); r=max(z["box"].right for z in items); b=max(z["box"].bottom for z in items)
        out.append({"text":" ".join(z["text"] for z in items),"confidence":sum(z["confidence"] for z in items)/len(items),"box":Box(x,y,r-x,b-y),"words":items})
    return sorted(out,key=lambda z:(z["box"].y,z["box"].x))

def _ocr_norm(text:str)->str:
    return "".join(ch.casefold() for ch in text if ch.isalnum())

def merge_multiscale_words(scans:list[tuple[float,list[dict[str,Any]]]])->tuple[list[dict[str,Any]],dict[str,int]]:
    """Use scale-1 layout as the spine; higher scales refine/recover source words.

    This avoids duplicate full-screen text while preserving genuinely recovered
    high-resolution-only observations. All coordinates are already mapped back
    to source pixels by ``run_tesseract_tsv``.
    """
    merged:list[dict[str,Any]]=[];counts={}
    for scan_idx,(scale,words) in enumerate(scans):
        counts[str(scale)]=len(words)
        for raw_idx,raw in enumerate(words,1):
            w=dict(raw);obs=f"P0B-OCR-S{scan_idx+1}-{raw_idx:05d}";w["scan_scale"]=scale;w["observation_id"]=obs
            if scan_idx==0:
                w["block"]=f"S1:{w.get('block')}";w["par"]=f"S1:{w.get('par')}";w["line"]=f"S1:{w.get('line')}";merged.append(w);continue
            spatial=[]
            for i,existing in enumerate(merged):
                score=iou(existing["box"],w["box"]);center=abs(existing["box"].cx-w["box"].cx)<10 and abs(existing["box"].cy-w["box"].cy)<10
                if score>=.28 or center:spatial.append((max(score,.30 if center else 0.0),i))
            if spatial:
                _,i=max(spatial);existing=merged[i];same=_ocr_norm(existing["text"])==_ocr_norm(w["text"]) and bool(_ocr_norm(w["text"]))
                text_sim=1.0 if same else __import__('difflib').SequenceMatcher(None,_ocr_norm(existing["text"]),_ocr_norm(w["text"])).ratio()
                existing.setdefault("source_scan_refs",[]).append(obs)
                if w["confidence"]>existing["confidence"]+.08 and (same or text_sim>=.62 or existing["confidence"]<.60):
                    existing["text"]=w["text"];existing["confidence"]=w["confidence"];existing["refined_by_scale"]=scale
                continue
            if w["confidence"]>=.78 and len(_ocr_norm(w["text"]))>=2:
                w["block"]=f"S{scan_idx+1}:{w.get('block')}";w["par"]=f"S{scan_idx+1}:{w.get('par')}";w["line"]=f"S{scan_idx+1}:{w.get('line')}";merged.append(w)
    return merged,counts


def detect_geometry(image_path:Path,*,canny_low:int=45,canny_high:int=120)->dict[str,list[Box]]:
    cv2,np,Image=_imports(); img=cv2.imread(str(image_path));
    if img is None: raise ValueError("source_decode_failed")
    h,w=img.shape[:2]; gray=cv2.cvtColor(img,cv2.COLOR_BGR2GRAY); edges=cv2.Canny(gray,canny_low,canny_high)
    contours,_=cv2.findContours(edges,cv2.RETR_LIST,cv2.CHAIN_APPROX_SIMPLE)
    raw=[]
    for c in contours:
        x,y,bw,bh=cv2.boundingRect(c); area=cv2.contourArea(c)
        if bw<6 or bh<5: continue
        raw.append((Box(x,y,bw,bh),area))
    def dedup(items:Iterable[Box],thr=.86)->list[Box]:
        keep=[]
        for b in sorted(items,key=lambda q:q.area,reverse=True):
            if any(iou(b,k)>=thr for k in keep): continue
            keep.append(b)
        return sorted(keep,key=lambda q:(q.y,q.x,q.area))
    large_cards=dedup([b for b,a in raw if b.w>w*.35 and b.h>h*.30 and b.area<w*h*.95])
    controls=dedup([b for b,a in raw if b.w>w*.18 and 38<=b.h<=85 and b.x>w*.25 and a>b.area*.45])
    wide_actions=dedup([b for b,a in raw if b.w>w*.35 and 35<=b.h<=80 and a>b.area*.45])
    small_squares=dedup([b for b,a in raw if 14<=b.w<=32 and 14<=b.h<=34 and .55<=b.w/b.h<=1.5 and a>30])
    progress=dedup([b for b,a in raw if b.w>w*.10 and 4<=b.h<=14 and b.w/b.h>12 and b.y<h*.30 and a>b.area*.55])
    dividers=dedup([b for b,a in raw if (b.w<5 and b.h>35) or (b.h<5 and b.w>w*.12)])
    return {"large_cards":large_cards,"controls":controls,"wide_actions":wide_actions,"small_squares":small_squares,"progress":progress,"dividers":dividers,"all":[b for b,a in raw]}

def foreground_rgb(image_path:Path,box:Box)->tuple[int,int,int]:
    cv2,np,Image=_imports(); img=cv2.imread(str(image_path)); h,w=img.shape[:2]
    x1=max(0,box.x); y1=max(0,box.y); x2=min(w,box.right); y2=min(h,box.bottom)
    crop=img[y1:y2,x1:x2]
    if crop.size==0:return (0,0,0)
    gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY); mask=gray<210
    if not np.any(mask): return (255,255,255)
    vals=crop[mask]
    med=np.median(vals,axis=0).astype(int)
    return int(med[2]),int(med[1]),int(med[0])

def expanded_background_green(image_path:Path,box:Box,margin:int=22)->float:
    cv2,np,Image=_imports(); img=cv2.imread(str(image_path)); h,w=img.shape[:2]
    x1=max(0,box.x-margin); y1=max(0,box.y-margin); x2=min(w,box.right+margin); y2=min(h,box.bottom+margin)
    hsv=cv2.cvtColor(img[y1:y2,x1:x2],cv2.COLOR_BGR2HSV)
    mask=cv2.inRange(hsv,np.array([35,70,50]),np.array([95,255,255]))
    return float(np.count_nonzero(mask))/max(1,mask.size)

def evidence_ref(source_sha:str,box:Box)->str:
    token=f"{source_sha}:{box.x}:{box.y}:{box.w}:{box.h}".encode(); return f"p0://source-crop/{sha256_bytes(token)}"

def crop_file_sha(image_path:Path,box:Box)->str:
    cv2,np,Image=_imports(); img=cv2.imread(str(image_path)); h,w=img.shape[:2]
    crop=img[max(0,box.y):min(h,box.bottom),max(0,box.x):min(w,box.right)]
    ok,encoded=cv2.imencode('.png',crop)
    if not ok: raise ValueError('crop_encode_failed')
    return sha256_bytes(bytes(encoded))

def _inside_word_runs(line:dict[str,Any],control:Box)->list[dict[str,Any]]:
    words=[w for w in line["words"] if contains(control,w["box"],8)]
    if not words:return []
    words=sorted(words,key=lambda z:z["box"].x)
    runs=[]; cur=[]
    for w in words:
        if cur and w["box"].x-cur[-1]["box"].right>28:
            runs.append(cur);cur=[]
        cur.append(w)
    if cur:runs.append(cur)
    out=[]
    for rs in runs:
        x=min(w["box"].x for w in rs); y=min(w["box"].y for w in rs); r=max(w["box"].right for w in rs); b=max(w["box"].bottom for w in rs)
        out.append({"text":" ".join(w["text"] for w in rs),"confidence":sum(w["confidence"] for w in rs)/len(rs),"box":Box(x,y,r-x,b-y),"words":rs})
    return out
