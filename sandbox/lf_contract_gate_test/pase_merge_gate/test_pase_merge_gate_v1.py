#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, importlib.util, json, uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent
TARGET=HERE/'pase_merge_gate_v1.py'
HEAD='d'*40; PLAN_DIGEST='e'*64; ROUTE_REV='a'*64; VALIDATOR_REV='b'*64

def load():
 spec=importlib.util.spec_from_file_location('pase_merge_gate_v1_test_target',TARGET)
 if spec is None or spec.loader is None: raise SystemExit('FAIL_PASE_MERGE_GATE_LOAD')
 m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def canonical(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=True)
def digest(v): return hashlib.sha256(canonical(v).encode()).hexdigest()
def plan(required): return {'schema_version':'lf-ci-execution-plan/v2','coverage_complete':True,'required_controls':sorted(required),'plan_sha256':PLAN_DIGEST}
def enforcement(required,blocking):
 required=sorted(required); blocking=sorted(blocking); observe=sorted(set(required)-set(blocking))
 v={'schema_version':'lf-pase-control-enforcement/v1','authority':'CHANGESET_GOVERNANCE_LF_V1','policy_id':'PASE_CONTROL_REPAIR_QUARANTINE_V1','source_plan_sha256':PLAN_DIGEST,'required_controls':required,'blocking_controls':blocking,'observe_only_controls':observe,'repair_window_active':True,'manual_diagnostic_execution_allowed':True,'observe_only_results_cannot_block_merge':True,'no_applicability_reclassification':True,'structural_governance_fail_closed':True,'silent_reactivation_forbidden':True}; v['result_sha256']=digest(v); return v
def route(mode,required,candidate_id=None): return {'schema_version':'lf-pase-merge-route/v1','authority':'CHANGESET_GOVERNANCE_LF_V1','mode':mode,'head_sha':HEAD,'source_revision':ROUTE_REV,'required_control_ids':sorted(required),'candidate_id':candidate_id}
def terminal(cid, verdict='PASS', **overrides):
 v={'schema_version':'lf-pase-control-terminal-verdict/v1','control_id':cid,'capability_code':cid,'plan_digest':PLAN_DIGEST,'head_sha':HEAD,'source_head_sha':HEAD,'verdict':verdict,'authority':'EVIDENCE_LEDGER','receipt_kind':'CONTROL_TERMINAL_VERDICT','verification_state':'VERIFIED','execution_id':f'EXEC-{cid}','runner_execution_id':f'EXEC-{cid}','orchestrator_execution_id':'EXEC-ORCH','dispatch_receipt_id':str(uuid.UUID(int=1)),'dispatch_receipt_sha256':'1'*64,'evidence_ledger_receipt_id':str(uuid.UUID(int=2)),'receipt_sha256':'2'*64,'evidence_sha256':'3'*64,'actual_runner_execution':True,'terminal':True,'dispatch_only':False}; v.update(overrides); return v
def diagnostic(cid,verdict='FAIL'): return {'control_id':cid,'head_sha':HEAD,'verdict':verdict}
def qualification_result(verdict='CANDIDATE_QUALIFIED'):
 return {'schema_version':'lf-pase-control-qualification-result/v1','candidate_id':'PASE_ORCHESTRATOR_V1','base_sha':'8'*40,'head_sha':HEAD,'declared_owner':'LF_GOVERNANCE','checks':[],'external_findings':[],'coverage_complete':True,'verdict':verdict,'qualified_only':True,'activation_authorized':False,'cutover_authorized':False,'rebind_authorized':False,'legacy_retirement_authorized':False}
def qualification():
 r=qualification_result(); return {'schema_version':'lf-pase-qualified-evidence/v1','authority':'PASE_CONTROL_QUALIFICATION_V1','independent':True,'validated':True,'validator_revision':VALIDATOR_REV,'result_sha256':digest(r),'result':r}
def packet(blocking=True):
 applicable=['CONTROL_A','CONTROL_B']; b=['CONTROL_A'] if blocking else []
 return {'schema_version':'lf-pase-merge-gate-input/v1','head_sha':HEAD,'route':route('EXECUTION_PLAN',b),'plan':plan(applicable),'enforcement':enforcement(applicable,b),'qualification':None,'control_results':[terminal('CONTROL_A')] if blocking else [],'diagnostic_results':[diagnostic(x) for x in applicable if x not in b]}
def qpacket():
 applicable=['E16_GOVERNANCE']; return {'schema_version':'lf-pase-merge-gate-input/v1','head_sha':HEAD,'route':route('CONTROL_SYSTEM_QUALIFICATION',[],'PASE_ORCHESTRATOR_V1'),'plan':plan(applicable),'enforcement':enforcement(applicable,[]),'qualification':qualification(),'control_results':[],'diagnostic_results':[diagnostic('E16_GOVERNANCE')]}
