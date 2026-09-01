#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).with_name('learning_act0058_missing_judge_triage_v1.json')
def fail(m): raise SystemExit('FAIL act0058-judge-triage: '+m)
def main():
 d=json.loads(P.read_text())
 ready=d.get('ready_for_judge_spec',[]); repair=d.get('needs_contract_repair',[])
 if d.get('missing_total')!=11 or len(ready)!=9 or len(repair)!=2: fail('counts')
 if {x['step_id'] for x in repair}!={'init_execution','restock_queue'}: fail('repair set')
 if any(not x.get('evidence_keys') for x in ready): fail('ready without evidence')
 if any(x.get('step_id')=='restock_queue' for x in ready): fail('restock prematurely ready')
 if d.get('db_mutation_performed') is not False or d.get('production_impact') is not False: fail('impact')
 print('ACT0058_JUDGE_TRIAGE=PASS missing=11 ready=9 repair=2 db_mutation=0')
if __name__=='__main__': main()
