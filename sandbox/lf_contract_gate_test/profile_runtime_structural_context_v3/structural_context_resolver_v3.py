#!/usr/bin/env python3
"""Structural Context Resolver V3.

Consumes precomputed OCR observations (text+bbox+confidence) and classifies
screen structure without rerunning OCR. It never turns canonical context into
visual evidence: context is used only to reconcile already-visible tokens.
"""
from __future__ import annotations
import argparse, json, re, unicodedata
from collections import Counter
from pathlib import Path

FILTER_ANCHORS = ("buscar","estado","tipo de carga","cargado por","aprobacion","desde","hasta","ordenar por","direccion")
FILTER_VISIBLE = FILTER_ANCHORS + ("todos","todas","mas recientes","limpiar filtros","fecha de creacion")
TABLE_HEADERS = ("lote","nombre","archivo","tipo","cargado por","fecha","total","validos","estado","acciones")
STATE_HINTS = ("procesado","procesado con observaciones","pendiente de aprobacion","validando","rechazado","cancelado","aprobado","autoaprobado")
ROW_ACTION_HINTS = ("ver detalle","original","observados","rechazados")
ROLE_EXACT = {
    "FILTER_BAR": FILTER_VISIBLE,
    "TABLE_HEADER": TABLE_HEADERS,
    "STATE_BADGE": STATE_HINTS,
    "ROW_ACTION": ROW_ACTION_HINTS,
    "TABLE_SUMMARY": ("cargas",),
}

def norm(s:str)->str:
    s=unicodedata.normalize("NFKD", str(s)).encode("ascii","ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+"," ",s).strip()

def _bbox(o):
    if "bbox" in o and isinstance(o["bbox"], (list,tuple)) and len(o["bbox"]) == 4:
        x,y,w,h = o["bbox"]
    else:
        x,y,w,h = o.get("left",0),o.get("top",0),o.get("width",0),o.get("height",0)
    return float(x),float(y),float(w),float(h)

def prepare(observations):
    out=[]
    for i,o in enumerate(observations):
        x,y,w,h=_bbox(o)
        text=str(o.get("text","")).strip()
        if not text or w<=0 or h<=0: continue
        out.append({**o,"id":o.get("id",i),"text":text,"norm":norm(text),
                    "x":x,"y":y,"w":w,"h":h,"r":x+w,"b":y+h,
                    "cx":x+w/2,"cy":y+h/2,"conf":float(o.get("conf",o.get("confidence",100)))})
    return out

