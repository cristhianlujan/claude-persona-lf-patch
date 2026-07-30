#!/usr/bin/env python3
from __future__ import annotations
import argparse,copy,hashlib,importlib.util,json,os,re,subprocess,sys,tempfile
from pathlib import Path
from typing import Any
import yaml
ROOT=Path(__file__).resolve().parents[1];SKILL=ROOT/'skills'/'creating-integral-user-stories'
CONFIG={
'A43':{'path':'references/screen-decomposition-protocol.md','kind':'screen','judge':'judges/screen-decomposition.yaml','validator':'scripts/validate_screen_decomposition.py'},
'A45':{'path':'references/security-privacy-contract.md','kind':'security','judge':'judges/security-privacy.yaml','validator':'scripts/validate_security_coverage.py'},
'A46':{'path':'references/audit-traceability-contract.md','kind':'trace','judge':'judges/audit-traceability.yaml','validator':'scripts/validate_traceability.py'},
'A47':{'path':'references/tokens-messages-contract.md','kind':'tokens','judge':'judges/tokens-messages.yaml','validator':'scripts/validate_tokens.py'},
'A48':{'path':'references/analytics-observability-contract.md','kind':'analytics','judge':'judges/analytics-observability.yaml','validator':'scripts/detect_pii_telemetry.py'},
'A49':{'path':'references/accessibility-responsive-contract.md','kind':'accessibility'},
'A50':{'path':'references/supabase-source-map.md','kind':'supabase'},
}
JSON_FENCE=re.compile(r'```json\n(.*?)\n```',re.S)
TEXT_ASSERT=re.compile(r'## 7\. Assertions de paso\n\n```text\n(.*?)\n```',re.S)
CUSTOM_ASSERTIONS={
'A49':['primary_actions_inaccessible_small_breakpoint','interactive_controls_not_keyboard_operable','fields_without_label_association','errors_without_programmatic_announcement','color_only_state_indicators','reduced_motion_violations'],
'A50':['canonical_store_exists','event_store_exists','destination_registry_exists','current_artifact_count','current_distinct_paths','canonical_sha_mismatches','current_duplicate_paths','github_readback_mismatches','unexpected_written_files','direct_main_write_detected'],
}
def assertions_from_judge(path:Path)->list[str]:
 d=yaml.safe_load(path.read_text());out=[]
 for item in d.get('assertions',[]):out.append(item.get('assertion_id') if isinstance(item,dict) else item)
 return [x for x in out if x]
def assertions_from_contract(text:str)->list[str]:
 m=TEXT_ASSERT.search(text)
 if not m:return []
 return [line.split('=')[0].strip() for line in m.group(1).splitlines() if '=' in line]
def env(metadata=True):
 value=os.environ.copy();value['PYTHONPATH']=str(SKILL/'scripts')
 if metadata:value.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_CROSS_CONTRACT_AUDITOR')
 else:value.pop('LF_JUDGE_VERSION',None);value.pop('LF_EXECUTOR_IDENTITY',None)
 return value
def parse_emitted(stdout:str)->dict[str,Any]:
 for line in reversed([x.strip() for x in stdout.splitlines() if x.strip()]):
  if line.startswith('{'):return json.loads(line)
 raise ValueError('json_output_missing')
def invoke(validator:str,payload:dict[str,Any],expected:str,metadata=True)->dict[str,Any]:
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'input.json';path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
  process=subprocess.run([sys.executable,validator,str(path),'--evidence-ref',f'file:{path}'],cwd=SKILL,env=env(metadata),text=True,capture_output=True,timeout=240)
  try:
   result=parse_emitted(process.stdout);actual=result.get('result');return {'expected':expected,'actual':actual,'passed':actual==expected,'failed_assertions':result.get('failed_assertions'),'blocking_assertions':result.get('blocking_assertions'),'checks':result.get('evidence',{}).get('checks'),'hashes':{key:result.get(key) for key in ('input_sha256','evidence_sha256','output_sha256')}}
  except Exception as exc:return {'expected':expected,'actual':'NO_OUTPUT','passed':False,'error':f'{type(exc).__name__}:{exc}','stdout':process.stdout[-2000:],'stderr':process.stderr[-1000:]}
