-- RUNTIME_UPDATE_OPERATION_ENFORCEMENT_CANDIDATE_V1
-- SOURCE ONLY / NOT APPLIED
-- Existing operation only: ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF
-- No Router mutation, no operation activation, no lifecycle promotion.
-- The transaction intentionally rolls back after topology + negative/positive canary checks.

begin;

do $baseline$
declare
  v_registry_status text;
  v_lifecycle text;
  v_steps_total integer;
  v_steps_active integer;
  v_contracts_total integer;
  v_contracts_active integer;
  v_judges integer;
  v_bindings integer;
  v_router_count integer;
begin
  select status,lifecycle_state_code into v_registry_status,v_lifecycle
  from public.lf_operation_registry
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

  select count(*),count(*) filter(where active)
  into v_steps_total,v_steps_active
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

  select count(*),count(*) filter(where status='ACTIVE_ENFORCEMENT')
  into v_contracts_total,v_contracts_active
  from public.lf_operation_step_contracts
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

  select count(*) into v_judges
  from public.lf_operation_judges
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

  select count(*) into v_bindings
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

  select count(*) into v_router_count
  from public.lf_router_action_registry
  where asset_type='OPERATION_CODE'
    and action_code='RUNTIME_UPDATE'
    and operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and status='ACTIVE';

  if v_registry_status is distinct from 'CANDIDATO_READ_ONLY'
     or v_lifecycle is distinct from 'OP_CANDIDATE'
     or v_steps_total<>14 or v_steps_active<>0
     or v_contracts_total<>14 or v_contracts_active<>14
     or v_judges<>0 or v_bindings<>0 or v_router_count<>1 then
    raise exception 'RUNTIME_UPDATE_BASELINE_DRIFT registry=% lifecycle=% steps=%/% contracts=%/% judges=% bindings=% router=%',
      v_registry_status,v_lifecycle,v_steps_total,v_steps_active,v_contracts_total,v_contracts_active,v_judges,v_bindings,v_router_count;
  end if;
end;
$baseline$;

-- Create the transaction-local canary through the canonical reservation path.
-- Provenance anchor is the latest verified prior execution of this same operation.
do $provenance$
declare
  v_exec constant text := 'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY';
  v_anchor text;
  v_res jsonb;
begin
  select execution_id into v_anchor
  from public.lf_operation_execution
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and status in ('CLOSED_PASS','CLOSED_WITH_VERIFIED_EVIDENCE','COMPLETED')
  order by coalesce(completed_at,started_at,created_at) desc
  limit 1;

  if v_anchor is null then
    raise exception 'RUNTIME_UPDATE_PROVENANCE_ANCHOR_MISSING';
  end if;

  v_res:=public.fn_lf_operation_reserve_execution_v1(
    v_exec,
    'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',
    'OPERATION_CODE',
    'EJECUCION_PERFIL_LF',
    'runtime-update-enforcement-source-only-canary-v1',
    '9cf4c38c8d37c4c2ea85f76ebd34d3329bc9a040ebbd08c86c6a413a10d195fd',
    v_anchor,
    'cristhianlujan/claude-persona-lf-patch',
    'sandbox/lf_contract_gate_test/profile_execution_runtime',
    jsonb_build_object(
      'source_only_canary',true,
      'no_live_apply',true,
      'provenance_anchor',v_anchor
    )
  );

  if v_res->>'result'<>'RESERVED_NEW_EXECUTION'
     or v_res->>'status'<>'IN_PROGRESS'
     or v_res->>'execution_id'<>v_exec then
    raise exception 'RUNTIME_UPDATE_CANARY_RESERVATION_NOT_CLEAN:%',v_res;
  end if;
end;
$provenance$;

insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
  created_by_execution_id,updated_by_execution_id
) values
(
  'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',
  'JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-v1',
  'sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_update_judge_structural_source_v1.json',
  'SOURCE_DERIVED_AT_MATERIALIZATION_TIME',
  '[]'::jsonb,
  '[]'::jsonb,
  '{"pass":"STEP_PASS_WITH_EVIDENCE","blocked":"BLOCKED_STEP_NOT_CLEAN","return":"RETURN_TO_ROUTER"}'::jsonb,
  'ACTIVE_ENFORCEMENT',
  'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY',
  'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY'
),
(
  'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',
  'JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-PREWRITE-v1',
  'sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_update_prewrite_judge_semantics_v1.json',
  'SOURCE_DERIVED_AT_MATERIALIZATION_TIME',
  '["execution_id_matches_current_execution","target_type_is_operation_code","target_code_is_ejecucion_perfil_lf","target_path_matches_execution_target","execution_bound_to_target_before_change_is_true","bound_revision_is_structured","bound_revision_matches_current_resolved_revision"]'::jsonb,
  '["execution_binding_missing_or_false","target_identity_mismatch","bound_revision_missing_or_unstructured","bound_revision_mismatch","target_path_mismatch","pre_write_gate_missing_or_false"]'::jsonb,
  '{"pass":"STEP_PASS_WITH_EVIDENCE","blocked":"BLOCKED_STEP_NOT_CLEAN","return":"RETURN_TO_ROUTER"}'::jsonb,
  'ACTIVE_ENFORCEMENT',
  'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY',
  'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY'
);

update public.lf_operation_step_contracts
set mini_judge_code=case
      when step_id='pre_write_execution_binding_gate' and step_order=60
        then 'JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-PREWRITE-v1'
      else 'JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-v1'
    end,
    required_evidence_keys=case
      when step_id='pre_write_execution_binding_gate' and step_order=60
        then '["execution_id","target_code","target_path","write_plan","pre_write_gate_passed","bound_revision","execution_bound_to_target_before_change"]'::jsonb
      else required_evidence_keys
    end,
    updated_by_execution_id='CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY',
    updated_at=now()
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and status='ACTIVE_ENFORCEMENT';

insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
select
  c.operation_code,c.step_order,c.step_id,c.mini_judge_code,
  'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
  c.required_evidence_keys,'ACTIVE_ENFORCEMENT',
  'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY',
  'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY'
from public.lf_operation_step_contracts c
where c.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and c.status='ACTIVE_ENFORCEMENT';

update public.lf_operation_steps
set active=true,
    updated_by_execution_id='CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY',
    updated_at=now()
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

do $target_topology$
declare
  v_active_steps integer;
  v_bindings integer;
  v_generic integer;
  v_prewrite integer;
  v_wrong_judge integer;
  v_step60_keys jsonb;
  v_registry_status text;
  v_lifecycle text;
begin
  select count(*) into v_active_steps
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and active;

  select count(*) into v_bindings
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';

  select count(*) into v_generic
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and status='ACTIVE_ENFORCEMENT'
    and judge_code='JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-v1';

  select count(*) into v_prewrite
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and step_id='pre_write_execution_binding_gate' and step_order=60
    and status='ACTIVE_ENFORCEMENT'
    and judge_code='JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-PREWRITE-v1';

  select count(*) into v_wrong_judge
  from public.lf_operation_step_contracts
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and mini_judge_code like 'JUDGE-ACTUALIZACION-PERFIL-LF%';

  select required_evidence_keys into v_step60_keys
  from public.lf_operation_step_contracts
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and step_id='pre_write_execution_binding_gate' and step_order=60;

  select status,lifecycle_state_code into v_registry_status,v_lifecycle
  from public.lf_operation_registry
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

  if v_active_steps<>14 or v_bindings<>14 or v_generic<>13 or v_prewrite<>1 or v_wrong_judge<>0 then
    raise exception 'RUNTIME_UPDATE_TARGET_TOPOLOGY_INVALID steps=% bindings=% generic=% prewrite=% wrong=%',
      v_active_steps,v_bindings,v_generic,v_prewrite,v_wrong_judge;
  end if;

  if v_step60_keys is distinct from '["execution_id","target_code","target_path","write_plan","pre_write_gate_passed","bound_revision","execution_bound_to_target_before_change"]'::jsonb then
    raise exception 'RUNTIME_UPDATE_STEP60_KEYS_INVALID:%',v_step60_keys;
  end if;

  if v_registry_status is distinct from 'CANDIDATO_READ_ONLY'
     or v_lifecycle is distinct from 'OP_CANDIDATE' then
    raise exception 'RUNTIME_UPDATE_CANDIDATE_ESCALATED:%:%',v_registry_status,v_lifecycle;
  end if;
end;
$target_topology$;

