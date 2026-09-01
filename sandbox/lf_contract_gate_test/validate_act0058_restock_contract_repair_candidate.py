#!/usr/bin/env python3
from pathlib import Path
P=Path(__file__).with_name('act0058_restock_contract_repair_candidate.sql')
def fail(m): raise SystemExit('FAIL act0058-restock-repair-candidate: '+m)
def main():
 s=P.read_text()
 required=["operation_code = 'ORQUESTACION_PIPELINE_LF'","step_id = 'restock_queue'","step_order = 105","mini_judge_code = 'MINI_JUDGE_ACT0058_RESTOCK'","'''MEDIA'''","'''WARN'''","DO NOT APPLY FROM THIS FILE"]
 for x in required:
  if x not in s: fail('missing '+x)
 if s.count('UPDATE public.lf_operation_step_contracts')!=1: fail('update cardinality')
 if 'DELETE ' in s.upper() or 'TRUNCATE ' in s.upper() or 'DROP ' in s.upper(): fail('unsafe operation')
 if "LIKE '%''MEDIA''%'" not in s: fail('precondition absent')
 print('ACT0058_RESTOCK_REPAIR_CANDIDATE=PASS scope=1 step=restock_queue source_only=1 apply=0')
if __name__=='__main__': main()
