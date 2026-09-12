#!/usr/bin/env python3
"""Source-bound combined selective-challenger benchmark.

Baseline is the exact post-PR159 strict P-03 packet (21 observations). The
benchmark evaluates two disjoint challenger lanes without changing product
runtime:
  * PaddleOCR PP-OCRv5 on the six remaining text elements (8 observation codes)
  * frozen CLIP identity output + conservative geometry/context policy on the
    13 remaining ICON_FUNCTION_NOT_OBSERVABLE observations.

No cross-engine confidence comparison is allowed. CLIP identity never proves
click behavior. Technical reference is not authentic human adjudication.
"""
from __future__ import annotations

import argparse, hashlib, json, re, statistics, time
from pathlib import Path

SOURCE_SHA256="e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
SOURCE_BYTES=1_384_686
PACKET_SHA256="089ac58eede164d1e6fcd42070373d2abf482e5a4cc18d163ad9189a7015c781"
PACKET_BYTES=1_237_214
BASELINE_HEAD="714aaf959c0cbfb951075f4394c45cdfb4d0bf89"
BASELINE_TOTAL=21
CURRENT_ICON_IDS=["V4-I-0001","V4-I-0002","V4-I-0003","V4-I-0007","V4-I-0008","V4-I-0009","V4-I-0010","V4-I-0011","V4-I-0012","V4-I-0013","V4-I-0014","V4-I-0015","V4-I-0018"]
TEXT_TARGETS=[
 {"element_id":"V4-T-0022","kind":"document_placeholder","bbox":[1093,463,85,13],"codes":["OCR_DISAGREEMENT"]},
 {"element_id":"V4-T-0028","kind":"phone_bundle","bbox":[626,565,221,21],"codes":["OCR_DISAGREEMENT","TEXT_GROUPING_DISAGREEMENT"]},
 {"element_id":"V4-T-0029","kind":"email_placeholder","bbox":[1046,568,196,16],"codes":["OCR_DISAGREEMENT"]},
 {"element_id":"V4-T-0037","kind":"exact_text","bbox":[661,695,458,13],"codes":["OCR_DISAGREEMENT"]},
 {"element_id":"V4-T-0039","kind":"exact_text","bbox":[661,717,430,14],"codes":["OCR_DISAGREEMENT"]},
 {"element_id":"V4-T-0047","kind":"button_text","bbox":[926,887,166,15],"codes":["OCR_DISAGREEMENT","TEXT_GROUPING_DISAGREEMENT"]},
]
PASSIVE={"SHIELD","LOCK","LIGHTNING","PERSON","IDENTITY_CARD","BRAND_MARK"}
EMAIL_RE=re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def norm(s:str)->str:return " ".join((s or "").casefold().split())
def strip_ej(s:str)->str:return re.sub(r"^ej\.?\s*","",(s or "").strip(),flags=re.I)
def region(item):
 r=item.get("region") or item.get("bbox") or {}; return {k:float(r.get(k,0)) for k in ("x","y","width","height")}
def center(r):return r["x"]+r["width"]/2,r["y"]+r["height"]/2
def overlap_primary(a,b):
 x1,y1=max(a["x"],b["x"]),max(a["y"],b["y"]);x2,y2=min(a["x"]+a["width"],b["x"]+b["width"]),min(a["y"]+a["height"],b["y"]+b["height"]);return max(0,x2-x1)*max(0,y2-y1)/max(1,a["width"]*a["height"])
def inside(a,b):
 x,y=center(a);return b["x"]<=x<=b["x"]+b["width"] and b["y"]<=y<=b["y"]+b["height"]
def horizontal(a,b):
 gap=b["x"]-(a["x"]+a["width"]);return 0<=gap<=48 and abs(center(a)[1]-center(b)[1])<=24
def vertical(a,b):
 gap=b["y"]-(a["y"]+a["height"]);return 0<=gap<=60 and abs(center(a)[0]-center(b)[0])<=48

def self_test():
 assert len(CURRENT_ICON_IDS)==13 and sum(len(x["codes"]) for x in TEXT_TARGETS)==8
 assert not set(CURRENT_ICON_IDS)&{"V4-I-0004","V4-I-0005","V4-I-0006","V4-I-0016","V4-I-0017"}
 print(json.dumps({"gate":"PASS_COMBINED_SELF_TEST","icons":13,"text_observations":8},sort_keys=True))