-- Transaction-local probe for the dedicated step-60 judge.
-- Prior clean rows are synthetic prerequisites only, provenance-bound and rolled back;
-- they are not claimed as operation evidence or E2E execution.
do $step60_canary$
declare
  v_exec constant text := 'CANARY-RUNTIME-UPDATE-STEP60-SOURCE-ONLY';
  v_neg jsonb;
  v_pos jsonb;
  v_order integer;
begin
  if not exists(
    select 1 from public.lf_operation_execution
    where execution_id=v_exec
      and operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and target_type='OPERATION_CODE'
      and target_code='EJECUCION_PERFIL_LF'
      and status='IN_PROGRESS'
  ) then
    raise exception 'RUNTIME_UPDATE_CANARY_EXECUTION_NOT_BOUND';
  end if;

  for v_order in select unnest(array[0,10,20,30,40,50]) loop
    insert into public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,
      created_by_execution_id,updated_by_execution_id
    )
    select v_exec,s.step_order,s.step_id,'STEP_PASS_WITH_EVIDENCE','source-only://fixture',
           jsonb_build_object('fixture',true,'source_only',true,'rolled_back',true),
           'Synthetic prerequisite for source-only step60 probe; never operation evidence.',
           v_exec,v_exec
    from public.lf_operation_steps s
    where s.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and s.step_order=v_order;
  end loop;

  v_neg:=public.lf_record_operation_step_core_v1(
    v_exec,'pre_write_execution_binding_gate','source-only://negative',
    jsonb_build_object(
      'execution_id',v_exec,
      'target_code','EJECUCION_PERFIL_LF',
      'target_path','sandbox/lf_contract_gate_test/profile_execution_runtime',
      'write_plan','runtime-only candidate',
      'pre_write_gate_passed',true,
      'execution_bound_to_target_before_change',true
    ),
    v_exec,
    'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF','OPERATION_CODE',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    jsonb_build_object(
      'valid',true,
      'server_assertions',jsonb_build_array(
        'execution_id_matches_current_execution','target_type_is_operation_code',
        'target_code_is_ejecucion_perfil_lf','target_path_matches_execution_target',
        'execution_bound_to_target_before_change_is_true','bound_revision_is_structured',
        'bound_revision_matches_current_resolved_revision'
      ),
      'server_hard_fails','[]'::jsonb
    ),
    false,'runtime_update_source_only_canary'
  );

  if v_neg->>'outcome'<>'BLOCKED' or v_neg->>'code'<>'REQUIRED_EVIDENCE_MISSING' then
    raise exception 'RUNTIME_UPDATE_STEP60_NEGATIVE_NOT_BLOCKED:%',v_neg;
  end if;

  v_pos:=public.lf_record_operation_step_core_v1(
    v_exec,'pre_write_execution_binding_gate','source-only://positive',
    jsonb_build_object(
      'execution_id',v_exec,
      'target_code','EJECUCION_PERFIL_LF',
      'target_path','sandbox/lf_contract_gate_test/profile_execution_runtime',
      'write_plan','runtime-only candidate',
      'pre_write_gate_passed',true,
      'bound_revision','0123456789abcdef0123456789abcdef01234567',
      'execution_bound_to_target_before_change',true
    ),
    v_exec,
    'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF','OPERATION_CODE',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    jsonb_build_object(
      'valid',true,
      'server_assertions',jsonb_build_array(
        'execution_id_matches_current_execution','target_type_is_operation_code',
        'target_code_is_ejecucion_perfil_lf','target_path_matches_execution_target',
        'execution_bound_to_target_before_change_is_true','bound_revision_is_structured',
        'bound_revision_matches_current_resolved_revision'
      ),
      'server_hard_fails','[]'::jsonb
    ),
    false,'runtime_update_source_only_canary'
  );

  if v_pos->>'outcome'<>'STEP_RECORDED' or v_pos->>'status'<>'STEP_PASS_WITH_EVIDENCE' then
    raise exception 'RUNTIME_UPDATE_STEP60_POSITIVE_NOT_CLEAN:%',v_pos;
  end if;
end;
$step60_canary$;

rollback;

-- IMPORTANT: rollback is intentional. A separate, explicitly authorized live migration is required
-- before any of these topology changes can become authoritative.
