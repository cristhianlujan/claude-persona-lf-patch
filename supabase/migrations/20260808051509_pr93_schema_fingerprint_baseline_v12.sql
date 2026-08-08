-- LF_MIGRATION_SOURCE_CHECKPOINT_V1 cutover=20260808031006 legacy_start=20260801063708 legacy_end=20260801170332 legacy_count=112 legacy_sha256=6307389994425b00f0b7f3c59c00f2c531af0d37f7041d96756e5aaf9aa9907a
begin;

create table private.lf_schema_fingerprint_baseline_v12 (
  object_identity text primary key,
  object_type text not null check (object_type in ('TABLE','VIEW','FUNCTION','TRIGGER','CRON_JOB','ROLE')),
  definition_sha256 text not null check (definition_sha256 ~ '^[0-9a-f]{64}$'),
  definition_snapshot text not null,
  baseline_execution_id text not null,
  baselined_at timestamptz not null default clock_timestamp()
);

create or replace function private.fn_guard_schema_fingerprint_baseline_v12()
returns trigger
language plpgsql
set search_path='pg_catalog'
as $function$
begin
  if current_user<>'postgres' then
    raise exception using errcode='42501',message='schema fingerprint baseline v12 accepts inserts only from governed maintenance';
  end if;
  if tg_op in ('UPDATE','DELETE') then
    raise exception using errcode='55000',message='schema fingerprint baseline v12 is append-only';
  end if;
  return new;
end;
$function$;

revoke all on function private.fn_guard_schema_fingerprint_baseline_v12() from public,anon,authenticated,service_role;

alter table private.lf_schema_fingerprint_baseline_v12 enable row level security;
alter table private.lf_schema_fingerprint_baseline_v12 force row level security;
revoke all on private.lf_schema_fingerprint_baseline_v12 from public,anon,authenticated,service_role;

create policy pol_lf_schema_fingerprint_baseline_v12_postgres
on private.lf_schema_fingerprint_baseline_v12 for all to postgres using (true) with check (true);

create trigger trg_00_guard_lf_schema_fingerprint_baseline_v12
before insert or update or delete on private.lf_schema_fingerprint_baseline_v12
for each row execute function private.fn_guard_schema_fingerprint_baseline_v12();

create or replace view public.v_lf_schema_fingerprint_drift_v12
with (security_invoker=true)
as
select b.object_identity,b.object_type,b.definition_sha256 baseline_sha256,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),'sha256'),'hex') current_sha256,
       private.fn_architecture_object_definition_v3(b.object_type,b.object_identity)='<missing>' missing,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),'sha256'),'hex')<>b.definition_sha256 drifted
from private.lf_schema_fingerprint_baseline_v12 b
where b.object_identity not in (
  'public.v_lf_schema_fingerprint_drift_v12',
  'public.v_lf_architecture_closure_v4',
  'public.v_lf_architecture_closure_v5',
  'public.v_lf_architecture_closure_v6',
  'public.v_lf_architecture_closure_current'
);

revoke all on public.v_lf_schema_fingerprint_drift_v12 from anon,authenticated;

insert into private.lf_schema_fingerprint_baseline_v12(
  object_identity,object_type,definition_sha256,definition_snapshot,baseline_execution_id
)
select o.object_identity,o.object_type,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),'UTF8'),'sha256'),'hex'),
       private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),
       'WORK-PR93-BASELINE-V12-20260808'
from (
  select object_identity,object_type from private.lf_schema_fingerprint_baseline_v11
  union
  select 'private.lf_schema_fingerprint_baseline_v12','TABLE'
  union
  select 'private.fn_guard_schema_fingerprint_baseline_v12()','FUNCTION'
  union
  select 'public.v_lf_schema_fingerprint_drift_v12','VIEW'
) o
order by o.object_type,o.object_identity;

do $activate$
declare
  def text;
begin
  select pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true) into def;
  if position('v_lf_schema_fingerprint_drift_v11' in def)=0 then
    raise exception 'closure v4 does not reference v11';
  end if;
  def:=replace(def,'v_lf_schema_fingerprint_drift_v11','v_lf_schema_fingerprint_drift_v12');
  execute 'create or replace view public.v_lf_architecture_closure_v4 as '||def;
end;
$activate$;

do $assertions$
declare
  expected_count bigint;
  observed_count bigint;
  drift_count bigint;
begin
  select count(*)+3 into expected_count from private.lf_schema_fingerprint_baseline_v11;
  select count(*) into observed_count from private.lf_schema_fingerprint_baseline_v12;
  if observed_count<>expected_count then
    raise exception 'baseline v12 count mismatch expected %, got %',expected_count,observed_count;
  end if;
  select count(*) into drift_count from public.v_lf_schema_fingerprint_drift_v12 where drifted or missing;
  if drift_count<>0 then
    raise exception 'baseline v12 unexpected drift count %',drift_count;
  end if;
  if position('v_lf_schema_fingerprint_drift_v12' in pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true))=0 then
    raise exception 'closure v4 did not switch to baseline v12';
  end if;
end;
$assertions$;

commit;

