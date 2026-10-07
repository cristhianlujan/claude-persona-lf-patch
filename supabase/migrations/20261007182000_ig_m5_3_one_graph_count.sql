-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.3 / ONE_GRAPH_COUNT
-- Request-local instrumentation for actual canonical graph builds and freshness calls.
-- No new authority object: counters live only for the request transaction and are
-- returned in request_context_summary for observable per-request evidence.

do $preflight$
declare
  v_graph_def text;
  v_fresh_def text;
  v_materializer_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure
  ) into v_graph_def;
  select pg_get_functiondef(
    'programacion.fn_input_freshness_delta(bigint)'::regprocedure
  ) into v_fresh_def;
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_materializer_def;

  if position('lf.input_request_graph_build_count_v1' in v_graph_def)>0
     or position('lf.input_request_freshness_count_v1' in v_fresh_def)>0
     or position('graph_build_count' in v_materializer_def)>0 then
    raise exception 'M5_3_ONE_GRAPH_COUNT_ALREADY_APPLIED';
  end if;

  if position('return v_cached_graph;' in v_graph_def)=0
     or position('v_stale_reason text;' in v_fresh_def)=0
     or position('request_context_summary' in v_materializer_def)=0 then
    raise exception 'M5_3_ONE_GRAPH_COUNT_ANCHOR_DRIFT';
  end if;
end;
$preflight$;

do $migration$
declare
  v_def text;
begin
  -- A. Count only real canonical graph construction, never cache reuse.
  select pg_get_functiondef(
    'programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure
  ) into v_def;

  v_def:=replace(
    v_def,
    E'  v_cached_graph_sha text;\n',
    E'  v_cached_graph_sha text;\n'
    || E'  v_request_graph_build_count integer;\n'
  );

  v_def:=replace(
    v_def,
    E'    return v_cached_graph;\n  end if;\n  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code',
    E'    return v_cached_graph;\n'
    || E'  end if;\n'
    || E'  v_request_graph_build_count:=coalesce(nullif(current_setting(''lf.input_request_graph_build_count_v1'',true),'''')::integer,0);\n'
    || E'  perform set_config(''lf.input_request_graph_build_count_v1'',(v_request_graph_build_count+1)::text,true);\n'
    || E'  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code'
  );

  execute v_def;

  -- B. Count each freshness evaluation in the same request transaction.
  select pg_get_functiondef(
    'programacion.fn_input_freshness_delta(bigint)'::regprocedure
  ) into v_def;

  v_def:=replace(
    v_def,
    E'  v_stale_reason text;\n',
    E'  v_stale_reason text;\n'
    || E'  v_request_freshness_count integer;\n'
  );

  v_def:=replace(
    v_def,
    E'begin\n  select * into v_run from programacion.input_readiness_runs where id=p_run_id;',
    E'begin\n'
    || E'  v_request_freshness_count:=coalesce(nullif(current_setting(''lf.input_request_freshness_count_v1'',true),'''')::integer,0);\n'
    || E'  perform set_config(''lf.input_request_freshness_count_v1'',(v_request_freshness_count+1)::text,true);\n'
    || E'  select * into v_run from programacion.input_readiness_runs where id=p_run_id;'
  );

  execute v_def;

  -- C. Reset counters at request boundary, reject duplicate work, expose evidence.
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_def;

  v_def:=replace(
    v_def,
    E'  v_result jsonb;\n',
    E'  v_result jsonb;\n'
    || E'  v_graph_build_count integer;\n'
    || E'  v_freshness_count integer;\n'
  );

  v_def:=replace(
    v_def,
    E'begin\n  select c.version_id into v_version',
    E'begin\n'
    || E'  perform set_config(''lf.input_request_graph_build_count_v1'',''0'',true);\n'
    || E'  perform set_config(''lf.input_request_freshness_count_v1'',''0'',true);\n'
    || E'  select c.version_id into v_version'
  );

  v_def:=replace(
    v_def,
    E'  perform set_config(''lf.input_request_context_v1'','''',true);\n  return v_result || jsonb_build_object(\n    ''request_context_summary'',jsonb_build_object(\n      ''schema_version'',''INPUT_GOVERNANCE_REQUEST_CONTEXT_V1'',\n',
    E'  v_graph_build_count:=coalesce(nullif(current_setting(''lf.input_request_graph_build_count_v1'',true),'''')::integer,0);\n'
    || E'  v_freshness_count:=coalesce(nullif(current_setting(''lf.input_request_freshness_count_v1'',true),'''')::integer,0);\n'
    || E'  if v_graph_build_count<>1 then\n'
    || E'    raise exception ''INPUT_REQUEST_GRAPH_BUILD_COUNT_INVALID:%:%'',p_pantalla_id,v_graph_build_count;\n'
    || E'  end if;\n'
    || E'  if v_freshness_count>1 then\n'
    || E'    raise exception ''INPUT_REQUEST_FRESHNESS_COUNT_INVALID:%:%'',p_pantalla_id,v_freshness_count;\n'
    || E'  end if;\n'
    || E'  perform set_config(''lf.input_request_context_v1'','''',true);\n'
    || E'  perform set_config(''lf.input_request_graph_build_count_v1'','''',true);\n'
    || E'  perform set_config(''lf.input_request_freshness_count_v1'','''',true);\n'
    || E'  return v_result || jsonb_build_object(\n'
    || E'    ''request_context_summary'',jsonb_build_object(\n'
    || E'      ''schema_version'',''INPUT_GOVERNANCE_REQUEST_CONTEXT_V1'',\n'
    || E'      ''graph_build_count'',v_graph_build_count,\n'
    || E'      ''freshness_delta_count'',v_freshness_count,\n'
    || E'      ''graph_build_exactly_once'',v_graph_build_count=1,\n'
    || E'      ''freshness_at_most_once'',v_freshness_count<=1,\n'
  );

  v_def:=replace(
    v_def,
    E'exception when others then\n  perform set_config(''lf.input_request_context_v1'','''',true);\n  raise;',
    E'exception when others then\n'
    || E'  perform set_config(''lf.input_request_context_v1'','''',true);\n'
    || E'  perform set_config(''lf.input_request_graph_build_count_v1'','''',true);\n'
    || E'  perform set_config(''lf.input_request_freshness_count_v1'','''',true);\n'
    || E'  raise;'
  );

  execute v_def;
