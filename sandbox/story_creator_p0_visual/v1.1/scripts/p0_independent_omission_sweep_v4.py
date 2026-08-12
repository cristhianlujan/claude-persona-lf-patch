#!/usr/bin/env python3
"""Independent SOURCE_PIXELS omission/unsupported-candidate sweep for P0 V4."""
from __future__ import annotations
import hashlib
from difflib import SequenceMatcher
import cv2
from p0_full_reader_v4 import ocr_lines,iou,overlap_primary,norm
from p0_visual_grader_core_v4 import canonical_sha
ROOT_IDS={"ROOT","V4-ROOT"}
VISUAL_TYPES={'VISUAL_OBJECT','BRAND_MARK','ICON','IMAGE','ICON_OR_GLYPH'}
OBJECT_SWEEP_LIMIT=60
TEXT_CONF_STRONG=45.0
TEXT_CONF_LONG=35.0
OBJECT_MATERIAL_AREA=900

def file_sha256(path:str)->str:
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
def _crop(image,r:dict):
 h,w=image.shape[:2];x=max(0,int(r.get('x',0)));y=max(0,int(r.get('y',0)));x2=min(w,x+max(0,int(r.get('width',0))));y2=min(h,y+max(0,int(r.get('height',0))));return image[y:y2,x:x2]
def _pixel_evidence(source_sha:str,kind:str,r:dict,image)->tuple[str,str]:
 crop=_crop(image,r);pixel_sha=hashlib.sha256(crop.tobytes()).hexdigest() if crop.size else hashlib.sha256(b'').hexdigest();bbox=f"{int(r['x'])},{int(r['y'])},{int(r['width'])},{int(r['height'])}";return f"p0://v4/source-pixels/{source_sha}/{pixel_sha}/{kind}/{bbox}",pixel_sha
def _spatial(a:dict,b:dict)->float:return max(iou(a,b),overlap_primary(a,b),overlap_primary(b,a))
def _text_similarity(a:str|None,b:str|None)->float:
 if not a or not b:return 0.0
 aa,bb=norm(a),norm(b)
 if not aa or not bb:return 0.0
 if aa in bb or bb in aa:return .90
 return SequenceMatcher(None,aa,bb).ratio()
def _text_material(text:str,confidence:float)->bool:
 # Short high-confidence OCR fragments can be detector hallucinations over
 # illustration edges (for example, ``e » En``). Preserve real short labels
 # such as ``No``, ``Sí`` and ``DNI`` when they form one lexical token, while
 # requiring four alphanumerics for fragmented/multi-token evidence.
 tokens=[''.join(ch for ch in token if ch.isalnum()) for token in text.strip().split()]
 tokens=[token for token in tokens if token]
 clean=''.join(tokens)
 if not clean:return False
 if confidence>=TEXT_CONF_STRONG:
  return len(clean)>=4 or (len(tokens)==1 and len(tokens[0])>=2)
 return confidence>=TEXT_CONF_LONG and len(clean)>=4
def _object_material(area:int)->bool:return int(area)>=OBJECT_MATERIAL_AREA
def _candidate_nonroot(candidate:dict)->list[dict]:return [e for e in candidate.get('elements',[]) if e.get('element_id') not in ROOT_IDS and e.get('parent_id') is not None]
def _sweep_objects(image,text_regions:list[dict],*,limit:int=OBJECT_SWEEP_LIMIT)->tuple[list[dict],dict]:
 if limit<=0:raise ValueError('OBJECT_SWEEP_LIMIT_INVALID')
 gray=cv2.cvtColor(image,cv2.COLOR_BGR2GRAY);edges=cv2.Canny(gray,70,180);kernel=cv2.getStructuringElement(cv2.MORPH_RECT,(3,3));edges=cv2.morphologyEx(edges,cv2.MORPH_CLOSE,kernel);contours,_=cv2.findContours(edges,cv2.RETR_LIST,cv2.CHAIN_APPROX_SIMPLE);raw=[];page=image.shape[0]*image.shape[1]
 for c in contours:
  x,y,w,h=cv2.boundingRect(c);area=w*h
  if area<OBJECT_MATERIAL_AREA or area>min(130000,int(page*.22)) or w<16 or h<10:continue
  r={'x':int(x),'y':int(y),'width':int(w),'height':int(h)}
  if any(overlap_primary(r,t)>.65 for t in text_regions):continue
  raw.append(r)
 raw.sort(key=lambda r:r['width']*r['height'],reverse=True);deduped=[]
 for r in raw:
  if any(iou(r,k)>.80 for k in deduped):continue
  deduped.append(r)
 truncated=len(deduped)>limit;kept=deduped[:limit]
 return kept,{'detector':'CV_CANNY_70_180','raw_count':len(raw),'deduped_count':len(deduped),'emitted_count':len(kept),'limit':int(limit),'truncated':truncated}