def strict_packet(packet):
 readers=packet.get("reader_outputs") or []; strict=next((r for r in readers if r.get("pass_id")=="P-03"),None)
 if not strict: raise SystemExit("FAIL_COMBINED_P03_MISSING")
 u=strict.get("reader_uncertainties") or []; observed=[(x.get("element_id"),x.get("code")) for x in u]
 icons=[eid for eid,code in observed if code=="ICON_FUNCTION_NOT_OBSERVABLE"]
 text=[(eid,code) for eid,code in observed if code in {"OCR_DISAGREEMENT","TEXT_GROUPING_DISAGREEMENT"}]
 expected_text=[(t["element_id"],c) for t in TEXT_TARGETS for c in t["codes"]]
 if icons!=CURRENT_ICON_IDS: raise SystemExit(f"FAIL_COMBINED_ICON_BASELINE:{icons!r}")
 if sorted(text)!=sorted(expected_text) or len(observed)!=BASELINE_TOTAL: raise SystemExit(f"FAIL_COMBINED_TEXT_BASELINE:{text!r}:total={len(observed)}")
 return strict,observed

def document_valid(s):
 t=strip_ej(s); return not re.search(r"[A-Za-zÁÉÍÓÚáéíóúÑñ]",t) and len("".join(c for c in t if c.isdigit()))==8
def phone_valid(s):
 t=strip_ej(s); return not re.search(r"[A-IK-ZA-ik-zÁÉÍÓÚáéíóúÑñ]",t) and len("".join(c for c in t if c.isdigit()))==9
def email_valid(s):return bool(EMAIL_RE.fullmatch(strip_ej(s)))
def phone_bundle(texts):
 clean=[x.strip() for x in texts if x.strip()]; pfx=[i for i,x in enumerate(clean) if "+51" in x.replace(" ","")]; nums=[i for i,x in enumerate(clean) if phone_valid(x)]; return bool(pfx and nums),any(a!=b for a in pfx for b in nums)

def crop(source,bbox,pad=10,scale=4):
 from PIL import Image
 x,y,w,h=bbox;x0=max(0,x-pad);y0=max(0,y-pad);x1=min(source.width,x+w+pad);y1=min(source.height,y+h+pad);c=source.crop((x0,y0,x1,y1)).convert("RGB");return c.resize((c.width*scale,c.height*scale),Image.Resampling.LANCZOS)
def predict(ocr,path):
 t=time.perf_counter(); rows=[]
 for result in ocr.predict(str(path)):
  p=result.json;p=p.get("res",p)
  for text,score,box in zip(p.get("rec_texts") or [],p.get("rec_scores") or [],p.get("rec_boxes") or []):
   if str(text).strip(): rows.append({"text":str(text).strip(),"confidence":round(float(score),6),"box":[int(v) for v in box]})
 rows.sort(key=lambda x:(x["box"][1],x["box"][0]));return {"texts":[x["text"] for x in rows],"joined":" ".join(x["text"] for x in rows),"box_count":len(rows),"latency_seconds":round(time.perf_counter()-t,4),"boxes":rows}
def stable(ocr,source,bbox,tmp,name):
 p=tmp/f"{name}.png";crop(source,bbox).save(p);runs=[predict(ocr,p) for _ in range(3)];sig=[(norm(r["joined"]),tuple(norm(x) for x in r["texts"])) for r in runs];ok=len(set(sig))==1;return {"stable":ok,"joined":runs[0]["joined"] if ok else "","texts":runs[0]["texts"] if ok else [],"box_count":runs[0]["box_count"] if ok else 0,"median_latency_seconds":statistics.median(r["latency_seconds"] for r in runs),"runs":runs}
