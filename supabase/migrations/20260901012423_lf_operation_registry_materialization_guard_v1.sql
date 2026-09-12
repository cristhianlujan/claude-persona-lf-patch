create or replace function public.fn_lf_operation_registry_materialization_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_lifecycle_required boolean;
  v_required_steps integer;
  v_active_contracts integer;
  v_active_bindings integer;
  v_active_bound_judges integer;
begin
  if new.status <> 'PRODUCCION_CONTROLADA' then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  select exists (
    select 1
    from public.lf_operation_policy_bindings p
    where p.operation_code = new.operation_code
      and p.policy_role = 'GOVERNANCE_LIFECYCLE'
      and p.required = true
      and p.binding_status = 'ACTIVE'
  ) into v_lifecycle_required;

  if not v_lifecycle_required then
    return new;
  end if;

  select count(*) into v_required_steps
  from public.lf_operation_steps s
  where s.operation_code = new.operation_code and s.required = true;

  if v_required_steps = 0 then
    raise exception 'LF_OPERATION_MATERIALIZATION_REQUIRED_STEPS_MISSING:%', new.operation_code using errcode = '23514';
  end if;

  select count(*) into v_active_contracts
  from public.lf_operation_steps s
  join public.lf_operation_step_contracts c
    on c.operation_code = s.operation_code and c.step_order = s.step_order and c.step_id = s.step_id and c.status = 'ACTIVE_ENFORCEMENT'
  where s.operation_code = new.operation_code and s.required = true;

  if v_active_contracts <> v_required_steps then
    raise exception 'LF_OPERATION_MATERIALIZATION_CONTRACT_GAP:%:%:%', new.operation_code, v_active_contracts, v_required_steps using errcode = '23514';
  end if;

  select count(*), count(*) filter (where j.judge_code is not null)
    into v_active_bindings, v_active_bound_judges
  from public.lf_operation_steps s
  join public.lf_operation_step_judge_bindings b
    on b.operation_code = s.operation_code and b.step_order = s.step_order and b.step_id = s.step_id and b.status = 'ACTIVE_ENFORCEMENT'
  left join public.lf_operation_judges j
    on j.operation_code = b.operation_code and j.judge_code = b.judge_code and j.status = 'ACTIVE_ENFORCEMENT'
  where s.operation_code = new.operation_code and s.required = true;

  if v_active_bindings <> v_required_steps or v_active_bound_judges <> v_required_steps then
    raise exception 'LF_OPERATION_MATERIALIZATION_JUDGE_GAP:%:%:%:%', new.operation_code, v_active_bindings, v_active_bound_judges, v_required_steps using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.fn_lf_operation_registry_materialization_guard_v1() is
'Fail-closed promotion guard for operations governed by an ACTIVE required GOVERNANCE_LIFECYCLE policy. A transition to PRODUCCION_CONTROLADA requires every required step to have an ACTIVE_ENFORCEMENT contract and an ACTIVE_ENFORCEMENT binding to an active judge.';

revoke execute on function public.fn_lf_operation_registry_materialization_guard_v1() from public, anon, authenticated;

drop trigger if exists trg_lf_operation_registry_materialization_guard_v1 on public.lf_operation_registry;
create trigger trg_lf_operation_registry_materialization_guard_v1
before insert or update of status on public.lf_operation_registry
for each row execute function public.fn_lf_operation_registry_materialization_guard_v1();