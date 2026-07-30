#!/usr/bin/env python3
from __future__ import annotations
import argparse, copy, hashlib, json, os, re, subprocess, sys, tempfile
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[1]
SKILL=ROOT/'skills'/'creating-integral-user-stories'
CONFIG={
'A27':{'path':'references/field-contract.md','judge':'J04_FIELD_CONTRACTS','validator':'scripts/validate_field_coverage.py','judge_file':'judges/field-contracts.yaml','kind':'field'},
'A28':{'path':'references/observations-errors-contract.md','judge':'J05_OBSERVATIONS_ERRORS','validator':'scripts/validate_field_coverage.py','judge_file':'judges/observations-errors.yaml','kind':'error'},
'A29':{'path':'references/story-pack-contract.md','judge':'J03_STORY_CORE','validator':'scripts/validate_story_pack.py','judge_file':'judges/story-core.yaml','kind':'story'},
}
FENCE=re.compile(r'```json\n(.*?)\n```',re.S)
HEAD=re.compile(r'^##\s+(?:\d+\.\s+)?(.+?)\s*$',re.M)
V05={'schema_version','judge_code','judge_version','executor_identity','command','started_at','completed_at','exit_code','result','compliance_bit','assertions_total','assertions_passed','failed_assertions','blocking_assertions','repairs','repair_instructions','evidence_refs','evidence','evidence_sha256','input_sha256','output_sha256','retry_count'}

def heading_before(text,pos):
    heading=''
    for match in HEAD.finditer(text,0,pos): heading=match.group(1).strip()
    return heading

def examples(text):
    out={}
    for match in FENCE.finditer(text):
        heading=heading_before(text,match.start()).lower()
        if 'ejemplo positivo' in heading or 'ejemplo negativo' in heading: out[heading]=json.loads(match.group(1))
    return out

def assertion_ids(judge):
    rows=judge.get('assertions',[]); out=[]
    for item in rows:
        if isinstance(item,str): out.append(item)
        elif isinstance(item,dict): out.append(item.get('assertion_id'))
    return [item for item in out if item]

def static_checks(code,text):
    config=CONFIG[code]; judge=yaml.safe_load((SKILL/config['judge_file']).read_text()); ids=assertion_ids(judge); parsed=examples(text)
    checks={
      'objective':'## Objetivo' in text or '## 1. Objetivo' in text,
      'inputs':'Entradas obligatorias' in text,
      'preflight':'Preflight' in text,
      'procedure':'Procedimiento determinista' in text,
      'positive_example':any('positivo' in key for key in parsed),
      'negative_example':any('negativo' in key for key in parsed),
      'repair_stop':'stop conditions' in text.lower() and 'retry_limit = 2' in text,
      'judge_ref':config['judge'] in text and (SKILL/config['judge_file']).is_file(),
      'validator_ref':config['validator'] in text and (SKILL/config['validator']).is_file(),
      'assertions_aligned':all(item in text for item in ids),
      'no_temporal_star_counts':not re.search(r'~?\d{3,}[,.]?\d*\s+estrellas',text,re.I),
    }
    if code in ('A27','A28'):
        output=text[text.find('## Contrato de salida'):text.find('Condiciones de paso')]
        checks.update({'version_v05':'Versión operativa: `v0.5`' in text,'v05_output_complete':all(item in output for item in V05),'legacy_judged_at_absent':'judged_at' not in output})
    else:
        checks.update({'version_v04':'Story Pack v0.4' in text,'sections_A_Q':all(f'{letter} ' in text for letter in 'ABCDEFGHIJKLMNOPQ'),'context_budget_complete':all(item in text for item in ('measurement_method','canonical_story_tokens','active_context_tokens','direct_load_allowed','atomicity_review_result')),'schema_ref':'schemas/story-pack.schema.json' in text})
    return checks,parsed

def runtime_env(metadata=True):
    value=os.environ.copy()
    if metadata: value.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_REFERENCE_AUDITOR')
    else: value.pop('LF_JUDGE_VERSION',None); value.pop('LF_EXECUTOR_IDENTITY',None)
    return value

def emitted(stdout):
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith('{'): return json.loads(line)
    raise ValueError('json_output_missing')

def run_payload(config,payload,expected,metadata=True):
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/'input.json'; path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
        command=[sys.executable,config['validator'],str(path)]
        if config['validator'].endswith('validate_field_coverage.py'): command += ['--judge',config['judge']]
        command += ['--evidence-ref',f'file:{path}']
        process=subprocess.run(command,cwd=SKILL,env=runtime_env(metadata),text=True,capture_output=True)
        try:
            result=emitted(process.stdout); actual=result.get('result')
            return {'expected':expected,'actual':actual,'passed':actual==expected,'failed_assertions':result.get('failed_assertions'),'blocking_assertions':result.get('blocking_assertions'),'hashes':{key:result.get(key) for key in ('input_sha256','evidence_sha256','output_sha256')}}
        except Exception as exc:
            return {'expected':expected,'actual':'NO_OUTPUT','passed':False,'error':f'{type(exc).__name__}:{exc}','stdout':process.stdout[-2000:],'stderr':process.stderr[-1000:]}

