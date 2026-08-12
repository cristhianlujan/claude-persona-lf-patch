#!/usr/bin/env python3
"""Independent SOURCE_PIXELS omission/unsupported-candidate sweep for P0 V4."""
from __future__ import annotations
import hashlib
from difflib import SequenceMatcher
import cv2
import pytesseract
from p0_full_reader_v4 import ocr_lines,iou,overlap_primary,norm
from p0_visual_atomicity_v4 import repeated_control_cardinality_groups
from p0_visual_grader_core_v4 import canonical_sha
ROOT_IDS={"ROOT","V4-ROOT"}
VISUAL_TYPES={'VISUAL_OBJECT','BRAND_MARK','ICON','IMAGE','ICON_OR_GLYPH','CHECKBOX','RADIO','TOGGLE','CONTROL_REGION'}
COMPACT_TYPES={'BRAND_MARK','ICON','ICON_OR_GLYPH','CHECKBOX','RADIO','TOGGLE'}
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
 scores=[SequenceMatcher(None,aa,bb).ratio()]
 for left in aa.split():
  for right in bb.split():scores.append(SequenceMatcher(None,left,right).ratio())
 return max(scores)
def _text_material(text:str,confidence:float)->bool:
 # Short high-confidence OCR fragments can be detector hallucinations over
 # illustration edges (for example, ``e » En``). Preserve real short labels
 # such as ``No``, ``Sí`` and ``DNI`` when they form one lexical token, while
 # requiring four alphanumerics for fragmented/multi-token evidence.
 tokens=[''.join(ch for ch in token if ch.isalnum()) for token in text.strip().split()]
 tokens=[token for token in tokens if token]
 clean=''.join(tokens)
 if not clean:return False
 if len(clean)<=3 and any(not (char.isalnum() or char.isspace()) for char in text):return False
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

