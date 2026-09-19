
do $$
declare
  v_changed integer;
  v_remaining integer;
begin
  if not exists (
    select 1
      from public.lf_operation_execution
     where execution_id='EXEC-SRCR-MR02-GPT-NATIVE-POSTFIX-20260919-001'
       and operation_code='EJECUCION_PERFIL_LF'
       and status='COMPLETED'
  ) then
    raise exception 'BLOCK_NATIVE_RESOLVER_SCOPE_MATCHED_PROVENANCE_MISSING';
  end if;

  update public.lf_operation_step_contracts
     set resolver_ref = 'NATIVE_MODEL_RUNTIME_WITH_SUPABASE_CONTEXT',
         updated_at = now(),
         updated_by_execution_id = 'EXEC-SRCR-MR02-GPT-NATIVE-POSTFIX-20260919-001'
   where operation_code = 'EJECUCION_PERFIL_LF'
     and resolver_ref = 'GPT_RUNTIME_WITH_SUPABASE_CONTEXT';

  get diagnostics v_changed = row_count;
  if v_changed < 1 then
    raise exception 'BLOCK_NATIVE_RESOLVER_NO_TARGET_ROWS_CHANGED';
  end if;

  select count(*)
    into v_remaining
    from public.lf_operation_step_contracts
   where operation_code = 'EJECUCION_PERFIL_LF'
     and resolver_ref = 'GPT_RUNTIME_WITH_SUPABASE_CONTEXT';

  if v_remaining <> 0 then
    raise exception 'BLOCK_NATIVE_RESOLVER_GPT_SPECIFIC_ROWS_REMAIN:%', v_remaining;
  end if;

  if not exists (
    select 1
      from public.lf_operation_step_contracts
     where operation_code = 'EJECUCION_PERFIL_LF'
       and step_id = 'router'
       and step_order = 10
       and resolver_ref = 'public.v_lf_fuente_operativa.ACT-0001 + public.lf_operation_registry'
  ) then
    raise exception 'BLOCK_NATIVE_RESOLVER_ROUTER_BINDING_CHANGED';
  end if;
end $$;