def _alnum_len(text:str)->int:return len(''.join(ch for ch in (text or '') if ch.isalnum()))
def _corroborated_line(line:dict,others:list[dict])->bool:
 return any(_spatial(line.get('region') or {},o.get('region') or {})>=.12 and _text_similarity(line.get('text'),o.get('text'))>=.72 for o in others)
def _independent_observations(image,source_sha:str)->tuple[list[dict],dict]:
 # PSM6 remains the independent full-page sweep. PSM12 is used only as a
 # segmentation corroborator/fallback so a weak PSM6 crop cannot erase a real
 # side-by-side UI label. Short 2-3 alphanumeric fragments require cross-PSM
 # corroboration; this suppresses icon/illustration hallucinations such as "En".
 p6=ocr_lines(image,6);p12=ocr_lines(image,12);observations=[];seq=0
 def emit(line:dict,detector:str,material:bool):
  nonlocal seq
  seq+=1;text=' '.join((line.get('text') or '').split());conf=float(line.get('confidence',0.0) or 0.0);r=line['region'];ref,pixel_sha=_pixel_evidence(source_sha,detector,r,image)
  observations.append({'observation_id':f'OBS-T-{seq:04d}','detector':detector,'kind':'TEXT','classification':'CONFIRMED' if conf>=65 else 'INFERRED','material':bool(material),'text':text,'confidence':round(max(0,min(1,conf/100.0)),6),'region':r,'pixel_sha256':pixel_sha,'evidence_refs':[ref]})
 for line in p6:
  text=' '.join((line.get('text') or '').split());conf=float(line.get('confidence',0.0) or 0.0);material=_text_material(text,conf)
  if material and _alnum_len(text)<=3 and not _corroborated_line(line,p12):material=False
  emit(line,'OCR_PSM6',material)
 for line in p12:
  text=' '.join((line.get('text') or '').split());conf=float(line.get('confidence',0.0) or 0.0)
  if any(_spatial(line.get('region') or {},x.get('region') or {})>=.18 and _text_similarity(text,x.get('text'))>=.62 for x in p6):continue
  material=_text_material(text,conf)
  if material and _alnum_len(text)<=3 and not _corroborated_line(line,p6):material=False
  emit(line,'OCR_PSM12_FALLBACK',material)
 text_regions=[o['region'] for o in observations if o['kind']=='TEXT'];objects,object_sweep=_sweep_objects(image,text_regions)
 for idx,r in enumerate(objects,1):
  area=int(r['width'])*int(r['height']);ref,pixel_sha=_pixel_evidence(source_sha,'CV_CANNY_70_180',r,image)
  observations.append({'observation_id':f'OBS-O-{idx:04d}','detector':'CV_CANNY_70_180','kind':'VISUAL_OBJECT','classification':'INFERRED','material':_object_material(area),'text':None,'confidence':.72,'region':r,'pixel_sha256':pixel_sha,'evidence_refs':[ref]})
 return observations,object_sweep
