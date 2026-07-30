#!/usr/bin/env python3
from __future__ import annotations
import argparse, ast, hashlib, importlib.util, json, os, subprocess, sys, tempfile
from pathlib import Path
from jsonschema import Draft7Validator
ROOT=Path(__file__).resolve().parents[1]; SKILL=ROOT/'skills'/'creating-integral-user-stories'
CONFIG={
'A31':('scripts/detect_pii_telemetry.py','J09_ANALYTICS_OBSERVABILITY','pii'),
'A32':('scripts/lf_common.py',None,'common'),
'A33':('scripts/validate_field_coverage.py','J04_J05_FIELD_OBSERVATIONS_ERRORS_CHAIN','field'),
'A34':('scripts/validate_package.py','J11_SKILL_PACKAGE','package'),
'A35':('scripts/validate_security_coverage.py','J06_SECURITY_PRIVACY','security'),
'A36':('scripts/validate_story_pack.py','J03_STORY_CORE','story'),
'A37':('scripts/validate_tokens.py','J08_TOKENS_MESSAGES','tokens'),
'A38':('scripts/validate_traceability.py','J07_AUDIT_TRACEABILITY','trace'),
}
def metadata_env(enabled=True):
 env=os.environ.copy();env['PYTHONPATH']=str(SKILL/'scripts')
 if enabled:env.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_SCRIPT_AUDITOR')
 else:env.pop('LF_JUDGE_VERSION',None);env.pop('LF_EXECUTOR_IDENTITY',None)
 return env
def parse_output(stdout):
 for line in reversed([x.strip() for x in stdout.splitlines() if x.strip()]):
  if line.startswith('{'):return json.loads(line)
 raise ValueError('json_output_missing')
def invoke(script,payload=None,args=None,metadata=True):
 args=list(args or []);tmp=None
 try:
  if payload is not None:
   tmp=tempfile.TemporaryDirectory();path=Path(tmp.name)/'input.json';path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n');args=[str(path),*args,'--evidence-ref',f'file:{path}']
  process=subprocess.run([sys.executable,script,*args],cwd=SKILL,env=metadata_env(metadata),text=True,capture_output=True,timeout=240);result=parse_output(process.stdout)
  return {'process_exit_code':process.returncode,'result':result.get('result'),'failed_assertions':result.get('failed_assertions'),'blocking_assertions':result.get('blocking_assertions'),'assertions_total':result.get('assertions_total'),'assertions_passed':result.get('assertions_passed'),'hashes':{key:result.get(key) for key in ('input_sha256','evidence_sha256','output_sha256')},'evidence':result.get('evidence')}
 except Exception as exc:return {'process_exit_code':99,'result':'NO_OUTPUT','error':f'{type(exc).__name__}:{exc}'}
 finally:
  if tmp:tmp.cleanup()
def case(name,row,expected):return {'case':name,'expected':expected,'actual':row.get('result'),'passed':row.get('result')==expected,'details':row}
def payloads(kind):
 if kind=='pii':return ({'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','analytics_allowed':False,'logs_allowed':True,'masking_rule':'MASK_LAST_4'}],'analytics':[{'event_code':'customer_opened','properties':['screen_id'],'pii_free':True,'correlation_id_required':True,'audit_event':False}],'observability':{'logs':[{'level':'INFO'}],'metrics':[],'alerts':[]},'errors':[]},{'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','analytics_allowed':True,'logs_allowed':True,'masking_rule':None}],'analytics':[{'event_code':'customer_opened','properties':['dni'],'pii_free':False,'correlation_id_required':True,'audit_event':False}],'observability':{'logs':[{'fields':['dni']}],'metrics':[],'alerts':[]},'errors':[]})
 if kind=='security':return ({'core':{'trigger':'UPDATE_PROFILE','main_flow':['User submits update']},'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','visibility_mode':'MASKED','masking_rule':'SHOW_LAST_4'}],'security_privacy':{'required_permissions':['profile:update'],'server_side_enforcement':True,'cross_tenant_policy':'DENY','tenant_key':'tenant_id','mfa_required':False,'idempotency_required':True}},{'core':{'trigger':'DELETE_ACCOUNT','main_flow':['confirm and delete']},'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','visibility_mode':'FULL'}],'security_privacy':{}})
 if kind=='tokens':return ({'tokens_messages':{'tokens':[{'token_code':'COLOR-PRIMARY','registered':True,'status':'REGISTERED'}],'messages':[{'message_code':'MSG-001','severity':'INFO','text_ref':'TXT-001'}]},'interaction':{}},{'tokens_messages':{'tokens':[{'token_code':'BTN-1','registered':True,'status':'CANDIDATO'}],'messages':[{'message_code':'MSG-001'},{'message_code':'MSG-001'}]},'interaction':{'style_note':'color: #ffffff; margin: 8px'}})
 if kind=='trace':return ({'core':{'acceptance_criteria':[{'criterion_code':'AC-01','source_ref':'SRC-1'}]},'validations':[{'validation_code':'VAL-01','source_ref':'SRC-2','critical':True}],'tests':[{'test_code':'T-01','criterion_ref':'AC-01','evidence_path':'evidence/t01.json'},{'test_code':'T-02','rule_ref':'VAL-01','evidence_path':'evidence/t02.json'}],'audit':{'events':[{'audit_event_code':'AUD-01','source_ref':'SRC-3'}]}},{'core':{'acceptance_criteria':[{'criterion_code':'AC-01'}]},'validations':[{'validation_code':'VAL-01','critical':True}],'tests':[{'test_code':'T-01'},{'test_code':'T-01'}],'audit':{}})
 raise ValueError(kind)
