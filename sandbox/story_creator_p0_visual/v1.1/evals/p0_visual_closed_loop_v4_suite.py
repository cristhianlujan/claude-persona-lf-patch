#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from run_p0_visual_quality_loop_v4 import run_loop
H40='b'*40;CFG='c'*64
def source():
 p=Path(tempfile.mkstemp(suffix='.bin')[1]);p.write_bytes(b'fixed-original-pixels');return p,hashlib.sha256(p.read_bytes()).hexdigest()
def candidate(bad=False):
 e={'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1,'region':{'x':0,'y':0,'width':100,'height':100},'parent_id':None,'evidence_refs':['r'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True}
 if bad:e.update({'element_type':'TEXT','visible_text':'7','graphic_score':.9,'ocr_variants':['7','?']})
 return {'width':100,'height':100,'elements':[e],'coverage_map':[{'region_id':'FULL','material':True,'observed_count':1,'represented_count':1,'sweep_status':'COMPLETE'}]}
def targeted(path,actions,ctx):return {'verified':True,'actions':len(actions),'source_sha256':ctx['source_sha256']}
def remediate(c,findings,state):state['fixed']=True;return state,[{'category':findings[0]['category']}]
def base(reader,**kw):
 p,sha=source();r=run_loop(source_path=str(p),expected_source_sha256=sha,full_reader=reader,remediator=kw.pop('remediator',remediate),targeted_reread=kw.pop('targeted_reread',targeted),code_head_sha=H40,configuration_id='P0-V4',configuration_sha256=CFG,**kw);p.unlink();return r
def main():
 checks=[];calls=[]
 def reader_fix(path,ctx):calls.append((path,ctx['pass_id'],dict(ctx['remediation_state'])));return candidate(not ctx['remediation_state'].get('fixed',False))
 r=base(reader_fix);assert r['result']=='PASS_P0_V4_CLOSED_LOOP' and r['human_review_ready'] and len(calls)==3 and r['cycles'][0]['forced_full_reread_required'];checks.append('REMEDIATION_FORCES_FULL_REREAD')
 assert r['cycles'][0]['result']=='REMEDIATE_AND_RERUN' and r['cycles'][1]['result']=='CLEAN_CONTINUE' and r['cycles'][1]['clean_pass_count_after']==1;checks.append('TARGETED_NOT_GLOBAL_PASS')
 assert r['convergence_receipt']['clean_passes'][0]['reader_execution_id']!=r['convergence_receipt']['clean_passes'][1]['reader_execution_id'];checks.append('TWO_FRESH_CLEAN_PASSES')
 seq=[False,True,False,False]
 def reader_reset(path,ctx):return candidate(seq.pop(0))
 r=base(reader_reset,remediator=lambda c,f,s:(s,[{'fixed':'policy'}]));assert r['result']=='PASS_P0_V4_CLOSED_LOOP' and [x['clean_pass_count_after'] for x in r['cycles']]==[1,0,1,2];checks.append('NEW_FINDING_RESETS_STREAK')
 r=base(lambda p,c:candidate(True),max_remediation_cycles=2);assert r['result']=='BLOCKED_MAX_REMEDIATION_V4';checks.append('MAX_CYCLES_BLOCKS')
 r=base(lambda p,c:candidate(False),id_factory=lambda kind,passid,seq:kind+'-SAME');assert r['result']=='BLOCKED_CONVERGENCE' and r['reason']=='REUSED_READER_EXECUTION';checks.append('REUSED_READER_BLOCKS')
 from p0_visual_graders_v4 import run_all
 def stale(c,ctx):
  outs=run_all(c,ctx)
  for i,o in enumerate(outs):o['execution_id']='STATIC-G-'+str(i)
  return outs
 r=base(lambda p,c:candidate(False),grader_runner=stale);assert r['result']=='BLOCKED_GRADER_FAILURE';checks.append('REUSED_JUDGE_BLOCKS')
 r=base(lambda p,c:candidate(False),regression_suite='FAIL');assert r['result']=='BLOCKED_CONVERGENCE' and not r['human_review_ready'];checks.append('ONE_GATE_FAILS_HUMAN_READY')
 print(json.dumps({'gate':'PASS_V4_CLOSED_LOOP_ENGINE','checks':len(checks),'results':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