def _best_match(obs:dict,candidates:list[dict])->tuple[dict|None,float]:
 best=None;best_score=0.0
 for e in candidates:
  er=e.get('region') or {};r=obs['region']
  if not all(k in er for k in ('x','y','width','height')):continue
  spatial=_spatial(r,er)
  if obs['kind']=='TEXT':
   if not e.get('visible_text'):continue
   sim=_text_similarity(obs.get('text'),e.get('visible_text'));acceptable=(spatial>=.20 and sim>=.35) or spatial>=.60 or (sim>=.80 and spatial>=.08);score=.65*spatial+.35*sim
  else:
   if e.get('visible_text') or e.get('element_type') not in VISUAL_TYPES:continue
   acceptable=spatial>=.18 or iou(r,er)>=.10;score=spatial
  if acceptable and score>best_score:best,best_score=e,score
 return best,best_score
def _candidate_support(image,e:dict,text_observations:list[dict])->str:
 r=e.get('region') or {};crop=_crop(image,r)
 if crop.size==0:return 'UNSUPPORTED'
 if e.get('visible_text'):
  target=str(e.get('visible_text') or '').strip();near=[o for o in text_observations if _spatial(r,o.get('region') or {})>=.08]
  best=max([_text_similarity(target,o.get('text')) for o in near] or [0.0])
  if best>=.62:return 'SUPPORTED'
  gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY);std=float(gray.std());edge=float((cv2.Canny(gray,70,180)>0).mean())
  if std<8 and edge<.006:return 'UNSUPPORTED'
  if near and max(float(o.get('confidence',0) or 0) for o in near)>=.60 and best<.30:return 'UNSUPPORTED'
  return 'UNCERTAIN'
 if e.get('element_type') in VISUAL_TYPES:
  gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY);edge=float((cv2.Canny(gray,70,180)>0).mean());return 'SUPPORTED' if edge>=.01 else 'UNSUPPORTED'
 return 'SUPPORTED'

def _region_of(r:dict,width:int)->str:return 'LEFT' if r['x']+r['width']/2<width/2 else 'RIGHT'
def _region_rows(observations:list[dict],width:int)->list[dict]:
 rows=[]
 for rid in ('FULL','LEFT','RIGHT'):
  items=[o for o in observations if o.get('material') and (rid=='FULL' or _region_of(o['region'],width)==rid)];represented=sum(o.get('match_status')=='REPRESENTED' for o in items);uncertain=sum(o.get('match_status')=='UNCERTAIN' for o in items);unrepresented=sum(o.get('match_status')=='UNREPRESENTED' for o in items);status='COMPLETE' if uncertain==0 else 'INCOMPLETE';refs=sorted({ref for o in items for ref in o.get('evidence_refs',[])})
  rows.append({'region_id':rid,'material':True,'observed_count':len(items),'represented_count':represented,'uncertain_count':uncertain,'unrepresented_count':unrepresented,'sweep_status':status,'evidence_refs':refs})
 return rows