def load_module(path:Path,name:str):
 sys.path.insert(0,str(SKILL/'scripts'));spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module);return module
def static(code:str)->tuple[bytes,dict[str,bool],float]:
 cfg=CONFIG[code];path=SKILL/cfg['path'];raw=path.read_bytes();text=raw.decode();expected=CUSTOM_ASSERTIONS.get(code)
 if expected is None:expected=assertions_from_judge(SKILL/cfg['judge'])
 actual=assertions_from_contract(text);blocks=JSON_FENCE.findall(text)
 checks={'version_v05':'Versión operativa: `v0.5`' in text,'sections_1_12':all(f'## {n}.' in text for n in range(1,13)),'purpose_inputs_preflight':all(x in text for x in ('Propósito','Contrato de entrada','Preflight')),'procedure':'Procedimiento obligatorio' in text,'assertions_exact':actual==expected,'repair_retry':'retry_limit = 2' in text,'benchmarks':all(x in text for x in ('anthropics/skills','freeCodeCamp/freeCodeCamp','Significant-Gravitas/AutoGPT')),'no_temporal_stars':not re.search(r'\d{6,}\s+estrellas',text,re.I),'no_legacy_assertions':len(actual)==len(set(actual)) and bool(actual)}
 if 'validator' in cfg:checks['validator_exists']=(SKILL/cfg['validator']).is_file()
 if 'judge' in cfg:checks['judge_exists']=(SKILL/cfg['judge']).is_file()
 if code in ('A45','A46','A47','A48','A49'):checks['positive_negative_examples']=len(blocks)>=2
 if code=='A43':checks['positive_negative_control']='### Positivo' in text and '### Negativo' in text
 if code=='A50':checks['current_execution']=all(x in text for x in ('EXEC-BISC-005-DEEP-AUDIT','fix/deep-audit-a01-a62','draft_pr'))
 score=10.0 if all(checks.values()) else round(8+2*sum(checks.values())/len(checks),2);return raw,checks,score
def accessibility_findings(value:dict[str,Any])->list[str]:
 f=[]
 if 'SMALL' not in value.get('breakpoints_supported',[]):f.append('primary_actions_inaccessible_small_breakpoint')
 if value.get('primary_action_accessible_small') is not True:f.append('primary_actions_inaccessible_small_breakpoint')
 if value.get('keyboard_operable') is not True:f.append('interactive_controls_not_keyboard_operable')
 if value.get('fields_have_labels') is not True:f.append('fields_without_label_association')
 if not value.get('error_announcement'):f.append('errors_without_programmatic_announcement')
 if value.get('non_color_state_indicator') is not True:f.append('color_only_state_indicators')
 if value.get('reduced_motion_supported') is not True:f.append('reduced_motion_violations')
 return sorted(set(f))