def _sweep_compact_geometry(image,text_observations:list[dict],*,limit:int=80)->tuple[list[dict],dict]:
 """Independent binary-threshold geometry, distinct from the reader's Canny hierarchy."""
 gray=cv2.cvtColor(image,cv2.COLOR_BGR2GRAY);_,binary=cv2.threshold(gray,180,255,cv2.THRESH_BINARY_INV)
 contours,hierarchy=cv2.findContours(binary,cv2.RETR_TREE,cv2.CHAIN_APPROX_SIMPLE);boxes=[]
 for index,contour in enumerate(contours):
  x,y,w,h=cv2.boundingRect(contour);perimeter=cv2.arcLength(contour,True);polygon=cv2.approxPolyDP(contour,.04*perimeter,True)
  boxes.append({'x':int(x),'y':int(y),'width':int(w),'height':int(h),'contour_area':float(cv2.contourArea(contour)),'polygon_sides':len(polygon),'convex':bool(cv2.isContourConvex(polygon)),'index':index})
 def overlap(a,b):return overlap_primary(a,b)
 def descendants(index):
  count=0
  if hierarchy is None:return 0
  for row in hierarchy[0]:
   parent=int(row[3])
   while parent>=0:
    if parent==index:count+=1;break
    parent=int(hierarchy[0][parent][3])
  return count
 def nearby(r):
  l=r['x'];rr=l+r['width'];t=r['y'];bb=t+r['height'];cx=(l+rr)/2;cy=(t+bb)/2
  for obs in text_observations:
   q=obs['region'];ql=q['x'];qr=ql+q['width'];qt=q['y'];qb=qt+q['height'];qcx=(ql+qr)/2;qcy=(qt+qb)/2
   if (min(abs(ql-rr),abs(l-qr))<=420 and abs(qcy-cy)<=34) or (min(abs(qt-bb),abs(t-qb))<=62 and abs(qcx-cx)<=85):return True
  return False
 square=[]
 for b in boxes:
  w,h=b['width'],b['height'];fill=b['contour_area']/max(1,w*h)
  if 14<=w<=31 and 14<=h<=31 and .72<=w/max(1,h)<=1.28 and fill>=.55 and b['polygon_sides']==4 and b['convex']:
   if not any(overlap(b,k)>=.78 for k in square):square.append(b)
 groups=[];unused=set(range(len(square)))
 while unused:
  seed=unused.pop();group=[seed];changed=True
  while changed:
   changed=False
   for index in list(unused):
    b=square[index]
    if any(abs((b['x']+b['width']/2)-(square[m]['x']+square[m]['width']/2))<=5 and abs((b['y']+b['height']/2)-(square[m]['y']+square[m]['height']/2))<=140 for m in group):group.append(index);unused.remove(index);changed=True
  if len(group)>=2:groups.append(sorted(group,key=lambda idx:square[idx]['y']))
 controls=[]
 for ordinal,group in enumerate(sorted(groups,key=lambda group:(square[group[0]]['x'],square[group[0]]['y'])),1):
  for index in group:
   b=square[index];controls.append({'region':{k:b[k] for k in ('x','y','width','height')},'control_type':'CHECKBOX','repeated_control_group_id':f'SW-RCG-{ordinal:03d}','detector':'CV_BINARY_REPEATED_QUADRILATERAL'})
 compact=[]
 for b in boxes:
  r={k:b[k] for k in ('x','y','width','height')};w,h=b['width'],b['height']
  if any(overlap(r,item['region'])>=.55 for item in controls):continue
  if not(14<=w<=48 and 14<=h<=54 and .42<=w/max(1,h)<=1.75 and descendants(b['index'])>=1 and b['convex'] and nearby(r)):continue
  covered=False
  for obs in text_observations:
   if overlap(r,obs['region'])<.55:continue
   raw=str(obs.get('text') or '');clean=''.join(ch for ch in raw if ch.isalnum());first=(raw.split() or [''])[0];first_clean=''.join(ch for ch in first if ch.isalnum())
   leading=len(first_clean)<=3 and any(not ch.isalnum() for ch in first) and abs(r['x']-obs['region']['x'])<=5 and r['width']<=.35*obs['region']['width']
   if len(clean)>3 and not leading:covered=True;break
  if covered:continue
  item={'region':r,'control_type':None,'repeated_control_group_id':None,'detector':'CV_BINARY_STRUCTURED_COMPACT'}
  if not any(overlap(r,kept['region'])>=.72 for kept in compact):compact.append(item)
 rows=controls+compact;rows.sort(key=lambda item:(item['region']['y'],item['region']['x']))
 truncated=len(rows)>limit;kept=rows[:limit]
 return kept,{'detector':'CV_BINARY_THRESHOLD_180','raw_count':len(rows),'emitted_count':len(kept),'limit':limit,'truncated':truncated,'producer_family':'INDEPENDENT_BINARY_GEOMETRY'}