def _materiality_policy()->dict:return {'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':TEXT_CONF_STRONG,'text_confidence_long_min':TEXT_CONF_LONG,'text_long_min_alnum':4,'object_material_area_min_px2':OBJECT_MATERIAL_AREA,'rationale':'Fail-closed recall bias: long OCR strings at 35-44 confidence remain material; every contour admitted by the object sweep is material from 900 px2 upward.'}
def run_independent_omission_sweep(source_path:str,expected_source_sha256:str,candidate:dict,*,execution_id:str)->dict:
 try:actual=file_sha256(source_path)
 except Exception as exc:return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':execution_id,'source_sha256':None,'candidate_sha256':None,'width':0,'height':0,'status':'ERROR','fresh_source_read':False,'observations':[],'regions':[],'object_sweep':None,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':['SOURCE_READ_ERROR:'+type(exc).__name__]}
 if actual!=expected_source_sha256:return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':execution_id,'source_sha256':actual,'candidate_sha256':None,'width':0,'height':0,'status':'BLOCKED','fresh_source_read':False,'observations':[],'regions':[],'object_sweep':None,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':['SOURCE_SHA256_MISMATCH']}
 image=cv2.imread(source_path)
 if image is None:return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':execution_id,'source_sha256':actual,'candidate_sha256':None,'width':0,'height':0,'status':'ERROR','fresh_source_read':True,'observations':[],'regions':[],'object_sweep':None,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':['SOURCE_DECODE_FAILED']}
 h,w=image.shape[:2];observations,object_sweep=_independent_observations(image,actual);candidates=_candidate_nonroot(candidate)
 for o in observations:
  if not o['material']:o['match_status']='NON_MATERIAL';o['matched_element_id']=None;o['match_score']=0.0;continue
  match,score=_best_match(o,candidates)
  if match is not None:o['match_status']='REPRESENTED';o['matched_element_id']=match.get('element_id');o['match_score']=round(score,6)
  elif o['kind']=='TEXT' and o.get('classification')!='CONFIRMED':o['match_status']='UNCERTAIN';o['matched_element_id']=None;o['match_score']=0.0
  else:o['match_status']='UNREPRESENTED';o['matched_element_id']=None;o['match_score']=0.0
 material_obs=[o for o in observations if o.get('material')];matched_ids={o.get('matched_element_id') for o in material_obs if o.get('match_status')=='REPRESENTED'};unsupported=[];support_uncertain=[];text_observations=[o for o in observations if o.get('kind')=='TEXT' and o.get('material')]
 for e in candidates:
  if e.get('classification')!='CONFIRMED' or not (e.get('visible_text') or e.get('element_type') in VISUAL_TYPES) or e.get('element_id') in matched_ids:continue
  support=_candidate_support(image,e,text_observations)
  if support=='UNSUPPORTED':unsupported.append(e.get('element_id'))
  elif support=='UNCERTAIN':support_uncertain.append(e.get('element_id'))
 regions=_region_rows(observations,w);errors=['SWEEP_UNIVERSE_TRUNCATED'] if object_sweep.get('truncated') else [];status='BLOCKED' if errors else ('COMPLETE' if regions and all(r['sweep_status']=='COMPLETE' for r in regions) else 'INCOMPLETE');candidate_sha=canonical_sha({k:v for k,v in candidate.items() if k!='reader_execution_id'})
 return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':execution_id,'source_sha256':actual,'candidate_sha256':candidate_sha,'width':w,'height':h,'status':status,'fresh_source_read':True,'observations':observations,'regions':regions,'object_sweep':object_sweep,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[o['observation_id'] for o in material_obs if o['match_status']=='UNREPRESENTED'],'unsupported_candidate_ids':sorted(x for x in unsupported if x),'candidate_support_uncertain_ids':sorted(x for x in support_uncertain if x),'errors':errors}
