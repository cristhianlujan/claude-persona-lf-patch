#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
RECON=ROOT/'supabase/migrations/20260901153300_act0058_step_105_110_contract_reconciliation_v1.sql'
JUDGES=ROOT/'supabase/migrations/20260901153500_act0058_missing_judges_candidate_v1.sql'

def fail(msg: str): raise SystemExit('FAIL ACT0058_CANDIDATE_MIGRATIONS: '+msg)
def main() -> int:
 r=RECON.read_text(encoding='utf-8')
 j=JUDGES.read_text(encoding='utf-8')
 for name,text in [('reconciliation',r),('judges',j)]:
  if "current_setting('app.lf_execution_id',true)" not in text: fail(name+' execution setting')
  if "operation_code='ORQUESTACION_PIPELINE_LF'" not in text: fail(name+' operation provenance')
  if "status='IN_PROGRESS'" not in text: fail(name+' execution state')
  if 'updated_by_execution_id=v_execution_id' not in text and name=='reconciliation': fail('reconciliation update provenance')
 if 'ACT0058_RECONCILIATION_EXECUTION_ID_REQUIRED' not in r or 'ACT0058_RECONCILIATION_EXECUTION_INVALID' not in r: fail('reconciliation guards')
 if 'RESTOCK_NOOP_WARN' not in r or 'RETRY_TERMINAL_FAILED' not in r: fail('reconciliation semantics')
 if "array['retry_count','error_detail','stage_status']::text[]" not in r: fail('retry material evidence keys')
 if "'stage_status','PENDING'" not in r or "'stage_status','FAILED'" not in r: fail('retry stage_status semantics')
 retry_update = r.split("where operation_code='ORQUESTACION_PIPELINE_LF' and step_order=110",1)[0].rsplit('update public.lf_operation_step_contracts',1)[-1]
 if 'next_action' in retry_update: fail('retry reconciliation must not invent next_action')
 if 'ACT0058_JUDGE_CANDIDATE_EXECUTION_ID_REQUIRED' not in j or 'ACT0058_JUDGE_CANDIDATE_EXECUTION_INVALID' not in j: fail('judge guards')
 if j.count("'CANDIDATO_READ_ONLY',v_execution_id,v_execution_id")!=10: fail('candidate judge cardinality')
 if "'ACTIVE_ENFORCEMENT'" in j: fail('candidate migration must not activate judges')
 if 'insert into public.lf_operation_step_judge_bindings' in j.lower(): fail('candidate migration must not bind judges')
 retry_row=j.split("'MINI_JUDGE_ACT0058_RETRY'",1)[-1]
 if 'next_action' in retry_row: fail('candidate retry judge must not invent next_action')
 if 'retry_count_lt_3_and_stage_status_pending' not in j or 'retry_count_gte_3_and_stage_status_failed' not in j: fail('candidate retry material evidence semantics')
 required=['MINI_JUDGE_ACT0058_INIT_EXECUTION','MINI_JUDGE_ACT0058_INIT','MINI_JUDGE_ACT0058_SCOPE','MINI_JUDGE_ACT0058_CAPTURA','MINI_JUDGE_ACT0058_HOMOLOG','MINI_JUDGE_ACT0058_ANALISIS','MINI_JUDGE_ACT0058_KB_WRITE','MINI_JUDGE_ACT0058_COMPLETED','MINI_JUDGE_ACT0058_RESTOCK','MINI_JUDGE_ACT0058_RETRY']
 if any(code not in j for code in required): fail('judge coverage')
 print('ACT0058_CANDIDATE_MIGRATIONS=PASS reconciliation=SOURCE_ONLY judges=10 candidate_only provenance=REQUIRED bindings=0 retry_material_evidence=PASS')
 return 0
if __name__=='__main__': raise SystemExit(main())