def _independent_observations(image,source_sha:str)->tuple[list[dict],dict]:
 observations=[]
 for idx,line in enumerate(ocr_lines(image,6),1):
  text=' '.join((line.get('text') or '').split());conf=float(line.get('confidence',0.0) or 0.0);r=line['region'];material=_text_material(text,conf);ref,pixel_sha=_pixel_evidence(source_sha,'OCR_PSM6',r,image)
  observations.append({'observation_id':f'OBS-T-{idx:04d}','detector':'OCR_PSM6','kind':'TEXT','classification':'CONFIRMED' if conf>=65 else 'INFERRED','material':material,'text':text,'confidence':round(max(0,min(1,conf/100.0)),6),'region':r,'pixel_sha256':pixel_sha,'evidence_refs':[ref]})
 for observation in observations:
  clean=''.join(char for char in str(observation.get('text') or '') if char.isalnum())
  if not observation.get('material') or len(clean)>=4:continue
  region=observation['region'];cy=region['y']+region['height']/2
  contextual=any(
   other is not observation
   and other.get('material') is True
   and ((other['region']['x']+other['region']['width']/2)<image.shape[1]/2)==((region['x']+region['width']/2)<image.shape[1]/2)
   and abs((other['region']['y']+other['region']['height']/2)-cy)<=70
   and min(abs(other['region']['x']-(region['x']+region['width'])),abs(region['x']-(other['region']['x']+other['region']['width'])))<=220
   for other in observations
  )
  if not contextual:observation['material']=False;observation['materiality_note']='ISOLATED_SHORT_OCR_NOT_MATERIAL'
 text_observations=[o for o in observations if o['kind']=='TEXT'];text_regions=[o['region'] for o in text_observations];objects,object_sweep=_sweep_objects(image,text_regions)
 for idx,r in enumerate(objects,1):
  area=int(r['width'])*int(r['height']);ref,pixel_sha=_pixel_evidence(source_sha,'CV_CANNY_70_180',r,image)
  observations.append({'observation_id':f'OBS-O-{idx:04d}','detector':'CV_CANNY_70_180','kind':'VISUAL_OBJECT','classification':'INFERRED','material':_object_material(area),'text':None,'confidence':.72,'region':r,'pixel_sha256':pixel_sha,'evidence_refs':[ref]})
 compact,compact_sweep=_sweep_compact_geometry(image,text_observations)
 for idx,item in enumerate(compact,1):
  r=item['region'];ref,pixel_sha=_pixel_evidence(source_sha,item['detector'],r,image)
  observations.append({'observation_id':f'OBS-C-{idx:04d}','detector':item['detector'],'kind':'COMPACT_VISUAL','classification':'CONFIRMED','material':True,'text':None,'confidence':.94,'region':r,'pixel_sha256':pixel_sha,'evidence_refs':[ref],'control_type':item.get('control_type'),'repeated_control_group_id':item.get('repeated_control_group_id')})
 object_sweep['compact_sweep']=compact_sweep
 object_sweep['denominator_modalities']=['OCR_PSM6','CV_CANNY_70_180','CV_BINARY_THRESHOLD_180']
 object_sweep['candidate_list_producer_excluded']=True
 return observations,object_sweep
def _best_match(obs:dict,candidates:list[dict])->tuple[dict|None,float]:
 best=None;best_score=0.0
 for e in candidates:
  er=e.get('region') or {};r=obs['region']
  if not all(k in er for k in ('x','y','width','height')):continue
  spatial=_spatial(r,er)
  if obs['kind']=='TEXT':
   if not e.get('visible_text'):continue
   sim=_text_similarity(obs.get('text'),e.get('visible_text'));short=min(len(norm(obs.get('text') or '').replace(' ','')),len(norm(e.get('visible_text') or '').replace(' ','')))<=8;minimum=.72 if short else .55;acceptable=(spatial>=.12 and sim>=minimum) or (sim>=.85 and spatial>=.05);score=.58*spatial+.42*sim
  else:
   if e.get('visible_text') or e.get('element_type') not in VISUAL_TYPES:continue
   if obs['kind']=='COMPACT_VISUAL':
    if e.get('element_type') not in COMPACT_TYPES:continue
    observation_area=max(1,int(r.get('width',0))*int(r.get('height',0)));candidate_area=max(1,int(er.get('width',0))*int(er.get('height',0)))
    if candidate_area>6*observation_area:continue
    acceptable=spatial>=.18 or iou(r,er)>=.10;score=spatial
   else:
    if e.get('element_type') not in {'VISUAL_OBJECT','IMAGE','CONTROL_REGION'}:continue
    observation_area=max(1,int(r.get('width',0))*int(r.get('height',0)));candidate_area=max(1,int(er.get('width',0))*int(er.get('height',0)));ratio=candidate_area/observation_area
    obs_coverage=overlap_primary(r,er);joint_iou=iou(r,er)
    acceptable=.30<=ratio<=3.0 and (joint_iou>=.18 or obs_coverage>=.55);score=max(joint_iou,obs_coverage)
  if acceptable and score>best_score:best,best_score=e,score
 return best,best_score
