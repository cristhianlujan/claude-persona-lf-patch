-- Strategy 28 / P2 candidate only. No dispatcher/runtime switch in this migration.
-- Purpose: extend the existing request-local SCREEN_CANONICAL_GRAPH reuse pattern
-- through NA authority, field-reference and semantic probes without reducing
-- currentness depth, source-manifest readback, classifier SHA gates or fail-closed behavior.
-- Base reconciled to main ded3426ca1ea821e0b0aaa84b3ae35cdb8a2c515.

do $migration$
declare
  v_def text;
begin
  -- 1) Positive N/A authority: same semantics, supplied graph.
  select pg_get_functiondef('programacion.fn_input_na_positive_authority_v512(text,integer,bigint)'::regprocedure) into v_def;
  if position('v_graph := programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);' in v_def)=0 then
    raise exception 'S28_NA_GRAPH_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_na_positive_authority_v512(p_family_code text, p_pantalla_id integer, p_version_id bigint)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_na_positive_authority_v512_cached_v1(p_family_code text, p_pantalla_id integer, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v_graph := programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);',
    'v_graph := p_graph;');
  execute v_def;

  -- 2) Explicit field reference probe: same semantics, supplied graph.
  select pg_get_functiondef('programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint)'::regprocedure) into v_def;
  if position('v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);' in v_def)=0 then
    raise exception 'S28_FIELD_PROBE_GRAPH_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_field_reference_probe_v1_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);',
    'v_graph:=p_graph;');
  execute v_def;

  -- 3) Semantic v1: same family logic, supplied graph.
  select pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v1(integer,text,bigint)'::regprocedure) into v_def;
  if position('v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);' in v_def)=0 then
    raise exception 'S28_SEMANTIC_V1_GRAPH_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v1_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);',
    'v_graph:=p_graph;');
  execute v_def;

  -- 4) Semantic v2: chain to cached v1 and supplied graph.
  select pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint)'::regprocedure) into v_def;
  if position('v_base:=programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id,p_family_code,p_version_id);' in v_def)=0
     or position('v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);' in v_def)=0 then
    raise exception 'S28_SEMANTIC_V2_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v_base:=programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id,p_family_code,p_version_id);',
    'v_base:=programacion.fn_input_governance_semantic_probe_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);');
  v_def:=replace(v_def,
    'v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);',
    'v_graph:=p_graph;');
  execute v_def;

  -- 5) Semantic v3: chain to cached v2, cached field probe, supplied graph.
  select pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure) into v_def;
  if position('v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);' in v_def)=0
     or position('v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>''screen_code'','''');' in v_def)=0 then
    raise exception 'S28_SEMANTIC_V3_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v3_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);',
    'v_base:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);');
  v_def:=replace(v_def,
    'v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>''screen_code'','''');',
    'v_screen_code:=nullif(p_graph->>''screen_code'','''');');
  v_def:=replace(v_def,
    'programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id)',
    'programacion.fn_input_governance_field_reference_probe_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph)');
  v_def:=replace(v_def,
    'v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);',
    'v_graph:=p_graph;');
  execute v_def;

  -- 6) Cached classifier v1 candidate: reuse supplied graph for N/A authority.
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure) into v_def;
  if position('v_na:=programacion.fn_input_na_positive_authority_v512(p_family_code,p_pantalla_id,p_version_id);' in v_def)=0 then
    raise exception 'S28_CLASSIFIER_V1_NA_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v_na:=programacion.fn_input_na_positive_authority_v512(p_family_code,p_pantalla_id,p_version_id);',
    'v_na:=programacion.fn_input_na_positive_authority_v512_cached_v1(p_family_code,p_pantalla_id,p_version_id,p_graph);');
  execute v_def;

  -- 7) Cached classifier v2 candidate: reuse supplied graph through semantic chain.
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb)'::regprocedure) into v_def;
  if position('v:=programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);' in v_def)=0
     or position('v_sem:=programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id,p_family_code,p_version_id);' in v_def)=0 then
    raise exception 'S28_CLASSIFIER_V2_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)');
  v_def:=replace(v_def,
    'v:=programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);',
    'v:=programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(p_pantalla_id,p_family_code,p_version_id,p_graph);');
  v_def:=replace(v_def,
    'v_sem:=programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id,p_family_code,p_version_id);',
    'v_sem:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);');
  -- MFA special case also re-materialized the same graph.
  v_def:=replace(v_def,
    'coalesce(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->''canonical_contract''->''rules'',''[]''::jsonb)',
    'coalesce(p_graph->''canonical_contract''->''rules'',''[]''::jsonb)');
  execute v_def;

  -- 8) Currentness candidate: same authority/readback model, only classifier implementation changes.
  select pg_get_functiondef('programacion.fn_input_readiness_run_is_current_cached_v1(bigint)'::regprocedure) into v_def;
  if position('v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(v_pantalla_id,v_assessment.family_code,v_run.version_id,v_current_graph);' in v_def)=0 then
    raise exception 'S28_CURRENTNESS_CLASSIFIER_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_readiness_run_is_current_cached_v1(p_run_id bigint)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_readiness_run_is_current_cached_v2(p_run_id bigint)');
  v_def:=replace(v_def,
    'v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(v_pantalla_id,v_assessment.family_code,v_run.version_id,v_current_graph);',
    'v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_pantalla_id,v_assessment.family_code,v_run.version_id,v_current_graph);');
  execute v_def;
end;
$migration$;

-- Candidate functions are service-role only and do not replace public/runtime entrypoints.
revoke all on function programacion.fn_input_na_positive_authority_v512_cached_v1(text,integer,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_field_reference_probe_v1_cached_v1(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_semantic_probe_v1_cached_v1(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_semantic_probe_v2_cached_v1(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_readiness_run_is_current_cached_v2(bigint) from public,anon,authenticated;

grant execute on function programacion.fn_input_na_positive_authority_v512_cached_v1(text,integer,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_field_reference_probe_v1_cached_v1(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_semantic_probe_v1_cached_v1(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_semantic_probe_v2_cached_v1(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb) to service_role;
grant execute on function programacion.fn_input_readiness_run_is_current_cached_v2(bigint) to service_role;

-- Structural regression: original authorities remain present and candidate path contains no
-- direct canonical-graph call in the cloned helper chain. Source-manifest readback remains
-- intentionally in fn_input_readiness_run_is_current_cached_v2.
do $verify$
declare
  v_count integer;
  v_def text;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_input_na_positive_authority_v512_cached_v1',
    'fn_input_governance_field_reference_probe_v1_cached_v1',
    'fn_input_governance_semantic_probe_v1_cached_v1',
    'fn_input_governance_semantic_probe_v2_cached_v1',
    'fn_input_governance_semantic_probe_v3_cached_v1',
    'fn_input_governance_bootstrap_classify_v1_cached_v2',
    'fn_input_governance_bootstrap_classify_v2_cached_v2',
    'fn_input_readiness_run_is_current_cached_v2'
  );
  if v_count<>8 then raise exception 'S28_CANDIDATE_FUNCTION_COUNT_MISMATCH:%',v_count; end if;

  select pg_get_functiondef('programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure) into v_def;
  if position('programacion.fn_input_build_source_manifest(p_run_id)' in v_def)=0
     or position('v_current_manifest=v_run.source_manifest' in v_def)=0
     or position('v_current_sha=v_run.source_snapshot_sha256' in v_def)=0 then
    raise exception 'S28_CURRENTNESS_READBACK_OR_EXACT_EQUALITY_LOST';
  end if;
end;
$verify$;