def validate_sweep_receipt(sweep:dict|None,candidate:dict,ctx:dict)->list[str]:
 if not isinstance(sweep,dict):return ['INDEPENDENT_SWEEP_MISSING']
 errors=[]
 if not sweep.get('execution_id'):errors.append('SWEEP_EXECUTION_ID_MISSING')
 if sweep.get('source_sha256')!=ctx.get('source_sha256'):errors.append('SWEEP_SOURCE_HASH_MISMATCH')
 if sweep.get('candidate_sha256')!=ctx.get('candidate_sha256'):errors.append('SWEEP_CANDIDATE_HASH_MISMATCH')
 if sweep.get('fresh_source_read') is not True:errors.append('SWEEP_NOT_FRESH_SOURCE_READ')
 if sweep.get('status') not in {'COMPLETE','INCOMPLETE','ERROR','BLOCKED'}:errors.append('SWEEP_STATUS_INVALID')
 observations=sweep.get('observations');regions=sweep.get('regions')
 if not isinstance(observations,list):errors.append('SWEEP_OBSERVATIONS_INVALID');observations=[]
 if not isinstance(regions,list) or not regions:errors.append('SWEEP_REGIONS_INVALID');regions=[]
 policy=sweep.get('materiality_policy')
 if not isinstance(policy,dict) or policy.get('schema_version')!='p0-sweep-materiality-policy/v1':errors.append('SWEEP_MATERIALITY_POLICY_MISSING')
 object_sweep=sweep.get('object_sweep');object_observations=[o for o in observations if isinstance(o,dict) and o.get('kind')=='VISUAL_OBJECT']
 if not isinstance(object_sweep,dict):errors.append('SWEEP_OBJECT_UNIVERSE_METADATA_MISSING')
 else:
  try:raw_count=int(object_sweep.get('raw_count',-1));deduped_count=int(object_sweep.get('deduped_count',-1));emitted_count=int(object_sweep.get('emitted_count',-1));limit=int(object_sweep.get('limit',-1))
  except Exception:raw_count=deduped_count=emitted_count=limit=-1;errors.append('SWEEP_OBJECT_UNIVERSE_METADATA_INVALID')
  if min(raw_count,deduped_count,emitted_count)<0 or limit<=0 or deduped_count>raw_count or emitted_count>deduped_count or emitted_count>limit:errors.append('SWEEP_OBJECT_UNIVERSE_COUNTS_INVALID')
  if emitted_count!=len(object_observations):errors.append('SWEEP_OBJECT_EMITTED_COUNT_INCONSISTENT')
  expected_truncated=deduped_count>limit
  if bool(object_sweep.get('truncated'))!=expected_truncated:errors.append('SWEEP_OBJECT_TRUNCATION_FLAG_INCONSISTENT')
  if expected_truncated:
   if sweep.get('status')!='BLOCKED':errors.append('SWEEP_TRUNCATION_NOT_BLOCKED')
   if 'SWEEP_UNIVERSE_TRUNCATED' not in (sweep.get('errors') or []):errors.append('SWEEP_TRUNCATION_ERROR_MISSING')
  elif 'SWEEP_UNIVERSE_TRUNCATED' in (sweep.get('errors') or []):errors.append('SWEEP_TRUNCATION_ERROR_SPURIOUS')
 material=[o for o in observations if isinstance(o,dict) and o.get('material') is True];declared_unrep=set(sweep.get('unrepresented_observation_ids') or []);actual_unrep={o.get('observation_id') for o in material if o.get('match_status')=='UNREPRESENTED'}
 if declared_unrep!=actual_unrep:errors.append('SWEEP_UNREPRESENTED_SET_INCONSISTENT')
 width=int(sweep.get('width') or candidate.get('width') or 0)
 for rid in ('FULL','LEFT','RIGHT'):
  row=next((r for r in regions if r.get('region_id')==rid),None)
  if row is None:errors.append('SWEEP_REGION_MISSING:'+rid);continue
  items=material if rid=='FULL' else [o for o in material if _region_of(o.get('region') or {'x':0,'width':0},width)==rid];observed=len(items);represented=sum(o.get('match_status')=='REPRESENTED' for o in items);uncertain=sum(o.get('match_status')=='UNCERTAIN' for o in items);unrepresented=sum(o.get('match_status')=='UNREPRESENTED' for o in items)
  if int(row.get('observed_count',-1))!=observed:errors.append('SWEEP_OBSERVED_COUNT_INCONSISTENT:'+rid)
  if int(row.get('represented_count',-1))!=represented:errors.append('SWEEP_REPRESENTED_COUNT_INCONSISTENT:'+rid)
  if int(row.get('uncertain_count',-1))!=uncertain:errors.append('SWEEP_UNCERTAIN_COUNT_INCONSISTENT:'+rid)
  if int(row.get('unrepresented_count',-1))!=unrepresented:errors.append('SWEEP_UNREPRESENTED_COUNT_INCONSISTENT:'+rid)
  expected_status='COMPLETE' if uncertain==0 else 'INCOMPLETE'
  if row.get('sweep_status')!=expected_status:errors.append('SWEEP_REGION_STATUS_INCONSISTENT:'+rid)
 candidate_ids={e.get('element_id') for e in candidate.get('elements',[])}
 for eid in (sweep.get('unsupported_candidate_ids') or [])+(sweep.get('candidate_support_uncertain_ids') or []):
  if eid not in candidate_ids:errors.append('SWEEP_CANDIDATE_SUPPORT_UNKNOWN_ELEMENT:'+str(eid))
 if sweep.get('errors') and sweep.get('status') not in {'ERROR','BLOCKED'}:errors.append('SWEEP_ERRORS_WITH_NONERROR_STATUS')
 return errors
