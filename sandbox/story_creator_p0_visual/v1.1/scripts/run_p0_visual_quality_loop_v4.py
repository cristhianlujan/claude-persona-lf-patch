#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,uuid
from p0_visual_graders_v4 import run_all,canonical_sha,MATERIAL_SEVERITIES
from p0_visual_discovery_v4 import union_findings,coverage_receipt
from p0_visual_convergence_v4 import convergence_receipt,make_gate_proof
from p0_independent_omission_sweep_v4 import run_independent_omission_sweep

def file_sha(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def default_id(kind,pass_id,seq):return f"{kind}-{pass_id}-{seq:02d}-{uuid.uuid4().hex[:12]}"
def counts(fs):
 c={'critical':0,'high':0,'medium':0,'low':0,'info':0}
 for f in fs:c[f.get('severity','INFO').lower()]=c.get(f.get('severity','INFO').lower(),0)+1
 return c

def run_loop(*,source_path,expected_source_sha256,full_reader,remediator,targeted_reread,code_head_sha,configuration_id,configuration_sha256,max_remediation_cycles=5,required_clean_passes=2,grader_runner=run_all,omission_sweep_runner=run_independent_omission_sweep,id_factory=default_id,regression_proof=None,adversarial_proof=None,artifact_hash_proof=None):
 actual=file_sha(source_path)
 if actual!=expected_source_sha256:return {'result':'BLOCKED_SOURCE_QUALITY','human_review_ready':False,'source_sha256':actual,'cycles':[]}
 source_binding_proof=make_gate_proof(gate='source_sha_binding',source_sha256=actual,code_head_sha=code_head_sha,configuration_sha256=configuration_sha256,details={'expected_source_sha256':expected_source_sha256,'observed_source_sha256':actual,'matched':actual==expected_source_sha256})
 clean=remediations=pass_no=0;state={};cycles=[];clean_receipts=[];seen_readers=set();seen_graders=set();seen_sweeps=set()
 while pass_no<max_remediation_cycles+required_clean_passes+3:
  pass_no+=1;pid=f'P-{pass_no:02d}';cid=f'C-{pass_no:02d}';rex=id_factory('READER',pid,pass_no)
  if rex in seen_readers:return {'result':'BLOCKED_CONVERGENCE','human_review_ready':False,'reason':'REUSED_READER_EXECUTION','cycles':cycles}
  seen_readers.add(rex);rctx={'cycle_id':cid,'pass_id':pid,'reader_execution_id':rex,'source_sha256':actual,'remediation_state':json.loads(json.dumps(state))}
  try:cand=full_reader(source_path,rctx)
  except Exception as exc:return {'result':'BLOCKED_DISCOVERY_COVERAGE','human_review_ready':False,'reason':'FULL_READER_ERROR:'+type(exc).__name__,'cycles':cycles}
  if cand.get('reader_execution_id') not in (None,rex):return {'result':'BLOCKED_CONVERGENCE','human_review_ready':False,'reason':'READER_EXECUTION_MISMATCH','cycles':cycles}
  cand=dict(cand);cand.pop('previous_candidate',None);cand['reader_execution_id']=rex;csha=canonical_sha({k:v for k,v in cand.items() if k!='reader_execution_id'})
  swid=id_factory('SWEEP',pid,pass_no)
  if not swid or swid in seen_sweeps:return {'result':'BLOCKED_DISCOVERY_COVERAGE','human_review_ready':False,'reason':'REUSED_OR_MISSING_SWEEP_EXECUTION','cycles':cycles}
  seen_sweeps.add(swid)
  try:sweep=omission_sweep_runner(source_path,actual,cand,execution_id=swid)
  except Exception as exc:return {'result':'BLOCKED_DISCOVERY_COVERAGE','human_review_ready':False,'reason':'OMISSION_SWEEP_ERROR:'+type(exc).__name__,'cycles':cycles}
  if not isinstance(sweep,dict) or sweep.get('execution_id')!=swid:return {'result':'BLOCKED_DISCOVERY_COVERAGE','human_review_ready':False,'reason':'OMISSION_SWEEP_EXECUTION_MISMATCH','cycles':cycles}
  ssha=canonical_sha(sweep);gctx={'cycle_id':cid,'pass_id':pid,'reader_execution_id':rex,'source_sha256':actual,'candidate_sha256':csha,'coverage_execution_id':id_factory('COVERAGE',pid,pass_no),'independent_sweep':sweep}
  try:outs=grader_runner(cand,gctx)
  except Exception as exc:return {'result':'BLOCKED_GRADER_FAILURE','human_review_ready':False,'reason':'GRADER_RUNNER_ERROR:'+type(exc).__name__,'cycles':cycles}
  ids=[o.get('execution_id') for o in outs]
  if any(not x for x in ids) or len(ids)!=len(set(ids)) or any(x in seen_graders for x in ids):return {'result':'BLOCKED_GRADER_FAILURE','human_review_ready':False,'reason':'REUSED_OR_MISSING_GRADER_EXECUTION','cycles':cycles}
  seen_graders.update(ids);cov=coverage_receipt(cand,outs,gctx);fs=union_findings(outs);material=[f for f in fs if f.get('severity') in MATERIAL_SEVERITIES and f.get('status')=='OPEN'];cycle={'schema_version':'p0-loop-cycle-v4/v1','cycle_id':cid,'pass_id':pid,'reader_execution_id':rex,'omission_sweep_execution_id':swid,'omission_sweep_sha256':ssha,'source_sha256':actual,'candidate_sha256':csha,'grader_execution_ids':ids,'coverage_receipt_sha256':canonical_sha(cov),'finding_counts':counts(fs),'material_findings':len(material),'remediation_applied':False,'targeted_reread_sha256':None,'forced_full_reread_required':False,'clean_pass_count_after':clean,'result':'CLEAN_CONTINUE'}
  if sweep.get('status') in {'ERROR','BLOCKED'}:
   cycle['result']='BLOCKED_DISCOVERY_COVERAGE';cycles.append(cycle);return {'result':'BLOCKED_DISCOVERY_COVERAGE','human_review_ready':False,'reason':'INDEPENDENT_SWEEP_'+str(sweep.get('status')),'cycles':cycles,'coverage':cov,'independent_sweep':sweep}
  if not cov['coverage_pass']:
   hard_errors=[e for e in cov.get('grader_errors',[]) if e.get('error')!='INDEPENDENT_SCREEN_COVERAGE_INCOMPLETE'];candidate_complete=bool((cov.get('candidate_grader_coverage') or {}).get('complete'))
   if hard_errors or not candidate_complete or not material:
    cycle['result']='BLOCKED_DISCOVERY_COVERAGE';cycles.append(cycle);return {'result':'BLOCKED_DISCOVERY_COVERAGE','human_review_ready':False,'cycles':cycles,'coverage':cov,'independent_sweep':sweep}
  if material:
   clean=0;clean_receipts=[];cycle['clean_pass_count_after']=0
   if remediations>=max_remediation_cycles:cycle['result']='BLOCKED_MAX_REMEDIATION_V4';cycles.append(cycle);return {'result':'BLOCKED_MAX_REMEDIATION_V4','human_review_ready':False,'cycles':cycles}
   new_state,actions=remediator(cand,material,json.loads(json.dumps(state)))
   if not actions:cycle['result']='BLOCKED_REMEDIATION';cycles.append(cycle);return {'result':'BLOCKED_REMEDIATION','human_review_ready':False,'cycles':cycles}
   tctx={'cycle_id':cid,'pass_id':pid,'source_sha256':actual,'candidate_sha256':csha,'reader_execution_id':rex,'omission_sweep_execution_id':swid};targeted=targeted_reread(source_path,actions,tctx)
   if targeted.get('verified') is not True:cycle['result']='BLOCKED_REMEDIATION';cycles.append(cycle);return {'result':'BLOCKED_REMEDIATION','human_review_ready':False,'cycles':cycles,'targeted_reread':targeted}
   state=new_state;remediations+=1;cycle.update({'remediation_applied':True,'targeted_reread_sha256':canonical_sha(targeted),'forced_full_reread_required':True,'result':'REMEDIATE_AND_RERUN'});cycles.append(cycle);continue
  clean+=1;cycle['clean_pass_count_after']=clean;cycles.append(cycle);clean_receipts.append({'pass_id':pid,'reader_execution_id':rex,'omission_sweep_execution_id':swid,'omission_sweep_sha256':ssha,'candidate_sha256':csha,'coverage_receipt_sha256':cycle['coverage_receipt_sha256'],'grader_execution_ids':ids})
  if clean<required_clean_passes:continue
  z={'critical':0,'high':0,'unresolved_medium':0,'suspicious_confirmed':0,'contradictions':0,'unsupported_claims':0,'critical_omissions':0};receipt=convergence_receipt(source_sha256=actual,code_head_sha=code_head_sha,configuration_id=configuration_id,configuration_sha256=configuration_sha256,clean_passes=clean_receipts[-required_clean_passes:],coverage_percent=cov['coverage_percent'],counts=z,regression_proof=regression_proof,adversarial_proof=adversarial_proof,source_binding_proof=source_binding_proof,artifact_hash_proof=artifact_hash_proof);cycle['result']='CONVERGED' if receipt['human_review_ready'] else 'BLOCKED_CONVERGENCE';return {'result':receipt['result'],'human_review_ready':receipt['human_review_ready'],'cycles':cycles,'convergence_receipt':receipt,'remediation_cycles':remediations,'clean_pass_count':clean}
 return {'result':'BLOCKED_CONVERGENCE','human_review_ready':False,'reason':'PASS_GUARD_EXHAUSTED','cycles':cycles}
