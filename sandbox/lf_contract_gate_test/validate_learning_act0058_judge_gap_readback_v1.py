#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).with_name('learning_act0058_judge_gap_readback_v1.json')
def fail(m): raise SystemExit('FAIL learning-act0058-gap: '+m)
def main():
 d=json.loads(P.read_text())
 if d.get('operation_code')!='ORQUESTACION_PIPELINE_LF': fail('operation')
 if d.get('active_steps')!=15 or d.get('active_judge_bindings')!=4 or d.get('missing_judge_bindings')!=11: fail('counts')
 if len(d.get('missing_steps',[]))!=11 or len(d.get('bound_steps',[]))!=4: fail('step lists')
 if d.get('db_mutation_performed') is not False or d.get('production_impact') is not False: fail('impact')
 f=d.get('contract_drift_findings',[])
 if len(f)!=1 or f[0].get('step_id')!='restock_queue' or f[0].get('observed_contract_value')!='MEDIA': fail('restock drift')
 if f[0].get('matched_ekb')!='SQL-008' or 'INFO|WARN|CRITICAL' not in f[0].get('live_constraint',''): fail('constraint/EKB')
 print('LEARNING_ACT0058_JUDGE_GAP=PASS active_steps=15 bound=4 missing=11 restock_drift=1 db_mutation=0')
if __name__=='__main__': main()
