#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).with_name('learning_act0058_9_judge_specs_v1.json')
def fail(m): raise SystemExit('FAIL act0058-9-judge-specs: '+m)
def main():
 d=json.loads(P.read_text()); js=d.get('judges',[])
 if len(js)!=9: fail('count')
 if len({x['judge_code'] for x in js})!=9 or len({(x['step_order'],x['step_id']) for x in js})!=9: fail('duplicates')
 for j in js:
  if not j.get('pass_if') or not j.get('fail_if') or not j.get('required_evidence_keys') or not j.get('result_values'): fail('incomplete '+j.get('step_id','?'))
  if 'BLOCKED' not in ' '.join(j['result_values']) and 'FAIL' not in j['result_values']: fail('no fail-closed result '+j['step_id'])
 if set(d.get('excluded_until_contract_repair',[]))!={'init_execution','restock_queue'}: fail('excluded set')
 if d.get('database_apply_authorized') is not False or d.get('db_mutation_performed') is not False or d.get('production_impact') is not False: fail('impact')
 print('ACT0058_9_JUDGE_SPECS=PASS specs=9 excluded_repair=2 source_only=1 db_mutation=0')
if __name__=='__main__': main()
