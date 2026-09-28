-- Allow the governed V7 evidence owner to evaluate the closed-strategy event guard.
-- Minimal privilege only: SELECT + RLS visibility on public.lf_strategy_snapshots.
-- No write privilege is granted.

begin;

do $preflight$
begin
  if to_regrole('lf_governance_owner_v3') is null then
    raise exception 'LF_GOVERNANCE_OWNER_V3_MISSING';
  end if;

  if to_regclass('public.lf_strategy_snapshots') is null then
    raise exception 'LF_STRATEGY_SNAPSHOTS_MISSING';
  end if;

  if to_regprocedure('private.fn_lf_strategy_closed_event_stream_guard_v1()') is null then
    raise exception 'LF_STRATEGY_CLOSED_EVENT_GUARD_MISSING';
  end if;
end;
$preflight$;

grant select on table public.lf_strategy_snapshots
  to lf_governance_owner_v3;

drop policy if exists lf_governance_owner_select_strategy_snapshots_v1
  on public.lf_strategy_snapshots;

create policy lf_governance_owner_select_strategy_snapshots_v1
  on public.lf_strategy_snapshots
  for select
  to lf_governance_owner_v3
  using (true);

do $postconditions$
declare
  v_policy_count integer;
begin
  if has_table_privilege(
    'lf_governance_owner_v3',
    'public.lf_strategy_snapshots',
    'SELECT'
  ) is not true then
    raise exception 'LF_STRATEGY_SNAPSHOT_GOV_OWNER_SELECT_NOT_GRANTED';
  end if;

  if has_table_privilege(
    'lf_governance_owner_v3',
    'public.lf_strategy_snapshots',
    'INSERT'
  ) or has_table_privilege(
    'lf_governance_owner_v3',
    'public.lf_strategy_snapshots',
    'UPDATE'
  ) or has_table_privilege(
    'lf_governance_owner_v3',
    'public.lf_strategy_snapshots',
    'DELETE'
  ) then
    raise exception 'LF_STRATEGY_SNAPSHOT_GOV_OWNER_WRITE_PRIVILEGE_UNEXPECTED';
  end if;

  select count(*)
    into v_policy_count
  from pg_policies
  where schemaname='public'
    and tablename='lf_strategy_snapshots'
    and policyname='lf_governance_owner_select_strategy_snapshots_v1'
    and cmd='SELECT'
    and roles @> array['lf_governance_owner_v3']::name[]
    and qual='true';

  if v_policy_count<>1 then
    raise exception
      'LF_STRATEGY_SNAPSHOT_GOV_OWNER_RLS_POLICY_INVALID count=%',
      v_policy_count;
  end if;
end;
$postconditions$;

commit;
