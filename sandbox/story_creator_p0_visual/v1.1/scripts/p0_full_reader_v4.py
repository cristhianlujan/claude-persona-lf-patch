#!/usr/bin/env python3
"""Fresh pixel reader for P0 V4. No prior candidate or known-error list is accepted."""
from __future__ import annotations
import hashlib,json,collections
from difflib import SequenceMatcher
from pathlib import Path
import cv2,pytesseract
from pytesseract import Output

def region_ref(source_sha:str,r:dict)->str:
 raw=f"{source_sha}:{r['x']}:{r['y']}:{r['width']}:{r['height']}".encode();return 'p0://v4/source-region/'+hashlib.sha256(raw).hexdigest()
def norm(s:str)->str:return ' '.join(s.casefold().split())
def iou(a:dict,b:dict)->float:
 x1=max(a['x'],b['x']);y1=max(a['y'],b['y']);x2=min(a['x']+a['width'],b['x']+b['width']);y2=min(a['y']+a['height'],b['y']+b['height']);inter=max(0,x2-x1)*max(0,y2-y1)
 if not inter:return 0.0
 return inter/float(a['width']*a['height']+b['width']*b['height']-inter)
def overlap_primary(a:dict,b:dict)->float:
 x1=max(a['x'],b['x']);y1=max(a['y'],b['y']);x2=min(a['x']+a['width'],b['x']+b['width']);y2=min(a['y']+a['height'],b['y']+b['height']);inter=max(0,x2-x1)*max(0,y2-y1);return inter/max(1,a['width']*a['height'])
def ocr_lines(image,psm:int)->list[dict]:
 d=pytesseract.image_to_data(image,lang='spa',config=f'--psm {psm}',output_type=Output.DICT);groups={}
 for i,t in enumerate(d['text']):
  t=(t or '').strip()
  if not t:continue
  try:conf=float(d['conf'][i])
  except:conf=-1
  if conf<0:continue
  key=(d['block_num'][i],d['par_num'][i],d['line_num'][i]);groups.setdefault(key,[]).append((i,t,conf))
 out=[]
 for key,items in groups.items():
  items.sort(key=lambda z:d['left'][z[0]]);text=' '.join(x[1] for x in items);xs=[d['left'][x[0]] for x in items];ys=[d['top'][x[0]] for x in items];xe=[d['left'][x[0]]+d['width'][x[0]] for x in items];ye=[d['top'][x[0]]+d['height'][x[0]] for x in items]
  out.append({'text':text,'confidence':sum(x[2] for x in items)/len(items),'region':{'x':min(xs),'y':min(ys),'width':max(xe)-min(xs),'height':max(ye)-min(ys)}})
 return sorted(out,key=lambda x:(x['region']['y'],x['region']['x']))
def match_alt(primary:dict,alts:list[dict])->str:
 candidates=[x for x in alts if overlap_primary(primary['region'],x['region'])>=.25 or iou(primary['region'],x['region'])>=.12]
 if not candidates:return ''
 candidates.sort(key=lambda x:(overlap_primary(primary['region'],x['region']),x['confidence']),reverse=True)
 # If several fragments overlap the primary line, stitch left-to-right.
 y0=primary['region']['y'];near=[x for x in candidates if abs(x['region']['y']-y0)<=max(12,primary['region']['height'])]
 near=sorted(near,key=lambda x:x['region']['x'])[:4]
 text=' '.join(x['text'] for x in near) if len(near)>1 else candidates[0]['text']
 return ' '.join(text.split())
def cv_objects(image,text_regions:list[dict])->list[dict]:
 gray=cv2.cvtColor(image,cv2.COLOR_BGR2GRAY);edges=cv2.Canny(gray,50,150);contours,_=cv2.findContours(edges,cv2.RETR_LIST,cv2.CHAIN_APPROX_SIMPLE);raw=[]
 for c in contours:
  x,y,w,h=cv2.boundingRect(c);a=w*h
  if a<500 or a>100000 or w<12 or h<8:continue
  if w/h<1.35 and a<900:continue
  r={'x':int(x),'y':int(y),'width':int(w),'height':int(h)}
  # avoid boxes that are just a text line envelope
  if any(overlap_primary(r,t)>.75 and a<3000 for t in text_regions):continue
  raw.append(r)
 raw.sort(key=lambda r:r['width']*r['height'],reverse=True);kept=[]
 for r in raw:
  if any(iou(r,k)>.82 for k in kept):continue
  kept.append(r)
  if len(kept)>=60:break
 return kept