def eval_text(target,baseline,pred):
 resolved=[];reason=[];joined=pred["joined"] if pred["stable"] else "";texts=pred["texts"] if pred["stable"] else []
 if not pred["stable"]: reason.append("PADDLE_UNSTABLE_ACROSS_3_RUNS")
 elif target["kind"]=="document_placeholder" and document_valid(joined) and not document_valid(baseline):resolved+=["OCR_DISAGREEMENT"];reason+=["STRUCTURAL_DOCUMENT_CORRECTION"]
 elif target["kind"]=="phone_bundle":
  v,sep=phone_bundle(texts);bv,_=phone_bundle([baseline])
  if v and not bv:resolved+=["OCR_DISAGREEMENT"];reason+=["STRUCTURAL_PHONE_BUNDLE_CORRECTION"]
  if v and sep:resolved+=["TEXT_GROUPING_DISAGREEMENT"];reason+=["INDEPENDENT_GROUPING_CORROBORATION"]
 elif target["kind"]=="email_placeholder":
  cand=next((x for x in texts if "@" in x),joined)
  if email_valid(cand) and not email_valid(baseline):resolved+=["OCR_DISAGREEMENT"];reason+=["STRUCTURAL_EMAIL_CORRECTION"]
 elif target["kind"] in {"exact_text","button_text"} and norm(joined)==norm(baseline):
  resolved+=["OCR_DISAGREEMENT"];reason+=["EXACT_CROSS_FAMILY_AGREEMENT"]
  if target["kind"]=="button_text" and pred["box_count"]==1:resolved+=["TEXT_GROUPING_DISAGREEMENT"];reason+=["INDEPENDENT_SINGLE_LINE_GROUPING_CORROBORATION"]
 resolved=[c for c in target["codes"] if c in set(resolved)];return resolved,reason

