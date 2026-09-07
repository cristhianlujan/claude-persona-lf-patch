-- Strategy 28 / Input Governance IG-006 + IG-007 exact-version sandbox forward.
-- Source-first. Sandbox canary only. No production authorization. No execute-entrypoint switch.
-- Live guard semantics are preserved when no request-local graph is present.

do $preflight$
declare
  v_rebind text;
  v_assertions text;
  v_rebind_assertion text;
  v_guard text;
  v_exec text;
  v_count integer;
begin
  perform 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure;
  perform 'programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure;

  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),
         pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
         pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into v_rebind,v_assertions,v_rebind_assertion,v_guard,v_exec;

  if encode(extensions.digest(convert_to(v_rebind,'UTF8'),'sha256'),'hex') <> '1bbf57bb5f51fff22e540664a3fe4e07a547a5e62b855c69abb2f981e5d92c79' then
    raise exception 'S28_IG006_FORWARD_REBIND_BASELINE_SHA_DRIFT';
  end if;
  if encode(extensions.digest(convert_to(v_assertions,'UTF8'),'sha256'),'hex') <> 'd02e3d07523debdb2acf38f46a7ebfd4c0b7d8d5238ed4b5d13de3581e9d4822' then
    raise exception 'S28_IG006_FORWARD_ASSERTIONS_BASELINE_SHA_DRIFT';
  end if;
  if encode(extensions.digest(convert_to(v_rebind_assertion,'UTF8'),'sha256'),'hex') <> 'b3ab572553e592fa8e8c64b9031ec741936995be67c2c469c2a0834ce11d6f9e' then
    raise exception 'S28_IG006_FORWARD_REBIND_ASSERTION_BASELINE_SHA_DRIFT';
  end if;
  if encode(extensions.digest(convert_to(v_guard,'UTF8'),'sha256'),'hex') <> 'd000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574' then
    raise exception 'S28_IG007_FORWARD_INSERT_GUARD_BASELINE_SHA_DRIFT';
  end if;
  if position('fn_input_governance_curator_rebind_candidate_v1' in v_exec)>0 then
    raise exception 'S28_IG006_FORWARD_LIVE_EXECUTE_ALREADY_CANDIDATE';
  end if;

  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
    'fn_input_rebind_assertion_cached_v1',
    'fn_input_v58_build_assertions_cached_v1',
    'fn_input_governance_curator_rebind_candidate_v1'
  );
  if v_count<>0 then raise exception 'S28_IG006_FORWARD_PREEXISTING_RESIDUE:%',v_count; end if;
end;
$preflight$;

do $migration$
declare
  v_def text;
