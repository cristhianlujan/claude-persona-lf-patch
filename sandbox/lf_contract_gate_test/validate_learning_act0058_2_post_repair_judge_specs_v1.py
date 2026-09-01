#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).with_name('learning_act0058_2_post_repair_judge_specs_v1.json')
def fail(m): raise SystemExit('FAIL act0058-post-repair-judge-specs: '+m)
def main():
 d=json.loads(P.read_text()); js=d.get('judges',[])
 if d.get('status')!='BLOCKED_UNTIL_CONTRACT_REPAIR_READBACK': fail('status')
 if len(js)!=2 or {x['step_id'] for x in js}!={'init_execution','restock_queue'}: fail('judge set')
 if any(not x.get('required_evidence_keys') or not x.get('pass_if') or not x.get('fail_if') for x in js): fail('incomplete')
 rest=[x for x in js if x['step_id']=='restock_queue'][0]
 if 'SKIP_RESTOCK' not in rest.get('result_values',[]) or not rest.get('non_failure_skip_if'): fail('restock skip semantics')
 if d.get('prerequisite_db_readback')!='NOT_EXECUTED' or d.get('database_apply_authorized') is not False or d.get('db_mutation_performed') is not False: fail('premature apply')
 print('ACT0058_POST_REPAIR_JUDGE_SPECS=PASS specs=2 blocked_until_readback=1 db_mutation=0')
if __name__=='__main__': main()
