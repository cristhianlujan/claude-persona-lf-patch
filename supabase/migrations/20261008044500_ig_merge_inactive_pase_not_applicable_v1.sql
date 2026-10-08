-- IG generic repair: PASE is conditional, never a mandatory dependency when disabled.
-- Do not invent prerequisite tokens unsupported by the currently installed executor.
-- Requires exact trusted-base activation readback by the runner. Does not enable PASE.
create or replace function programacion.fn_engineering_merge_authorization_contract_v1()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $function$
select jsonb_build_object(
  'schema_version','ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1_1',
  'authorization_owner','PROCESS',
  'human_approval_required',false,
  'auto_merge_when_authorized',true,
  'authorization_capability','SAFE_CHANGE_ADMISSION',
  'required_execution_permission','DOWNSTREAM_EXECUTION_ELIGIBLE',
  'required_preconditions',jsonb_build_array(
    'EKB_PREFLIGHT_CLEAR',
    'EXACT_HEAD_MATCH',
    'PR_MERGEABLE_TRUE'
  ),
  'pase_policy',jsonb_build_object(
    'repair_policy_id','PASE_CONTROL_REPAIR_QUARANTINE_V1',
    'repair_window_state','SUPPORTED',
    'activation_resolution','TRUSTED_BASE_EXACT_HEAD_READBACK_REQUIRED',
    'on_disabled','NOT_APPLICABLE',
    'disabled_skipped_workflow_is_pass',false,
    'on_enabled','REQUIRE_PASE_MERGE_POLICY_EFFECTIVE_ALLOW',
    'on_unknown','BLOCK',
    'observe_only_results_cannot_block_merge',true,
    'active_blocking_controls_require_exact_terminal_pass',true,
    'structural_governance_remains_fail_closed',true,
    'global_f09_f10_completion_required_for_ordinary_merge',false,
    'control_system_activation_requires_separate_terminal_qualification',true
  ),
  'forbidden',jsonb_build_array(
    'MERGE_WITHOUT_PROCESS_AUTHORIZATION',
    'TREAT_RECOMMENDATION_AS_PERMISSION',
    'SKIP_EKB_PREFLIGHT',
    'SKIP_ACTIVE_BLOCKING_CONTROL_WHEN_APPLICABLE',
    'TREAT_REPAIR_OBSERVE_ONLY_AS_MERGE_BLOCKER',
    'REQUIRE_GLOBAL_PASE_F09_F10_FOR_ORDINARY_MERGE',
    'MERGE_DIFFERENT_HEAD',
    'TREAT_SKIPPED_WORKFLOW_AS_PASS',
    'ASSUME_DISABLED_WITHOUT_TRUSTED_BASE_READBACK'
  ),
  'on_authorized','MERGE_AND_CONTINUE_CURRENT_UNIT',
  'on_not_authorized','YIELD_CURRENT_UNIT_CONTINUE_SCHEDULER',
  'global_scheduler_stop',false,
  'fail_closed',true
);
$function$;

comment on function programacion.fn_engineering_merge_authorization_contract_v1()
is 'PASE inactive is NOT_APPLICABLE only on trusted-base activation readback; enabled PASE demands effective policy PASS; unknown blocks. Safe-change admission, active controls, exact head and native PR protections remain mandatory.';

do $assert$
declare
  v jsonb:=programacion.fn_engineering_merge_authorization_contract_v1();
begin
  if coalesce(v->'required_preconditions' ? 'PASE_MERGE_POLICY_EFFECTIVE_ALLOW',true)
     or coalesce(v->'required_preconditions' ? 'GOVERNED_MERGE_APPLICABILITY_RESOLVED',false)
     or coalesce(v->'required_preconditions' ? 'ACTIVE_BLOCKING_CONTROLS_PASS_WHEN_APPLICABLE',false) then
    raise exception 'FAIL_MERGE_CONTRACT_UNCONDITIONAL_PASE';
  end if;
  if v#>>'{pase_policy,on_disabled}' <> 'NOT_APPLICABLE'
     or v#>>'{pase_policy,on_enabled}' <> 'REQUIRE_PASE_MERGE_POLICY_EFFECTIVE_ALLOW'
     or v#>>'{pase_policy,on_unknown}' <> 'BLOCK'
     or v#>>'{pase_policy,activation_resolution}' <> 'TRUSTED_BASE_EXACT_HEAD_READBACK_REQUIRED' then
    raise exception 'FAIL_MERGE_CONTRACT_APPLICABILITY';
  end if;
  if v->>'required_execution_permission' <> 'DOWNSTREAM_EXECUTION_ELIGIBLE'
     or v#>>'{pase_policy,structural_governance_remains_fail_closed}' <> 'true'
     or v#>>'{pase_policy,active_blocking_controls_require_exact_terminal_pass}' <> 'true'
     or v->>'fail_closed' <> 'true' then
    raise exception 'FAIL_MERGE_CONTRACT_GOVERNANCE';
  end if;
end;
$assert$;

-- Preserve EKB history while correcting the old unconditional wording.
update public.lf_error_knowledge
set prevencion=replace(
      prevencion,
      'Require PASE_MERGE_POLICY_EFFECTIVE_ALLOW. During the repair window',
      'Require PASE_MERGE_POLICY_EFFECTIVE_ALLOW ONLY IF PASE is proven ACTIVE; when independently verified DISABLED classify NOT_APPLICABLE, and when UNKNOWN block. During the repair window'
    ),
    ultima_vez=now(),updated_at=now()
where codigo='ENGINEERING-MERGE-AUTH-PASE-REPAIR-WINDOW-001'
  and prevencion like '%Require PASE_MERGE_POLICY_EFFECTIVE_ALLOW. During the repair window%';
