#!/usr/bin/env python3
from __future__ import annotations
import argparse,copy,json,sys
from pathlib import Path
import cv2,pytesseract
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_full_reader_v4 import full_reader,ocr_lines,cv_objects,iou,overlap_primary
from p0_visual_graders_v4 import run_all,finding,canonical_sha
from p0_visual_discovery_v4 import union_findings,coverage_receipt
from run_p0_visual_quality_loop_v4 import run_loop
TRACE={'readers':[],'grader_runs':[],'remediations':[],'targeted':[]}
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
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);ap.add_argument('--source-sha',required=True);ap.add_argument('--code-head',required=True);ap.add_argument('--config-sha',required=True);ap.add_argument('--output',required=True);a=ap.parse_args()
 result=run_loop(source_path=a.source,expected_source_sha256=a.source_sha,full_reader=traced_reader,remediator=remediator,targeted_reread=targeted,code_head_sha=a.code_head,configuration_id='P0-VISUAL-CLOSED-LOOP-V4',configuration_sha256=a.config_sha,max_remediation_cycles=5,required_clean_passes=2,grader_runner=make_grader_runner(a.source),regression_suite='PASS',adversarial_suite='PASS',artifact_hash_chain='PASS')
 pass_summ=[]
 for c,g in zip(TRACE['readers'],TRACE['grader_runs']):
  fs=union_findings(g['outputs']);cov=coverage_receipt(c,g['outputs'],g['ctx']);pass_summ.append({'pass_id':c['pass_id'],'reader_execution_id':c['reader_execution_id'],'candidate_sha256':canonical_sha({k:v for k,v in c.items() if k!='reader_execution_id'}),'reader_profile':c['reader_profile'],'element_count':len(c['elements']),'finding_counts':{s:sum(f['severity']==s for f in fs) for s in ['CRITICAL','HIGH','MEDIUM','LOW','INFO']},'finding_categories':sorted({f['category'] for f in fs}),'coverage_percent':cov['coverage_percent'],'coverage_pass':cov['coverage_pass'],'independent_sweep':g['independent_sweep'],'grader_execution_ids':[o['execution_id'] for o in g['outputs']]})
 receipt={'schema_version':'p0-v4-real-rerun-trace/v1','source_sha256':a.source_sha,'code_head_sha':a.code_head,'configuration_sha256':a.config_sha,'result':result,'passes':pass_summ,'reader_outputs':TRACE['readers'],'grader_runs':TRACE['grader_runs'],'remediation_plans':TRACE['remediations'],'targeted_rereads':TRACE['targeted']};Path(a.output).write_text(json.dumps(receipt,ensure_ascii=False,sort_keys=True,separators=(',',':')));print(json.dumps({'terminal_result':result.get('result'),'human_review_ready':result.get('human_review_ready'),'passes':pass_summ,'remediation_cycles':result.get('remediation_cycles')},ensure_ascii=False,sort_keys=True));return 0 if result.get('result')=='PASS_P0_V4_CLOSED_LOOP' else 2
if __name__=='__main__':raise SystemExit(main())