def _candidate_support(image,e:dict,text_observations:list[dict])->str:
 r=e.get('region') or {};crop=_crop(image,r)
 if crop.size==0:return 'UNSUPPORTED'
 if e.get('visible_text'):
  target=str(e.get('visible_text') or '').strip();near=[o for o in text_observations if _spatial(r,o.get('region') or {})>=.08]
  best=max([_text_similarity(target,o.get('text')) for o in near] or [0.0])
  if best>=.62:return 'SUPPORTED'
  # Candidate-directed OCR is support validation only. It is never admitted to
  # the omission denominator or independent-screen coverage producer set.
  padded=cv2.copyMakeBorder(crop,6,6,6,6,cv2.BORDER_CONSTANT,value=(255,255,255));scaled=cv2.resize(padded,None,fx=3,fy=3,interpolation=cv2.INTER_CUBIC)
  targeted=' '.join(pytesseract.image_to_string(scaled,lang='spa',config='--psm 7').split())
  if _text_similarity(target,targeted)>=.80:return 'SUPPORTED'
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
def _materiality_policy()->dict:return {'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':TEXT_CONF_STRONG,'text_confidence_long_min':TEXT_CONF_LONG,'text_long_min_alnum':4,'object_material_area_min_px2':OBJECT_MATERIAL_AREA,'rationale':'Fail-closed recall bias: long OCR strings at 35-44 confidence remain material; strong short labels remain material when they form one lexical token, while fragmented sub-4-alphanumeric OCR noise is non-material; every contour admitted by the object sweep is material from 900 px2 upward.'}
def run_independent_omission_sweep(source_path:str,expected_source_sha256:str,candidate:dict,*,execution_id:str)->dict:
 try:actual=file_sha256(source_path)
 except Exception as exc:return {'schema_version':'p0-independent-omission-sweep-v4/v2','execution_id':execution_id,'source_sha256':None,'candidate_sha256':None,'width':0,'height':0,'status':'ERROR','fresh_source_read':False,'observations':[],'regions':[],'object_sweep':None,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':['SOURCE_READ_ERROR:'+type(exc).__name__]}
 if actual!=expected_source_sha256:return {'schema_version':'p0-independent-omission-sweep-v4/v2','execution_id':execution_id,'source_sha256':actual,'candidate_sha256':None,'width':0,'height':0,'status':'BLOCKED','fresh_source_read':False,'observations':[],'regions':[],'object_sweep':None,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':['SOURCE_SHA256_MISMATCH']}
 image=cv2.imread(source_path)
 if image is None:return {'schema_version':'p0-independent-omission-sweep-v4/v2','execution_id':execution_id,'source_sha256':actual,'candidate_sha256':None,'width':0,'height':0,'status':'ERROR','fresh_source_read':True,'observations':[],'regions':[],'object_sweep':None,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':['SOURCE_DECODE_FAILED']}
 h,w=image.shape[:2];observations,object_sweep=_independent_observations(image,actual);candidates=_candidate_nonroot(candidate)
 for o in observations:
  if not o['material']:o['match_status']='NON_MATERIAL';o['matched_element_id']=None;o['match_score']=0.0;continue
  match,score=_best_match(o,candidates)
  if match is not None:o['match_status']='REPRESENTED';o['matched_element_id']=match.get('element_id');o['match_score']=round(score,6)
  elif o['kind']=='TEXT' and o.get('classification')!='CONFIRMED':o['match_status']='UNCERTAIN';o['matched_element_id']=None;o['match_score']=0.0
  else:o['match_status']='UNREPRESENTED';o['matched_element_id']=None;o['match_score']=0.0
 material_obs=[o for o in observations if o.get('material')];matched_ids={o.get('matched_element_id') for o in material_obs if o.get('match_status')=='REPRESENTED'};unsupported=[];support_uncertain=[];text_observations=[o for o in observations if o.get('kind')=='TEXT']
 for e in candidates:
  if e.get('classification')!='CONFIRMED' or not (e.get('visible_text') or e.get('element_type') in VISUAL_TYPES) or e.get('element_id') in matched_ids:continue
  support=_candidate_support(image,e,text_observations)
  if support=='UNSUPPORTED':unsupported.append(e.get('element_id'))
  elif support=='UNCERTAIN':support_uncertain.append(e.get('element_id'))
 repeated_groups=repeated_control_cardinality_groups(observations);regions=_region_rows(observations,w);compact_truncated=bool((object_sweep.get('compact_sweep') or {}).get('truncated'));errors=['SWEEP_UNIVERSE_TRUNCATED'] if object_sweep.get('truncated') or compact_truncated else [];status='BLOCKED' if errors else ('COMPLETE' if regions and all(r['sweep_status']=='COMPLETE' for r in regions) else 'INCOMPLETE');candidate_sha=canonical_sha({k:v for k,v in candidate.items() if k!='reader_execution_id'})
 return {'schema_version':'p0-independent-omission-sweep-v4/v2','execution_id':execution_id,'source_sha256':actual,'candidate_sha256':candidate_sha,'width':w,'height':h,'status':status,'fresh_source_read':True,'observations':observations,'regions':regions,'object_sweep':object_sweep,'repeated_control_groups':repeated_groups,'materiality_policy':_materiality_policy(),'unrepresented_observation_ids':[o['observation_id'] for o in material_obs if o['match_status']=='UNREPRESENTED'],'unsupported_candidate_ids':sorted(x for x in unsupported if x),'candidate_support_uncertain_ids':sorted(x for x in support_uncertain if x),'errors':errors}
def validate_sweep_receipt(sweep:dict|None,candidate:dict,ctx:dict)->list[str]:
 if not isinstance(sweep,dict):return ['INDEPENDENT_SWEEP_MISSING']
 errors=[]
 atomicity_schema=sweep.get('schema_version')=='p0-independent-omission-sweep-v4/v2'
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
  compact_sweep=object_sweep.get('compact_sweep');compact_raw=compact_emitted=compact_limit=-1;compact_observations=[o for o in observations if isinstance(o,dict) and o.get('kind')=='COMPACT_VISUAL']
  if atomicity_schema:
   modalities=set(object_sweep.get('denominator_modalities') or [])
   if not {'OCR_PSM6','CV_CANNY_70_180','CV_BINARY_THRESHOLD_180'}<=modalities:errors.append('SWEEP_DISTINCT_MODALITIES_MISSING')
   if object_sweep.get('candidate_list_producer_excluded') is not True:errors.append('SWEEP_CANDIDATE_PRODUCER_IN_DENOMINATOR')
   if not isinstance(compact_sweep,dict):errors.append('SWEEP_COMPACT_UNIVERSE_METADATA_MISSING')
  if isinstance(compact_sweep,dict):
   try:compact_raw=int(compact_sweep.get('raw_count',-1));compact_emitted=int(compact_sweep.get('emitted_count',-1));compact_limit=int(compact_sweep.get('limit',-1))
   except Exception:compact_raw=compact_emitted=compact_limit=-1;errors.append('SWEEP_COMPACT_UNIVERSE_METADATA_INVALID')
   if min(compact_raw,compact_emitted)<0 or compact_limit<=0 or compact_emitted>compact_raw or compact_emitted>compact_limit:errors.append('SWEEP_COMPACT_UNIVERSE_COUNTS_INVALID')
   if compact_emitted!=len(compact_observations):errors.append('SWEEP_COMPACT_EMITTED_COUNT_INCONSISTENT')
   if bool(compact_sweep.get('truncated'))!=(compact_raw>compact_limit):errors.append('SWEEP_COMPACT_TRUNCATION_FLAG_INCONSISTENT')
  any_truncated=expected_truncated or (atomicity_schema and isinstance(compact_sweep,dict) and compact_raw>compact_limit)
  if any_truncated:
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
 if atomicity_schema:
  recomputed_groups=repeated_control_cardinality_groups(observations)
  if sweep.get('repeated_control_groups')!=recomputed_groups:errors.append('SWEEP_REPEATED_CONTROL_CARDINALITY_INCONSISTENT')
  if any(group.get('status')!='PASS' for group in recomputed_groups):errors.append('SWEEP_REPEATED_CONTROL_CARDINALITY_MISMATCH')
 if sweep.get('errors') and sweep.get('status') not in {'ERROR','BLOCKED'}:errors.append('SWEEP_ERRORS_WITH_NONERROR_STATUS')
 return errors