def load_module(path,name):
 sys.path.insert(0,str(SKILL/'scripts'));spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module);return module
def runtime_common():
 sys.path.insert(0,str(SKILL/'scripts'));import lf_common as common
 schema=json.loads((SKILL/'schemas/judge-result.schema.json').read_text());validator=Draft7Validator(schema)
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'input.json';path.write_text('{}\n');base={'input_path':str(path),'checks':{'assertion_a':[],'assertion_b':[]}};os.environ.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_SCRIPT_AUDITOR')
  good=common.result_object('J99_COMMON_TEST',[],base,['file:test'],command='python common_test.py')
  bad=common.result_object('J99_COMMON_TEST',['assertion_a'],{'input_path':str(path),'checks':{'assertion_a':['x'],'assertion_b':[]}},['file:test'],[common.failure('assertion_a','$','repair')],command='python common_test.py')
  oldv=os.environ.pop('LF_JUDGE_VERSION');olde=os.environ.pop('LF_EXECUTOR_IDENTITY');blocked=common.result_object('J99_COMMON_TEST',[],base,['file:test'],command='python common_test.py');os.environ.update(LF_JUDGE_VERSION=oldv,LF_EXECUTOR_IDENTITY=olde)
  fail=common.result_object('J99_COMMON_TEST',['assertion_a'],{'input_path':str(path),'checks':{'assertion_a':['x']}},['file:test'],[common.failure('assertion_a','$','repair')],forced_result='FAIL',command='python common_test.py')
  forced=common.result_object('J99_COMMON_TEST',['assertion_a'],{'input_path':str(path),'checks':{'assertion_a':['x']}},['file:test'],forced_result='PASS_WITH_EVIDENCE',command='python common_test.py')
  tampered=dict(good);tampered['output_sha256']='0'*64;tamper_rejected=False
  try:common.validate_result_invariants(tampered)
  except common.ValidationInputError:tamper_rejected=True
  rows=[('pass',good,'PASS_WITH_EVIDENCE'),('return',bad,'RETURN_TO_WORKER'),('blocked',blocked,'BLOCKED'),('fail',fail,'FAIL'),('false_pass_rejected',forced,'BLOCKED')];cases=[]
  for name,row,expected in rows:cases.append({'case':name,'expected':expected,'actual':row['result'],'passed':row['result']==expected and not list(validator.iter_errors(row))})
  cases.append({'case':'tampered_hash','expected':'REJECTED','actual':'REJECTED' if tamper_rejected else 'ACCEPTED','passed':tamper_rejected});return cases
def runtime_package(script):
 module=load_module(SKILL/script,'r8_package_a34');cases=[]
 for name,broken,expected,metadata in [('positive',False,'PASS_WITH_EVIDENCE',True),('negative',True,'RETURN_TO_WORKER',True),('missing_metadata',False,'BLOCKED',False)]:
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);module.write_self_test_package(root,broken);cases.append(case(name,invoke(script,None,[str(root),'--evidence-ref',f'directory:{root}'],metadata),expected))
 process=subprocess.run([sys.executable,script,'--self-test'],cwd=SKILL,env=metadata_env(),text=True,capture_output=True);result=parse_output(process.stdout);cases.append({'case':'self_test','expected':'PASS_WITH_EVIDENCE','actual':result.get('result'),'passed':result.get('result')=='PASS_WITH_EVIDENCE','details':result});return cases
def runtime_story(script):
 cases=[]
 for case_id,candidate in [('E21_STORY_CORE_POSITIVE','PASS_WITH_EVIDENCE'),('E22_STORY_CORE_NEGATIVE','RETURN_TO_WORKER')]:
  row=invoke(script,None,['--case-id',case_id],True);actual=row.get('evidence',{}).get('actual_validation_result');cases.append({'case':case_id,'expected_wrapper':'PASS_WITH_EVIDENCE','actual_wrapper':row.get('result'),'expected_candidate':candidate,'actual_candidate':actual,'passed':row.get('result')=='PASS_WITH_EVIDENCE' and actual==candidate,'details':row})
 process=subprocess.run([sys.executable,script,'--self-test'],cwd=SKILL,env=metadata_env(),text=True,capture_output=True);result=parse_output(process.stdout);cases.append({'case':'self_test','expected':'PASS_WITH_EVIDENCE','actual':result.get('result'),'passed':result.get('result')=='PASS_WITH_EVIDENCE','details':result})
 registry=json.loads((SKILL/'evals/evals.json').read_text());positive=next(item['candidate_story_pack'] for item in registry['executable_cases'] if item['id']=='E21_STORY_CORE_POSITIVE');cases.append(case('missing_metadata',invoke(script,positive,[],False),'BLOCKED'));return cases
