-- Option C, phase 1: governed close for ACTUALIZACION_DB_LF executions.
-- The DB step recorder (lf_record_db_operation_step_v1) never closes an
-- execution. This function closes one only when every required active step is
-- PASS_CLEAN, every effect reservation is SUCCEEDED with a receipt, and the
-- caller holds the current lease. It never fabricates evidence: it only checks
-- what the recorder already persisted. Used by the LF Migration Merge Train.
begin;

create or replace function public.lf_close_db_operation_execution_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_closure_evidence jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path = public, pg_temp
as $fn$
declare
  v_now timestamptz := clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_not_clean integer;
  v_effects integer;
  v_effects_open integer;
begin
  if p_closure_evidence is null or jsonb_typeof(p_closure_evidence) <> 'object' then
    raise exception 'DB_CLOSE_EVIDENCE_INVALID';
  end if;
  if btrim(coalesce(p_actor_execution_id, '')) = '' then
    raise exception 'DB_CLOSE_ACTOR_MISSING';
  end if;

  select * into v_exec from public.lf_operation_execution
  where execution_id = p_execution_id for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.operation_code <> 'ACTUALIZACION_DB_LF' then raise exception 'DB_CLOSE_OPERATION_MISMATCH'; end if;
  if v_exec.status = 'COMPLETED' then
    return jsonb_build_object('result', 'REPLAY_ALREADY_COMPLETED', 'execution_id', p_execution_id);
  end if;
  if v_exec.status <> 'IN_PROGRESS' then raise exception 'DB_CLOSE_NOT_IN_PROGRESS:%', v_exec.status; end if;
  if v_exec.lease_owner is distinct from p_lease_owner or v_exec.lease_fence is distinct from p_lease_fence
     or v_exec.lease_expires_at is null or v_exec.lease_expires_at <= v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;

  select count(*) into v_not_clean
  from public.lf_operation_steps s
  left join public.lf_operation_execution_steps es
    on es.execution_id = p_execution_id and es.step_order = s.step_order and es.step_id = s.step_id
  left join public.lf_operation_step_judge_bindings b
    on b.operation_code = s.operation_code and b.step_order = s.step_order and b.step_id = s.step_id
   and b.status = 'ACTIVE_ENFORCEMENT'
  where s.operation_code = v_exec.operation_code and s.required is true and s.active is true
    and (es.step_id is null or b.clean_result_value is null or es.status <> b.clean_result_value);
  if v_not_clean > 0 then raise exception 'DB_CLOSE_REQUIRED_STEPS_NOT_CLEAN:%', v_not_clean; end if;

  select count(*), count(*) filter (where state <> 'SUCCEEDED' or receipt is null)
    into v_effects, v_effects_open
  from public.lf_operation_effect_guard where execution_id = p_execution_id;
  if v_effects = 0 then raise exception 'DB_CLOSE_NO_EFFECT_RECORDED'; end if;
  if v_effects_open > 0 then raise exception 'DB_CLOSE_EFFECT_NOT_SUCCEEDED:%', v_effects_open; end if;

  update public.lf_operation_execution
  set status = 'COMPLETED',
      completed_at = coalesce(completed_at, v_now),
      lease_owner = null,
      lease_expires_at = null,
      manifest = coalesce(manifest, '{}'::jsonb) || jsonb_build_object(
        'operation_closed', true,
        'closed_by', 'lf_close_db_operation_execution_v1',
        'closure_evidence', p_closure_evidence),
      updated_by_execution_id = p_actor_execution_id,
      updated_at = v_now
  where execution_id = p_execution_id and status = 'IN_PROGRESS';

  return jsonb_build_object('result', 'EXECUTION_COMPLETED', 'execution_id', p_execution_id,
                            'effects', v_effects, 'completed_at', v_now);
end;
$fn$;

revoke all on function public.lf_close_db_operation_execution_v1(text, text, bigint, jsonb, text) from public;
revoke all on function public.lf_close_db_operation_execution_v1(text, text, bigint, jsonb, text) from anon, authenticated;
grant execute on function public.lf_close_db_operation_execution_v1(text, text, bigint, jsonb, text) to service_role;

do $post$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'lf_close_db_operation_execution_v1') then
    raise exception 'LF_DB_CLOSE_FN_MISSING';
  end if;
  if has_function_privilege('anon', 'public.lf_close_db_operation_execution_v1(text,text,bigint,jsonb,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.lf_close_db_operation_execution_v1(text,text,bigint,jsonb,text)', 'EXECUTE')
     or has_function_privilege('supabase_read_only_user', 'public.lf_close_db_operation_execution_v1(text,text,bigint,jsonb,text)', 'EXECUTE') then
    raise exception 'LF_DB_CLOSE_FN_EXPOSED';
  end if;
end $post$;

commit;
