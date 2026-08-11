#!/usr/bin/env python3
from __future__ import annotations
import copy
import cv2,pytesseract
from p0_full_reader_v4 import full_reader
from p0_independent_omission_sweep_v4 import run_independent_omission_sweep
from p0_visual_graders_v4 import run_all
TRACE={'readers':[],'grader_runs':[],'omission_sweeps':[],'remediations':[],'targeted':[]}
def reset_trace():
 for v in TRACE.values():v.clear()
def traced_sweep(source_path,expected_sha,candidate,*,execution_id):
 sw=run_independent_omission_sweep(source_path,expected_sha,candidate,execution_id=execution_id);TRACE['omission_sweeps'].append(copy.deepcopy(sw));return sw
def traced_grader_runner(candidate,ctx):
 outs=run_all(candidate,ctx);TRACE['grader_runs'].append({'ctx':copy.deepcopy(ctx),'outputs':copy.deepcopy(outs)});return outs
def make_grader_runner(source_path=None):return traced_grader_runner
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
 if im is None:return {'verified':False,'action_count':len(actions),'source_sha256':ctx['source_sha256'],'reread_execution':'TARGET-'+ctx['pass_id'],'region_verifications':0}
 for a in actions:
  r=a['region'];x=max(0,r['x']-8);y=max(0,r['y']-8);x2=min(im.shape[1],r['x']+r['width']+8);y2=min(im.shape[0],r['y']+r['height']+8);crop=im[y:y2,x:x2]
  if crop.size==0:verified.append(False);continue
  for psm in (6,11):pytesseract.image_to_string(crop,lang='spa',config=f'--psm {psm}')
  verified.append(True)
 out={'verified':all(verified) if verified else False,'action_count':len(actions),'source_sha256':ctx['source_sha256'],'reread_execution':'TARGET-'+ctx['pass_id'],'region_verifications':len(verified)};TRACE['targeted'].append(copy.deepcopy(out));return out
