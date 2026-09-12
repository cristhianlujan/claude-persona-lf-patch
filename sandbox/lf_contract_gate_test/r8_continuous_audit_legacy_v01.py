#!/usr/bin/env python3
"""Evidence-first A01-A62 audit. Read-only: never writes canonical state."""
from __future__ import annotations
import argparse, ast, hashlib, json, os, re, subprocess, sys, tempfile
from pathlib import Path
import yaml

EXEC="EXEC-BISC-007-A03-A62-CONTINUOUS"
PAIRS='''A01 agents/cross-cutting-enricher.md
A02 agents/field-contract-author.md
A03 agents/screen-decomposer.md
A04 agents/story-core-author.md
A05 agents/test-deriver.md
A06 evals/assertions.json
A07 evals/evals.json
A08 evals/fixtures/screen_insufficient_definition.json
A09 evals/fixtures/screen_sensitive_fields.json
A10 evals/fixtures/screen_simple_query.json
A11 evals/fixtures/screen_wizard_six_steps.json
A12 evals/trigger-evals.json
A13 judges/analytics-observability.yaml
A14 judges/audit-traceability.yaml
A15 judges/field-contracts.yaml
A16 judges/observations-errors.yaml
A17 judges/screen-decomposition.yaml
A18 judges/security-privacy.yaml
A19 judges/skill-package.yaml
A20 judges/story-core.yaml
A21 judges/test-coverage.yaml
A22 judges/tokens-messages.yaml
A23 manifest.yaml
A24 perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md
A25 perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md
A26 perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md
A27 references/field-contract.md
A28 references/observations-errors-contract.md
A29 references/story-pack-contract.md
A30 schemas/story-pack.schema.json
A31 scripts/detect_pii_telemetry.py
A32 scripts/lf_common.py
A33 scripts/validate_field_coverage.py
A34 scripts/validate_package.py
A35 scripts/validate_security_coverage.py
A36 scripts/validate_story_pack.py
A37 scripts/validate_tokens.py
A38 scripts/validate_traceability.py
A39 perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md
A40 perfiles/PERFIL_STORY_TEST_DERIVER_LF.md
A41 references/test-derivation-contract.md
A42 judges/source-integrity.yaml
A43 references/screen-decomposition-protocol.md
A44 schemas/screen-decomposition.schema.json
A45 references/security-privacy-contract.md
A46 references/audit-traceability-contract.md
A47 references/tokens-messages-contract.md
A48 references/analytics-observability-contract.md
A49 references/accessibility-responsive-contract.md
A50 references/supabase-source-map.md
A51 schemas/task-packet.schema.json
A52 schemas/coverage-report.schema.json
A53 schemas/execution-ledger.schema.json
A54 templates/story-pack.template.json
A55 templates/story-pack.template.md
A56 templates/judge-contract.template.yaml
A57 scripts/calculate_binary_completion.py
A58 judges/github-integrity.yaml
A59 judges/integration-close.yaml
A60 templates/execution-report.template.md
A61 schemas/judge-result.schema.json
A62 SKILL.md'''
MAP=dict(line.split(maxsplit=1) for line in PAIRS.splitlines())
CLOSED={'A01','A02'}
FBD=re.compile(r'(?im)^\s*(?:[-*]\s*)?(?:status|estado|state|result|resultado)\s*[:=]\s*`?(?:VALIDATED|PRODUCTION|PRODUCTION_READY|PRODUCTION_AUTHORIZED|APROBADO_FINAL|VIGENTE)\b')
PH=re.compile(r'\b(?:TODO|TBD|FIXME|LOREM_IPSUM|PENDIENTE_RELLENAR)\b')
REF=re.compile(r'(?<![\w/])(?:SKILL\.md|manifest\.yaml|(?:agents|perfiles|references|schemas|templates|scripts|judges|evals)/[\w./-]+\.(?:md|yaml|yml|json|py))')
LINK={
'j01':'A42 A50','j02':'A03 A11 A17 A26 A43 A44','j03':'A04 A06 A07 A08 A10 A20 A29 A30 A36 A39 A54 A55',
'j04':'A02 A09 A15 A25 A27 A33','j05':'A01 A09 A16 A24 A28 A33','j06':'A01 A18 A24 A35 A45',
'j07':'A01 A14 A24 A38 A46','j08':'A01 A22 A24 A37 A47','j09':'A01 A13 A24 A31 A48',
'j10':'A05 A06 A21 A40 A41','j11':'A12 A19 A23 A34 A49 A51 A52 A53 A56 A62','j12':'A58','j13':'A57 A59 A60',
'all':'A32 A61'}
CODE_KEYS={a:[k for k,v in LINK.items() if a in v.split()] or ['j11'] for a in MAP}

