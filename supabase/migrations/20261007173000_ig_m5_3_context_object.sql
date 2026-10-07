-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.3 / CONTEXT_OBJECT
-- Request-local canonical context. The graph is constructed once, then reused
-- through transaction-local context by nested canonical graph lookups.

do $preflight$
declare
  v_graph_def text;
  v_materializer_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure
  ) into v_graph_def;

  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_materializer_def;

  if position('lf.input_request_context_v1' in v_graph_def) > 0
     or position('lf.input_request_context_v1' in v_materializer_def) > 0 then
    raise exception 'M5_3_CONTEXT_OBJECT_ALREADY_APPLIED';
  end if;

  if position(
    'v_screen_code text; v_module_code text; v_shell_code text; v_contract jsonb;'
    in v_graph_def
  ) = 0 then
    raise exception 'M5_3_GRAPH_DECLARATION_ANCHOR_DRIFT';
  end if;

  if position(
    'v_completed:=nullif(v_plan->>''completed_run_id'','''')::bigint;'
    in v_materializer_def
  ) = 0 then
    raise exception 'M5_3_MATERIALIZER_PLAN_ANCHOR_DRIFT';
  end if;

  if position('case v_strategy' in v_materializer_def) = 0 then
    raise exception 'M5_3_MATERIALIZER_CASE_ANCHOR_DRIFT';
  end if;
end;
$preflight$;

do $migration$
declare
  v_def text;
begin
  -- A. Canonical graph: reuse only an exact request-local graph with matching
  -- screen/version identity and SHA; fail closed on stale/malformed context.
  select pg_get_functiondef(
    'programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure
  ) into v_def;

  v_def := replace(
    v_def,
    E'  v_screen_code text; v_module_code text; v_shell_code text; v_contract jsonb;\n',
    E'  v_request_context jsonb;\n'
    || E'  v_cached_graph jsonb;\n'
    || E'  v_cached_graph_sha text;\n'
    || E'  v_screen_code text; v_module_code text; v_shell_code text; v_contract jsonb;\n'
  );

  v_def := replace(
    v_def,
    E'begin\n  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code',
    E'begin\n'
    || E'  begin\n'
    || E'    v_request_context:=nullif(current_setting(''lf.input_request_context_v1'',true),'''')::jsonb;\n'
    || E'  exception when others then\n'
    || E'    raise exception ''INPUT_REQUEST_CONTEXT_INVALID'';\n'
    || E'  end;\n'
    || E'  if v_request_context is not null then\n'
    || E'    if coalesce((v_request_context->>''pantalla_id'')::integer,-1)<>p_pantalla_id\n'
    || E'       or coalesce((v_request_context->>''version_id'')::bigint,-1)<>p_version_id then\n'
    || E'      raise exception ''INPUT_REQUEST_CONTEXT_IDENTITY_MISMATCH:%:%'',p_pantalla_id,p_version_id;\n'
    || E'    end if;\n'
    || E'    v_cached_graph:=v_request_context->''graph'';\n'
    || E'    v_cached_graph_sha:=nullif(v_request_context->>''graph_sha256'','''');\n'
    || E'    if v_cached_graph is null\n'
    || E'       or v_cached_graph_sha is null\n'
    || E'       or v_cached_graph_sha is distinct from programacion.fn_v09_sha256_jsonb(v_cached_graph) then\n'
    || E'      raise exception ''INPUT_REQUEST_CONTEXT_GRAPH_SHA_MISMATCH:%:%'',p_pantalla_id,p_version_id;\n'
    || E'    end if;\n'
    || E'    return v_cached_graph;\n'
    || E'  end if;\n'
    || E'  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code'
  );

  execute v_def;

  -- B. Curator materializer: construct one request-local context before dispatch.
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_def;

  v_def := replace(
    v_def,
    E'  v_completed bigint;\n',
    E'  v_completed bigint;\n'
    || E'  v_version bigint;\n'
    || E'  v_source_snapshot_sha256 text;\n'
    || E'  v_source_manifest jsonb:=''[]''::jsonb;\n'
    || E'  v_contract_registry jsonb:=''[]''::jsonb;\n'
    || E'  v_graph jsonb;\n'
    || E'  v_context jsonb;\n'
    || E'  v_result jsonb;\n'
  );

  v_def := replace(
    v_def,
    E'begin\n  v_plan:=programacion.fn_input_governance_curator_plan_v1(',
    E'begin\n'
    || E'  select c.version_id into v_version\n'
    || E'  from programacion.contratos c\n'
    || E'  join programacion.versiones_agente v on v.id=c.version_id\n'
    || E'  join programacion.agentes a on a.id=v.agente_id\n'
    || E'  where a.agente_codigo=''INPUT_GOVERNANCE_AGENT''\n'
    || E'    and c.contrato_codigo=''INPUT_READINESS_CONTRACT''\n'
    || E'    and c.estado=''defined'' and c.fail_closed\n'
    || E'  order by c.version_id desc,c.id desc limit 1;\n'
    || E'  if v_version is null then\n'
    || E'    raise exception ''INPUT_REQUEST_CONTEXT_VERSION_UNRESOLVED:%'',p_pantalla_id;\n'
    || E'  end if;\n'
    || E'  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);\n'
    || E'  v_context:=jsonb_build_object(\n'
    || E'    ''schema_version'',''INPUT_GOVERNANCE_REQUEST_CONTEXT_V1'',\n'
    || E'    ''pantalla_id'',p_pantalla_id,\n'
    || E'    ''version_id'',v_version,\n'
    || E'    ''consumer'',p_consumer,\n'
    || E'    ''request_identity'',p_curator_identity,\n'
    || E'    ''strategy'',null,\n'
    || E'    ''completed_run_id'',null,\n'
    || E'    ''graph'',v_graph,\n'
    || E'    ''graph_sha256'',programacion.fn_v09_sha256_jsonb(v_graph),\n'
    || E'    ''contract_registry'',''[]''::jsonb,\n'
    || E'    ''source_snapshot_sha256'',null,\n'
    || E'    ''source_manifest'',''[]''::jsonb\n'
    || E'  );\n'
    || E'  perform set_config(''lf.input_request_context_v1'',v_context::text,true);\n'
    || E'  v_plan:=programacion.fn_input_governance_curator_plan_v1('
  );

  v_def := replace(
    v_def,
    E'  v_completed:=nullif(v_plan->>''completed_run_id'','''')::bigint;\n\n  case v_strategy',
    E'  v_completed:=nullif(v_plan->>''completed_run_id'','''')::bigint;\n'
    || E'\n'
    || E'  if v_completed is not null then\n'
    || E'    select r.source_snapshot_sha256,coalesce(r.source_manifest,''[]''::jsonb)\n'
    || E'      into v_source_snapshot_sha256,v_source_manifest\n'
    || E'    from programacion.input_readiness_runs r\n'
    || E'    where r.id=v_completed and r.pantalla_id=p_pantalla_id and r.version_id=v_version;\n'
    || E'    if not found then\n'
    || E'      raise exception ''INPUT_REQUEST_CONTEXT_RUN_IDENTITY_MISMATCH:%:%'',p_pantalla_id,v_completed;\n'
    || E'    end if;\n'
    || E'  end if;\n'
    || E'\n'
    || E'  select coalesce(jsonb_agg(jsonb_build_object(\n'
    || E'      ''id'',c.id,\n'
    || E'      ''contract_code'',c.contrato_codigo,\n'
    || E'      ''status'',c.estado,\n'
    || E'      ''fail_closed'',c.fail_closed\n'
    || E'    ) order by c.contrato_codigo,c.id),''[]''::jsonb)\n'
    || E'    into v_contract_registry\n'
    || E'  from programacion.contratos c\n'
    || E'  where c.version_id=v_version\n'
    || E'    and c.contrato_codigo in (\n'
    || E'      ''INPUT_READINESS_CONTRACT'',\n'
    || E'      ''INPUT_GOVERNANCE_EXECUTION_CONTRACT'',\n'
    || E'      ''INPUT_CONTEXT_MANIFEST_CONTRACT'',\n'
    || E'      ''INPUT_FRESHNESS_DELTA_CONTRACT'',\n'
    || E'      ''INPUT_RETRIEVAL_HANDLE_CONTRACT'',\n'
    || E'      ''INPUT_FAMILY_POLICY_REGISTRY''\n'
    || E'    );\n'
    || E'\n'
    || E'  v_context:=v_context || jsonb_build_object(\n'
    || E'    ''strategy'',v_strategy,\n'
    || E'    ''completed_run_id'',v_completed,\n'
    || E'    ''contract_registry'',v_contract_registry,\n'
    || E'    ''source_snapshot_sha256'',v_source_snapshot_sha256,\n'
    || E'    ''source_manifest'',v_source_manifest\n'
    || E'  );\n'
    || E'  perform set_config(''lf.input_request_context_v1'',v_context::text,true);\n'
    || E'\n'
    || E'  case v_strategy'
  );

  v_def := replace(
    v_def,
    '      return programacion.fn_input_governance_bootstrap_materialize_v2(',
    '      v_result:=programacion.fn_input_governance_bootstrap_materialize_v2('
  );
  v_def := replace(
    v_def,
    '      return programacion.fn_input_governance_curator_rebind_v1(',
    '      v_result:=programacion.fn_input_governance_curator_rebind_v1('
  );
  v_def := replace(
    v_def,
    '      return programacion.fn_input_governance_recurate_source_stale_v1(',
    '      v_result:=programacion.fn_input_governance_recurate_source_stale_v1('
  );
  v_def := replace(
    v_def,
    '      return programacion.fn_input_governance_recurate_v2(',
    '      v_result:=programacion.fn_input_governance_recurate_v2('
  );
  v_def := replace(
    v_def,
    '      return jsonb_build_object(',
    '      v_result:=jsonb_build_object('
  );

  v_def := replace(
    v_def,
    E'  end case;\nend;',
    E'  end case;\n'
    || E'  perform set_config(''lf.input_request_context_v1'','''',true);\n'
    || E'  return v_result || jsonb_build_object(\n'
    || E'    ''request_context_summary'',jsonb_build_object(\n'
    || E'      ''schema_version'',''INPUT_GOVERNANCE_REQUEST_CONTEXT_V1'',\n'
    || E'      ''pantalla_id'',p_pantalla_id,\n'
    || E'      ''version_id'',v_version,\n'
    || E'      ''graph_sha256'',v_context->>''graph_sha256'',\n'
    || E'      ''context_sha256'',programacion.fn_v09_sha256_jsonb(v_context)\n'
    || E'    )\n'
    || E'  );\n'
    || E'exception when others then\n'
    || E'  perform set_config(''lf.input_request_context_v1'','''',true);\n'
    || E'  raise;\n'
    || E'end;'
  );

  execute v_def;
end;
$migration$;

comment on function programacion.fn_input_screen_canonical_graph(integer,bigint)
is 'Canonical graph with fail-closed request-local reuse via lf.input_request_context_v1; M5.3.';

comment on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)
is 'Curator strategy dispatcher with one request-local canonical graph/context construction; M5.3.';

do $verify$
declare
  v_graph_def text;
  v_materializer_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure
  ) into v_graph_def;
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_materializer_def;

  if position('lf.input_request_context_v1' in v_graph_def)=0
     or position('INPUT_REQUEST_CONTEXT_IDENTITY_MISMATCH' in v_graph_def)=0
     or position('INPUT_REQUEST_CONTEXT_GRAPH_SHA_MISMATCH' in v_graph_def)=0 then
    raise exception 'M5_3_GRAPH_CACHE_CONTRACT_MISSING';
  end if;

  if regexp_count(v_materializer_def,'fn_input_screen_canonical_graph')<>1
     or position('INPUT_GOVERNANCE_REQUEST_CONTEXT_V1' in v_materializer_def)=0
     or position('request_context_summary' in v_materializer_def)=0 then
    raise exception 'M5_3_CONTEXT_OBJECT_CONTRACT_MISSING';
  end if;
end;
$verify$;