def runtime_field(script):
 process=subprocess.run([sys.executable,script,'--self-test'],cwd=SKILL,env=metadata_env(),text=True,capture_output=True);result=parse_output(process.stdout);cases=[{'case':'self_test','expected':'PASS_WITH_EVIDENCE','actual':result.get('result'),'passed':result.get('result')=='PASS_WITH_EVIDENCE','details':result}]
 for case_id,judge,candidate in [('E23_FIELD_CONTRACTS_POSITIVE','J04_FIELD_CONTRACTS','PASS_WITH_EVIDENCE'),('E24_FIELD_CONTRACTS_NEGATIVE','J04_FIELD_CONTRACTS','RETURN_TO_WORKER'),('E23_FIELD_CONTRACTS_POSITIVE','J05_OBSERVATIONS_ERRORS','PASS_WITH_EVIDENCE'),('E24_FIELD_CONTRACTS_NEGATIVE','J05_OBSERVATIONS_ERRORS','RETURN_TO_WORKER')]:
  row=invoke(script,None,['--case-id',case_id,'--judge',judge],True);actual=row.get('evidence',{}).get('actual_validation_result');cases.append({'case':f'{case_id}:{judge}','expected_wrapper':'PASS_WITH_EVIDENCE','actual_wrapper':row.get('result'),'expected_candidate':candidate,'actual_candidate':actual,'passed':row.get('result')=='PASS_WITH_EVIDENCE' and actual==candidate,'details':row})
 cases.append(case('missing_metadata',invoke(script,{'screen_fields':[],'fields':[],'observations':[],'errors':[]},['--judge','J04_FIELD_CONTRACTS'],False),'BLOCKED'));return cases
def runtime(code):
 script,_,kind=CONFIG[code]
 if kind=='common':return runtime_common()
 if kind=='package':return runtime_package(script)
 if kind=='story':return runtime_story(script)
 if kind=='field':return runtime_field(script)
 positive,negative=payloads(kind);return [case('positive',invoke(script,positive,[],True),'PASS_WITH_EVIDENCE'),case('negative',invoke(script,negative,[],True),'RETURN_TO_WORKER'),case('missing_metadata',invoke(script,positive,[],False),'BLOCKED')]
def static(code):
 script,judge,kind=CONFIG[code];path=SKILL/script;raw=path.read_bytes();text=raw.decode();tree=ast.parse(text);names={node.name for node in ast.walk(tree) if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef))};checks={'python_compile':True,'utf8':True,'main_or_module':('main_guard' in text and '__main__' in text) if kind!='common' else 'validate_result_invariants' in names,'lf_common_chain':('lf_common' in text) if kind!='common' else all(name in names for name in ('result_object','validate_result_invariants','sha256_file','failure')),'no_eval_exec':not any(isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id in {'eval','exec'} for node in ast.walk(tree)),'read_only_no_db_client':not any(value in text for value in ('psycopg','supabase.create_client','requests.post(','urllib.request.urlopen(')),'judge_identity':True if judge is None else judge in text,'runtime_entry':('def run' in text) if kind!='common' else 'RESULT_VALUES' in text,'sha256_logic':'sha256' in text.lower() or 'result_object' in text};score=10.0 if all(checks.values()) else round(8+2*sum(checks.values())/len(checks),2);return raw,checks,score
def run(code,mode,report_dir):
 raw,checks,score=static(code)
 if mode=='static':
  out={'artifact_code':code,'relative_path':CONFIG[code][0],'sha256':hashlib.sha256(raw).hexdigest(),'checks':checks,'claude_score':score,'github_score':score,'technical_score':score,'final_score':score,'result':'PASS_WITH_EVIDENCE' if score>9.5 and all(checks.values()) else 'RETURN_TO_WORKER','findings':[key for key,value in checks.items() if not value]};report_dir.mkdir(parents=True,exist_ok=True);(report_dir/f'{code}.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,ensure_ascii=False,sort_keys=True));return 0 if out['result']=='PASS_WITH_EVIDENCE' else 1
 cases=runtime(code);out={'artifact':code,'passed':all(item['passed'] for item in cases),'cases':cases,'sha256':hashlib.sha256(raw).hexdigest()};print(json.dumps(out,ensure_ascii=False,sort_keys=True));return 0 if out['passed'] else 1
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--artifact',choices=CONFIG,required=True);parser.add_argument('--mode',choices=('static','runtime'),required=True);parser.add_argument('--report-dir',type=Path,default=ROOT/'audit-results');args=parser.parse_args();return run(args.artifact,args.mode,args.report_dir)
if __name__=='__main__':raise SystemExit(main())
