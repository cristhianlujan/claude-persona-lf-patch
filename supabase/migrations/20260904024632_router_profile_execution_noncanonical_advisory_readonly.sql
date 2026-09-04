do $patch$
declare
  v_definition text;
  v_anchor text := E'    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1(p_request_text,v_adapters,''STORY_CREATOR'');\n    if v_input_governance is null or not (v_input_governance ? ''applicable'') then';
  v_replacement text := E'    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1(p_request_text,v_adapters,''STORY_CREATOR'');\n\n    -- PROFILE_EXECUTION is strictly read-only. If the reviewed subject is not a canonical screen,\n    -- keep the same Router/Input Governance path but switch governance to advisory artifact mode.\n    -- Exact artifact identity remains mandatory downstream; this does not create or promote canon.\n    if v_operation.operation_code = ''EJECUCION_PERFIL_LF''\n       and v_operation.status = ''PRODUCCION_CONTROLADA_READ_ONLY''\n       and coalesce(v_input_governance->>''blocking_code'','''') = ''BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED'' then\n      v_input_governance := jsonb_build_object(\n        ''applicable'',true,\n        ''status'',''ADVISORY_READ_ONLY'',\n        ''blocking_code'',null,\n        ''decision'',''ADVISORY'',\n        ''continuation_allowed'',true,\n        ''subject_mode'',''NON_CANONICAL_ARTIFACT'',\n        ''required_by_adapters'',coalesce(v_input_governance->''required_by_adapters'',''[]''::jsonb),\n        ''required_artifact_binding'',jsonb_build_array(''artifact_ref'',''artifact_sha256'',''dimensions''),\n        ''constraints'',jsonb_build_object(\n          ''operation_must_equal'',''EJECUCION_PERFIL_LF'',\n          ''read_only'',true,\n          ''no_write'',true,\n          ''no_promotion'',true,\n          ''canonical_registration_required'',false,\n          ''artifact_binding_required_before_profile_execution'',true\n        ),\n        ''resume_via'',''EJECUCION_PERFIL_LF/input_validate''\n      );\n    end if;\n\n    if v_input_governance is null or not (v_input_governance ? ''applicable'') then';
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_definition;
  if v_definition is null then
    raise exception 'ROUTER_FUNCTION_NOT_FOUND';
  end if;
  if position('NON_CANONICAL_ARTIFACT' in v_definition) > 0 then
    raise exception 'ROUTER_NONCANONICAL_ADVISORY_ALREADY_PRESENT';
  end if;
  if position(v_anchor in v_definition) = 0 then
    raise exception 'ROUTER_NONCANONICAL_ADVISORY_ANCHOR_DRIFT';
  end if;
  v_definition := replace(v_definition,v_anchor,v_replacement);
  execute v_definition;
end
$patch$;

comment on function public.lf_router_resolve_v1(text,text,text,text,text) is
'ACT-0001 canonical Router. PROFILE_EXECUTION remains read-only and may continue for a NON_CANONICAL_ARTIFACT through Input Governance advisory mode only; no canon creation, write or promotion is authorized, and exact artifact_ref + sha256 + dimensions are required before profile execution.';
