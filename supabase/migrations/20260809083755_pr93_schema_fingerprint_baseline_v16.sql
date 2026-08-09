-- PR93 follow-up: rebaseline the one authorized notification delivery view change.
-- Forward-only. No application or historical notification rows are rewritten.

begin;

do $preflight$
declare
  v_drift_count bigint;
  v_unexpected_count bigint;
begin
  if to_regclass('private.lf_schema_fingerprint_baseline_v15') is null
     or to_regclass('public.v_lf_schema_fingerprint_drift_v15') is null
     or to_regclass('public.v_lf_architecture_closure_v4') is null then
    raise exception using
      errcode='55000',
      message='schema fingerprint baseline v15 and architecture closure v4 are required';
  end if;

  select count(*)
    into v_drift_count
  from public.v_lf_schema_fingerprint_drift_v15
  where drifted or missing;

  select count(*)
    into v_unexpected_count
  from public.v_lf_schema_fingerprint_drift_v15
  where (drifted or missing)
    and object_identity <> 'public.v_lf_architecture_notification_delivery_v4';

  if v_drift_count <> 1
     or v_unexpected_count <> 0
     or not exists (
       select 1
       from public.v_lf_schema_fingerprint_drift_v15
       where object_identity='public.v_lf_architecture_notification_delivery_v4'
         and drifted
         and not missing
     ) then
    raise exception using
      errcode='55000',
      message=format(
        'V16 preflight requires exactly one authorized drift on notification delivery view; drift=%s unexpected=%s',
        v_drift_count,
        v_unexpected_count
      );
  end if;

  if position(
       'v_lf_schema_fingerprint_drift_v15'
       in pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true)
     )=0 then
    raise exception using
      errcode='55000',
      message='architecture closure v4 does not reference fingerprint baseline v15';
  end if;
end
$preflight$;

create table private.lf_schema_fingerprint_baseline_v16 (
  object_identity text primary key,
  object_type text not null check (object_type in ('TABLE','VIEW','FUNCTION','TRIGGER','CRON_JOB','ROLE')),
  definition_sha256 text not null check (definition_sha256 ~ '^[0-9a-f]{64}$'),
  definition_snapshot text not null,
  baseline_execution_id text not null,
  baselined_at timestamptz not null default clock_timestamp()
);

create or replace function private.fn_guard_schema_fingerprint_baseline_v16()
returns trigger
language plpgsql
set search_path='pg_catalog'
as $function$
begin
  if current_user<>'postgres' then
    raise exception using
      errcode='42501',
      message='schema fingerprint baseline v16 accepts inserts only from governed maintenance';
  end if;
  if tg_op in ('UPDATE','DELETE') then
    raise exception using
      errcode='55000',
      message='schema fingerprint baseline v16 is append-only';
  end if;
  return new;
end;
$function$;

revoke all on function private.fn_guard_schema_fingerprint_baseline_v16() from public,anon,authenticated,service_role;

alter table private.lf_schema_fingerprint_baseline_v16 enable row level security;
alter table private.lf_schema_fingerprint_baseline_v16 force row level security;
revoke all on private.lf_schema_fingerprint_baseline_v16 from public,anon,authenticated,service_role;

create policy pol_lf_schema_fingerprint_baseline_v16_postgres
on private.lf_schema_fingerprint_baseline_v16
for all to postgres
using (true)
with check (true);

create trigger trg_00_guard_lf_schema_fingerprint_baseline_v16
before insert or update or delete on private.lf_schema_fingerprint_baseline_v16
for each row execute function private.fn_guard_schema_fingerprint_baseline_v16();

create or replace view public.v_lf_schema_fingerprint_drift_v16
with (security_invoker=true)
as
select
  b.object_identity,
  b.object_type,
  b.definition_sha256 baseline_sha256,
  encode(
    extensions.digest(
      convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),
      'sha256'
    ),
    'hex'
  ) current_sha256,
  private.fn_architecture_object_definition_v3(b.object_type,b.object_identity)='<missing>' missing,
  encode(
    extensions.digest(
      convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),
      'sha256'
    ),
    'hex'
  )<>b.definition_sha256 drifted
from private.lf_schema_fingerprint_baseline_v16 b
where b.object_identity not in (
  'public.v_lf_schema_fingerprint_drift_v16',
  'public.v_lf_architecture_closure_v4',
  'public.v_lf_architecture_closure_v5',
  'public.v_lf_architecture_closure_v6',
  'public.v_lf_architecture_closure_current'
);

revoke all on public.v_lf_schema_fingerprint_drift_v16 from anon,authenticated;

insert into private.lf_schema_fingerprint_baseline_v16(
  object_identity,
  object_type,
  definition_sha256,
  definition_snapshot,
  baseline_execution_id
)
select
  o.object_identity,
  o.object_type,
  encode(
    extensions.digest(
      convert_to(private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),
  'WORK-PR93-BASELINE-V16-20260809'
from (
  select object_identity,object_type
  from private.lf_schema_fingerprint_baseline_v15
  union
  select 'private.lf_schema_fingerprint_baseline_v16','TABLE'
  union
  select 'private.fn_guard_schema_fingerprint_baseline_v16()','FUNCTION'
  union
  select 'public.v_lf_schema_fingerprint_drift_v16','VIEW'
) o
order by o.object_type,o.object_identity;

do $activate$
declare
  def text;
begin
  select pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true)
    into def;

  if position('v_lf_schema_fingerprint_drift_v15' in def)=0 then
    raise exception using
      errcode='55000',
      message='architecture closure v4 no longer references fingerprint baseline v15';
  end if;

  def:=replace(
    def,
    'v_lf_schema_fingerprint_drift_v15',
    'v_lf_schema_fingerprint_drift_v16'
  );

  execute 'create or replace view public.v_lf_architecture_closure_v4 as '||def;
end
$activate$;

do $postflight$
declare
  v_expected_count bigint;
  v_observed_count bigint;
  v_drift_count bigint;
  v_baseline_sha text;
  v_current_sha text;
begin
  select count(*)+3
    into v_expected_count
  from private.lf_schema_fingerprint_baseline_v15;

  select count(*)
    into v_observed_count
  from private.lf_schema_fingerprint_baseline_v16;

  if v_observed_count<>v_expected_count then
    raise exception using
      errcode='55000',
      message=format(
        'baseline v16 count mismatch expected %s got %s',
        v_expected_count,
        v_observed_count
      );
  end if;

  select count(*)
    into v_drift_count
  from public.v_lf_schema_fingerprint_drift_v16
  where drifted or missing;

  if v_drift_count<>0 then
    raise exception using
      errcode='55000',
      message=format('baseline v16 unexpected drift count %s',v_drift_count);
  end if;

  if position(
       'v_lf_schema_fingerprint_drift_v16'
       in pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true)
     )=0 then
    raise exception using
      errcode='55000',
      message='architecture closure v4 did not switch to fingerprint baseline v16';
  end if;

  select definition_sha256
    into v_baseline_sha
  from private.lf_schema_fingerprint_baseline_v16
  where object_identity='public.v_lf_architecture_notification_delivery_v4'
    and object_type='VIEW';

  v_current_sha:=encode(
    extensions.digest(
      convert_to(
        private.fn_architecture_object_definition_v3(
          'VIEW',
          'public.v_lf_architecture_notification_delivery_v4'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  if v_baseline_sha is null or v_baseline_sha<>v_current_sha then
    raise exception using
      errcode='55000',
      message='notification delivery view fingerprint was not captured by baseline v16';
  end if;
end
$postflight$;

commit;
