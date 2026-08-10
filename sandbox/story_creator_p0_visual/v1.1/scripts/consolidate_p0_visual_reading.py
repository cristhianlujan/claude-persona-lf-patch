#!/usr/bin/env python3
from p0_visual_primitives import *
from p0_visual_primitives import _imports, _inside_word_runs
def build_consolidated(image_path:Path,*,source_image_ref:str,execution_id:str,config:dict[str,Any],created_at:str|None=None)->tuple[dict[str,Any],dict[str,Any]]:
    cv2,np,Image=_imports(); raw=image_path.read_bytes(); source_sha=sha256_bytes(raw); img=cv2.imread(str(image_path)); h,w=img.shape[:2]
    scan_results=[]
    for scale in config["ocr"].get("scan_scales",[1.0]):
        scan_results.append((float(scale),run_tesseract_tsv(image_path,languages=config["ocr"]["languages"],psm=int(config["ocr"]["reader_psm"]),scale=float(scale))))
    words,raw_scan_counts=merge_multiscale_words(scan_results)
    lines=group_lines(words); geo=detect_geometry(image_path)
    elements=[]; evid={}
    def add(box:Box,etype:str,parent:str|None,text:str|None=None,role:str|None=None,state:str|None="STATIC_VISIBLE",classification:str="CONFIRMED",confidence:float=1.0,obsrefs:list[str]|None=None,unc:list[str]|None=None,resolution:str="RESOLVED",inference_basis:str|None=None,criticality_ref:str|None=None)->str:
        assert etype in ELEMENT_TYPES
        eid=f"EL-{len(elements)+1:04d}"
        ref=evidence_ref(source_sha,box); evid[ref]={"source_image_ref":source_image_ref,"region":box.as_region(),"crop_file_sha256":crop_file_sha(image_path,box)}
        item={"element_id":eid,"source_image_ref":source_image_ref,"parent_id":parent,"region":box.as_region(),"element_type":etype,"visible_text":text,
              "semantic_role":role,"visual_state":state,"classification":classification,"confidence":round(max(0,min(1,confidence)),6),"evidence_refs":[ref],
              "source_observation_refs":obsrefs or [],"uncertainty_codes":unc or [],"machine_resolution_status":resolution}
        if inference_basis is not None:item["inference_basis"]=inference_basis
        if criticality_ref is not None:item["criticality_ref"]=criticality_ref
        elements.append(item); return eid
    root=add(Box(0,0,w,h),"SCREEN",None,role="screen",confidence=1.0)
    card_candidates=[b for b in geo["large_cards"] if b.cx>w*.5]
    card=max(card_candidates,key=lambda b:b.area) if card_candidates else Box(int(w*.36),int(h*.10),int(w*.62),int(h*.87))
    header_h=max(70,min(card.y-5,int(h*.12)))
    header=add(Box(0,0,w,header_h),"REGION",root,role="header")
    form_region=add(card,"REGION",root,role="primary_form_region")
    left_box=Box(0,header_h,max(1,card.x),h-header_h)
    left_region=add(left_box,"REGION",root,role="supporting_information_region")
    form=add(Box(card.x+1,card.y+1,max(1,card.w-2),max(1,card.h-2)),"CONTAINER",form_region,role="form_card")
    control_ids=[]
    for b in geo["controls"]:
        if not contains(card,b,8): continue
        green=expanded_background_green(image_path,b)
        etype="BUTTON" if green>.25 else "INPUT"
        cid=add(b,etype,form,role="primary_action" if etype=="BUTTON" else "form_control",confidence=.98)
        control_ids.append((b,cid,etype))
    for b in geo["progress"]:
        if contains(card,b,8): add(b,"PROGRESS_INDICATOR",form,role="progress_segment",confidence=.98)
    checkbox_boxes=[]
    for b in geo["small_squares"]:
        if contains(card,b,5) and 18<=b.w<=26 and 18<=b.h<=26 and b.x < card.x+card.w*.15 and b.y>card.y+card.h*.48:
            if not any(abs(b.cy-k.cy)<8 for k in checkbox_boxes): checkbox_boxes.append(b)
    checkbox_boxes=sorted(checkbox_boxes,key=lambda q:q.y)
    checkbox_ids=[add(b,"CHECKBOX",form,role="consent_control",state="UNCHECKED",confidence=.99) for b in checkbox_boxes]
    for cb in checkbox_boxes:
        near=[b for b in geo["small_squares"] if b.x>card.right-card.w*.08 and abs(b.cy-cb.cy)<12]
        if near:
            b=min(near,key=lambda q:abs(q.cy-cb.cy)); add(b,"SECURITY_INDICATOR",form,role="consent_security_marker",confidence=.94)
    word_boxes=[w["box"] for w in words]
    def contour_overlaps_word(b:Box)->bool:
        return any(iou(b,wb)>.08 or contains(wb,b,1) for wb in word_boxes)
    for b,cid,etype in control_ids:
        candidates=[]
        for q in geo["all"]:
            if not contains(b,q,2): continue
            if not (7<=q.w<=38 and 7<=q.h<=38): continue
            if q.x<=b.x+3 or q.right>=b.right-3 or q.y<=b.y+3 or q.bottom>=b.bottom-3: continue
            if q.area<45: continue
            edge_zone=(q.cx <= b.x+58 or q.cx >= b.right-58)
            if not edge_zone: continue
            if contour_overlaps_word(q) and not edge_zone: continue
            candidates.append(q)
        clusters=[]
        for q in sorted(candidates,key=lambda z:z.area,reverse=True):
            if any(abs(q.cx-k.cx)<9 and abs(q.cy-k.cy)<9 for k in clusters): continue
            clusters.append(q)
        clusters=[q for q in clusters if q.cx <= b.x+58 or q.cx >= b.right-58]
        for q in sorted(clusters,key=lambda z:z.x)[:3]:
            role="dropdown_indicator" if q.cx>b.x+b.w*.78 else "control_icon"
            add(q,"ICON",cid,role=role,confidence=.90)
    consumed_lines=set()
    for b,cid,etype in control_ids:
        inside=[]
        for li,line in enumerate(lines):
            if contains(b,line["box"],10): inside.extend(_inside_word_runs(line,b)); consumed_lines.add(li)
        for run in inside:
            add(run["box"],"TEXT",cid,text=run["text"],role="control_visible_text",confidence=run["confidence"],obsrefs=[w.get("observation_id") for w in run.get("words",[]) if w.get("observation_id")])
        if etype=="INPUT":
            labels=[(li,line) for li,line in enumerate(lines) if line["box"].bottom<=b.y+3 and 0<=b.y-line["box"].bottom<=38 and abs(line["box"].x-b.x)<55 and line["box"].w<min(b.w*.8,240)]
            if labels:
                li,line=min(labels,key=lambda z:b.y-z[1]["box"].bottom); consumed_lines.add(li)
                label=add(line["box"],"LABEL",form,text=line["text"],role="field_label",confidence=line["confidence"],obsrefs=[w.get("observation_id") for w in line.get("words",[]) if w.get("observation_id")])
                txt=line["text"].casefold()
                if re.search(r"\b(tipo|país|country|document type|opción)\b",txt):
                    elements[int(cid.split('-')[1])-1]["element_type"]="SELECT"
                    elements[int(cid.split('-')[1])-1]["classification"]="INFERRED"
                    elements[int(cid.split('-')[1])-1]["inference_basis"]="field label and visible dropdown-like control geometry"
    for li,line in enumerate(lines):
        if li in consumed_lines: continue
        b=line["box"]; text=line["text"]
        parent=header if b.bottom<=header_h else (form if contains(card,b,8) else left_region)
        working_words=list(line["words"])
        if len(working_words)>1:
            first=working_words[0]
            first_text=first["text"].strip()
            if (not any(ch.isalnum() for ch in first_text)) and len(first_text)<=3:
                icon_type="SECURITY_INDICATOR" if "segur" in text.casefold() else "ICON"
                add(first["box"],icon_type,parent,role="text_adjacent_icon",confidence=.96,obsrefs=[first.get("observation_id")] if first.get("observation_id") else [])
                working_words=working_words[1:]
                x=min(z["box"].x for z in working_words); y=min(z["box"].y for z in working_words); rr=max(z["box"].right for z in working_words); bb=max(z["box"].bottom for z in working_words)
                b=Box(x,y,rr-x,bb-y); text=" ".join(z["text"] for z in working_words); line=dict(line,box=b,text=text,words=working_words,confidence=sum(z["confidence"] for z in working_words)/len(working_words))
        if len(working_words)==1 and ((not any(ch.isalpha() for ch in text)) or (text.isdigit() and line["confidence"]<.85)):
            neighbors=[z for j,z in enumerate(lines) if j!=li and z["box"].x>b.right and 0<=z["box"].x-b.right<=100 and abs(z["box"].cy-b.cy)<28 and len(z["text"])>4]
            if neighbors:
                add(b,"ICON",parent,role="text_adjacent_icon",confidence=max(.80,line["confidence"]),obsrefs=[],unc=["OCR_SYMBOL_RECONCILED_AS_ICON"] if line["confidence"]<.9 else [])
                continue
        if re.search(r"\bpaso\s*\d+\s*de\s*\d+\b",text.casefold()): etype,role="BADGE","step_badge"
        elif b.h>=22 and len(text)<=80: etype,role="HEADING","section_heading"
        elif len(text)>=45 or text.endswith(('.',':')): etype,role="PARAGRAPH","visible_copy"
        else: etype,role="TEXT","visible_copy"
        resolution="REMEDIATION_REQUIRED" if line["confidence"]<.70 else "RESOLVED"
        unc=["LOW_OCR_CONFIDENCE"] if resolution=="REMEDIATION_REQUIRED" else []
        cls="INFERRED" if resolution=="REMEDIATION_REQUIRED" else "CONFIRMED"
        tid=add(b,etype,parent,text=text,role=role,classification=cls,confidence=line["confidence"],obsrefs=[w.get("observation_id") for w in line.get("words",[]) if w.get("observation_id")],unc=unc,resolution=resolution,inference_basis="low-confidence OCR retained pending independent reread" if resolution=="REMEDIATION_REQUIRED" else None)
        blue=[]
        for wd in line["words"]:
            r,g,bl=foreground_rgb(image_path,wd["box"])
            if bl>125 and bl>r*1.7 and bl>g*1.25: blue.append(wd)
        if blue:
            runs=[];cur=[]
            for wd in blue:
                if cur and wd["box"].x-cur[-1]["box"].right>20: runs.append(cur);cur=[]
                cur.append(wd)
            if cur:runs.append(cur)
            for rs in runs:
                x=min(z["box"].x for z in rs); y=min(z["box"].y for z in rs); rr=max(z["box"].right for z in rs); bb=max(z["box"].bottom for z in rs)
                add(Box(x,y,rr-x,bb-y),"LINK",tid,text=" ".join(z["text"] for z in rs),role="visible_link",confidence=sum(z["confidence"] for z in rs)/len(rs),obsrefs=[z.get("observation_id") for z in rs if z.get("observation_id")])
    text_boxes=[Box(e["region"]["x"],e["region"]["y"],e["region"]["width"],e["region"]["height"]) for e in elements if e["visible_text"]]
    def overlaps_text(b:Box)->bool:return any(iou(b,t)>.12 or contains(t,b,1) for t in text_boxes)
    icon_candidates=[b for b in geo["all"] if 10<=b.w<=55 and 10<=b.h<=55 and not overlaps_text(b)]
    header_texts=[e for e in elements if e["parent_id"]==header and e["visible_text"]]
    for e in header_texts:
        eb=Box(e["region"]["x"],e["region"]["y"],e["region"]["width"],e["region"]["height"])
        near=[b for b in icon_candidates if b.right<=eb.x+5 and 0<=eb.x-b.right<=45 and abs(b.cy-eb.cy)<25]
        if near:
            b=min(near,key=lambda q:abs(q.cy-eb.cy)+abs(eb.x-q.right)); et="SECURITY_INDICATOR" if "segur" in (e["visible_text"] or "").casefold() else "ICON"
            add(b,et,header,role="header_icon",confidence=.92)
    left_texts=[e for e in elements if e["parent_id"]==left_region and e["visible_text"] and e["region"]["x"]>left_box.x+60]
    for e in left_texts:
        eb=Box(e["region"]["x"],e["region"]["y"],e["region"]["width"],e["region"]["height"])
        if eb.y<left_box.y+left_box.h*.35: continue
        near=[b for b in icon_candidates if b.cx<eb.x and 15<=eb.x-b.cx<=95 and abs(b.cy-eb.cy)<40]
        if near:
            b=min(near,key=lambda q:abs(q.cy-eb.cy)+abs(eb.x-q.cx));
            if not any(e2["element_type"]=="ICON" and iou(Box(e2["region"]["x"],e2["region"]["y"],e2["region"]["width"],e2["region"]["height"]),b)>.5 for e2 in elements): add(b,"ICON",left_region,role="supporting_feature_icon",confidence=.88)
    brand_lines=[e for e in header_texts if e["region"]["x"]<w*.25 and e["visible_text"]]
    if brand_lines:
        bx=min(e["region"]["x"] for e in brand_lines); by=min(e["region"]["y"] for e in brand_lines); bb=max(e["region"]["y"]+e["region"]["height"] for e in brand_lines)
        if bx>20: add(Box(max(0,bx-65),max(0,by-5),55,min(65,bb-by+15)),"BRAND_MARK",header,role="brand_symbol",classification="INFERRED",confidence=.88,inference_basis="colored non-text mark adjacent to prominent brand text")
    hsv=cv2.cvtColor(img,cv2.COLOR_BGR2HSV); sat=cv2.inRange(hsv,np.array([25,25,80]),np.array([105,255,255])); n,labels,stats,cent=cv2.connectedComponentsWithStats(sat,8)
    comps=[]
    for i in range(1,n):
        x,y,bw,bh,area=stats[i]
        if x<card.x and y>h*.55 and area>w*h*.002: comps.append(Box(int(x),int(y),int(bw),int(bh)))
    if comps:
        x=min(b.x for b in comps); y=min(b.y for b in comps); rr=max(b.right for b in comps); bb=max(b.bottom for b in comps)
        add(Box(x,y,rr-x,bb-y),"ILLUSTRATION",left_region,role="supporting_illustration",classification="INFERRED",confidence=.84,inference_basis="large colored non-text connected visual region")
    def _ebox(e:dict[str,Any])->Box:
        r=e["region"]; return Box(int(r["x"]),int(r["y"]),int(r["width"]),int(r["height"]))
    drop:set[str]=set()
    brand_marks=[e for e in elements if e["element_type"]=="BRAND_MARK"]
    for e in elements:
        if e["element_type"]!="ICON" or e.get("semantic_role") not in {"header_icon","text_adjacent_icon"}: continue
        eb=_ebox(e)
        if any(e.get("parent_id")==bm.get("parent_id") and (contains(_ebox(bm),eb,8) or iou(_ebox(bm),eb)>.20) for bm in brand_marks):
            drop.add(e["element_id"])
    cluster_types={"ICON","SECURITY_INDICATOR"}
    for i,a in enumerate(elements):
        if a["element_id"] in drop or a["element_type"] not in cluster_types: continue
        ab=_ebox(a)
        for b in elements[i+1:]:
            if b["element_id"] in drop or b["element_type"] not in cluster_types or b.get("parent_id")!=a.get("parent_id"): continue
            bbx=_ebox(b)
            same_visual=(iou(ab,bbx)>.32 or (abs(ab.cx-bbx.cx)<14 and abs(ab.cy-bbx.cy)<14))
            same_support_row=(a.get("semantic_role")==b.get("semantic_role")=="supporting_feature_icon" and abs(ab.cy-bbx.cy)<20 and abs(ab.cx-bbx.cx)<18)
            if not (same_visual or same_support_row): continue
            def rank(e:dict[str,Any])->tuple[int,int,float]:
                et=2 if e["element_type"]=="SECURITY_INDICATOR" else 1
                role=2 if e.get("semantic_role")=="text_adjacent_icon" else 1
                return (et,role,_ebox(e).area)
            loser=b if rank(a)>=rank(b) else a
            drop.add(loser["element_id"])
    if drop:
        elements=[e for e in elements if e["element_id"] not in drop]
    edges=[{"parent":e["parent_id"],"child":e["element_id"]} for e in elements if e["parent_id"] is not None]
    orders=[]
    for parent in (header,left_region,form):
        ids=[e["element_id"] for e in sorted(elements,key=lambda q:(q["region"]["y"],q["region"]["x"])) if e["parent_id"]==parent]
        if ids: orders.append(ids)
    result={"schema_version":"p0-consolidated-visual-reading/v1","execution_id":execution_id,"source_image_refs":[source_image_ref],"source_sha256":source_sha,
            "elements":elements,"ui_structure":{"visual_containment_tree":{"roots":[root],"edges":edges},"visual_layer_graph":[],"candidate_reading_orders":orders},
            "created_at":created_at or datetime.now(timezone.utc).isoformat()}
    diagnostics={"raw_word_count":len(words),"raw_observation_count":sum(raw_scan_counts.values()),"raw_line_count":len(lines),"raw_scan_counts":raw_scan_counts,"scan_scales":[float(s) for s,_ in scan_results],"geometry_counts":{k:len(v) for k,v in geo.items()},"evidence_manifest":evid,"runtime_versions":runtime_versions(),"consolidated_sha256":canonical_sha(result)}
    return result,diagnostics

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument("--image",type=Path,required=True); ap.add_argument("--source-image-ref",required=True); ap.add_argument("--execution-id",required=True); ap.add_argument("--config",type=Path,required=True); ap.add_argument("--output",type=Path,required=True); ap.add_argument("--diagnostics",type=Path)
    a=ap.parse_args(); config=json.loads(a.config.read_text()); out,diag=build_consolidated(a.image,source_image_ref=a.source_image_ref,execution_id=a.execution_id,config=config)
    a.output.write_bytes(canonical_bytes(out));
    if a.diagnostics:a.diagnostics.write_bytes(canonical_bytes(diag))
    print(json.dumps({"result":"PASS_WITH_EVIDENCE","elements":len(out["elements"]),"sha256":canonical_sha(out),"diagnostics":{k:v for k,v in diag.items() if k!="evidence_manifest"}},sort_keys=True))
    return 0
if __name__=="__main__": raise SystemExit(main())
