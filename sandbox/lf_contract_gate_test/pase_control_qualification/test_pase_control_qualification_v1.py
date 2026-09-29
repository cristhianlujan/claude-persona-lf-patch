#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parent
TARGET=HERE/'pase_control_qualification_v1.py'

def load():
    spec=importlib.util.spec_from_file_location('q',TARGET); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def inp(kind='NEW_CONTROL'):
    return {'schema_version':'lf-pase-control-qualification/v1','qualification_type':kind,'repository':'cristhianlujan/claude-persona-lf-patch','base_sha':'1'*40,'head_sha':'2'*40,'observed_main_sha':'3'*40,'candidate_id':'C','declared_owner':'OWNER','scope_paths':['x/'],'owner_local_tests':['x/test.py'],'boundary_invariants':['BOUNDARY'],'expected_coverage':['RESP'],'replacement':({'legacy_id':'OLD','replay_required':True} if kind=='CONTROL_REPLACEMENT' else None)}

def checks(status='PASS'):
    return [{'id':f'Q{i:02d}','status':status,'evidence':[f'e{i}@'+('2'*40)]} for i in range(1,12)]

def result(p,status='PASS',verdict='CANDIDATE_QUALIFIED'):
    return {'schema_version':'lf-pase-control-qualification-result/v1','candidate_id':p['candidate_id'],'base_sha':p['base_sha'],'head_sha':p['head_sha'],'declared_owner':p['declared_owner'],'checks':checks(status),'external_findings':[],'coverage_complete':True,'verdict':verdict,'qualified_only':True,'activation_authorized':False,'cutover_authorized':False,'rebind_authorized':False,'legacy_retirement_authorized':False}

def expect(m,p,r,code):
    try:m.validate_result(p,r)
    except m.QualificationError as e: assert str(e).startswith(code),(code,str(e)); return
    raise AssertionError(code)

def main():
    m=load(); n=0
    p=inp(); r=result(p); assert m.validate_result(p,r)=='CANDIDATE_QUALIFIED'; n+=1
    r=result(p); r['head_sha']='4'*40; expect(m,p,r,'FAIL_QUALIFICATION_IDENTITY_DRIFT'); n+=1
    r=result(p); r['checks'][0]['evidence']=[]; expect(m,p,r,'FAIL_QUALIFICATION_PASS_WITHOUT_EVIDENCE'); n+=1
    r=result(p); r['external_findings']=[{'finding_id':'E16','source_control':'E16','observed_failure':'legacy failed','candidate_causality':'DISPROVEN','causal_evidence':[],'owner':'E16_OWNER','effect_on_candidate_verdict':'FAIL'}]; expect(m,p,r,'FAIL_QUALIFICATION_EXTERNAL_CONTAMINATION'); n+=1
    r=result(p); r['external_findings']=[{'finding_id':'X','source_control':'X','observed_failure':'caused','candidate_causality':'PROVEN','causal_evidence':['diff@'+p['head_sha']],'owner':'OWNER','effect_on_candidate_verdict':'FAIL'}]; r['verdict']='FAIL'; assert m.validate_result(p,r)=='FAIL'; n+=1
    r=result(p); r['external_findings']=[{'finding_id':'X','source_control':'X','observed_failure':'unknown','candidate_causality':'UNRESOLVED','causal_evidence':[],'owner':'X_OWNER','effect_on_candidate_verdict':'BLOCKED'}]; r['verdict']='BLOCKED'; assert m.validate_result(p,r)=='BLOCKED'; n+=1
    r=result(p); r['cutover_authorized']=True; expect(m,p,r,'FAIL_QUALIFICATION_FORBIDDEN_AUTHORIZATION'); n+=1
    p=inp('CONTROL_REPLACEMENT'); r=result(p); r['checks'][8]={'id':'Q09','status':'NA','evidence':[]}; expect(m,p,r,'FAIL_QUALIFICATION_REPLAY_REQUIRED'); n+=1
    source=TARGET.read_text()
    for forbidden in ('subprocess','requests','execute_sql','apply_migration','changed_paths','cutover('): assert forbidden not in source,forbidden
    n+=1
    print(f'PASS_PASE_CONTROL_QUALIFICATION_V1 checks={n}')
    return 0
if __name__=='__main__': raise SystemExit(main())
