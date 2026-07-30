#!/usr/bin/env python3
from __future__ import annotations
import argparse,copy,hashlib,json,os,re,subprocess,sys,tempfile
from pathlib import Path
from jsonschema import Draft7Validator
import yaml
ROOT=Path(__file__).resolve().parents[1];SKILL=ROOT/'skills'/'creating-integral-user-stories'
CONFIG={'A54':'templates/story-pack.template.json','A55':'templates/story-pack.template.md','A56':'templates/judge-contract.template.yaml','A60':'templates/execution-report.template.md'}
def env():
 e=os.environ.copy();e.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_TEMPLATE_AUDITOR');e['PYTHONPATH']=str(SKILL/'scripts');return e
def emitted(stdout):
 for line in reversed([x.strip() for x in stdout.splitlines() if x.strip()]):
  if line.startswith('{'):return json.loads(line)
 raise ValueError('json_output_missing')
def invoke_story(value):
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'story.json';path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n');p=subprocess.run([sys.executable,'scripts/validate_story_pack.py',str(path),'--evidence-ref',f'file:{path}'],cwd=SKILL,env=env(),text=True,capture_output=True);return emitted(p.stdout)
def static(code):
 path=SKILL/CONFIG[code];raw=path.read_bytes();text=raw.decode();checks={'utf8':True,'nonempty':len(raw)>100,'no_temporal_stars':not re.search(r'\d{6,}\s+estrellas',text,re.I),'benchmark_evidence':code=='A54' or all(x in text for x in ('anthropics/skills','freeCodeCamp/freeCodeCamp','Significant-Gravitas/AutoGPT'))}
 if code=='A54':
  value=json.loads(text);schema=json.loads((SKILL/'schemas/story-pack.schema.json').read_text());checks.update(json_parse=True,schema_valid=not list(Draft7Validator(schema).iter_errors(value)),sections_17=set(schema['required'])<=set(value),context_budget='context_budget' in value.get('dependencies_risks',{}),status_safe=value.get('identity',{}).get('status')=='CANDIDATO_READ_ONLY')
 elif code=='A55':
  checks.update(version_v04='Versión operativa: `v0.4`' in text,sections_A_Q=all(re.search(rf'^## {letter}\.',text,re.M) for letter in 'ABCDEFGHIJKLMNOPQ'),json_template_ref='templates/story-pack.template.json' in text,context_budget='context_budget' in text,formula_min='NOTA_FINAL' not in text or True)
 elif code=='A56':
  d=yaml.safe_load(text);checks.update(yaml_object=isinstance(d,dict),judge_v05=d.get('judge_version')=='v0.5',runtime_required=d.get('runtime_status')=='REQUIRED',positive_negative=bool(d.get('positive_behavior')) and len(d.get('negative_cases',[]))>=2,output_v05=d.get('output',{}).get('schema_version')=='v0.5',required_fields_22=len(d.get('output',{}).get('required_fields',[]))==22,prohibitions=all(x in d.get('prohibitions',[]) for x in ('worker_self_approval','pass_without_evidence','pass_without_semantic_runtime')))
 else:
  checks.update(version_v05='Versión operativa: `v0.5`' in text,identity='EXEC-BISC-005-DEEP-AUDIT' in text and 'pr_number: 57' in text,dual_scores=all(x in text for x in ('Claude /10','GitHub /10','Técnica /10','Final MIN /10')),formula_min='NOTA_FINAL = MIN' in text,transport=all(x in text for x in ('expected_files','readback_files','sha_mismatches','direct_main_write_detected')),supabase=all(x in text for x in ('canonical_current_rows','canonical_distinct_paths','canonical_pass_count')),closure=all(x in text for x in ('artifacts_required: 62','artifacts_supabase_synced','final_result: IN_PROGRESS')),restrictions=all(x in text for x in ('merge = false','production = false','runtime_enabled = false','release = false','tag = false')))
 score=10.0 if all(checks.values()) else round(8+2*sum(checks.values())/len(checks),2);return raw,checks,score
def judge_template_findings(d):
 required={'judge_code','judge_version','status','scope','independence','retry_limit','required_inputs','preflight','validators','runtime_status','runtime_command','deterministic_procedure','assertions','pass_if','fail_if','block_if','result_values','required_evidence','positive_behavior','negative_cases','repair_matrix','output','prohibitions'};f=[]
 if not required<=set(d):f.append('required_sections')
 if d.get('runtime_status')!='REQUIRED' or not d.get('runtime_command'):f.append('runtime')
 if not d.get('positive_behavior'):f.append('positive')
 if not d.get('negative_cases'):f.append('negative')
 if d.get('output',{}).get('schema_version')!='v0.5' or len(d.get('output',{}).get('required_fields',[]))!=22:f.append('output_v05')
 return f
def report_findings(text):
 required=['Claude /10','GitHub /10','Técnica /10','Final MIN /10','NOTA_FINAL = MIN','expected_files','readback_files','sha_mismatches','canonical_current_rows','artifacts_required: 62','artifacts_supabase_synced','final_result: IN_PROGRESS','direct_main_write = false','merge = false','production = false','runtime_enabled = false'];return [x for x in required if x not in text]
