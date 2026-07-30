#!/usr/bin/env python3
from __future__ import annotations
import copy,json,os,re,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];SKILL=ROOT/'skills'/'creating-integral-user-stories';TEXT=(SKILL/'references/test-derivation-contract.md').read_text();BLOCKS=[json.loads(x) for x in re.findall(r'```json\n(.*?)\n```',TEXT,re.S)];TEST,FIXTURE=BLOCKS
def env(metadata=True):
 value=os.environ.copy();value['PYTHONPATH']=str(SKILL/'scripts')
 if metadata:value.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_A41_AUDITOR')
 else:value.pop('LF_JUDGE_VERSION',None);value.pop('LF_EXECUTOR_IDENTITY',None)
 return value
def emit(payload,metadata=True):
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'input.json';path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n');process=subprocess.run([sys.executable,'scripts/validate_test_coverage.py',str(path),'--evidence-ref',f'file:{path}'],cwd=SKILL,env=env(metadata),text=True,capture_output=True);lines=[x for x in process.stdout.splitlines() if x.strip().startswith('{')];return json.loads(lines[-1])
def case(name,payload,expected,metadata=True):
 result=emit(payload,metadata);return {'case':name,'expected':expected,'actual':result.get('result'),'passed':result.get('result')==expected,'failed_assertions':result.get('failed_assertions'),'blocking_assertions':result.get('blocking_assertions'),'checks':result.get('evidence',{}).get('checks')}
criterion={'criterion_code':'AC-1','given':'record belongs to another tenant','when':'unauthorized user requests it','then':'access is denied','source_ref':'SRC-1'}
criterion_test={'test_code':'TEST-AC-1','family':'FUNCTIONAL','criterion_ref':'AC-1','rule_ref':None,'preconditions':['record exists'],'steps':['request record from another tenant'],'expected_result':'access is denied and no data is returned','negative':True,'critical':True,'automatable':True,'actor_profile':'UNAUTHORIZED_USER','tenant_scope':'CROSS_TENANT','evidence_path':'evidence/tests/TEST-AC-1.json'}
criterion_fixture={'actor':'UNAUTHORIZED_USER','tenant':'COMPANY-A','initial_state':{'record_tenant':'COMPANY-B'},'exact_inputs':{'record_id':'REC-B-002'},'steps':['request REC-B-002 through the authorized application path'],'expected_result':'access is denied and no data is returned','evidence_path':'evidence/tests/TEST-AC-1.json'}
base={'story_pack':{'core':{'acceptance_criteria':[criterion]},'tests':[copy.deepcopy(TEST),criterion_test]},'critical_rules':[{'rule_code':'SEC-CROSS-TENANT-DENY','family':'TENANT','tenant_rule':True}],'fixtures':{'TEST-TENANT-001':copy.deepcopy(FIXTURE),'TEST-AC-1':criterion_fixture}}
cases=[case('documented_pair_integrated',copy.deepcopy(base),'PASS_WITH_EVIDENCE')]
broken=copy.deepcopy(base);broken['fixtures']['TEST-TENANT-001']['steps']=['TODO'];broken['fixtures']['TEST-TENANT-001']['expected_result']='example';cases.append(case('generic_fixture',broken,'RETURN_TO_WORKER'))
broken=copy.deepcopy(base);broken['story_pack']['tests']=[];broken['fixtures']={};cases.append(case('vacuous_suite',broken,'RETURN_TO_WORKER'))
cases.append(case('missing_metadata',copy.deepcopy(base),'BLOCKED',False))
process=subprocess.run([sys.executable,'scripts/validate_test_coverage.py','--self-test'],cwd=SKILL,env=env(),text=True,capture_output=True);data=json.loads(process.stdout.strip().splitlines()[-1]);cases.append({'case':'self_test','expected':'positive_pass_and_negative_rejected','actual':data,'passed':data.get('positive_pass') is True and data.get('negative_rejected') is True})
out={'artifact':'A41','passed':all(x['passed'] for x in cases),'cases':cases};print(json.dumps(out,ensure_ascii=False,sort_keys=True));raise SystemExit(0 if out['passed'] else 1)
