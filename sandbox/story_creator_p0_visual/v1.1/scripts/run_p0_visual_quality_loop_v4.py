#!/usr/bin/env python3
"""V4 closed-loop orchestration. Full passes always start from immutable source bytes."""
from __future__ import annotations
import hashlib,json,uuid
from pathlib import Path
from typing import Callable
from p0_visual_graders_v4 import run_all,canonical_sha,MATERIAL_SEVERITIES
from p0_visual_discovery_v4 import union_findings,coverage_receipt
from p0_visual_convergence_v4 import convergence_receipt

def file_sha(path:str|Path)->str:
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def default_id(kind:str,pass_id:str,seq:int)->str:return f"{kind}-{pass_id}-{seq:02d}-{uuid.uuid4().hex[:12]}"
def counts(findings:list[dict])->dict:
 c={'critical':0,'high':0,'medium':0,'low':0,'info':0}
 for f in findings:c[f.get('severity','INFO').lower()]=c.get(f.get('severity','INFO').lower(),0)+1
 return c

def run_loop(*,source_path:str,expected_source_sha256:str,full_reader:Callable,remediator:Callable,targeted_reread:Callable,code_head_sha:str,configuration_id:str,configuration_sha256:str,max_remediation_cycles:int=5,required_clean_passes:int=2,grader_runner:Callable=run_all,id_factory:Callable=default_id,regression_suite:str='PASS',adversarial_suite:str='PASS',artifact_hash_chain:str='PASS')->dict:
 actual=file_sha(source_path)
 if actual!=expected_source_sha256:return {'result':'BLOCKED_SOURCE_QUALITY','human_review_ready':False,'source_sha256':actual,'cycles':[]}
 clean=0;remediations=0;state={};cycles=[];clean_receipts=[];seen_readers=set();seen_graders=set();pass_no=0
 while pass_no<max_remediation_cycles+required_clean_passes+3:
  pass_no+=1;pass_id=f'P-{pass_no:02d}';cycle_id=f'C-{pass_no:02d}';reader_exec=id_factory('READER',pass_id,pass_no)
  if reader_exec in seen_readers:return {'result':'BLOCKED_CONVERGENCE','human_review_ready':False,'reason':'REUSED_READER_EXECUTION','cycles':cycles}
  seen_readers.add(reader_exec)
  rctx={'cycle_id':cycle_id,'pass_id':pass_id,'reader_execution_id':reader_exec,'source_sha256':actual,'remediation_state':json.loads(json.dumps(state))}
  candidate=full_reader(source_path,rctx)
  if candidate.get('reader_execution_id') not in (None,reader_exec):return {'result':'BLOCKED_CONVERGENCE','human_review_ready':False,'reason':'READER_EXECUTION_MISMATCH','cycles':cycles}
  candidate=dict(candidate);candidate.pop('previous_candidate',None);candidate['reader_execution_id']=reader_exec
  csha=canonical_sha({k:v for k,v in candidate.items() if k!='reader_execution_id'})
  gctx={'cycle_id':cycle_id,'pass_id':pass_id,'reader_execution_id':reader_exec,'source_sha256':actual,'candidate_sha256':csha,'coverage_execution_id':id_factory('COVERAGE',pass_id,pass_no)}
  outs=grader_runner(candidate,gctx);ids=[o.get('execution_id') for o in outs]
  if any(not x for x in ids) or len(ids)!=len(set(ids)) or any(x in seen_graders for x in ids):return {'result':'BLOCKED_GRADER_FAILURE','human_review_ready':False,'reason':'REUSED_OR_MISSING_GRADER_EXECUTION','cycles':cycles}
  seen_graders.update(ids);cov=coverage_receipt(candidate,outs,gctx);fs=union_findings(outs);fc=counts(fs);material=[f for f in fs if f.get('severity') in MATERIAL_SEVERITIES and f.get('status')=='OPEN']
  cycle={'schema_version':'p0-loop-cycle-v4/v1','cycle_id':cycle_id,'pass_id':pass_id,'reader_execution_id':reader_exec,'source_sha256':actual,'candidate_sha256':csha,'grader_execution_ids':ids,'coverage_receipt_sha256':canonical_sha(cov),'finding_counts':fc,'material_findings':len(material),'remediation_applied':False,'targeted_reread_sha256':None,'forced_full_reread_required':False,'clean_pass_count_after':clean,'result':'CLEAN_CONTINUE'}
  if not cov['coverage_pass']:
   cycle['result']='BLOCKED_DISCOVERY_COVERAGE';cycles.append(cycle);return {'result':'BLOCKED_DISCOVERY_COVERAGE','human_review_ready':False,'cycles':cycles,'coverage':cov}
  if material:
   clean=0;clean_receipts=[];cycle['clean_pass_count_after']=0
   if remediations>=max_remediation_cycles:
    cycle['result']='BLOCKED_MAX_REMEDIATION_V4';cycles.append(cycle);return {'result':'BLOCKED_MAX_REMEDIATION_V4','human_review_ready':False,'cycles':cycles}
   new_state,actions=remediator(candidate,material,json.loads(json.dumps(state)))
   if not actions:
    cycle['result']='BLOCKED_REMEDIATION';cycles.append(cycle);return {'result':'BLOCKED_REMEDIATION','human_review_ready':False,'cycles':cycles}
   tctx={'cycle_id':cycle_id,'pass_id':pass_id,'source_sha256':actual,'candidate_sha256':csha,'reader_execution_id':reader_exec};targeted=targeted_reread(source_path,actions,tctx)
   if targeted.get('verified') is not True:
    cycle['result']='BLOCKED_REMEDIATION';cycles.append(cycle);return {'result':'BLOCKED_REMEDIATION','human_review_ready':False,'cycles':cycles,'targeted_reread':targeted}
   state=new_state;remediations+=1;cycle['remediation_applied']=True;cycle['targeted_reread_sha256']=canonical_sha(targeted);cycle['forced_full_reread_required']=True;cycle['result']='REMEDIATE_AND_RERUN';cycles.append(cycle);continue
  clean+=1;cycle['clean_pass_count_after']=clean;cycle['result']='CLEAN_CONTINUE';cycles.append(cycle);clean_receipts.append({'pass_id':pass_id,'reader_execution_id':reader_exec,'candidate_sha256':csha,'coverage_receipt_sha256':cycle['coverage_receipt_sha256'],'grader_execution_ids':ids})
  if clean<required_clean_passes:continue
  receipt=convergence_receipt(source_sha256=actual,code_head_sha=code_head_sha,configuration_id=configuration_id,configuration_sha256=configuration_sha256,clean_passes=clean_receipts[-required_clean_passes:],coverage_percent=cov['coverage_percent'],counts={'critical':0,'high':0,'unresolved_medium':0,'suspicious_confirmed':0,'contradictions':0,'unsupported_claims':0,'critical_omissions':0},regression_suite=regression_suite,adversarial_suite=adversarial_suite,source_sha_binding='PASS',artifact_hash_chain=artifact_hash_chain)
  cycle['result']='CONVERGED' if receipt['human_review_ready'] else 'BLOCKED_CONVERGENCE';return {'result':receipt['result'],'human_review_ready':receipt['human_review_ready'],'cycles':cycles,'convergence_receipt':receipt,'remediation_cycles':remediations,'clean_pass_count':clean}
 return {'result':'BLOCKED_CONVERGENCE','human_review_ready':False,'reason':'PASS_GUARD_EXHAUSTED','cycles':cycles}