def icon_decision(icon,identity,texts,controls,checkboxes):
 ir=region(icon);ov=[t for t in texts if overlap_primary(ir,region(t))>=.8]
 if ov:return False,"RECLASSIFY_TEXT_OVERLAP",[ov[0].get("element_id")]
 cont=[c for c in controls if inside(ir,region(c))]
 if cont:return False,"INHERIT_PARENT_CONTROL",[min(cont,key=lambda c:region(c)["width"]*region(c)["height"]).get("element_id")]
 if identity=="HELP_QUESTION":return True,"INDEPENDENT_INTERACTION_NOT_PROVEN",[]
 if identity in PASSIVE:
  pair=[t for t in texts if horizontal(ir,region(t))]
  if pair:return False,"SUPPORTS_ADJACENT_COPY",[pair[0].get("element_id")]
  below=[t for t in texts if vertical(ir,region(t))]
  if below:return False,"SUPPORTS_STACKED_COPY",[below[0].get("element_id")]
  if identity=="SHIELD" and any(abs(center(region(c))[1]-center(ir)[1])<=8 for c in checkboxes):return False,"ROW_ASSURANCE_MARK",[]
 return True,"ABSTAIN_ROLE_NOT_PROVEN",[]

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--source");ap.add_argument("--packet");ap.add_argument("--clip");ap.add_argument("--targets");ap.add_argument("--output");ap.add_argument("--self-test",action="store_true");a=ap.parse_args();self_test()
 if a.self_test:return 0
 sb=Path(a.source).read_bytes();pb=Path(a.packet).read_bytes()
 if len(sb)!=SOURCE_BYTES or sha(sb)!=SOURCE_SHA256:raise SystemExit("FAIL_COMBINED_SOURCE_BINDING")
 if len(pb)!=PACKET_BYTES or sha(pb)!=PACKET_SHA256:raise SystemExit("FAIL_COMBINED_PACKET_BINDING")
 packet=json.loads(pb);strict,baseline_obs=strict_packet(packet);clip=json.loads(Path(a.clip).read_text());targets=json.loads(Path(a.targets).read_text())
 if clip.get("source_sha256")!=SOURCE_SHA256 or targets.get("source_sha256")!=SOURCE_SHA256:raise SystemExit("FAIL_COMBINED_CHALLENGER_SOURCE_BINDING")
 if clip.get("runtime_promoted") or clip.get("p0_5_credit")!=0 or clip.get("real_corpus_credit")!=0:raise SystemExit("FAIL_COMBINED_CLIP_BOUNDARY")
 byid={e.get("element_id"):e for e in strict.get("elements") or []};clipid={x["element_id"]:x for x in clip["targets"]};refid={x["element_id"]:x for x in targets["targets"]};texts=[e for e in byid.values() if e.get("element_type")=="TEXT" and e.get("visible_text")];controls=[e for e in byid.values() if e.get("element_type")=="CONTROL_REGION"];checks=[e for e in byid.values() if e.get("element_type")=="CHECKBOX"]
 icon_rows=[];icon_resolved=[];fp=0
 for eid in CURRENT_ICON_IDS:
  need,disp,evidence=icon_decision(byid[eid],clipid[eid]["top1_identity"],texts,controls,checks);safe=not need;expected=bool(refid[eid]["policy_resolvable"]);fp+=int(safe and not expected)
  if safe:icon_resolved.append((eid,"ICON_FUNCTION_NOT_OBSERVABLE"))
  icon_rows.append({"element_id":eid,"clip_top1_identity":clipid[eid]["top1_identity"],"clip_top1_correct":clipid[eid]["top1_correct"],"needs_independent_function_review":need,"disposition":disp,"evidence_element_ids":evidence,"technical_reference_policy_resolvable":expected,"interaction_function_confirmed":False})
 if fp:raise SystemExit(f"FAIL_COMBINED_ICON_FALSE_POSITIVE:{fp}")
 from PIL import Image
 from paddleocr import PaddleOCR
 source=Image.open(a.source).convert("RGB");ocr=PaddleOCR(lang="es",ocr_version="PP-OCRv5",use_doc_orientation_classify=False,use_doc_unwarping=False,use_textline_orientation=False,device="cpu")
 import tempfile
 text_rows=[];text_resolved=[]
 with tempfile.TemporaryDirectory() as d:
  root=Path(d)
  for t in TEXT_TARGETS:
   baseline=byid[t["element_id"]].get("visible_text") or "";pred=stable(ocr,source,t["bbox"],root,t["element_id"]);resolved,reasons=eval_text(t,baseline,pred);text_resolved += [(t["element_id"],c) for c in resolved];text_rows.append({"element_id":t["element_id"],"baseline":baseline,"codes":t["codes"],"paddle":pred,"resolved_codes":resolved,"unresolved_codes":[c for c in t["codes"] if c not in resolved],"reasons":reasons})
 resolved=set(icon_resolved+text_resolved);baseline_set=set(baseline_obs)
 if not resolved<=baseline_set:raise SystemExit("FAIL_COMBINED_NONBASELINE_RESOLUTION")
 residual=sorted(baseline_set-resolved);result={"schema_version":"p0-combined-selective-challenger-benchmark/v1","reference_class":"SOURCE_BOUND_TECHNICAL_DIAGNOSTIC_NOT_HUMAN_ADJUDICATION","baseline":{"main_sha":BASELINE_HEAD,"packet_sha256":PACKET_SHA256,"source_sha256":SOURCE_SHA256,"observation_count":len(baseline_set),"icon_observations":13,"text_observations":8},"icon_lane":{"resolved":len(icon_resolved),"before":13,"remaining":13-len(icon_resolved),"technical_false_positive":fp,"rows":icon_rows},"text_lane":{"resolved":len(text_resolved),"before":8,"remaining":8-len(text_resolved),"rows":text_rows,"engine":{"family":"PaddleOCR","paddle_version":"3.2.0","paddleocr_version":"3.5.0","ocr_version":"PP-OCRv5","lang":"es","model_source_pinning_complete":False}},"combined":{"resolved_count":len(resolved),"residual_count":len(residual),"reduction_pct":round(100*len(resolved)/len(baseline_set),2),"residual_observations":[{"element_id":e,"code":c} for e,c in residual],"double_counted_observations":0,"interaction_functions_confirmed":0},"real_corpus_credit":0,"p0_5_credit":0,"holdout_accessed":False,"runtime_promoted":False,"production_authorized":False}
 out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+"\n");print(json.dumps({"gate":"PASS_P0_COMBINED_SELECTIVE_CHALLENGER_BENCHMARK","baseline":len(baseline_set),"text_resolved":len(text_resolved),"icons_resolved":len(icon_resolved),"residual":len(residual),"output_sha256":sha(out.read_bytes())},sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