def runtime(code:str)->list[dict[str,Any]]:
 cfg=CONFIG[code];text=(SKILL/cfg['path']).read_text();blocks=[json.loads(x) for x in JSON_FENCE.findall(text)]
 if code=='A43':
  module=load_module(SKILL/cfg['validator'],'r8_screen_contract');good=module.positive();bad=copy.deepcopy(good);bad['screen_decomposition']['coverage_items'][0]['mapping_status']='PENDING';bad['screen_decomposition']['functional_units'].append(copy.deepcopy(bad['screen_decomposition']['functional_units'][0]));cases=[{'case':'positive',**invoke(cfg['validator'],good,'PASS_WITH_EVIDENCE')},{'case':'negative',**invoke(cfg['validator'],bad,'RETURN_TO_WORKER')},{'case':'missing_metadata',**invoke(cfg['validator'],good,'BLOCKED',False)}];process=subprocess.run([sys.executable,cfg['validator'],'--self-test'],cwd=SKILL,env=env(),text=True,capture_output=True);d=json.loads(process.stdout.strip().splitlines()[-1]);cases.append({'case':'self_test','expected':'positive_pass_and_negative_rejected','actual':d,'passed':d.get('positive_pass') is True and d.get('negative_rejected') is True});return cases
 if code in ('A45','A46','A47','A48'):
  good,bad=blocks[0],blocks[1];return [{'case':'positive',**invoke(cfg['validator'],good,'PASS_WITH_EVIDENCE')},{'case':'negative',**invoke(cfg['validator'],bad,'RETURN_TO_WORKER')},{'case':'missing_metadata',**invoke(cfg['validator'],good,'BLOCKED',False)}]
 if code=='A49':
  good,bad=blocks[0],blocks[1];gf=accessibility_findings(good);bf=accessibility_findings(bad);return [{'case':'positive','expected':'PASS_WITH_EVIDENCE','actual':'PASS_WITH_EVIDENCE' if not gf else 'RETURN_TO_WORKER','findings':gf,'passed':not gf},{'case':'negative','expected':'RETURN_TO_WORKER','actual':'RETURN_TO_WORKER' if bf else 'PASS_WITH_EVIDENCE','findings':bf,'passed':len(bf)==6}]
 snapshot=json.loads((ROOT/'tools/supabase-snapshot-A50.json').read_text());base=snapshot['results']
 def evaluate(value):
  findings=[]
  if value.get('artifact_store')!='private.lf_skill_artifacts':findings.append('canonical_store_exists')
  if value.get('event_store')!='public.lf_eventos':findings.append('event_store_exists')
  if value.get('destination_registry')!='public.v_lf_artifact_destination_registry':findings.append('destination_registry_exists')
  if value.get('current_artifacts')!=62:findings.append('current_artifact_count')
  if value.get('distinct_paths')!=62:findings.append('current_distinct_paths')
  if value.get('sha_mismatches')!=0:findings.append('canonical_sha_mismatches')
  return findings
 cases=[]
 for name,value,expected in [('positive',copy.deepcopy(base),'PASS_WITH_EVIDENCE'),('missing_store',{**base,'artifact_store':None},'RETURN_TO_WORKER'),('count_61',{**base,'current_artifacts':61},'RETURN_TO_WORKER'),('sha_mismatch',{**base,'sha_mismatches':1},'RETURN_TO_WORKER')]:
  findings=evaluate(value);actual='PASS_WITH_EVIDENCE' if not findings else 'RETURN_TO_WORKER';cases.append({'case':name,'expected':expected,'actual':actual,'findings':findings,'passed':actual==expected})
 return cases
def run(code:str,mode:str,report_dir:Path)->int:
 raw,checks,score=static(code)
 if mode=='static':
  out={'artifact_code':code,'relative_path':CONFIG[code]['path'],'sha256':hashlib.sha256(raw).hexdigest(),'checks':checks,'claude_score':score,'github_score':score,'technical_score':score,'final_score':score,'result':'PASS_WITH_EVIDENCE' if score>9.5 and all(checks.values()) else 'RETURN_TO_WORKER','findings':[k for k,v in checks.items() if not v]};report_dir.mkdir(parents=True,exist_ok=True);(report_dir/f'{code}.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,ensure_ascii=False,sort_keys=True));return 0 if out['result']=='PASS_WITH_EVIDENCE' else 1
 cases=runtime(code);out={'artifact':code,'passed':all(x['passed'] for x in cases),'cases':cases,'sha256':hashlib.sha256(raw).hexdigest()};print(json.dumps(out,ensure_ascii=False,sort_keys=True));return 0 if out['passed'] else 1
def main():
 p=argparse.ArgumentParser();p.add_argument('--artifact',choices=CONFIG,required=True);p.add_argument('--mode',choices=('static','runtime'),required=True);p.add_argument('--report-dir',type=Path,default=ROOT/'audit-results');a=p.parse_args();return run(a.artifact,a.mode,a.report_dir)
if __name__=='__main__':raise SystemExit(main())
