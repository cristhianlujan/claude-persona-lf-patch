begin;

create or replace function public.lf_solution_ref_manifest_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_old_ref text;
  v_new_ref text;
  v_raw text;
begin
  if new.manifest ? 'solution_ref' then
    v_raw := new.manifest->>'solution_ref';
    v_new_ref := nullif(btrim(v_raw), '');
    if v_new_ref is null or v_new_ref !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' then
      raise exception 'SOLUTION_REF_INVALID';
    end if;
    new.manifest := jsonb_set(new.manifest, '{solution_ref}', to_jsonb(v_new_ref), true);
  else
    v_new_ref := null;
  end if;

  if tg_op = 'UPDATE' then
    v_old_ref := nullif(btrim(old.manifest->>'solution_ref'), '');
    if v_old_ref is not null and v_new_ref is distinct from v_old_ref then
      raise exception 'SOLUTION_REF_IMMUTABLE';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_lf_solution_ref_manifest_guard_v1
on public.lf_operation_execution;

create trigger trg_lf_solution_ref_manifest_guard_v1
before insert or update of manifest
on public.lf_operation_execution
for each row execute function public.lf_solution_ref_manifest_guard_v1();

revoke all on function public.lf_solution_ref_manifest_guard_v1() from public;

create or replace function public.lf_resolve_solution_ref_origin_v1(p_solution_ref text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_ref text := nullif(btrim(p_solution_ref), '');
  v_exec public.lf_operation_execution%rowtype;
  v_lifecycle text;
  v_step public.lf_operation_steps%rowtype;
  v_step_status text;
begin
  if v_ref is null or v_ref !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' then
    return jsonb_build_object('valid', false, 'code', 'SOLUTION_REF_INVALID', 'solution_ref', v_ref);
  end if;

  select e.* into v_exec
  from public.lf_operation_execution e
  where e.manifest->>'solution_ref' = v_ref
  order by e.created_at, e.execution_id
  limit 1;

  if not found then
    return jsonb_build_object('valid', false, 'code', 'SOLUTION_REF_NOT_FOUND', 'solution_ref', v_ref);
  end if;

  if v_exec.status not in ('IN_PROGRESS', 'COMPLETED') then
    return jsonb_build_object('valid', false, 'code', 'SOLUTION_REF_ORIGIN_STATUS_INVALID', 'solution_ref', v_ref, 'origin_execution_id', v_exec.execution_id, 'origin_status', v_exec.status);
  end if;

  select r.lifecycle_state_code into v_lifecycle
  from public.lf_operation_registry r
  where r.operation_code = v_exec.operation_code;

  if v_lifecycle is distinct from 'OP_OPERATIONAL' then
    return jsonb_build_object('valid', false, 'code', 'SOLUTION_REF_ORIGIN_OPERATION_NOT_OPERATIONAL', 'solution_ref', v_ref, 'origin_execution_id', v_exec.execution_id, 'operation_code', v_exec.operation_code, 'lifecycle_state_code', v_lifecycle);
  end if;

  if v_exec.operation_code = 'GITHUB_CONTRACT_GATE_LF' then
    return jsonb_build_object('valid', false, 'code', 'SOLUTION_REF_ORIGIN_VERIFICATION_GATE_FORBIDDEN', 'solution_ref', v_ref, 'origin_execution_id', v_exec.execution_id);
  end if;

  select s.* into v_step
  from public.lf_operation_steps s
  where s.operation_code = v_exec.operation_code
    and s.active is true
  order by coalesce(s.execution_order, s.step_order), s.step_order, s.step_id
  limit 1;

  if not found then
    return jsonb_build_object('valid', false, 'code', 'SOLUTION_REF_ORIGIN_FIRST_STEP_MISSING', 'solution_ref', v_ref, 'origin_execution_id', v_exec.execution_id);
  end if;

  select es.status into v_step_status
  from public.lf_operation_execution_steps es
  where es.execution_id = v_exec.execution_id
    and es.step_order = v_step.step_order
    and es.step_id = v_step.step_id;

  if v_step_status is null or upper(v_step_status) !~ '(^|_)PASS($|_)' then
    return jsonb_build_object('valid', false, 'code', 'SOLUTION_REF_ORIGIN_FIRST_STEP_NOT_PASS', 'solution_ref', v_ref, 'origin_execution_id', v_exec.execution_id, 'first_step_id', v_step.step_id, 'first_step_status', v_step_status);
  end if;

  return jsonb_build_object(
    'valid', true,
    'code', 'SOLUTION_REF_ORIGIN_VALID',
    'solution_ref', v_ref,
    'origin_execution_id', v_exec.execution_id,
    'operation_code', v_exec.operation_code,
    'origin_status', v_exec.status,
    'first_step_id', v_step.step_id,
    'first_step_status', v_step_status
  );
end;
$function$;

revoke all on function public.lf_resolve_solution_ref_origin_v1(text) from public;

commit;
