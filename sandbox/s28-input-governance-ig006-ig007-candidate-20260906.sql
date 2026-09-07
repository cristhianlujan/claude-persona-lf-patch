-- Strategy 28 / Input Governance IG-006 + IG-007 rollback-only candidate.
-- NEVER run as a migration. The canary workflow executes this file inside one
-- transaction and rolls it back. No runtime/public entrypoint is switched.

\set ON_ERROR_STOP on
begin;
set local statement_timeout = '180s';

do $candidate$
declare
  v_def text;
begin
  perform 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure;
  perform 'programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure;

  -- A. Assertion rebind with request-local canonical graph.
  select pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure) into v_def;
  if position('v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);' in v_def)=0 then
    raise exception 'S28_IG006_ASSERTION_GRAPH_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_rebind_assertion(p_run_id bigint, p_family_code text, p_assertion jsonb)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_rebind_assertion_cached_v1(p_run_id bigint, p_family_code text, p_assertion jsonb, p_graph jsonb)');
  v_def:=replace(v_def,
    '  if v_pantalla_id is null then raise exception ''ASSERTION_REBIND_RUN_NOT_FOUND:%'',p_run_id; end if;',
    E'  if v_pantalla_id is null then raise exception ''ASSERTION_REBIND_RUN_NOT_FOUND:%'',p_run_id; end if;\n  if p_graph is null\n     or coalesce(p_graph->>''screen_code'','''') is distinct from coalesce((select p.codigo from lf_ops.pantallas p where p.id=v_pantalla_id),'''')\n     or coalesce((p_graph->>''agent_contract_version_id'')::bigint,-1)<>v_version_id\n  then raise exception ''S28_ASSERTION_GRAPH_IDENTITY_MISMATCH:%'',v_pantalla_id; end if;');
  v_def:=replace(v_def,
    'v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);',
    'v_graph:=p_graph;');
  execute v_def;

  -- B. Assertion-set builder using the same request-local graph.
  select pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure) into v_def;
  if position('programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl)' in v_def)=0 then
    raise exception 'S28_IG006_ASSERTION_SET_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_v58_build_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_v58_build_assertions_cached_v1(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text, p_graph jsonb)');
  v_def:=replace(v_def,
    'programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl)',
    'programacion.fn_input_rebind_assertion_cached_v1(p_new_run_id,p_family_code,v_tpl,p_graph)');
  execute v_def;

  -- C. Candidate Curator rebind. Original runtime function remains untouched.
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure) into v_def;
  if position('programacion.fn_input_readiness_run_is_current(id)' in v_def)=0
     or position('v_assertions:=programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);' in v_def)=0
     or position('''semantic_policy'',''NO_INVENTION_REBIND_ONLY''' in v_def)=0
     or position('returning id into v_new;' in v_def)=0 then
    raise exception 'S28_IG006_CURATOR_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean DEFAULT false)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_rebind_candidate_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean DEFAULT false)');
  v_def:=replace(v_def,
    E'  v_payload jsonb;\nbegin',
    E'  v_payload jsonb;\n  v_graph jsonb;\n  v_expected_classifier jsonb;\nbegin');

  -- A forced self-test explicitly requests a new successor. Do not spend a full
  -- currentness pass proving a run is current only to ignore that result. Normal
  -- calls retain fail-closed currentness, using the already-governed cached_v2 path.
  v_def:=replace(v_def,
    E'  select id into v_current from programacion.input_readiness_runs\n  where version_id=v_version and pantalla_id=p_pantalla_id and status=''COMPLETED'' and invalidated_at is null\n    and programacion.fn_input_readiness_run_is_current(id)\n  order by id desc limit 1;\n  if v_current is not null and not p_force_selftest then\n    return jsonb_build_object(''status'',''NOOP_CURRENT'',''run_id'',v_current,''required_role'',''NONE'',''promotion_authorized'',false,''production_authorized'',false);\n  end if;',
    E'  if not p_force_selftest then\n    select id into v_current from programacion.input_readiness_runs\n    where version_id=v_version and pantalla_id=p_pantalla_id and status=''COMPLETED'' and invalidated_at is null\n      and programacion.fn_input_readiness_run_is_current_cached_v2(id)\n    order by id desc limit 1;\n    if v_current is not null then\n      return jsonb_build_object(''status'',''NOOP_CURRENT'',''run_id'',v_current,''required_role'',''NONE'',''promotion_authorized'',false,''production_authorized'',false);\n    end if;\n  end if;');

  v_def:=replace(v_def,
    E'  returning id into v_new;\n\n  for a in',
    E'  returning id into v_new;\n\n  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);\n\n  for a in');
  v_def:=replace(v_def,
    E'  loop\n    insert into programacion.input_family_assessments(',
    E'  loop\n    v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,a.family_code,v_version,v_graph);\n    insert into programacion.input_family_assessments(');
  v_def:=replace(v_def,
    '''semantic_policy'',''NO_INVENTION_REBIND_ONLY''',
    '''semantic_policy'',''NO_INVENTION_REBIND_ONLY'',''bootstrap_classifier_sha256'',v_expected_classifier->>''classifier_sha256'',''screen_canonical_graph_sha256'',programacion.fn_v09_sha256_jsonb(v_graph)');
  v_def:=replace(v_def,
    'v_assertions:=programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);',
    'v_assertions:=programacion.fn_input_v58_build_assertions_cached_v1(v_new,v_parent,a.family_code,v_graph);');
  execute v_def;
end;
$candidate$;

revoke all on function programacion.fn_input_rebind_assertion_cached_v1(bigint,text,jsonb,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_v58_build_assertions_cached_v1(bigint,bigint,text,jsonb) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_curator_rebind_candidate_v1(integer,text,text,boolean) from public,anon,authenticated;
grant execute on function programacion.fn_input_rebind_assertion_cached_v1(bigint,text,jsonb,jsonb) to service_role;
grant execute on function programacion.fn_input_v58_build_assertions_cached_v1(bigint,bigint,text,jsonb) to service_role;
grant execute on function programacion.fn_input_governance_curator_rebind_candidate_v1(integer,text,text,boolean) to service_role;

do $verify$
declare
  v_count integer;
  v_live text;
  v_candidate text;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_input_rebind_assertion_cached_v1',
    'fn_input_v58_build_assertions_cached_v1',
    'fn_input_governance_curator_rebind_candidate_v1');
  if v_count<>3 then raise exception 'S28_IG006_CANDIDATE_FUNCTION_COUNT:%',v_count; end if;

  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure) into v_live;
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_candidate_v1(integer,text,text,boolean)'::regprocedure) into v_candidate;
  if position('fn_input_v58_build_assertions_cached_v1' in v_candidate)=0
     or position('fn_input_governance_bootstrap_classify_v2_cached_v2' in v_candidate)=0
     or position('bootstrap_classifier_sha256' in v_candidate)=0
     or position('fn_input_readiness_run_is_current_cached_v2' in v_candidate)=0
     or position('if not p_force_selftest then' in v_candidate)=0 then
    raise exception 'S28_IG006_CANDIDATE_STRUCTURE_INCOMPLETE';
  end if;
  if position('fn_input_governance_curator_rebind_candidate_v1' in v_live)>0 then
    raise exception 'S28_IG006_LIVE_ENTRYPOINT_CONTAMINATED';
  end if;
end;
$verify$;
