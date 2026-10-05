-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M2.6 / PAULO-039
-- Checkpoint: REMOVE_VERSION_BRANCH
-- Replace agent-version text routing inside fn_input_screen_canonical_graph with
-- routing resolved from the governed INPUT_READINESS_CONTRACT for p_version_id.
-- No second graph or resolver is introduced.

begin;

do $m26_remove_version_branch$
declare
  v_def text;
  v_new text;
  v_start integer;
  v_end integer;
  v_like_count integer;
  v_decl_old constant text := '  v_version_code text; v_graph_contract text:=''SCREEN_CANONICAL_GRAPH_V4_2'';';
  v_decl_new constant text := E'  v_readiness_spec jsonb;\n  v_design_binding_contract text;\n  v_api_resolution_contract text;\n  v_graph_contract text;';
  v_contract_selector constant text := E'  if not exists(select 1 from programacion.versiones_agente where id=p_version_id) then raise exception ''SCREEN_CANONICAL_GRAPH_AGENT_VERSION_NOT_FOUND:%'',p_version_id; end if;\n  select c.especificacion into v_readiness_spec\n  from programacion.contratos c\n  where c.version_id=p_version_id\n    and c.contrato_codigo=''INPUT_READINESS_CONTRACT''\n    and c.estado=''defined''\n    and c.fail_closed\n  order by c.id desc\n  limit 1;\n  if v_readiness_spec is null then raise exception ''SCREEN_CANONICAL_GRAPH_READINESS_CONTRACT_NOT_FOUND:%'',p_version_id; end if;\n  v_graph_contract:=nullif(v_readiness_spec->>''screen_graph_contract'','''');\n  if v_graph_contract is null then raise exception ''SCREEN_CANONICAL_GRAPH_CONTRACT_NOT_PINNED:%'',p_version_id; end if;\n  v_design_binding_contract:=nullif(v_readiness_spec#>>''{design_system_readiness,binding_graph}'','''');\n  v_api_resolution_contract:=nullif(v_readiness_spec#>>''{api_data_contract_readiness,resolution_contract}'','''');\n';
  v_capability_routing constant text := E'  if v_design_binding_contract is not null then\n    case v_design_binding_contract\n      when ''DESIGN_BINDING_GRAPH_V1'' then\n        v_contract:=jsonb_set(v_contract,''{visual,design_bindings}'',programacion.fn_input_design_binding_graph(p_pantalla_id),true);\n      when ''DESIGN_BINDING_GRAPH_V2'' then\n        v_contract:=jsonb_set(v_contract,''{visual,design_bindings}'',programacion.fn_input_design_binding_graph_v2(p_pantalla_id),true);\n      else\n        raise exception ''SCREEN_CANONICAL_GRAPH_UNSUPPORTED_DESIGN_BINDING_CONTRACT:%:%'',p_version_id,v_design_binding_contract;\n    end case;\n  end if;\n\n  if v_api_resolution_contract is not null then\n    if v_api_resolution_contract<>''API_CONTRACT_RESOLUTION_V1'' then\n      raise exception ''SCREEN_CANONICAL_GRAPH_UNSUPPORTED_API_RESOLUTION_CONTRACT:%:%'',p_version_id,v_api_resolution_contract;\n    end if;\n    v_contract:=jsonb_set(v_contract,''{api_contract_resolution}'',programacion.fn_input_api_contract_resolution(p_pantalla_id),true);\n  end if;\n\n';
begin
  v_def:=pg_get_functiondef('programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure);

  select count(*) into v_like_count
  from regexp_matches(v_def,$$like\s+'v0\.$$,'gi');
  if v_like_count<>3 then
    raise exception 'M26_GRAPH_PREIMAGE_VERSION_BRANCH_DRIFT:%',v_like_count;
  end if;
  if position('lf_ops.fn_b2b_backoffice_login_contract' in v_def)=0 then
    raise exception 'M26_GRAPH_LOGIN_CONTRACT_CALL_MISSING';
  end if;
  if position(v_decl_old in v_def)=0 then
    raise exception 'M26_GRAPH_DECLARATION_ANCHOR_MISSING';
  end if;

  v_new:=replace(v_def,v_decl_old,v_decl_new);

  v_start:=position('  select version_codigo into v_version_code from programacion.versiones_agente where id=p_version_id;' in v_new);
  v_end:=position('  select f.contract into v_contract from lf_ops.fn_b2b_backoffice_login_contract' in v_new);
  if v_start=0 or v_end=0 or v_end<=v_start then
    raise exception 'M26_GRAPH_VERSION_SELECTOR_ANCHOR_DRIFT';
  end if;
  v_new:=substr(v_new,1,v_start-1)||v_contract_selector||substr(v_new,v_end);

  v_start:=position('  if v_version_code like ' in v_new);
  v_end:=position('  return jsonb_build_object(' in v_new);
  if v_start=0 or v_end=0 or v_end<=v_start then
    raise exception 'M26_GRAPH_VERSION_ROUTING_ANCHOR_DRIFT';
  end if;
  v_new:=substr(v_new,1,v_start-1)||v_capability_routing||substr(v_new,v_end);

  execute v_new;

  v_def:=pg_get_functiondef('programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure);
  select count(*) into v_like_count
  from regexp_matches(v_def,$$like\s+'v0\.$$,'gi');
  if v_like_count<>0 then
    raise exception 'M26_GRAPH_VERSION_TEXT_BRANCH_REMAINS:%',v_like_count;
  end if;
  if position('version_codigo' in v_def)>0 then
    raise exception 'M26_GRAPH_VERSION_CODE_TEXT_DEPENDENCY_REMAINS';
  end if;
  if position('lf_ops.fn_b2b_backoffice_login_contract' in v_def)=0 then
    raise exception 'M26_GRAPH_LOGIN_CONTRACT_CALL_REGRESSION';
  end if;
  if position('INPUT_READINESS_CONTRACT' in v_def)=0 then
    raise exception 'M26_GRAPH_CONTRACT_ROUTING_MISSING';
  end if;
end;
$m26_remove_version_branch$;

commit;