begin
  -- Preserve an exact runtime copy of the baseline trigger function for mandatory rollback.
  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure) into v_def;
  v_def:=replace(
    v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert()',
    'CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()'
  );
  execute v_def;

  -- A. Keep the insert authority guard. Reuse the request-local graph only when both
  -- graph+SHA are present and exact. If absent, execute the canonical resolver unchanged.
  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure) into v_def;
  if position('perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);' in v_def)=0 then
    raise exception 'S28_IG007_FORWARD_INSERT_GUARD_RESOLVER_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    E'  v_allow_story_incomplete boolean:=false; v_allow_impl_incomplete boolean:=false; v_allow_qa_incomplete boolean:=false; v_allow_prod_incomplete boolean:=false;\nbegin',
    E'  v_allow_story_incomplete boolean:=false; v_allow_impl_incomplete boolean:=false; v_allow_qa_incomplete boolean:=false; v_allow_prod_incomplete boolean:=false;\n  v_cached_graph jsonb;\n  v_cached_graph_sha text;\nbegin');
  v_def:=replace(v_def,
    '    perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);',
    E'    if v_ref->>''kind''=''SCREEN_CANONICAL_GRAPH'' then\n      begin\n        v_cached_graph:=nullif(current_setting(''lf.input_screen_canonical_graph_v1'',true),'''')::jsonb;\n        v_cached_graph_sha:=nullif(current_setting(''lf.input_screen_canonical_graph_sha256_v1'',true),'''');\n      exception when others then\n        raise exception ''INPUT_REQUEST_GRAPH_CACHE_INVALID:%'',new.family_code;\n      end;\n      if v_cached_graph is null and v_cached_graph_sha is null then\n        perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);\n      elsif v_cached_graph is null\n         or v_cached_graph_sha is null\n         or v_cached_graph_sha is distinct from programacion.fn_v09_sha256_jsonb(v_cached_graph)\n         or coalesce(v_cached_graph->>''screen_code'','''') is distinct from coalesce((select p.codigo from lf_ops.pantallas p where p.id=v_pantalla_id),'''')\n         or coalesce((v_cached_graph->>''agent_contract_version_id'')::bigint,-1)<>v_version_id\n      then\n        raise exception ''INPUT_REQUEST_GRAPH_CACHE_IDENTITY_MISMATCH:%:%'',v_pantalla_id,new.family_code;\n      end if;\n    else\n      perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);\n    end if;');
  execute v_def;

  -- B. Assertion rebind with the supplied exact request-local graph.
  select pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure) into v_def;
  if position('v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);' in v_def)=0 then
    raise exception 'S28_IG006_FORWARD_ASSERTION_GRAPH_ANCHOR_DRIFT';
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

  -- C. Assertion-set builder using the same graph.
  select pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure) into v_def;
  if position('programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl)' in v_def)=0 then
    raise exception 'S28_IG006_FORWARD_ASSERTION_SET_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_v58_build_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_v58_build_assertions_cached_v1(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text, p_graph jsonb)');
  v_def:=replace(v_def,
    'programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl)',
    'programacion.fn_input_rebind_assertion_cached_v1(p_new_run_id,p_family_code,v_tpl,p_graph)');
  execute v_def;

  -- D. Candidate Curator. Live Curator and public execute entrypoint remain unchanged.
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure) into v_def;
  if position('programacion.fn_input_readiness_run_is_current(id)' in v_def)=0
     or position('v_assertions:=programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);' in v_def)=0
     or position('''semantic_policy'',''NO_INVENTION_REBIND_ONLY''' in v_def)=0
     or position('returning id into v_new;' in v_def)=0 then
    raise exception 'S28_IG006_FORWARD_CURATOR_ANCHOR_DRIFT';
  end if;
  v_def:=replace(v_def,
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean DEFAULT false)',
    'CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_rebind_candidate_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean DEFAULT false)');
  v_def:=replace(v_def,
    E'  v_payload jsonb;\nbegin',
    E'  v_payload jsonb;\n  v_graph jsonb;\n  v_graph_sha text;\n  v_expected_classifier jsonb;\nbegin');

  v_def:=replace(v_def,
    E'  select id into v_current from programacion.input_readiness_runs\n  where version_id=v_version and pantalla_id=p_pantalla_id and status=''COMPLETED'' and invalidated_at is null\n    and programacion.fn_input_readiness_run_is_current(id)\n  order by id desc limit 1;\n  if v_current is not null and not p_force_selftest then\n    return jsonb_build_object(''status'',''NOOP_CURRENT'',''run_id'',v_current,''required_role'',''NONE'',''promotion_authorized'',false,''production_authorized'',false);\n  end if;',
    E'  if not p_force_selftest then\n    select id into v_current from programacion.input_readiness_runs\n    where version_id=v_version and pantalla_id=p_pantalla_id and status=''COMPLETED'' and invalidated_at is null\n      and programacion.fn_input_readiness_run_is_current_cached_v2(id)\n    order by id desc limit 1;\n    if v_current is not null then\n      return jsonb_build_object(''status'',''NOOP_CURRENT'',''run_id'',v_current,''required_role'',''NONE'',''promotion_authorized'',false,''production_authorized'',false);\n    end if;\n  end if;');

  v_def:=replace(v_def,
    E'  returning id into v_new;\n\n  for a in',
    E'  returning id into v_new;\n\n  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);\n  v_graph_sha:=programacion.fn_v09_sha256_jsonb(v_graph);\n  perform set_config(''lf.input_screen_canonical_graph_v1'',v_graph::text,true);\n  perform set_config(''lf.input_screen_canonical_graph_sha256_v1'',v_graph_sha,true);\n\n  for a in');
  v_def:=replace(v_def,
    E'  loop\n    insert into programacion.input_family_assessments(',
    E'  loop\n    v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,a.family_code,v_version,v_graph);\n    insert into programacion.input_family_assessments(');
  v_def:=replace(v_def,
    '''semantic_policy'',''NO_INVENTION_REBIND_ONLY''',
    '''semantic_policy'',''NO_INVENTION_REBIND_ONLY'',''bootstrap_classifier_sha256'',v_expected_classifier->>''classifier_sha256'',''screen_canonical_graph_sha256'',v_graph_sha');
  v_def:=replace(v_def,
    'v_assertions:=programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);',
    'v_assertions:=programacion.fn_input_v58_build_assertions_cached_v1(v_new,v_parent,a.family_code,v_graph);');
  v_def:=replace(v_def,
    E'  end loop;\n\n  select count(*) into v_assessed',
    E'  end loop;\n\n  perform set_config(''lf.input_screen_canonical_graph_v1'','''',true);\n  perform set_config(''lf.input_screen_canonical_graph_sha256_v1'','''',true);\n\n  select count(*) into v_assessed');
  execute v_def;
end;
$migration$;

revoke all on function programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1() from public,anon,authenticated;
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
  v_guard text;
  v_backup text;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
    'fn_input_rebind_assertion_cached_v1',
    'fn_input_v58_build_assertions_cached_v1',
    'fn_input_governance_curator_rebind_candidate_v1'
  );
  if v_count<>4 then raise exception 'S28_IG006_FORWARD_CANDIDATE_FUNCTION_COUNT:%',v_count; end if;

  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure) into v_live;
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_candidate_v1(integer,text,text,boolean)'::regprocedure) into v_candidate;
  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure) into v_guard;
  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()'::regprocedure) into v_backup;

  if position('fn_input_v58_build_assertions_cached_v1' in v_candidate)=0
     or position('fn_input_governance_bootstrap_classify_v2_cached_v2' in v_candidate)=0
     or position('bootstrap_classifier_sha256' in v_candidate)=0
     or position('fn_input_readiness_run_is_current_cached_v2' in v_candidate)=0
     or position('lf.input_screen_canonical_graph_v1' in v_candidate)=0 then
    raise exception 'S28_IG006_FORWARD_CANDIDATE_STRUCTURE_INCOMPLETE';
  end if;
  if position('lf.input_screen_canonical_graph_v1' in v_guard)=0
     or position('v_cached_graph is null and v_cached_graph_sha is null' in v_guard)=0
     or position('perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);' in v_guard)=0 then
    raise exception 'S28_IG007_FORWARD_GUARD_FALLBACK_STRUCTURE_INCOMPLETE';
  end if;
  if encode(extensions.digest(convert_to(replace(v_backup,'fn_guard_input_family_assessment_insert_baseline_ig007_v1','fn_guard_input_family_assessment_insert'),'UTF8'),'sha256'),'hex')
     <> 'd000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574' then
    raise exception 'S28_IG007_FORWARD_BACKUP_GUARD_SHA_MISMATCH';
  end if;
  if position('fn_input_governance_curator_rebind_candidate_v1' in v_live)>0 then
    raise exception 'S28_IG006_FORWARD_LIVE_CURATOR_CONTAMINATED';
  end if;
end;
$verify$;
