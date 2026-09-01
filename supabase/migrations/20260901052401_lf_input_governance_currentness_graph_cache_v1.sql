do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'::regprocedure) into v_def;
  if position('v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);' in v_def)=0 then
    raise exception 'CLASSIFY_V1_GRAPH_CALL_BASELINE_NOT_FOUND';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);',
    'v_graph:=p_graph;');
  if position('fn_input_governance_bootstrap_classify_v1_cached_v1' in v_def)=0 or position('v_graph:=p_graph;' in v_def)=0 then
    raise exception 'CLASSIFY_V1_CACHE_PATCH_FAILED';
  end if;
  execute v_def;

  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure) into v_def;
  if position('v:=programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,p_family_code,p_version_id);' in v_def)=0 then
    raise exception 'CLASSIFY_V2_V1_CALL_BASELINE_NOT_FOUND';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v:=programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,p_family_code,p_version_id);',
    'v:=programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);');
  if position('fn_input_governance_bootstrap_classify_v2_cached_v1' in v_def)=0 or position('fn_input_governance_bootstrap_classify_v1_cached_v1' in v_def)=0 then
    raise exception 'CLASSIFY_V2_CACHE_PATCH_FAILED';
  end if;
  execute v_def;

  select pg_get_functiondef('programacion.fn_input_readiness_run_is_current(bigint)'::regprocedure) into v_def;
  if position('v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,v_assessment.family_code,v_run.version_id);' in v_def)=0 then
    raise exception 'CURRENTNESS_CLASSIFIER_BASELINE_NOT_FOUND';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_readiness_run_is_current(p_run_id bigint)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_readiness_run_is_current_cached_v1(p_run_id bigint)');
  v_def:=replace(v_def,
    '  v_current_manifest jsonb;',
    E'  v_current_manifest jsonb;\n  v_current_graph jsonb;');
  v_def:=replace(v_def,
    '    for v_assessment in',
    E'    v_current_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_run.version_id);\n    for v_assessment in');
  v_def:=replace(v_def,
    'v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,v_assessment.family_code,v_run.version_id);',
    'v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(v_pantalla_id,v_assessment.family_code,v_run.version_id,v_current_graph);');
  if position('fn_input_readiness_run_is_current_cached_v1' in v_def)=0 or position('v_current_graph' in v_def)=0 or position('fn_input_governance_bootstrap_classify_v2_cached_v1' in v_def)=0 then
    raise exception 'CURRENTNESS_CACHE_PATCH_FAILED';
  end if;
  execute v_def;
end;
$migration$;

revoke all on function programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_readiness_run_is_current_cached_v1(bigint) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_readiness_run_is_current_cached_v1(bigint) to service_role;