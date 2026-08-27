create or replace function public.lf_attach_operation_policy_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_snapshots jsonb;
begin
  select
    count(*) filter (where b.required),
    count(*) filter (where b.required and v.policy_code is not null)
  into v_required_count, v_resolved_required_count
  from public.lf_operation_policy_bindings b
  left join public.lf_policy_versions v
    on v.policy_code = b.policy_code
   and v.status = 'ACTIVE'
  where b.operation_code = new.operation_code
    and b.binding_status = 'ACTIVE';

  if v_required_count > v_resolved_required_count then
    raise exception 'BLOCK_PROFILE_UPDATE_POLICY_MISSING operation=% required=% resolved=%',
      new.operation_code, v_required_count, v_resolved_required_count;
  end if;

  select jsonb_object_agg(
    b.policy_role,
    jsonb_build_object(
      'policy_code', b.policy_code,
      'policy_version', v.policy_version,
      'policy_sha', v.policy_sha,
      'policy_payload', v.policy_payload,
      'distribution_modes', to_jsonb(b.distribution_modes),
      'effective_at', v.effective_at,
      'source_ref', v.source_ref
    )
  )
  into v_snapshots
  from public.lf_operation_policy_bindings b
  join public.lf_policy_versions v
    on v.policy_code = b.policy_code
   and v.status = 'ACTIVE'
  where b.operation_code = new.operation_code
    and b.binding_status = 'ACTIVE';

  if v_snapshots is not null then
    new.manifest := coalesce(new.manifest, '{}'::jsonb) || jsonb_build_object(
      'operation_policy_snapshots', v_snapshots,
      'operation_policy_snapshot_at', now(),
      'operation_policy_source', 'SUPABASE'
    );
  end if;

  return new;
end;
$$;

revoke all on function public.lf_attach_operation_policy_snapshot_v1() from public, anon, authenticated;

drop trigger if exists trg_00_lf_operation_policy_snapshot_v1 on public.lf_operation_execution;
create trigger trg_00_lf_operation_policy_snapshot_v1
before insert on public.lf_operation_execution
for each row execute function public.lf_attach_operation_policy_snapshot_v1();

create or replace function public.lf_operation_policy_snapshot_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  r record;
  v_current_sha text;
begin
  select count(*) into v_required_count
  from public.lf_operation_policy_bindings b
  where b.operation_code = new.operation_code
    and b.binding_status = 'ACTIVE'
    and b.required;

  if old.manifest ? 'operation_policy_snapshots'
     and (old.manifest->'operation_policy_snapshots') is distinct from (new.manifest->'operation_policy_snapshots') then
    raise exception 'BLOCK_POLICY_SNAPSHOT_IMMUTABLE execution=% operation=%', new.execution_id, new.operation_code;
  end if;

  if new.status is distinct from old.status and v_required_count > 0 then
    if not (new.manifest ? 'operation_policy_snapshots') then
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

drop trigger if exists trg_01_lf_operation_policy_snapshot_guard_v1 on public.lf_operation_execution;
create trigger trg_01_lf_operation_policy_snapshot_guard_v1
before update of status, manifest on public.lf_operation_execution
for each row execute function public.lf_operation_policy_snapshot_guard_v1();
