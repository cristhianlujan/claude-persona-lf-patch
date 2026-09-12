create or replace function public.lf_operation_policy_snapshot_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_enforcement_at timestamptz;
  r record;
  v_current_sha text;
begin
  select
    count(*) filter (where b.required),
    min(v.effective_at) filter (where b.required)
  into v_required_count, v_enforcement_at
  from public.lf_operation_policy_bindings b
  join public.lf_policy_versions v
    on v.policy_code = b.policy_code
   and v.status = 'ACTIVE'
  where b.operation_code = new.operation_code
    and b.binding_status = 'ACTIVE';

  if old.manifest ? 'operation_policy_snapshots'
     and (old.manifest->'operation_policy_snapshots') is distinct from (new.manifest->'operation_policy_snapshots') then
    raise exception 'BLOCK_POLICY_SNAPSHOT_IMMUTABLE execution=% operation=%', new.execution_id, new.operation_code;
  end if;

  if new.status is distinct from old.status and v_required_count > 0 then
    if not (new.manifest ? 'operation_policy_snapshots') then
      if v_enforcement_at is not null and old.started_at < v_enforcement_at then
        return new;
      end if;
      raise exception 'BLOCK_PROFILE_UPDATE_POLICY_MISSING execution=% operation=%', new.execution_id, new.operation_code;
    end if;

    for r in
      select key as policy_role, value as snapshot
      from jsonb_each(new.manifest->'operation_policy_snapshots')
    loop
      select v.policy_sha into v_current_sha
      from public.lf_operation_policy_bindings b
      join public.lf_policy_versions v
        on v.policy_code = b.policy_code
       and v.status = 'ACTIVE'
      where b.operation_code = new.operation_code
        and b.policy_role = r.policy_role
        and b.binding_status = 'ACTIVE';

      if v_current_sha is null then
        raise exception 'BLOCK_PROFILE_UPDATE_POLICY_MISSING execution=% role=%', new.execution_id, r.policy_role;
      end if;

      if v_current_sha <> (r.snapshot->>'policy_sha') then
        raise exception 'BLOCK_STALE_PROFILE_UPDATE_POLICY execution=% role=% snapshot_sha=% current_sha=%',
          new.execution_id, r.policy_role, r.snapshot->>'policy_sha', v_current_sha;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

revoke all on function public.lf_operation_policy_snapshot_guard_v1() from public, anon, authenticated;