def expect(m,p,code):
 try: m.evaluate_merge_gate(p)
 except m.PaseMergeGateError as exc: assert str(exc).startswith(code),(code,str(exc)); return
 raise AssertionError(code)
def rehash(p): p['enforcement'].pop('result_sha256',None); p['enforcement']['result_sha256']=digest(p['enforcement'])

def main():
 m=load(); checks=0
 g=m.evaluate_merge_gate(packet()); assert g['merge_ready'] and g['terminal_verdict_authority']=='EVIDENCE_LEDGER' and g['dispatch_receipt_is_terminal_verdict'] is False and g['terminal_verdict_receipt_ids']['CONTROL_A']==str(uuid.UUID(int=2)); checks+=1
 g=m.evaluate_merge_gate(packet(False)); assert g['required_control_ids']==[] and g['observe_only_control_ids']==['CONTROL_A','CONTROL_B']; checks+=1
 g=m.evaluate_merge_gate(qpacket()); assert g['mode']=='CONTROL_SYSTEM_QUALIFICATION' and g['merge_ready']; checks+=1
 p=packet(); p['control_results']=[{'control_id':'CONTROL_A','head_sha':HEAD,'verdict':'PASS','authority':'CONTROL_A_OWNER','evidence_sha256':'c'*64}]; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_SCHEMA'); checks+=1
 p=packet(); p['control_results'][0]['authority']='ORCHESTRATOR_DISPATCH_RECEIPT'; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_AUTHORITY'); checks+=1
 p=packet(); p['control_results'][0]['receipt_kind']='DISPATCH_RECEIPT'; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_LEDGER_STATE'); checks+=1
 p=packet(); p['control_results'][0]['verification_state']='ANCHORED'; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_LEDGER_STATE'); checks+=1
 p=packet(); p['control_results'][0]['plan_digest']='f'*64; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_PLAN'); checks+=1
 p=packet(); p['control_results'][0]['source_head_sha']='1'*40; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_HEAD'); checks+=1
 p=packet(); p['control_results'][0]['runner_execution_id']='EXEC-OTHER'; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_RUNNER'); checks+=1
 p=packet(); p['control_results'][0]['dispatch_receipt_id']=p['control_results'][0]['evidence_ledger_receipt_id']; expect(m,p,'FAIL_PASE_MERGE_DISPATCH_IS_TERMINAL_VERDICT'); checks+=1
 p=packet(); p['control_results'][0]['actual_runner_execution']=False; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_EXECUTION_PROOF'); checks+=1
 p=packet(); p['control_results'][0]['dispatch_only']=True; expect(m,p,'FAIL_PASE_MERGE_TERMINAL_VERDICT_DISPATCH_ONLY'); checks+=1
 p=packet(); p['control_results'][0]['verdict']='FAIL'; expect(m,p,'BLOCK_PASE_MERGE_CONTROL_NOT_PASS'); checks+=1
 p=packet(); p['control_results']=[]; expect(m,p,'FAIL_PASE_MERGE_CONTROL_RESULT_COVERAGE'); checks+=1
 p=packet(); p['control_results'].append(terminal('CONTROL_B')); expect(m,p,'FAIL_PASE_MERGE_CONTROL_RESULT_UNPLANNED'); checks+=1
 p=packet(); p['route']['required_control_ids']=[]; expect(m,p,'FAIL_PASE_MERGE_ROUTE_ENFORCEMENT_DRIFT'); checks+=1
 p=packet(); p['diagnostic_results']=[diagnostic('CONTROL_A')]; expect(m,p,'FAIL_PASE_MERGE_DIAGNOSTIC_RESULT_CONTROL'); checks+=1
 p=qpacket(); p['qualification']=None; expect(m,p,'FAIL_PASE_MERGE_QUALIFICATION_MISSING'); checks+=1
 p=qpacket(); p['qualification']['independent']=False; expect(m,p,'FAIL_PASE_MERGE_QUALIFICATION_NOT_INDEPENDENT_VALIDATED'); checks+=1
 p=packet(); p['enforcement']['blocking_controls']=['CONTROL_A','CONTROL_B']; p['enforcement']['observe_only_controls']=[]; rehash(p); expect(m,p,'FAIL_PASE_MERGE_ROUTE_ENFORCEMENT_DRIFT'); checks+=1
 p=packet(); p['plan']['coverage_complete']=False; expect(m,p,'FAIL_PASE_MERGE_PLAN_COVERAGE'); checks+=1
 source=TARGET.read_text(encoding='utf-8')
 for forbidden in ('import subprocess','import requests','urllib','execute_sql','apply_migration','merge_pull_request'):
  assert forbidden not in source,forbidden
 checks+=1
 print(f'PASS_PASE_MERGE_GATE_TERMINAL_VERDICT_V1 checks={checks}'); return 0
if __name__=='__main__': raise SystemExit(main())