def dump(p,v): p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
def last_json(s):
 for x in reversed([x.strip() for x in s.splitlines() if x.strip()]):
  try:
   v=json.loads(x)
   if isinstance(v,dict): return v
  except json.JSONDecodeError: pass
 return None
def run(name,cmd,cwd,ok=(0,),env=None):
 e=os.environ.copy();e.update(env or {});p=subprocess.run(cmd,cwd=cwd,env=e,text=True,capture_output=True)
 return {'name':name,'command':cmd,'exit_code':p.returncode,'expected':list(ok),'passed':p.returncode in ok,'parsed':last_json(p.stdout),'stdout':p.stdout[-16000:],'stderr':p.stderr[-8000:]}
def pair(key,script,pos,neg,root,tmp,args=(),ver='v0.5'):
 out=[];env={'LF_JUDGE_VERSION':ver,'LF_EXECUTOR_IDENTITY':EXEC}
 for label,obj,ok in [('positive',pos,(0,)),('negative',neg,(1,))]:
  p=tmp/f'{key}_{label}.json';dump(p,obj);out.append(run(f'{key}_{label}',[sys.executable,str(script),str(p),*args],root,ok,env))
 return out

def suite(root,tmp):
 s=root/'scripts';env={'LF_JUDGE_VERSION':'v0.6','LF_EXECUTOR_IDENTITY':EXEC};R={}
 for k,f in [('j01','validate_source_integrity.py'),('j02','validate_screen_decomposition.py'),('j10','validate_test_coverage.py'),('j12','validate_github_integrity.py'),('j13','calculate_binary_completion.py')]:R[k]=[run(k+'_selftest',[sys.executable,str(s/f),'--self-test'],root,(0,),env)]
 reg=json.loads((root/'evals/evals.json').read_text());cases={x['id']:x for x in reg['executable_cases']}
 R['j03']=[run('j03_selftest',[sys.executable,str(s/'validate_story_pack.py'),'--self-test'],root,(0,),env)]+pair('j03',s/'validate_story_pack.py',cases['E21_STORY_CORE_POSITIVE']['candidate_story_pack'],cases['E22_STORY_CORE_NEGATIVE']['candidate_story_pack'],root,tmp,ver='v0.6')
 fp={'screen_fields':['customer_dni'],'fields':[{'field_code':'customer_dni','data_type':'STRING','required':True,'editable':False,'visibility_mode':'MASKED','pii_classification':'PII_DIRECT','analytics_allowed':False,'logs_allowed':False,'export_allowed':False,'masking_rule':'SHOW_LAST_4','validation_codes':['VAL-DNI-LENGTH'],'source_ref':'SRC#dni'}]};fn={'screen_fields':['email','phone'],'fields':[{'field_code':'email','data_type':'STRING','required':True,'editable':True,'pii_classification':'PII_DIRECT','analytics_allowed':True,'logs_allowed':True,'source_ref':'SRC#email'}]}
 R['j04']=[run('j04_selftest',[sys.executable,str(s/'validate_field_coverage.py'),'--self-test'],root,(0,),env)]+pair('j04',s/'validate_field_coverage.py',fp,fn,root,tmp,('--judge','J04_FIELD_CONTRACTS'),'v0.6')
 op={'observations':[{'observation_code':'OBS-1','user_action':'Corregir y reenviar','message_code':'MSG-1'}],'errors':[{'error_code':'ERR-1','blocking':True,'retryable':True,'retry_policy':{'max_attempts':2,'backoff':'EXPONENTIAL'},'correlation_id_required':True,'technical_detail_visibility':'INTERNAL_ONLY','user_message_code':'MSG-2'}]};on={'observations':[{'observation_code':'OBS-X','message_code':'MSG-X'}],'errors':[{'blocking':True,'retryable':True,'correlation_id_required':False,'technical_detail_visibility':'USER_VISIBLE'}]}
 R['j05']=pair('j05',s/'validate_field_coverage.py',op,on,root,tmp,('--judge','J05_OBSERVATIONS_ERRORS'),'v0.6')
 sp={'core':{'trigger':'UPDATE_PROFILE','main_flow':['save']},'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','visibility_mode':'MASKED','masking_rule':'LAST4'}],'security_privacy':{'required_permissions':['profile:update'],'server_side_enforcement':True,'cross_tenant_policy':'DENY','tenant_key':'tenant_id','mfa_required':False,'idempotency_required':True}};sn={'core':{'trigger':'DELETE_ACCOUNT','main_flow':['delete']},'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','visibility_mode':'FULL'}],'security_privacy':{}}
 R['j06']=pair('j06',s/'validate_security_coverage.py',sp,sn,root,tmp,('--judge-version','v0.5','--executor-identity',EXEC))
 tp={'core':{'acceptance_criteria':[{'criterion_code':'AC-1','source_ref':'SRC-1'}]},'validations':[{'validation_code':'VAL-1','source_ref':'SRC-2','critical':True}],'tests':[{'test_code':'T-1','criterion_ref':'AC-1','evidence_path':'e/t1.json'},{'test_code':'T-2','rule_ref':'VAL-1','evidence_path':'e/t2.json'}],'audit':{'events':[{'audit_event_code':'AUD-1','source_ref':'SRC-3'}]}};tn={'core':{'acceptance_criteria':[{'criterion_code':'AC-1'}]},'validations':[{'validation_code':'VAL-1','critical':True}],'tests':[{'test_code':'T-1'},{'test_code':'T-1'}],'audit':{}}
 R['j07']=pair('j07',s/'validate_traceability.py',tp,tn,root,tmp,('--judge-version','v0.5','--executor-identity',EXEC))
 kp={'tokens_messages':{'tokens':[{'token_code':'COLOR-1','registered':True,'status':'REGISTERED'}],'messages':[{'message_code':'MSG-1','severity':'INFO','text_ref':'TXT-1'}]},'interaction':{}};kn={'tokens_messages':{'tokens':[{'token_code':'BTN-1','registered':True,'status':'CANDIDATO'}],'messages':[{'message_code':'MSG-1'},{'message_code':'MSG-1'}]},'interaction':{'style':'#fff 8px'}}
 R['j08']=pair('j08',s/'validate_tokens.py',kp,kn,root,tmp,('--judge-version','v0.5','--executor-identity',EXEC))
 pp={'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','analytics_allowed':False,'logs_allowed':True,'masking_rule':'LAST4'}],'analytics':[{'event_code':'opened','properties':['screen_id'],'pii_free':True,'correlation_id_required':True,'audit_event':False}],'observability':{'logs':[],'metrics':[],'alerts':[]},'errors':[]};pn={'fields':[{'field_code':'dni','pii_classification':'PII_DIRECT','analytics_allowed':True,'logs_allowed':True}],'analytics':[{'event_code':'AUDIT-opened','properties':['dni'],'pii_free':False,'correlation_id_required':False,'audit_event':True}],'observability':{'logs':[{'fields':['dni']}],'metrics':[],'alerts':[]},'errors':[]}
 R['j09']=pair('j09',s/'detect_pii_telemetry.py',pp,pn,root,tmp,('--judge-version','v0.5','--executor-identity',EXEC))
 R['j11']=[run('j11_selftest',[sys.executable,str(s/'validate_package.py'),'--self-test'],root,(0,),env),run('j11_package',[sys.executable,str(s/'validate_package.py'),str(root),'--evidence-ref','continuous'],root,(0,),env)]
 R['all']=[x for k,v in R.items() if k!='all' for x in v];return R