def runtime(code,text):
    config=CONFIG[code]; parsed=examples(text); positive=next(value for key,value in parsed.items() if 'positivo' in key); negative=next(value for key,value in parsed.items() if 'negativo' in key)
    if config['kind']=='field':
        good={'screen_fields':[positive['field_code']],'fields':[positive],'observations':[],'errors':[]}; bad={'screen_fields':[negative['field_code']],'fields':[negative],'observations':[],'errors':[]}
        cases=[('positive',run_payload(config,good,'PASS_WITH_EVIDENCE')),('negative',run_payload(config,bad,'RETURN_TO_WORKER')),('missing_metadata',run_payload(config,good,'BLOCKED',False))]
    elif config['kind']=='error':
        good={'observations':[],'errors':[positive]}; bad={'observations':[],'errors':[negative]}
        cases=[('positive',run_payload(config,good,'PASS_WITH_EVIDENCE')),('negative',run_payload(config,bad,'RETURN_TO_WORKER')),('missing_metadata',run_payload(config,good,'BLOCKED',False))]
    else:
        registry=json.loads((SKILL/'evals/evals.json').read_text()); base=copy.deepcopy(next(item['candidate_story_pack'] for item in registry['executable_cases'] if item['id']=='E21_STORY_CORE_POSITIVE'))
        good=copy.deepcopy(base); good['dependencies_risks']=positive['dependencies_risks']; bad=copy.deepcopy(base); bad['dependencies_risks']=negative['dependencies_risks']
        cases=[('positive_fragment',run_payload(config,good,'PASS_WITH_EVIDENCE')),('negative_fragment',run_payload(config,bad,'RETURN_TO_WORKER'))]
        for case_id in ('E21_STORY_CORE_POSITIVE','E22_STORY_CORE_NEGATIVE'):
            command=[sys.executable,config['validator'],'--case-id',case_id]; process=subprocess.run(command,cwd=SKILL,env=runtime_env(),text=True,capture_output=True); result=emitted(process.stdout)
            cases.append((case_id,{'expected':'PASS_WITH_EVIDENCE','actual':result.get('result'),'passed':result.get('result')=='PASS_WITH_EVIDENCE','candidate_actual':result.get('evidence',{}).get('actual_validation_result')}))
        command=[sys.executable,config['validator'],'--self-test']; process=subprocess.run(command,cwd=SKILL,env=runtime_env(),text=True,capture_output=True); result=emitted(process.stdout)
        cases.append(('self_test',{'expected':'PASS_WITH_EVIDENCE','actual':result.get('result'),'passed':result.get('result')=='PASS_WITH_EVIDENCE'}))
    return [{'case':name,**value} for name,value in cases]

def run(code,mode,report_dir):
    config=CONFIG[code]; path=SKILL/config['path']; raw=path.read_bytes(); text=raw.decode(); checks,_=static_checks(code,text)
    if mode=='static':
        score=10.0 if all(checks.values()) else round(8+2*sum(checks.values())/len(checks),2)
        out={'artifact_code':code,'relative_path':config['path'],'sha256':hashlib.sha256(raw).hexdigest(),'checks':checks,'claude_score':score,'github_score':score,'technical_score':score,'final_score':score,'result':'PASS_WITH_EVIDENCE' if score>9.5 and all(checks.values()) else 'RETURN_TO_WORKER','findings':[key for key,value in checks.items() if not value]}
        report_dir.mkdir(parents=True,exist_ok=True); (report_dir/f'{code}.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); print(json.dumps(out,ensure_ascii=False,sort_keys=True)); return 0 if out['result']=='PASS_WITH_EVIDENCE' else 1
    cases=runtime(code,text); out={'artifact':code,'passed':all(item['passed'] for item in cases),'cases':cases,'sha256':hashlib.sha256(raw).hexdigest()}; print(json.dumps(out,ensure_ascii=False,sort_keys=True)); return 0 if out['passed'] else 1

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--artifact',choices=CONFIG,required=True); parser.add_argument('--mode',choices=('static','runtime'),required=True); parser.add_argument('--report-dir',type=Path,default=ROOT/'audit-results'); args=parser.parse_args(); return run(args.artifact,args.mode,args.report_dir)
if __name__=='__main__': raise SystemExit(main())
