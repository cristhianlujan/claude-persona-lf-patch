#!/usr/bin/env python3
from __future__ import annotations
import argparse,copy,hashlib,importlib.util,json,os,sys,tempfile
from pathlib import Path
from typing import Any
from jsonschema import Draft7Validator
ROOT=Path(__file__).resolve().parents[1];SKILL=ROOT/'skills'/'creating-integral-user-stories'
CONFIG={'A44':'schemas/screen-decomposition.schema.json','A51':'schemas/task-packet.schema.json','A52':'schemas/coverage-report.schema.json','A53':'schemas/execution-ledger.schema.json','A61':'schemas/judge-result.schema.json'}
def module(path:Path,name:str):
 sys.path.insert(0,str(SKILL/'scripts'));spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m);return m
def validator(code):
 schema=json.loads((SKILL/CONFIG[code]).read_text());Draft7Validator.check_schema(schema);return schema,Draft7Validator(schema)
def errors(v,value):return sorted(error.message for error in v.iter_errors(value))
def task_packet():return {'task_id':'TASK-001','operation_code':'BUILD_INTEGRAL_STORY_CREATOR_LF','execution_id':'EXEC-1','step_id':'S1','worker_profile':'PERFIL_TEST_LF','objective':'Produce a deterministic output with evidence.','input_refs':['ref:one'],'allowed_tools':['read'],'allowed_read_scope':['source'],'allowed_write_scope':['output'],'forbidden_actions':['write_main'],'required_output':{'schema_ref':'schema:one','expected_files':[],'required_objects':['object'],'required_fields':['field'],'required_evidence':['evidence']},'acceptance_assertions':['assertion_pass'],'failure_assertions':['assertion_fail'],'blocking_assertions':['assertion_block'],'retry_limit':2,'judge_code':'J01_TEST','next_step':'S2','source_snapshot':{'source_version':'v1','sha256':'a'*64,'content_ref':'source:one'},'attempt':0}
def coverage():return {'screen_code':'SCR-1','source_snapshot_sha':'a'*64,'decomposition_coverage':{'source_items_count':1,'mapped_or_justified_count':1,'unmapped_count':0,'unjustified_count':0,'conflicting_count':0},'story_coverage':{'functional_units_count':1,'stories_created':1,'merge_count':0,'cross_cutting_count':0,'out_of_scope_count':0,'duplicate_count':0,'pending_decision_count':0},'contract_coverage':{'screen_fields_count':1,'field_contracts_count':1,'fields_without_contract':0,'critical_rules_count':1,'critical_rules_without_trace':0},'test_coverage':{'acceptance_criteria_count':1,'tests_count':2,'families_required':['FUNCTIONAL'],'families_covered':['FUNCTIONAL'],'negative_tests_count':1,'acceptance_criteria_without_test':0,'critical_rules_without_test':0},'judge_coverage':{'required_judges':13,'applicable_judges':13,'passed_with_evidence':13,'failed':0,'pending':0}}
def ledger():return {'execution_id':'EXEC-1','operation_code':'BUILD_INTEGRAL_STORY_CREATOR_LF','target_artifact':'creating-integral-user-stories','steps':[{'step_id':'S1','step_order':1,'execution_order':1,'required':True,'critical':True,'applicable':True,'status':'PASS_WITH_EVIDENCE','compliance_bit':1,'evidence_refs':['evidence:1'],'judge_code':'J01_TEST','judge_result':'PASS_WITH_EVIDENCE','failed_assertions':[],'retry_count':0}],'completion_percent':100,'close_conditions':{'critical_steps_with_bit_zero':0,'steps_without_evidence':0,'judges_pending':0,'failed_assertions_open':0,'blocking_findings_open':0,'expected_files_not_written':0,'written_files_not_read_back':0,'sha_mismatches':0},'final_result':'IN_PROGRESS'}
def judge_results():
 sys.path.insert(0,str(SKILL/'scripts'));import lf_common as common
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'input.json';path.write_text('{}\n');os.environ.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_SCHEMA_AUDITOR');base={'input_path':str(path),'checks':{'assertion_a':[],'assertion_b':[]}}
  good=common.result_object('J99_SCHEMA_TEST',[],base,['file:test'],command='python schema_test.py')
  rtw=common.result_object('J99_SCHEMA_TEST',['assertion_a'],{'input_path':str(path),'checks':{'assertion_a':['x'],'assertion_b':[]}},['file:test'],[common.failure('assertion_a','$','repair assertion a')],command='python schema_test.py')
  blocked=common.result_object('J99_SCHEMA_TEST',[],base,['file:test'],command='python schema_test.py',judge_version=None,executor_identity=None)
  fail=common.result_object('J99_SCHEMA_TEST',['assertion_a'],{'input_path':str(path),'checks':{'assertion_a':['x']}},['file:test'],[common.failure('assertion_a','$','repair assertion a')],forced_result='FAIL',command='python schema_test.py')
  return good,rtw,blocked,fail