def inventory(root):
 d=yaml.safe_load((root/'manifest.yaml').read_text());out={'SKILL.md','manifest.yaml'}
 for v in d['files'].values():
  if isinstance(v,list):out.update(map(str,v))
 return out
def static(rel,root,inv):
 p=root/rel;f=[]
 if not p.is_file():return {'passed':False,'findings':['missing']}
 b=p.read_bytes();t=b.decode('utf-8')
 if b.startswith(b'\xef\xbb\xbf'):f+=['bom']
 if b'\r\n' in b:f+=['crlf']
 if not b.endswith(b'\n'):f+=['final_newline']
 if rel not in inv:f+=['not_in_manifest']
 try:
  if p.suffix=='.json':json.loads(t)
  elif p.suffix in('.yaml','.yml'):yaml.safe_load(t)
  elif p.suffix=='.py':ast.parse(t)
 except Exception as e:f+=[f'parse:{type(e).__name__}']
 if rel not in {'manifest.yaml','scripts/validate_package.py'} and FBD.search(t):f+=['forbidden_status']
 refs=sorted(set(REF.findall(t))-{rel});broken=[x for x in refs if x not in inv]
 if broken:f+=['broken_refs:'+','.join(broken[:8])]
 if not rel.startswith('templates/') and rel!='scripts/validate_package.py':
  hits=sorted(set(PH.findall(re.sub(r'`[^`\n]+`','',t))))
  if hits:f+=['placeholders:'+','.join(hits)]
 if p.suffix=='.md' and (not re.search(r'(?m)^#\s+\S',t) or len(re.findall(r'(?m)^##\s+',t))<2):f+=['markdown_structure']
 if rel.startswith('judges/'):
  d=yaml.safe_load(t)
  for k in ('scope','required_inputs','preflight','pass_if','block_if','output','prohibitions'):
   if not d.get(k):f+=[f'judge_missing:{k}']
  if not(d.get('judge_code')or d.get('code')):f+=['judge_code']
  if not(d.get('version')or d.get('judge_version')):f+=['judge_version']
 if rel.startswith('schemas/'):
  d=json.loads(t)
  for k in('$schema','title','type'):
   if k not in d:f+=[f'schema_missing:{k}']
 return {'passed':not f,'findings':f,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'git_blob_sha1':subprocess.run(['git','hash-object',str(p)],text=True,capture_output=True).stdout.strip(),'broken_refs':broken}
