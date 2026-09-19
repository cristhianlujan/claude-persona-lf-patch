#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
C=json.loads((ROOT/'contracts/profile_update_lifecycle_reconciliation_v1.json').read_text())
M=(ROOT.parents[1]/'supabase/migrations/20260919065202_lf_profile_update_begin_reconcile_v1.sql').read_text()

checks={
  'contract_schema':C.get('schema')=='LF_PROFILE_UPDATE_LIFECYCLE_RECONCILIATION_V1',
  'operation_exact':C.get('operation_code')=='ACTUALIZACION_PERFIL_LF',
  'begin_rpc_materialized':'create or replace function public.lf_profile_update_begin_v1' in M.lower(),
  'begin_calls_reservation':'fn_lf_operation_reserve_execution_v1' in M,
  'begin_materializes_init':"'init_execution'" in M and 'Initialized transactionally by governed Profile Update begin RPC.' in M,
  'post_merge_step_materialized':"'post_merge_reconcile'" in M and '115' in M,
  'regression_routes_to_reconcile':"next_if_pass='post_merge_reconcile'" in M,
  'reconcile_rpc_materialized':'create or replace function public.lf_profile_update_post_merge_reconcile_v1' in M.lower(),
  'activation_is_next_gate_not_promotion':'SOURCE_RECONCILED_ACTIVATION_REQUIRED' in M and "'automatic_promotion',false" in M,
  'runtime_refresh_is_next_gate':'SOURCE_RECONCILED_RUNTIME_REFRESH_REQUIRED' in M and 'PROFILE_RUNTIME_REFRESH_REQUIRED' in M,
  'state_drift_guard':'LF_PROFILE_UPDATE_RECONCILE_STATE_DRIFT' in M,
  'policy_v11_declares_reconcile':"'POL-PROFILE-UPDATE-PASS','v1.1'" in M and "'post_merge_reconcile'" in M,
  'governed_pr_persisted':"'last_governed_pr',p_pr_number" in M,
  'service_role_only':'grant execute on function public.lf_profile_update_begin_v1' in M.lower() and 'to service_role' in M.lower(),
  'lifecycle_declares_reconcile':'post_merge_reconcile' in C.get('lifecycle',[]),
}
failed=[k for k,v in checks.items() if not v]
print(json.dumps({'contract':'PROFILE_UPDATE_LIFECYCLE_RECONCILIATION_V1','checks':checks,'count':len(checks),'result':'PASS' if not failed else 'FAIL','failed':failed},sort_keys=True))
raise SystemExit(1 if failed else 0)

