-- Strategy 28 / P3 sandbox-only runtime canary switch.
-- Exact-version source-first migration. No production authorization. No merge implied.
-- Switches the single governed currentness call in fn_input_governance_execute
-- from cached_v1 to the already-proven cached_v2 candidate.
do $migration$
declare
  v_def text;
  v_new text;
  v_candidate_sha text;
  v_v1_count integer;
  v_v2_count integer;
begin
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into v_def;

  if encode(extensions.digest(convert_to(v_def,'UTF8'),'sha256'),'hex')
     <> '3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588' then
    raise exception 'S28_CACHED_V2_SWITCH_EXECUTE_SOURCE_DRIFT';
  end if;

  select encode(extensions.digest(
           convert_to(pg_get_functiondef('programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure),'UTF8'),
           'sha256'),'hex')
    into v_candidate_sha;

  if v_candidate_sha <> '4a1c9f5446c321dac97b5a0bfe5c5e4d5c359b3317d228a67fd17b619bc3899a' then
    raise exception 'S28_CACHED_V2_SWITCH_CANDIDATE_SOURCE_DRIFT:%',v_candidate_sha;
  end if;

  v_v1_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v1','')))
    / length('fn_input_readiness_run_is_current_cached_v1');
  v_v2_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v2','')))
    / length('fn_input_readiness_run_is_current_cached_v2');

  if v_v1_count <> 1 or v_v2_count <> 0 then
    raise exception 'S28_CACHED_V2_SWITCH_BINDING_PRECONDITION_FAILED:v1=% v2=%',v_v1_count,v_v2_count;
  end if;

  v_new := replace(
    v_def,
    'fn_input_readiness_run_is_current_cached_v1',
    'fn_input_readiness_run_is_current_cached_v2'
  );

  if encode(extensions.digest(
       convert_to(replace(v_new,'fn_input_readiness_run_is_current_cached_v2','fn_input_readiness_run_is_current_cached_v1'),'UTF8'),
       'sha256'),'hex')
     <> '3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588' then
    raise exception 'S28_CACHED_V2_SWITCH_REVERSIBILITY_GUARD_FAILED';
  end if;

  execute v_new;

  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into v_def;

  v_v1_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v1','')))
    / length('fn_input_readiness_run_is_current_cached_v1');
  v_v2_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v2','')))
    / length('fn_input_readiness_run_is_current_cached_v2');

  if v_v1_count <> 0 or v_v2_count <> 1 then
    raise exception 'S28_CACHED_V2_SWITCH_POSTCONDITION_FAILED:v1=% v2=%',v_v1_count,v_v2_count;
  end if;

  raise notice 'S28_CACHED_V2_SANDBOX_SWITCH_PASS';
end;
$migration$;
