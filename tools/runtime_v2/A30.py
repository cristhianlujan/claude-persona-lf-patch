#!/usr/bin/env python3
from __future__ import annotations
import copy,json,os,subprocess,sys,tempfile
from pathlib import Path
from jsonschema import Draft7Validator
ROOT=Path(__file__).resolve().parents[2];SKILL=ROOT/'skills'/'creating-integral-user-stories';schema=json.loads((SKILL/'schemas/story-pack.schema.json').read_text());validator=Draft7Validator(schema);registry=json.loads((SKILL/'evals/evals.json').read_text());base=copy.deepcopy(next(item['candidate_story_pack'] for item in registry['executable_cases'] if item['id']=='E21_STORY_CORE_POSITIVE'))
def schema_errors(value): return [error.message for error in validator.iter_errors(value)]
def validator_result(value):
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'input.json';path.write_text(json.dumps(value));env=os.environ.copy();env.update(LF_JUDGE_VERSION='v0.5',LF_EXECUTOR_IDENTITY='R8_A30_AUDITOR');process=subprocess.run([sys.executable,'scripts/validate_story_pack.py',str(path),'--evidence-ref',f'file:{path}'],cwd=SKILL,env=env,text=True,capture_output=True);return json.loads([line for line in process.stdout.splitlines() if line.strip().startswith('{')][-1])['result']
def case(name,value,schema_expected,validator_expected=None):
 errors=schema_errors(value);actual='PASS' if not errors else 'REJECTED';row={'case':name,'schema_expected':schema_expected,'schema_actual':actual,'schema_errors':errors[:5],'passed':actual==schema_expected}
 if validator_expected is not None: row['validator_expected']=validator_expected;row['validator_actual']=validator_result(value);row['passed'] &= row['validator_actual']==validator_expected
 return row
cases=[case('E21_positive',copy.deepcopy(base),'PASS','PASS_WITH_EVIDENCE')]
value=copy.deepcopy(base);value.pop('core');cases.append(case('missing_core',value,'REJECTED','RETURN_TO_WORKER'))
value=copy.deepcopy(base);value['unexpected']=1;cases.append(case('additional_property',value,'REJECTED','RETURN_TO_WORKER'))
value=copy.deepcopy(base);value['identity']['status']='APPROVED';cases.append(case('unsafe_status',value,'REJECTED','RETURN_TO_WORKER'))
value=copy.deepcopy(base);value['dependencies_risks']['context_budget'].update(canonical_story_tokens=13001,direct_load_allowed=True,specialized_views_required=False,atomicity_review_required=False);cases.append(case('oversized_context_wrong_flags',value,'REJECTED','RETURN_TO_WORKER'))
out={'artifact':'A30','passed':all(item['passed'] for item in cases),'cases':cases};print(json.dumps(out,sort_keys=True));raise SystemExit(0 if out['passed'] else 1)
