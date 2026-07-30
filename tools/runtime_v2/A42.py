#!/usr/bin/env python3
from __future__ import annotations
import copy,hashlib,json,os,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];SKILL=ROOT/'skills'/'creating-integral-user-stories'
def env(metadata=True):
 e=os.environ.copy();e['PYTHONPATH']=str(SKILL/'scripts')
 if metadata:e.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_A42_AUDITOR')
 else:e.pop('LF_JUDGE_VERSION',None);e.pop('LF_EXECUTOR_IDENTITY',None)
 return e
def invoke(payload,metadata=True):
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'input.json';path.write_text(json.dumps(payload)+'\n');process=subprocess.run([sys.executable,'scripts/validate_source_integrity.py',str(path),'--evidence-ref',f'file:{path}'],cwd=SKILL,env=env(metadata),text=True,capture_output=True);return json.loads([x for x in process.stdout.splitlines() if x.strip().startswith('{')][-1])
def case(name,payload,expected,metadata=True):
 r=invoke(payload,metadata);return {'case':name,'expected':expected,'actual':r.get('result'),'passed':r.get('result')==expected,'failed_assertions':r.get('failed_assertions'),'blocking_assertions':r.get('blocking_assertions'),'checks':r.get('evidence',{}).get('checks')}
content='canonical source';sha=hashlib.sha256(content.encode()).hexdigest();base={'source_snapshot':{'content':content,'sha256':sha,'source_version':'v1'},'target_source_version':'v1','source_references':[{'ref':'S1','resolved':True}],'classification_ledger':[{'classification':'CONFIRMED','source_ref':'S1'}]}
cases=[case('positive',copy.deepcopy(base),'PASS_WITH_EVIDENCE')]
x=copy.deepcopy(base);x['source_snapshot']['sha256']='0'*64;cases.append(case('hash_mismatch',x,'RETURN_TO_WORKER'))
x=copy.deepcopy(base);x['source_references'][0]['resolved']=False;cases.append(case('unresolved_reference',x,'RETURN_TO_WORKER'))
cases.append(case('missing_metadata',copy.deepcopy(base),'BLOCKED',False))
process=subprocess.run([sys.executable,'scripts/validate_source_integrity.py','--self-test'],cwd=SKILL,env=env(),text=True,capture_output=True);d=json.loads(process.stdout.strip().splitlines()[-1]);cases.append({'case':'self_test','expected':'positive_pass_and_negative_rejected','actual':d,'passed':d.get('positive_pass') is True and d.get('negative_rejected') is True})
out={'artifact':'A42','passed':all(x['passed'] for x in cases),'cases':cases};print(json.dumps(out,sort_keys=True));raise SystemExit(0 if out['passed'] else 1)
