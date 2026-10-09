
do $patch$
declare
  v_def text;
  v_new text;
begin
  v_def:=pg_get_functiondef('programacion.fn_input_governance_recurate_v2(integer,text,text)'::regprocedure);

  if md5(v_def) <> '5945edb811c12b3f92b7073b11146714' then
    raise exception 'M49_RECURATE_CACHE_PREIMAGE_DRIFT expected=% actual=%',
      '5945edb811c12b3f92b7073b11146714',md5(v_def);
  end if;

  if position('fn_input_governance_bootstrap_classify_v2_cached_v2' in v_def)>0 then
    raise exception 'M49_RECURATE_CACHE_ALREADY_PRESENT';
  end if;

  v_new:=replace(
    v_def,
    'v_class jsonb; v_count int; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb;',
    'v_class jsonb; v_graph jsonb; v_count int; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb;'
  );

  v_new:=replace(
    v_new,
    '  for v_family in select value from jsonb_array_elements_text((select valor_config->''families'' from lf_ops.reglas where codigo=''B2B-RULE-STORY-READINESS-001'')) loop',
    '  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);' || E'\n' ||
    '  for v_family in select value from jsonb_array_elements_text((select valor_config->''families'' from lf_ops.reglas where codigo=''B2B-RULE-STORY-READINESS-001'')) loop'
  );

  v_new:=replace(
    v_new,
    'v_class:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version);',
    'v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);'
  );

  if v_new=v_def
     or position('v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);' in v_new)=0
     or position('fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph)' in v_new)=0
     or position('pg_advisory_xact_lock' in v_new)=0 then
    raise exception 'M49_RECURATE_CACHE_PATCH_CONSTRUCTION_FAILED';
  end if;

  execute v_new;
end;
$patch$;

do $verify$
declare
  v_def text;
begin
  v_def:=pg_get_functiondef('programacion.fn_input_governance_recurate_v2(integer,text,text)'::regprocedure);

  if position('fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version)' in v_def)>0 then
    raise exception 'M49_RECURATE_CACHE_UNCACHED_CALL_REMAINS';
  end if;
  if position('fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph)' in v_def)=0 then
    raise exception 'M49_RECURATE_CACHE_CACHED_CALL_MISSING';
  end if;
  if position('v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);' in v_def)=0 then
    raise exception 'M49_RECURATE_CACHE_GRAPH_ONCE_MISSING';
  end if;
  if position('pg_advisory_xact_lock' in v_def)=0 then
    raise exception 'M49_RECURATE_CACHE_LOCK_LOST';
  end if;
end;
$verify$;
