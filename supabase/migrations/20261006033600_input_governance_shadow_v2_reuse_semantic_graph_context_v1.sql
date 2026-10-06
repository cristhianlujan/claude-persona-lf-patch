
do $$
declare
  d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_governance_semantic_probe_v3'
  limit 1;

  d:=replace(
    d,
    'FUNCTION programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'FUNCTION programacion.fn_input_governance_semantic_probe_v3_ctx(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)'
  );
  d:=replace(
    d,
    'programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)',
    'p_graph'
  );
  execute d;

  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_governance_bootstrap_classify_v2'
  limit 1;

  d:=replace(
    d,
    'FUNCTION programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'FUNCTION programacion.fn_input_governance_bootstrap_classify_v2_ctx(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)'
  );
  d:=replace(
    d,
    'programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,p_family_code,p_version_id)',
    'programacion.fn_input_governance_bootstrap_classify_v1_ctx(p_pantalla_id,p_family_code,p_version_id,p_graph)'
  );
  d:=replace(
    d,
    'programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id,p_family_code,p_version_id)',
    'programacion.fn_input_governance_semantic_probe_v3_ctx(p_pantalla_id,p_family_code,p_version_id,p_graph)'
  );
  d:=replace(
    d,
    'programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)',
    'p_graph'
  );
  execute d;
end $$;
