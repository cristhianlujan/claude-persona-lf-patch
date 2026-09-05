do $migration$
declare
  v_binding_count integer;
  v_judge_count integer;
begin
  select count(*) into v_binding_count
  from public.lf_operation_step_judge_bindings
  where operation_code = 'CREACION_PERFIL_LF'
    and step_id = 'pre_destination_resolution_gate'
    and judge_code = 'MINI_JUDGE_CREACION_PERFIL_LF_PRE_DESTINATION_RESOLUTION_GATE_V1'
    and clean_result_value = 'STEP_CLEAN_PASS'
    and status = 'ACTIVE_ENFORCEMENT';

  if v_binding_count <> 1 then
    raise exception 'PROFILE_CREATOR_PRE_DESTINATION_BINDING_GUARD_FAILED:%', v_binding_count;
  end if;

  select count(*) into v_judge_count
  from public.lf_operation_judges
  where operation_code = 'CREACION_PERFIL_LF'
    and judge_code = 'MINI_JUDGE_CREACION_PERFIL_LF_PRE_DESTINATION_RESOLUTION_GATE_V1'
    and status = 'ACTIVE_ENFORCEMENT'
    and jsonb_typeof(result_values) = 'object'
    and result_values->>'pass' = 'DESTINATION_ROLES_RESOLVED'
    and result_values->>'return' = 'RETURN_TO_BACKEND_DESTINATION_CONFIG'
    and result_values->>'blocked' = 'BLOCKED_DESTINATION_ROLE_NOT_CONFIGURED';

  if v_judge_count <> 1 then
    raise exception 'PROFILE_CREATOR_PRE_DESTINATION_JUDGE_GUARD_FAILED:%', v_judge_count;
  end if;

  update public.lf_operation_judges
  set result_values = jsonb_set(result_values, '{pass}', to_jsonb('STEP_CLEAN_PASS'::text), false),
      updated_at = now(),
      updated_by_execution_id = 'EXEC-CREACION-PERFIL-LF-OIDC-5f133751-fd18-4176-af31-936d4324d338'
  where operation_code = 'CREACION_PERFIL_LF'
    and judge_code = 'MINI_JUDGE_CREACION_PERFIL_LF_PRE_DESTINATION_RESOLUTION_GATE_V1'
    and status = 'ACTIVE_ENFORCEMENT';

  if not exists (
    select 1
    from public.lf_operation_judges
    where operation_code = 'CREACION_PERFIL_LF'
      and judge_code = 'MINI_JUDGE_CREACION_PERFIL_LF_PRE_DESTINATION_RESOLUTION_GATE_V1'
      and status = 'ACTIVE_ENFORCEMENT'
      and result_values->>'pass' = 'STEP_CLEAN_PASS'
      and result_values->>'return' = 'RETURN_TO_BACKEND_DESTINATION_CONFIG'
      and result_values->>'blocked' = 'BLOCKED_DESTINATION_ROLE_NOT_CONFIGURED'
  ) then
    raise exception 'PROFILE_CREATOR_PRE_DESTINATION_JUDGE_READBACK_FAILED';
  end if;
end
$migration$;
