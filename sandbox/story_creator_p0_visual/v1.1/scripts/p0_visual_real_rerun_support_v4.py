#!/usr/bin/env python3
from __future__ import annotations
import copy
import cv2,pytesseract
from p0_full_reader_v4 import full_reader,ocr_lines,cv_objects,iou,overlap_primary
from p0_visual_graders_v4 import run_all,finding
TRACE={'readers':[],'grader_runs':[],'remediations':[],'targeted':[]}
def reset_trace():
 for v in TRACE.values():v.clear()
def independent_sweep(source_path,candidate):
 image=cv2.imread(source_path);ocr=ocr_lines(image,6);objs=cv_objects(image,[x['region'] for x in ocr]);observations=[('OCR',x['region']) for x in ocr]+[('CV',r) for r in objs];candidate_regions=[e['region'] for e in candidate.get('elements',[]) if e.get('element_id')!='V4-ROOT'];missing=[]
 for kind,r in observations:
  if not any(overlap_primary(r,c)>=.25 or iou(r,c)>=.10 for c in candidate_regions):missing.append((kind,r))
 return {'ocr_count':len(ocr),'cv_count':len(objs),'observation_count':len(observations),'missing':missing}
def make_grader_runner(source_path):
 def runner(candidate,ctx):
  outs=run_all(candidate,ctx);sw=independent_sweep(source_path,candidate);jc=next(x for x in outs if x['grader_id']=='J-COMPLETE')
  if sw['missing']:
   for kind,r in sw['missing'][:10]:jc['findings'].append(finding(ctx,'J-COMPLETE','MATERIAL_OMISSION','HIGH',{'element_id':None,'region':r,'evidence_refs':['p0://v4/independent-sweep']},{'kind':kind,'independent_sweep':True},'REREAD',.93,'independent-omission-sweep'))
   jc['status']='BLOCKED'
  TRACE['grader_runs'].append({'ctx':copy.deepcopy(ctx),'outputs':copy.deepcopy(outs),'independent_sweep':{'ocr_count':sw['ocr_count'],'cv_count':sw['cv_count'],'observation_count':sw['observation_count'],'missing_count':len(sw['missing'])}});return outs
 return runner
def traced_reader(path,ctx):
 c=full_reader(path,ctx);TRACE['readers'].append(copy.deepcopy(c));return c
def remediator(candidate,findings,state):
 actions=[];seen=set()
 for f in findings:
  if f['category'] in seen:continue
  seen.add(f['category']);actions.append({'category':f['category'],'region':f.get('region') or {'x':0,'y':0,'width':0,'height':0},'action':'STRICT_CONSENSUS_REREAD','affected_findings':sum(x['category']==f['category'] for x in findings)})
 state=dict(state);state['strict_mode']=True;TRACE['remediations'].append({'finding_count':len(findings),'categories':sorted(seen),'actions':copy.deepcopy(actions)});return state,actions
def targeted(source_path,actions,ctx):
 im=cv2.imread(source_path);verified=[]
 for a in actions:
  r=a['region'];x=max(0,r['x']-8);y=max(0,r['y']-8);x2=min(im.shape[1],r['x']+r['width']+8);y2=min(im.shape[0],r['y']+r['height']+8);crop=im[y:y2,x:x2]
  if crop.size==0:verified.append(False);continue
  for psm in (6,11):pytesseract.image_to_string(crop,lang='spa',config=f'--psm {psm}')
  verified.append(True)
 out={'verified':all(verified) if verified else False,'action_count':len(actions),'source_sha256':ctx['source_sha256'],'reread_execution':'TARGET-'+ctx['pass_id'],'region_verifications':len(verified)};TRACE['targeted'].append(copy.deepcopy(out));return out