def cluster_lines(obs):
    if not obs: return []
    items=sorted(obs,key=lambda o:(o["cy"],o["x"]))
    med_h=sorted(o["h"] for o in items)[len(items)//2]
    lines=[]
    for o in items:
        best=None; best_dist=None
        for line in lines[-4:]:
            tol=max(4.0,0.42*max(med_h,line["median_h"],o["h"]))
            d=abs(o["cy"]-line["cy"])
            if d<=tol and (best_dist is None or d<best_dist):
                best,best_dist=line,d
        if best is None:
            lines.append({"items":[o],"cy":o["cy"],"median_h":o["h"]})
        else:
            best["items"].append(o)
            best["cy"]=sum(x["cy"] for x in best["items"])/len(best["items"])
            hs=sorted(x["h"] for x in best["items"])
            best["median_h"]=hs[len(hs)//2]
    for line in lines:
        line["items"].sort(key=lambda o:o["x"])
        line["text"]=" ".join(o["text"] for o in line["items"])
        line["norm"]=norm(line["text"])
        line["x0"]=min(o["x"] for o in line["items"]); line["x1"]=max(o["r"] for o in line["items"])
    return lines

def phrase_hits(lines, phrases, min_x=0):
    hits=[]
    for ln in lines:
        if ln["x1"] < min_x: continue
        n=ln["norm"]
        for p in phrases:
            if norm(p) in n:
                hits.append((p,ln))
    return hits

def _hint_match(text, hints):
    n=norm(text)
    return any(n == norm(h) or norm(h) in n for h in hints)

def _exact_visible_resolution(item, all_items):
    candidates={norm(x) for x in ROLE_EXACT.get(item["role"],())}
    if not candidates:
        return None
    if item["norm"] in candidates:
        return item["text"]
    neighbors=[]
    for other in all_items:
        if other is item or other["role"] != item["role"]:
            continue
        if abs(other["cy"]-item["cy"]) > max(5.0,0.45*max(item["h"],other["h"])):
            continue
        if other["r"] <= item["x"]:
            gap=item["x"]-other["r"]
        elif item["r"] <= other["x"]:
            gap=other["x"]-item["r"]
        else:
            gap=0.0
        if gap <= 14:
            neighbors.append(other)
    for other in neighbors:
        pair=sorted((item,other),key=lambda x:x["x"])
        visible=" ".join(x["text"] for x in pair)
        if norm(visible) in candidates:
            return visible
    return None

def infer_geometry(obs, width, height):
    lines=cluster_lines(obs)
    content_x=max(220, width*0.16)
    filter_hits=phrase_hits(lines,FILTER_ANCHORS,content_x)
    header_hits=phrase_hits(lines,TABLE_HEADERS,content_x)
    fy=[ln["cy"] for _,ln in filter_hits if ln["cy"] < height*0.36]
    filter_top=min(fy)-18 if fy else height*0.20
    filter_bottom=max(fy)+55 if fy else height*0.36
    candidates={}
    for p,ln in header_hits:
        if ln["cy"] <= filter_bottom: continue
        candidates.setdefault(round(ln["cy"]/8)*8,{"lines":[],"phrases":set()})
        candidates[round(ln["cy"]/8)*8]["lines"].append(ln); candidates[round(ln["cy"]/8)*8]["phrases"].add(p)
    if candidates:
        key=max(candidates,key=lambda k:(len(candidates[k]["phrases"]),k))
        table_header_cy=sum(l["cy"] for l in candidates[key]["lines"])/len(candidates[key]["lines"])
    else:
        table_header_cy=height*0.42
    table_header_top=table_header_cy-22; table_header_bottom=table_header_cy+22
    header_columns={}
    for o in obs:
        if not (table_header_top <= o["cy"] <= table_header_bottom):
            continue
        for header in TABLE_HEADERS:
            hn=norm(header)
            if o["norm"] == hn or (len(hn) > 4 and hn in o["norm"]):
                header_columns.setdefault(header,[]).append(o["cx"])
    header_columns={k:sum(v)/len(v) for k,v in header_columns.items()}
    ordered_columns=sorted((x,k) for k,x in header_columns.items())
    column_bounds={}
    for i,(x,k) in enumerate(ordered_columns):
        left=(ordered_columns[i-1][0]+x)/2 if i else -float("inf")
        right=(x+ordered_columns[i+1][0])/2 if i+1<len(ordered_columns) else float("inf")
        column_bounds[k]=(left,right)
    row_lines=[ln for ln in lines if ln["cy"]>table_header_bottom+8 and ln["cy"]<height*0.82 and ln["x1"]>content_x]
    row_centers=[]
    for ln in row_lines:
        if not row_centers or ln["cy"]-row_centers[-1][-1] > 28:
            row_centers.append([ln["cy"]])
        else: row_centers[-1].append(ln["cy"])
    row_centers=[sum(g)/len(g) for g in row_centers]
    return {
      "content_x":content_x,
      "filter_top":filter_top,"filter_bottom":filter_bottom,
      "table_header_top":table_header_top,"table_header_bottom":table_header_bottom,
      "table_rows_top":table_header_bottom+8,
      "table_rows_bottom":(max(row_centers)+28 if row_centers else height*0.80),
      "pagination_top":height*0.82,
      "line_count":len(lines),"row_centers":row_centers,
      "anchors":{"filter":len(filter_hits),"table_header":len(header_hits)},
      "header_columns":header_columns,"column_bounds":column_bounds
    }, lines

def classify(observations,width,height,context=None):
    context=context or {}
    obs=prepare(observations); g,lines=infer_geometry(obs,width,height)
    out=[]
    for o in obs:
        x,y,cx,cy,n,conf=o["x"],o["y"],o["cx"],o["cy"],o["norm"],o["conf"]
        role="UNKNOWN"; reread=True; material=True
        if cy < height*0.09:
            role="SHELL_TOPBAR"; reread=False
        elif cx < g["content_x"] and cy >= height*0.09:
            role="SHELL_SIDEBAR"; reread=False
        elif cy < height*0.13:
            role="BREADCRUMB"; reread=False
        elif cy < g["filter_top"] and cx >= g["content_x"]:
            role="PAGE_HEADER" if cx < width*0.68 else "PAGE_ACTIONS"; reread=False
        elif g["filter_top"] <= cy <= g["filter_bottom"]:
            role="FILTER_BAR"; reread=False
        elif g["filter_bottom"] < cy < g["table_header_top"]:
            role="TABLE_SUMMARY"; reread=False
        elif g["table_header_top"] <= cy <= g["table_header_bottom"]:
            role="TABLE_HEADER"; reread=False
        elif g["table_rows_top"] <= cy <= g["table_rows_bottom"]:
            state_bounds=g["column_bounds"].get("estado")
            action_bounds=g["column_bounds"].get("acciones")
            if _hint_match(o["text"], ROW_ACTION_HINTS):
                role="ROW_ACTION"; reread=False
            elif _hint_match(o["text"], STATE_HINTS):
                role="STATE_BADGE"; reread=False
            elif action_bounds and action_bounds[0] <= cx <= action_bounds[1]:
                role="ROW_ACTION"; reread=False
            elif state_bounds and state_bounds[0] <= cx <= state_bounds[1]:
                role="STATE_BADGE"; reread=False
            else:
                role="DYNAMIC_DATA"; reread=False
        elif cy >= g["pagination_top"]:
            role="PAGINATION"; reread=False
        if role=="UNKNOWN" and (len(n)<=2 or conf<55):
            role="VISUAL_FRAGMENT"; reread=False; material=False
        if role in {"PAGE_HEADER","PAGE_ACTIONS","FILTER_BAR","TABLE_SUMMARY","TABLE_HEADER","STATE_BADGE","ROW_ACTION"} and conf < 65 and len(n) > 2:
            reread=True
        out.append({**o,"role":role,"needs_reread":reread,"material":material})
    for item in out:
        if not item["needs_reread"]:
            continue
        visible_group=_exact_visible_resolution(item,out)
        if visible_group is not None:
            item["needs_reread"]=False
            item["resolved_by_visible_group"]=True
            item["visible_group_text"]=visible_group
    residual=[o for o in out if o["needs_reread"] and o["material"]]
    visible_header_text = " ".join(o["norm"] for o in out if o["role"]=="TABLE_HEADER")
    canonical_fields = context.get("canonical_table_fields") or []
    overflow = bool(context.get("horizontal_overflow_observed", False))
    canonical_visibility=[]
    for field in canonical_fields:
        fn=norm(field)
        visible = bool(fn and fn in visible_header_text)
        canonical_visibility.append({
          "field":field,
          "status":"VISIBLE" if visible else ("NOT_CURRENTLY_VISIBLE" if overflow else "UNKNOWN_VISIBILITY"),
          "material_omission": False if (visible or overflow) else None
        })
    return {
      "schema":"lf-structural-context-resolver/v3",
      "geometry":g,
      "counts":dict(Counter(o["role"] for o in out)),
      "input_count":len(out),
      "residual_count":len(residual),
      "reread_reduction_pct":round(100*(1-len(residual)/max(1,len(out))),2),
      "visible_group_resolutions":sum(1 for o in out if o.get("resolved_by_visible_group")),
      "residual":[{"id":o["id"],"text":o["text"],"bbox":[o["x"],o["y"],o["w"],o["h"]],"conf":o["conf"],"role":o["role"]} for o in residual],
      "canonical_visibility":canonical_visibility,
      "observations":out
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("observations_json")
    ap.add_argument("--width",type=int,required=True); ap.add_argument("--height",type=int,required=True)
    ap.add_argument("--output",required=True)
    ap.add_argument("--context")
    a=ap.parse_args()
    src=json.loads(Path(a.observations_json).read_text())
    observations=src["observations"] if isinstance(src,dict) else src
    context=json.loads(Path(a.context).read_text()) if a.context else {}
    result=classify(observations,a.width,a.height,context)
    Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps({k:result[k] for k in ("schema","input_count","counts","residual_count","reread_reduction_pct","visible_group_resolutions")},ensure_ascii=False))
if __name__=="__main__": main()
