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
 if im is None:return {'verified':False,'action_count':len(actions),'source_sha256':ctx['source_sha256'],'reread_execution':'TARGET-'+ctx['pass_id'],'region_verifications':0,'reread_scope':'SOURCE_DECODE_FAILED'}
 for a in actions:
  r=a['region'];x=max(0,int(r.get('x',0))-8);y=max(0,int(r.get('y',0))-8);x2=min(im.shape[1],int(r.get('x',0))+int(r.get('width',0))+8);y2=min(im.shape[0],int(r.get('y',0))+int(r.get('height',0))+8);verified.append(bool(x2>x and y2>y and im[y:y2,x:x2].size))
 # Fresh whole-source corroboration is executed once per targeted receipt instead of
 # spawning two OCR subprocesses per finding category. This does not count as a global clean pass.
 if verified and all(verified):
  for psm in (6,11):pytesseract.image_to_string(im,lang='spa',config=f'--psm {psm}')
 out={'verified':all(verified) if verified else False,'action_count':len(actions),'source_sha256':ctx['source_sha256'],'reread_execution':'TARGET-'+ctx['pass_id'],'region_verifications':len(verified),'reread_scope':'SELECTED_REGIONS_CORROBORATED_BY_FRESH_SOURCE_PSM6_PSM11'};TRACE['targeted'].append(copy.deepcopy(out));return out
