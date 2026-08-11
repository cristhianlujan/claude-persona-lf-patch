#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from run_p0_visual_quality_loop_v4 import run_loop
from p0_visual_grader_core_v4 import canonical_sha
from p0_visual_convergence_v4 import convergence_receipt_binding
H40='b'*40;CFG='c'*64
POLICY={'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':45.0,'text_confidence_long_min':35.0,'text_long_min_alnum':4,'object_material_area_min_px2':900,'rationale':'test fixture mirrors product policy'}

def source():
 p=Path(tempfile.mkstemp(suffix='.bin')[1]);p.write_bytes(b'fixed-original-pixels');return p,hashlib.sha256(p.read_bytes()).hexdigest()
def candidate(bad=False):
 e={'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1,'region':{'x':0,'y':0,'width':100,'height':100},'parent_id':None,'evidence_refs':['r'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True}
 if bad:e.update({'element_type':'TEXT','visible_text':'7','graphic_score':.9,'ocr_variants':['7','?']})
 return {'width':100,'height':100,'elements':[e],'fresh_source_read':True,'reader_origin':'SOURCE_PIXELS'}
def blank_sweep(path,sha,candidate,*,execution_id):
 return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':execution_id,'source_sha256':sha,'candidate_sha256':canonical_sha({k:v for k,v in candidate.items() if k!='reader_execution_id'}),'width':100,'height':100,'status':'COMPLETE','fresh_source_read':True,'observations':[],'regions':[{'region_id':r,'material':True,'observed_count':0,'represented_count':0,'uncertain_count':0,'unrepresented_count':0,'sweep_status':'COMPLETE','evidence_refs':[]} for r in ('FULL','LEFT','RIGHT')],'object_sweep':{'detector':'TEST_FIXTURE','raw_count':0,'deduped_count':0,'emitted_count':0,'limit':60,'truncated':False},'materiality_policy':POLICY,'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':[]}
def targeted(path,actions,ctx):return {'verified':True,'actions':len(actions),'source_sha256':ctx['source_sha256']}
def remediate(c,findings,state):state['fixed']=True;return state,[{'category':findings[0]['category']}]
def base(reader,**kw):
 p,sha=source();r=run_loop(source_path=str(p),expected_source_sha256=sha,full_reader=reader,remediator=kw.pop('remediator',remediate),targeted_reread=kw.pop('targeted_reread',targeted),code_head_sha=H40,configuration_id='P0-V4',configuration_sha256=CFG,omission_sweep_runner=kw.pop('omission_sweep_runner',blank_sweep),**kw);p.unlink();return r
def main():
 checks=[];calls=[]
 def reader_fix(path,ctx):calls.append((path,ctx['pass_id'],dict(ctx['remediation_state'])));return candidate(not ctx['remediation_state'].get('fixed',False))
 r=base(reader_fix);assert r['result']=='PASS_P0_V4_CLOSED_LOOP' and r['human_review_ready'] and len(calls)==3 and r['cycles'][0]['forced_full_reread_required'];checks.append('REMEDIATION_FORCES_FULL_REREAD')
 assert r['cycles'][0]['result']=='REMEDIATE_AND_RERUN' and r['cycles'][1]['result']=='CLEAN_CONTINUE' and r['cycles'][1]['clean_pass_count_after']==1;checks.append('TARGETED_NOT_GLOBAL_PASS')
 cp=r['convergence_receipt']['clean_passes'];assert cp[0]['reader_execution_id']!=cp[1]['reader_execution_id'] and cp[0]['omission_sweep_execution_id']!=cp[1]['omission_sweep_execution_id'];checks.append('TWO_FRESH_READER_AND_SWEEP_PASSES')
 binding=convergence_receipt_binding(r['convergence_receipt']);assert binding['logical_receipt_canonical_sha256']==binding['logical_receipt_canonical_bytes_sha256'] and binding['logical_receipt_canonical_bytes_length']>0 and binding['detector_diversity']['second_ocr_engine_evaluation']=='DEFERRED_NOT_IN_RUNTIME';checks.append('CONVERGENCE_EXTERNAL_BINDING_AND_OCR_LIMITATION_PUBLISHED')
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
 r=base(lambda p,c:candidate(False),omission_sweep_runner=lambda *a,**k:(_ for _ in ()).throw(RuntimeError('boom')));assert r['result']=='BLOCKED_DISCOVERY_COVERAGE' and r['reason'].startswith('OMISSION_SWEEP_ERROR');checks.append('SWEEP_EXECUTION_ERROR_FAILS_CLOSED')
 def saturated(path,sha,candidate,*,execution_id):
  s=blank_sweep(path,sha,candidate,execution_id=execution_id);s['status']='BLOCKED';s['errors']=['SWEEP_UNIVERSE_TRUNCATED'];s['object_sweep'].update({'raw_count':61,'deduped_count':61,'emitted_count':60,'limit':60,'truncated':True});s['observations']=[{'observation_id':f'OBS-O-{i:04d}','detector':'TEST_FIXTURE','kind':'VISUAL_OBJECT','classification':'INFERRED','material':False,'text':None,'confidence':.7,'region':{'x':0,'y':0,'width':1,'height':1},'pixel_sha256':'a'*64,'evidence_refs':['r'],'match_status':'NON_MATERIAL','matched_element_id':None,'match_score':0.0} for i in range(60)];return s
 r=base(lambda p,c:candidate(False),omission_sweep_runner=saturated);assert r['result']=='BLOCKED_DISCOVERY_COVERAGE';checks.append('SWEEP_UNIVERSE_TRUNCATION_BLOCKS_LOOP')
 print(json.dumps({'gate':'PASS_V4_CLOSED_LOOP_ENGINE','checks':len(checks),'results':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