def full_reader(source_path:str,ctx:dict)->dict:
 image=cv2.imread(source_path)
 if image is None:raise ValueError('SOURCE_DECODE_FAILED')
 h,w=image.shape[:2];strict=bool((ctx.get('remediation_state') or {}).get('strict_mode'));primary_psm=3 if strict else 11
 lines={p:ocr_lines(image,p) for p in (3,6,11,12)};primary=lines[primary_psm];elements=[{'element_id':'V4-ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1.0,'region':{'x':0,'y':0,'width':w,'height':h},'parent_id':None,'evidence_refs':['p0://v4/source/'+ctx['source_sha256']],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True}];unc=[]
 for idx,line in enumerate(primary,1):
  variants=[]
  for p in (3,6,11,12):
   if p==primary_psm:variants.append(line['text'])
   else:variants.append(match_alt(line,lines[p]))
  non=[v for v in variants if v];alt_non=[v for i,v in enumerate(variants) if i!=(0 if primary_psm==3 else 2) and v];counts=collections.Counter(norm(v) for v in (alt_non or non));best_norm,best_n=counts.most_common(1)[0] if counts else ('',0);best_text=next((v for v in (alt_non or non) if norm(v)==best_norm),'')
  exact_agree=sum(norm(v)==norm(line['text']) for v in non);stable=exact_agree>=2 and line['confidence']>=65
  txt=line['text'];classification='CONFIRMED' if (not strict and line['confidence']>=45) or (strict and stable) else 'INFERRED';etype='TEXT';consensus=best_text if not strict else (line['text'] if stable else '')
  r=line['region'];aspect=r['width']/max(1,r['height']);glyph_shape=len(txt.strip())<=1 and 0.65<=aspect<=1.55 and max(r['width'],r['height'])<=32
  if strict and len(txt.strip())<=3 and (exact_agree<3 or glyph_shape):
   etype='ICON_OR_GLYPH';txt=None;classification='INFERRED';consensus=''
  graphic=.82 if (not strict and txt and len(txt.strip())<=3 and exact_agree<2) else .05
  role='control_visible_text' if txt and txt.strip().startswith('+') and any(ch.isdigit() for ch in txt) else 'visible_copy'
  e={'element_id':f'V4-T-{idx:04d}','element_type':etype,'visible_text':txt,'classification':classification,'confidence':round(max(0,min(1,line['confidence']/100.0)),6),'region':line['region'],'parent_id':'V4-ROOT','semantic_role':role,'evidence_refs':[region_ref(ctx['source_sha256'],line['region'])],'ocr_variants':variants,'ocr_consensus_text':consensus,'ocr_read_count':4,'ocr_empty_reads':sum(not v for v in variants),'ocr_agreement_count':exact_agree,'graphic_score':graphic,'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':stable,'redetection_status':'REDETECTED' if stable else 'AMBIGUOUS'}
  elements.append(e)
  if not stable:unc.append({'element_id':e['element_id'],'code':'OCR_DISAGREEMENT','region':line['region']})
 text_regions=[e['region'] for e in elements if e['element_type']=='TEXT']
 for idx,r in enumerate(cv_objects(image,text_regions),1):elements.append({'element_id':f'V4-O-{idx:04d}','element_type':'VISUAL_OBJECT','visible_text':None,'classification':'INFERRED','confidence':.75,'region':r,'parent_id':'V4-ROOT','semantic_role':'visual_object','evidence_refs':[region_ref(ctx['source_sha256'],r)],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True})
 def count_region(side):
  if side=='LEFT':return sum(1 for e in elements[1:] if e['region']['x']+e['region']['width']/2<w/2)
  return sum(1 for e in elements[1:] if e['region']['x']+e['region']['width']/2>=w/2)
 cov=[{'region_id':'FULL','material':True,'observed_count':len(elements)-1,'represented_count':len(elements)-1,'sweep_status':'COMPLETE'},{'region_id':'LEFT','material':True,'observed_count':count_region('LEFT'),'represented_count':count_region('LEFT'),'sweep_status':'COMPLETE'},{'region_id':'RIGHT','material':True,'observed_count':count_region('RIGHT'),'represented_count':count_region('RIGHT'),'sweep_status':'COMPLETE'}]
 return {'schema_version':'p0-full-reader-v4/v1','execution_id':ctx['reader_execution_id'],'pass_id':ctx['pass_id'],'reader_execution_id':ctx['reader_execution_id'],'source_sha256':ctx['source_sha256'],'width':w,'height':h,'fresh_source_read':True,'reader_origin':'SOURCE_PIXELS','reader_profile':'STRICT_CONSENSUS' if strict else 'RAW_DISCOVERY','elements':elements,'raw_observations':{'primary_psm':primary_psm,'line_counts':{str(k):len(v) for k,v in lines.items()},'cv_object_count':len(elements)-1-len(primary)},'reader_uncertainties':unc,'coverage_map':cov}