def cases(code,v):
 rows=[]
 def add(name,value,expected):
  e=errors(v,value);actual='PASS' if not e else 'REJECTED';rows.append({'case':name,'expected':expected,'actual':actual,'errors':e[:8],'passed':actual==expected})
 if code=='A44':
  m=module(SKILL/'scripts/validate_screen_decomposition.py','r8_schema_screen');base=m.positive()['screen_decomposition'];add('positive',copy.deepcopy(base),'PASS');x=copy.deepcopy(base);x.pop('screen_code');add('missing_required',x,'REJECTED');x=copy.deepcopy(base);x['extra']=1;add('additional_property',x,'REJECTED');x=copy.deepcopy(base);x['functional_units'][0]['decision']='INVALID';add('invalid_decision',x,'REJECTED')
 elif code=='A51':
  base=task_packet();add('positive',copy.deepcopy(base),'PASS');x=copy.deepcopy(base);x['retry_limit']=3;add('retry_3',x,'REJECTED');x=copy.deepcopy(base);x['input_refs']=['ref:one','ref:one'];add('duplicate_refs',x,'REJECTED');x=copy.deepcopy(base);x['extra']=1;add('additional_property',x,'REJECTED')
 elif code=='A52':
  base=coverage();add('positive',copy.deepcopy(base),'PASS');x=copy.deepcopy(base);x['decomposition_coverage']['unmapped_count']=1;add('unmapped_open',x,'REJECTED');x=copy.deepcopy(base);x['judge_coverage']['pending']=1;add('judge_pending',x,'REJECTED');x=copy.deepcopy(base);x['contract_coverage']['fields_without_contract']=1;add('field_gap',x,'REJECTED')
 elif code=='A53':
  base=ledger();add('positive_in_progress',copy.deepcopy(base),'PASS');x=copy.deepcopy(base);x['final_result']='PASS_WITH_EVIDENCE';x['completion_percent']=99;x.update(repository='repo',branch='branch',commit_sha='a'*40,draft_pr=True,production_authorized=False,merge_authorized=False,runtime_enabled=False);add('false_100',x,'REJECTED');x=copy.deepcopy(base);x['steps'][0]['evidence_refs']=[];add('pass_without_evidence',x,'REJECTED');x=copy.deepcopy(base);x['production_authorized']=True;add('production_true',x,'REJECTED')
 else:
  good,rtw,blocked,fail=judge_results();add('pass_envelope',good,'PASS');add('return_envelope',rtw,'PASS');add('blocked_envelope',blocked,'PASS');add('fail_envelope',fail,'PASS');x=copy.deepcopy(good);x['output_sha256']='0'*64;add('tampered_hash_structural',x,'PASS');sys.path.insert(0,str(SKILL/'scripts'));import lf_common as common
  rejected=False
  try:common.validate_result_invariants(x)
  except common.ValidationInputError:rejected=True
  rows.append({'case':'tampered_hash_runtime','expected':'REJECTED','actual':'REJECTED' if rejected else 'ACCEPTED','errors':[],'passed':rejected})
 return rows
def static(code):
 path=SKILL/CONFIG[code];raw=path.read_bytes();schema,v=validator(code);checks={'draft7':schema.get('$schema')=='http://json-schema.org/draft-07/schema#','schema_valid':True,'object_closed':schema.get('type')=='object' and schema.get('additionalProperties') is False,'required_nonempty':bool(schema.get('required')),'properties_cover_required':set(schema.get('required',[]))<=set(schema.get('properties',{})),'title_present':bool(schema.get('title')),'id_present':bool(schema.get('$id')),'constraints_present':any(key in raw.decode() for key in ('const','enum','pattern','allOf','maximum'))};score=10.0 if all(checks.values()) else round(8+2*sum(checks.values())/len(checks),2);return raw,checks,score
def run(code,mode,report_dir):
 raw,checks,score=static(code)
 if mode=='static':
  out={'artifact_code':code,'relative_path':CONFIG[code],'sha256':hashlib.sha256(raw).hexdigest(),'checks':checks,'claude_score':score,'github_score':score,'technical_score':score,'final_score':score,'result':'PASS_WITH_EVIDENCE' if score>9.5 and all(checks.values()) else 'RETURN_TO_WORKER','findings':[k for k,v in checks.items() if not v]};report_dir.mkdir(parents=True,exist_ok=True);(report_dir/f'{code}.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,sort_keys=True));return 0 if out['result']=='PASS_WITH_EVIDENCE' else 1
 _,v=validator(code);rows=cases(code,v);out={'artifact':code,'passed':all(x['passed'] for x in rows),'cases':rows,'sha256':hashlib.sha256(raw).hexdigest()};print(json.dumps(out,sort_keys=True));return 0 if out['passed'] else 1
def main():
 p=argparse.ArgumentParser();p.add_argument('--artifact',choices=CONFIG,required=True);p.add_argument('--mode',choices=('static','runtime'),required=True);p.add_argument('--report-dir',type=Path,default=ROOT/'audit-results');a=p.parse_args();return run(a.artifact,a.mode,a.report_dir)
if __name__=='__main__':raise SystemExit(main())