def main():
 a=argparse.ArgumentParser();a.add_argument('root',type=Path);a.add_argument('--output',type=Path,required=True);a.add_argument('--commit-sha',default=os.getenv('GITHUB_SHA'));x=a.parse_args();root=x.root.resolve();out=x.output.resolve();out.mkdir(parents=True,exist_ok=True)
 assert set(MAP)=={f'A{i:02d}' for i in range(1,63)} and len(set(MAP.values()))==62
 inv=inventory(root)
 with tempfile.TemporaryDirectory() as z:R=suite(root,Path(z))
 dump(out/'runtime-suite.json',{k:v for k,v in R.items() if k!='all'})
 rows=[]
 for code,rel in MAP.items():
  st=static(rel,root,inv);keys=CODE_KEYS[code];rr=[q for k in keys for q in R[k]];ok=st['passed'] and all(q['passed'] for q in rr);decision=('REGRESSION_PASS' if code in CLOSED else 'PASS_CANDIDATE') if ok else 'RETURN_TO_WORKER'
  row={'audit_code':code,'relative_path':rel,'execution_id':EXEC,'commit_sha':x.commit_sha,'state_before':'PASS_WITH_EVIDENCE' if code in CLOSED else 'NOT_VALIDATED','decision':decision,'static':st,'runtime_keys':keys,'runtime':rr,'state_write_performed':False,'requires_post_merge_readback':code not in CLOSED};dump(out/'artifacts'/f'{code}.json',row);rows.append(row)
 pending=[r for r in rows if r['audit_code'] not in CLOSED];fail=[r for r in pending if r['decision']!='PASS_CANDIDATE'];reg=[r for r in rows if r['audit_code'] in CLOSED and r['decision']!='REGRESSION_PASS'];rf=[r for r in R['all'] if not r['passed']]
 summary={'execution_id':EXEC,'commit_sha':x.commit_sha,'canonical_map_count':62,'manifest_inventory_count':len(inv),'already_closed':2,'pending_total':60,'pass_candidates':60-len(fail),'return_to_worker':len(fail),'return_to_worker_codes':[r['audit_code'] for r in fail],'closed_regressions':len(reg),'closed_regression_codes':[r['audit_code'] for r in reg],'runtime_failures':len(rf),'runtime_failure_names':[r['name'] for r in rf],'canonical_state_written':False,'bulk_pass_forbidden':True,'all_passed':not fail and not reg and not rf};dump(out/'summary.json',summary);print(json.dumps(summary,sort_keys=True));return 0 if summary['all_passed'] else 1
if __name__=='__main__':raise SystemExit(main())