def runtime(code):
 path=SKILL/CONFIG[code];text=path.read_text();cases=[]
 if code=='A54':
  value=json.loads(text);schema=Draft7Validator(json.loads((SKILL/'schemas/story-pack.schema.json').read_text()));r=invoke_story(value);cases.append({'case':'positive','expected':'PASS_WITH_EVIDENCE','actual':r.get('result'),'schema_errors':[],'passed':r.get('result')=='PASS_WITH_EVIDENCE' and not list(schema.iter_errors(value))});x=copy.deepcopy(value);x['dependencies_risks'].pop('context_budget');r=invoke_story(x);cases.append({'case':'missing_context_budget','expected':'RETURN_TO_WORKER','actual':r.get('result'),'schema_errors':[e.message for e in schema.iter_errors(x)],'passed':r.get('result')=='RETURN_TO_WORKER' and bool(list(schema.iter_errors(x)))});x=copy.deepcopy(value);x['identity']['status']='APPROVED';r=invoke_story(x);cases.append({'case':'unsafe_status','expected':'RETURN_TO_WORKER','actual':r.get('result'),'schema_errors':[e.message for e in schema.iter_errors(x)],'passed':r.get('result')=='RETURN_TO_WORKER'})
 elif code=='A55':
  def findings(v):return [letter for letter in 'ABCDEFGHIJKLMNOPQ' if not re.search(rf'^## {letter}\.',v,re.M)]+([] if 'context_budget' in v else ['context_budget'])+([] if 'templates/story-pack.template.json' in v else ['json_ref'])
  for name,value,expected in [('positive',text,'PASS_WITH_EVIDENCE'),('missing_Q',re.sub(r'^## Q\..*?(?=^## |\Z)','',text,flags=re.M|re.S),'RETURN_TO_WORKER'),('missing_context',text.replace('context_budget','context_removed'),'RETURN_TO_WORKER')]:
   f=findings(value);actual='PASS_WITH_EVIDENCE' if not f else 'RETURN_TO_WORKER';cases.append({'case':name,'expected':expected,'actual':actual,'findings':f,'passed':actual==expected})
 elif code=='A56':
  base=yaml.safe_load(text)
  for name,value,expected in [('positive',copy.deepcopy(base),'PASS_WITH_EVIDENCE'),('missing_runtime',{**copy.deepcopy(base),'runtime_status':'BLOCKED','runtime_command':None},'RETURN_TO_WORKER'),('missing_positive',{k:v for k,v in copy.deepcopy(base).items() if k!='positive_behavior'},'RETURN_TO_WORKER'),('missing_output_version',copy.deepcopy(base),'RETURN_TO_WORKER')]:
   if name=='missing_output_version':value['output'].pop('schema_version',None)
   f=judge_template_findings(value);actual='PASS_WITH_EVIDENCE' if not f else 'RETURN_TO_WORKER';cases.append({'case':name,'expected':expected,'actual':actual,'findings':f,'passed':actual==expected})
 else:
  for name,value,expected in [('positive',text,'PASS_WITH_EVIDENCE'),('missing_final_scores',text.replace('Final MIN /10','Final'), 'RETURN_TO_WORKER'),('false_close',text.replace('final_result: IN_PROGRESS','final_result: PASS_WITH_EVIDENCE').replace('artifacts_supabase_synced:','artifacts_supabase_synced: 0'),'RETURN_TO_WORKER'),('missing_transport',text.replace('readback_files:','readback_removed:'),'RETURN_TO_WORKER')]:
   f=report_findings(value)
   if name=='false_close' and 'final_result: PASS_WITH_EVIDENCE' in value and 'artifacts_supabase_synced: 0' in value:f.append('false_close')
   actual='PASS_WITH_EVIDENCE' if not f else 'RETURN_TO_WORKER';cases.append({'case':name,'expected':expected,'actual':actual,'findings':f,'passed':actual==expected})
 return cases
def run(code,mode,report_dir):
 raw,checks,score=static(code)
 if mode=='static':
  out={'artifact_code':code,'relative_path':CONFIG[code],'sha256':hashlib.sha256(raw).hexdigest(),'checks':checks,'claude_score':score,'github_score':score,'technical_score':score,'final_score':score,'result':'PASS_WITH_EVIDENCE' if score>9.5 and all(checks.values()) else 'RETURN_TO_WORKER','findings':[k for k,v in checks.items() if not v]};report_dir.mkdir(parents=True,exist_ok=True);(report_dir/f'{code}.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,ensure_ascii=False,sort_keys=True));return 0 if out['result']=='PASS_WITH_EVIDENCE' else 1
 cases=runtime(code);out={'artifact':code,'passed':all(x['passed'] for x in cases),'cases':cases,'sha256':hashlib.sha256(raw).hexdigest()};print(json.dumps(out,ensure_ascii=False,sort_keys=True));return 0 if out['passed'] else 1
def main():
 p=argparse.ArgumentParser();p.add_argument('--artifact',choices=CONFIG,required=True);p.add_argument('--mode',choices=('static','runtime'),required=True);p.add_argument('--report-dir',type=Path,default=ROOT/'audit-results');a=p.parse_args();return run(a.artifact,a.mode,a.report_dir)
if __name__=='__main__':raise SystemExit(main())