end;
$migration$;

comment on function programacion.fn_input_screen_canonical_graph(integer,bigint)
is 'Canonical graph with fail-closed request-local reuse and request-local actual-build counter; M5.3.';

comment on function programacion.fn_input_freshness_delta(bigint)
is 'Freshness delta with request-local invocation counter for duplicate-work detection; M5.3.';

comment on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)
is 'Curator dispatcher with one request-local graph build, at-most-one freshness evaluation, and observable request_context_summary counters; M5.3.';

do $verify$
declare
  v_graph_def text;
  v_fresh_def text;
  v_materializer_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure
  ) into v_graph_def;
  select pg_get_functiondef(
    'programacion.fn_input_freshness_delta(bigint)'::regprocedure
  ) into v_fresh_def;
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_materializer_def;

  if position('lf.input_request_graph_build_count_v1' in v_graph_def)=0
     or position('(v_request_graph_build_count+1)::text' in v_graph_def)=0 then
    raise exception 'M5_3_GRAPH_COUNTER_MISSING';
  end if;

  if position('lf.input_request_freshness_count_v1' in v_fresh_def)=0
     or position('(v_request_freshness_count+1)::text' in v_fresh_def)=0 then
    raise exception 'M5_3_FRESHNESS_COUNTER_MISSING';
  end if;

  if position('graph_build_count' in v_materializer_def)=0
     or position('freshness_delta_count' in v_materializer_def)=0
     or position('INPUT_REQUEST_GRAPH_BUILD_COUNT_INVALID' in v_materializer_def)=0
     or position('INPUT_REQUEST_FRESHNESS_COUNT_INVALID' in v_materializer_def)=0 then
    raise exception 'M5_3_REQUEST_COUNTER_CONTRACT_MISSING';
  end if;
end;
$verify$;
