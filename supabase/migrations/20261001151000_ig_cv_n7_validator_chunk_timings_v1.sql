-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L2 · N-7 / PAULO-172
-- Persist deterministic timing for every validator RPC chunk without creating a parallel runtime.

create table programacion.input_validator_chunk_timings(
  id bigint generated always as identity primary key,
  run_id bigint not null references programacion.input_readiness_runs(id) on delete restrict,
  validator_identity text not null,
  chunk_no integer not null check(chunk_no>0),
  route text not null check(route in ('VALIDATE_V2','BOOTSTRAP_VALIDATE_V1','VALIDATOR_REBIND_V1')),
  started_at timestamptz not null,
  completed_at timestamptz not null,
  duration_ms bigint not null check(duration_ms>=0),
  result_status text,
  validator_pass_count integer,
  family_count integer,
  pending_count integer,
  created_at timestamptz not null default now(),
  unique(run_id,validator_identity,chunk_no)
);

comment on table programacion.input_validator_chunk_timings is
  'N-7: per-call validator chunk timing projected by the existing governed validator dispatcher.';

do $migration$
declare
  v_def text;
begin
  v_def:=pg_get_functiondef('programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure);
  if md5(v_def)<>'ec782276102acf3376f30b0136b71314' then
    raise exception 'N7_VALIDATOR_WRAPPER_BASELINE_DRIFT:%',md5(v_def);
  end if;
end;
$migration$;

create or replace function programacion.fn_input_governance_validator_validate_v1(p_run_id bigint,p_validator_identity text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_analysis text;
  v_bootstrap boolean;
  v_result jsonb;
  v_started timestamptz:=clock_timestamp();
  v_completed timestamptz;
  v_route text;
  v_chunk_no integer;
begin
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended('IG_VALIDATOR_CHUNK:'||p_run_id::text||':'||coalesce(p_validator_identity,''),0));
  select scope->>'analysis_revision',supersedes_run_id is null and scope->>'mode'='GOVERNED_CANONICAL_BOOTSTRAP_V1'
    into v_analysis,v_bootstrap
  from programacion.input_readiness_runs
  where id=p_run_id and version_id=19;

  if v_analysis='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX' then
    v_route:='VALIDATE_V2';
    v_result:=programacion.fn_input_governance_validate_v2(p_run_id,p_validator_identity);
  elsif coalesce(v_bootstrap,false) then
    v_route:='BOOTSTRAP_VALIDATE_V1';
    v_result:=programacion.fn_input_governance_bootstrap_validate_v1(p_run_id,p_validator_identity);
  else
    v_route:='VALIDATOR_REBIND_V1';
    v_result:=programacion.fn_input_governance_validator_rebind_v1(p_run_id,p_validator_identity);
  end if;

  v_completed:=clock_timestamp();
  select coalesce(max(chunk_no),0)+1 into v_chunk_no
  from programacion.input_validator_chunk_timings
  where run_id=p_run_id and validator_identity=p_validator_identity;

  insert into programacion.input_validator_chunk_timings(
    run_id,validator_identity,chunk_no,route,started_at,completed_at,duration_ms,
    result_status,validator_pass_count,family_count,pending_count
  ) values(
    p_run_id,p_validator_identity,v_chunk_no,v_route,v_started,v_completed,
    round(extract(epoch from(v_completed-v_started))*1000)::bigint,
    v_result->>'status',nullif(v_result->>'validator_pass_count','')::integer,
    nullif(v_result->>'family_count','')::integer,nullif(v_result->>'pending_count','')::integer
  );
  return v_result;
end;
$function$;

comment on function programacion.fn_input_governance_validator_validate_v1(bigint,text) is
  'N-7: existing validator dispatch wrapper plus persisted per-call chunk timing; validation semantics unchanged.';
