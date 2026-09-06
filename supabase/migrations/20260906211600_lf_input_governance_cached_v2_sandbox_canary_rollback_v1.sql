-- Strategy 28 / P3 sandbox-only automatic rollback.
-- Exact-version source-first rollback paired with 20260906211500.
-- Restores fn_input_governance_execute to the exact pre-canary cached_v1 source.
do $rollback$
declare
  v_def text;
  v_back text;
  v_v1_count integer;
  v_v2_count integer;
begin
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into v_def;

  v_v1_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v1','')))
    / length('fn_input_readiness_run_is_current_cached_v1');
  v_v2_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v2','')))
    / length('fn_input_readiness_run_is_current_cached_v2');

  if v_v1_count <> 0 or v_v2_count <> 1 then
    raise exception 'S28_CACHED_V2_ROLLBACK_BINDING_PRECONDITION_FAILED:v1=% v2=%',v_v1_count,v_v2_count;
  end if;

  v_back := replace(
    v_def,
    'fn_input_readiness_run_is_current_cached_v2',
    'fn_input_readiness_run_is_current_cached_v1'
  );

  if encode(extensions.digest(convert_to(v_back,'UTF8'),'sha256'),'hex')
     <> '3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588' then
    raise exception 'S28_CACHED_V2_ROLLBACK_EXACT_SOURCE_GUARD_FAILED';
  end if;

  execute v_back;

  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into v_def;

  if encode(extensions.digest(convert_to(v_def,'UTF8'),'sha256'),'hex')
     <> '3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588' then
    raise exception 'S28_CACHED_V2_ROLLBACK_POSTCONDITION_HASH_FAILED';
  end if;

  v_v1_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v1','')))
    / length('fn_input_readiness_run_is_current_cached_v1');
  v_v2_count :=
    (length(v_def)-length(replace(v_def,'fn_input_readiness_run_is_current_cached_v2','')))
    / length('fn_input_readiness_run_is_current_cached_v2');

  if v_v1_count <> 1 or v_v2_count <> 0 then
    raise exception 'S28_CACHED_V2_ROLLBACK_POSTCONDITION_BINDING_FAILED:v1=% v2=%',v_v1_count,v_v2_count;
  end if;

  raise notice 'S28_CACHED_V2_SANDBOX_ROLLBACK_PASS';
end;
$rollback$;
-- Trigger exact-version canary after workflow hardening; semantic SQL unchanged.
