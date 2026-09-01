#!/usr/bin/env python3
from pathlib import Path
P=Path(__file__).with_name('act0058_two_contracts_hardening_candidate.sql')
def fail(m): raise SystemExit('FAIL act0058-two-contracts-hardening: '+m)
def main():
 s=P.read_text()
 if s.count('UPDATE public.lf_operation_step_contracts')!=2: fail('expected two updates')
 for step in ["step_id='init_execution'","step_id='restock_queue'"]:
  if step not in s: fail('missing '+step)
 for token in ["operation_code='ORQUESTACION_PIPELINE_LF'","step_order=5","step_order=105","required_evidence_keys","'''WARN'''","'''MEDIA'''","DO NOT APPLY FROM THIS FILE"]:
  if token not in s: fail('missing '+token)
 if "pass_condition='{}'::jsonb" not in s or "required_evidence_keys='[]'::jsonb" not in s: fail('fail-closed preconditions absent')
 if any(x in s.upper() for x in ['DELETE ','TRUNCATE ','DROP ']): fail('unsafe SQL')
 print('ACT0058_TWO_CONTRACTS_HARDENING=PASS target_rows=2 source_only=1 db_apply=0')
if __name__=='__main__': main()
