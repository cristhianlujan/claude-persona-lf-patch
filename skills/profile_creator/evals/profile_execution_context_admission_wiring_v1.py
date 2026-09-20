from pathlib import Path
import json

ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parent.parent
C=json.loads((ROOT/"contracts/profile_execution_context_admission_wiring_v1.json").read_text())
M=(REPO/"supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql").read_text()

checks={
  "target_operation":C["target_operation"]=="EJECUCION_PERFIL_LF",
  "governed_update":C["governed_by"]=="ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF",
  "step_count_9_to_10":C["before"]["active_steps"]==9 and C["after"]["active_steps"]==10,
  "ordered_path":C["after"]["path"]==["input_validate","context_admission","execute_profile"],
  "existing_compiler_reused":C["after"]["context_compiler"]=="public.fn_lf_router_preflight_v1",
  "jit_resolver_reused":C["after"]["jit_resolver"]=="EVIDENCE_RESOLVER_REGISTRY",
  "jit_profile_source":C["after"]["profile_source_mode"]=="JIT_BY_REF",
  "migration_context_step":"'context_admission',45,45" in M,
  "migration_input_edge":"next_if_pass='context_admission'" in M,
  "migration_execute_receipt_keys":'["context_receipt_ref","context_receipt_digest","context_transport"]' in M,
  "server_context_function":"create or replace function public.lf_profile_execution_context_admission_v1" in M.lower(),
  "server_trust_function":"create or replace function public.lf_profile_execution_trust_validation_v1" in M.lower(),
  "server_recorder":"create or replace function public.lf_record_profile_execution_step_v1" in M.lower(),
  "server_begin":"create or replace function public.lf_profile_execution_begin_v1" in M.lower(),
  "provenance_guard_updated":"create or replace function public.fn_lf_operation_provenance_guard_v1" in M.lower(),
  "runtime_update_provenance_exact":"v_created_manifest->>'target_operation' = new.operation_code" in M and "v_updated_manifest->>'target_operation' = new.operation_code" in M,
  "runtime_update_provenance_in_progress":"v_created_status = 'IN_PROGRESS'" in M and "v_updated_status = 'IN_PROGRESS'" in M,
  "runtime_update_provenance_governed":"runtime_update_governed" in M,
  "preflight_called":"compiled:=public.fn_lf_router_preflight_v1(p_execution_id);" in M,
  "event_readback":"payload->'context_receipt'" in M and "created_by_execution_id=p_execution_id" in M,
  "budget_readback":"private.lf_context_budget_events_v2" in M,
  "digest_binding":"context_receipt_digest" in M and "extensions.digest" in M,
  "no_full_policy":"policy_payloads" in M and "is not false" in M,
  "no_full_ekb":"full_ekb_entries" in M,
  "no_full_readmes":"full_readmes" in M,
  "jit_only":"jit_only" in M,
  "full_prefetch_zero":"full_prefetch_count" in M,
  "no_profile_mutation":"update public.lf_activos" not in M.lower(),
  "no_auto_promotion":"promote_operation" not in M.lower(),
}
failed=[k for k,v in checks.items() if not v]
if failed:
    raise SystemExit("FAIL_PROFILE_EXECUTION_CONTEXT_ADMISSION_WIRING:"+",".join(failed))
print(f"PASS_PROFILE_EXECUTION_CONTEXT_ADMISSION_WIRING={sum(checks.values())}/{len(checks)}")
print("CONTEXT_PATH=input_validate->context_admission->execute_profile")
print("CONTEXT_DELIVERY=COMPACT_JIT_ONLY")
print("PROFILE_SOURCE_MODE=JIT_BY_REF")
print("AUTOMATIC_PROMOTION=false")
