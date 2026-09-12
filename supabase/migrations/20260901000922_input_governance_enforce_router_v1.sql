-- Remote ledger version: 20260901000922.
-- Enforce ACT-0001 -> INPUT_GOVERNANCE_AGENT -> PASS_ONLY without adding a new layer.
create or replace function programacion.fn_lf_router_input_governance_resolve_v1(
  p_request_text text,
  p_adapters jsonb,
  p_consumer text default 'STORY_CREATOR'::text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_required_adapters jsonb := '[]'::jsonb;
  v_required_count integer := 0;
  v_invalid_contract_count integer := 0;
  v_request_norm text;
  v_screen_count integer := 0;
  v_pantalla_id integer;
  v_screen_code text;
  v_screen_matches jsonb := '[]'::jsonb;
  v_worker_spec jsonb;
  v_agent_result jsonb;
  v_run_id bigint;
  v_source_snapshot_sha256 text;
  v_contract_revision text;
  v_contract_snapshot_sha256 text;
  v_run_created_at timestamptz;
  v_receipt jsonb;
begin
  if jsonb_typeof(coalesce(p_adapters, '[]'::jsonb)) <> 'array' then
    return jsonb_build_object(
      'applicable', true,
      'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_ADAPTER_METADATA_INVALID',
      'decision', 'BLOCKED',
      'continuation_allowed', false
    );
  end if;

  select count(*),
         coalesce(
           jsonb_agg(
             coalesce(e.value#>>'{adapter_metadata,canonical_adapter_id}', e.value->>'adapter_code')
             order by coalesce(e.value#>>'{adapter_metadata,canonical_adapter_id}', e.value->>'adapter_code')
           ),
           '[]'::jsonb
         )
    into v_required_count, v_required_adapters
  from jsonb_array_elements(coalesce(p_adapters, '[]'::jsonb)) e(value)
  where lower(coalesce(e.value#>>'{adapter_metadata,router_discoverable}', 'false')) = 'true'
    and lower(coalesce(e.value#>>'{adapter_metadata,runtime_enabled}', 'false')) = 'true'
    and lower(coalesce(e.value#>>'{adapter_metadata,input_governance_receipt_required}', 'false')) = 'true';

  if v_required_count = 0 then
    return jsonb_build_object(
      'applicable', false,
      'status', 'NOT_REQUIRED',
      'blocking_code', null,
      'decision', 'N/A',
      'continuation_allowed', true,
      'required_by_adapters', '[]'::jsonb
    );
  end if;

  select count(*)
    into v_invalid_contract_count
  from jsonb_array_elements(p_adapters) e(value)
  where lower(coalesce(e.value#>>'{adapter_metadata,router_discoverable}', 'false')) = 'true'
    and lower(coalesce(e.value#>>'{adapter_metadata,runtime_enabled}', 'false')) = 'true'
    and lower(coalesce(e.value#>>'{adapter_metadata,input_governance_receipt_required}', 'false')) = 'true'
    and (
      coalesce(e.value#>>'{adapter_metadata,input_governance_continuation_policy}', '') <> 'PASS_ONLY'
      or coalesce(e.value#>>'{adapter_metadata,input_governance_contract_resolution}', '') <> 'LIVE_CURRENT'
      or coalesce(e.value#>>'{adapter_metadata,input_governance_authority_contract}', '') <> 'INPUT_READINESS_CONTRACT'
    );

  if v_invalid_contract_count > 0 then
    return jsonb_build_object(
      'applicable', true,
      'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_ADAPTER_CONTRACT_INVALID',
      'decision', 'BLOCKED',
      'continuation_allowed', false,
      'required_by_adapters', v_required_adapters
    );
  end if;

  v_request_norm := ' ' || btrim(regexp_replace(lower(coalesce(p_request_text, '')), '[^a-z0-9_]+', ' ', 'g')) || ' ';

  select count(*), min(p.id), min(p.codigo),
         coalesce(jsonb_agg(jsonb_build_object('pantalla_id', p.id, 'screen_code', p.codigo) order by p.id), '[]'::jsonb)
    into v_screen_count, v_pantalla_id, v_screen_code, v_screen_matches
  from lf_ops.pantallas p
  where p.activa
    and strpos(
      v_request_norm,
      ' ' || btrim(regexp_replace(lower(p.codigo), '[^a-z0-9_]+', ' ', 'g')) || ' '
    ) > 0;

  if v_screen_count = 0 then
    return jsonb_build_object(
      'applicable', true,
      'status', 'INPUT_GOVERNANCE_REQUIRED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',
      'decision', 'PENDING',
      'continuation_allowed', false,
      'required_by_adapters', v_required_adapters,
      'dispatch', jsonb_build_object(
        'runtime_orchestrator', 'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1',
        'required_input', jsonb_build_array('pantalla_id'),
        'consumer', p_consumer,
        'resume_via', 'public.lf_router_resolve_v1'
      )
    );
  end if;

  if v_screen_count > 1 then
    return jsonb_build_object(
      'applicable', true,
      'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS',
      'decision', 'BLOCKED',
      'continuation_allowed', false,
      'required_by_adapters', v_required_adapters,
      'screen_matches', v_screen_matches
    );
  end if;

  v_worker_spec := programacion.fn_input_governance_worker_spec(v_pantalla_id, p_consumer);

  if nullif(v_worker_spec->>'current_run_id', '') is null then
    return jsonb_build_object(
      'applicable', true,
      'status', 'INPUT_GOVERNANCE_REQUIRED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED',
      'decision', 'PENDING',
      'continuation_allowed', false,
      'required_by_adapters', v_required_adapters,
      'pantalla_id', v_pantalla_id,
      'screen_code', v_screen_code,
      'worker_spec', v_worker_spec,
      'dispatch', jsonb_build_object(
        'runtime_orchestrator', coalesce(v_worker_spec->>'runtime_orchestrator', 'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1'),
        'runtime_action', v_worker_spec->>'runtime_action',
        'required_role', v_worker_spec->>'required_role',
        'consumer', p_consumer,
        'resume_via', 'public.lf_router_resolve_v1'
      )
    );
  end if;

  v_agent_result := programacion.fn_input_governance_execute(v_pantalla_id, p_consumer);

  if v_agent_result->>'status' = 'READY' then
    v_run_id := nullif(v_agent_result->>'run_id', '')::bigint;

    select r.source_snapshot_sha256,
           r.contract_revision,
           r.contract_snapshot_sha256,
           r.created_at
      into v_source_snapshot_sha256,
           v_contract_revision,
           v_contract_snapshot_sha256,
           v_run_created_at
    from programacion.input_readiness_runs r
    where r.id = v_run_id
      and r.pantalla_id = v_pantalla_id
      and r.status = 'COMPLETED'
      and r.invalidated_at is null
      and programacion.fn_input_readiness_run_is_current(r.id);

    if not found
       or (v_agent_result->>'pantalla_id')::integer is distinct from v_pantalla_id
       or v_agent_result->>'screen_code' is distinct from v_screen_code
       or v_source_snapshot_sha256 is null
       or v_contract_revision is null
       or v_contract_snapshot_sha256 is null then
      return jsonb_build_object(
        'applicable', true,
        'status', 'INPUT_GOVERNANCE_REQUIRED',
        'blocking_code', 'BLOCK_INPUT_GOVERNANCE_RECEIPT_STALE',
        'decision', 'PENDING',
        'continuation_allowed', false,
        'required_by_adapters', v_required_adapters,
        'pantalla_id', v_pantalla_id,
        'screen_code', v_screen_code,
        'worker_spec', programacion.fn_input_governance_worker_spec(v_pantalla_id, p_consumer)
      );
    end if;

    v_receipt := jsonb_build_object(
      'governance_agent_used', true,
      'governance_agent', 'input-governance-agent-v1',
      'governance_version', v_contract_revision,
      'sections_consumed', jsonb_build_array(
        'APPLICABILITY_READINESS',
        'SOURCE_AUTHORITY_PROVENANCE',
        'FRESHNESS_INVALIDATION',
        'NEGATIVE_REQUIREMENTS',
        'CONFLICT_PRECEDENCE'
      ),
      'source_refs', jsonb_build_array(
        'programacion.input_readiness_runs/' || v_run_id::text,
        'lf_ops.pantallas/' || v_pantalla_id::text,
        'programacion.contratos/INPUT_READINESS_CONTRACT@' || v_contract_revision
      ),
      'snapshot_hash', v_source_snapshot_sha256,
      'contract_snapshot_hash', v_contract_snapshot_sha256,
      'decision', 'PASS',
      'gap_or_na', 'NONE',
      'timestamp', now(),
      'run_id', v_run_id,
      'pantalla_id', v_pantalla_id,
      'screen_code', v_screen_code,
      'run_created_at', v_run_created_at,
      'agent_output_sha256', v_agent_result->>'output_sha256',
      'currentness', 'LIVE_CURRENT'
    );

    return jsonb_build_object(
      'applicable', true,
      'status', 'READY',
      'blocking_code', null,
      'decision', 'PASS',
      'continuation_allowed', true,
      'required_by_adapters', v_required_adapters,
      'pantalla_id', v_pantalla_id,
      'screen_code', v_screen_code,
      'worker_spec', v_worker_spec,
      'governance_receipt', v_receipt
    );
  end if;

  if v_agent_result->>'status' = 'HUMAN_DECISION_REQUIRED' then
    return jsonb_build_object(
      'applicable', true,
      'status', 'HUMAN_DECISION_REQUIRED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',
      'decision', 'PARTIAL',
      'continuation_allowed', false,
      'required_by_adapters', v_required_adapters,
      'pantalla_id', v_pantalla_id,
      'screen_code', v_screen_code,
      'run_id', v_agent_result->'run_id',
      'agent_output_sha256', v_agent_result->'output_sha256'
    );
  end if;

  if v_agent_result->>'status' = 'BLOCKED' then
    return jsonb_build_object(
      'applicable', true,
      'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE',
      'decision', 'BLOCKED',
      'continuation_allowed', false,
      'required_by_adapters', v_required_adapters,
      'pantalla_id', v_pantalla_id,
      'screen_code', v_screen_code,
      'run_id', v_agent_result->'run_id',
      'agent_output_sha256', v_agent_result->'output_sha256'
    );
  end if;

  return jsonb_build_object(
    'applicable', true,
    'status', 'INPUT_GOVERNANCE_REQUIRED',
    'blocking_code', 'BLOCK_INPUT_GOVERNANCE_RUNTIME_REQUIRED',
    'decision', 'PENDING',
    'continuation_allowed', false,
    'required_by_adapters', v_required_adapters,
    'pantalla_id', v_pantalla_id,
    'screen_code', v_screen_code,
    'worker_spec', programacion.fn_input_governance_worker_spec(v_pantalla_id, p_consumer),
    'agent_status', v_agent_result->>'status'
  );
exception when others then
  return jsonb_build_object(
    'applicable', coalesce(v_required_count, 0) > 0,
    'status', 'BLOCKED',
    'blocking_code', 'BLOCK_INPUT_GOVERNANCE_EVALUATION_FAILED',
    'decision', 'BLOCKED',
    'continuation_allowed', false,
    'required_by_adapters', coalesce(v_required_adapters, '[]'::jsonb),
    'error_sqlstate', sqlstate
  );
end;
$function$;

revoke all on function programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)
  from public, anon, authenticated;
grant execute on function programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)
  to service_role;

comment on function programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text) is
  'Internal ACT-0001 resolver. Reads adapter metadata, reuses INPUT_GOVERNANCE_AGENT currentness/execution contracts, and fail-closes unless PASS_ONLY has a live READY run. It never invokes an Edge Function and does not create another gate or agent.';

do $router_patch$
declare
  v_definition text;
  v_declare_anchor text := E'  v_step_count integer := 0;\n';
  v_policy_anchor text := E'  select coalesce(jsonb_agg(jsonb_build_array(p.policy_code,p.policy_version,p.policy_sha) order by p.policy_role,p.policy_code),''[]''::jsonb) into v_policy_refs\n  from public.v_lf_operation_policy_snapshot p\n  where p.operation_code=v_operation.operation_code and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));\n\n  if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),''[]''::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;';
  v_tail_anchor text := E'    ''composition_order'',jsonb_build_array(''SHELL'',''PROFILE'',''ADAPTER'',''POLICY_AND_CONTRACT_GATES'')\n  );';
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_definition;

  if v_definition is null then
    raise exception 'ROUTER_INPUT_GOVERNANCE_PATCH_FUNCTION_MISSING';
  end if;
  if position('fn_lf_router_input_governance_resolve_v1' in v_definition) > 0 then
    raise exception 'ROUTER_INPUT_GOVERNANCE_PATCH_ALREADY_PRESENT';
  end if;
  if position(v_declare_anchor in v_definition) = 0
     or position(v_policy_anchor in v_definition) = 0
     or position(v_tail_anchor in v_definition) = 0 then
    raise exception 'ROUTER_INPUT_GOVERNANCE_PATCH_ANCHOR_DRIFT';
  end if;

  v_definition := replace(
    v_definition,
    v_declare_anchor,
    v_declare_anchor || E'  v_input_governance jsonb := null;\n'
  );

  v_definition := replace(
    v_definition,
    v_policy_anchor,
    v_policy_anchor || E'\n\n  if jsonb_array_length(v_adapters)>0 then\n    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1(p_request_text,v_adapters,''STORY_CREATOR'');\n    if v_input_governance is null or not (v_input_governance ? ''applicable'') then\n      v_input_governance := jsonb_build_object(''applicable'',true,''status'',''BLOCKED'',''blocking_code'',''BLOCK_INPUT_GOVERNANCE_RESOLUTION_INVALID'',''decision'',''BLOCKED'',''continuation_allowed'',false);\n    end if;\n    if coalesce((v_input_governance->>''applicable'')::boolean,false) then\n      if not coalesce((v_input_governance->>''continuation_allowed'')::boolean,false) then\n        return jsonb_build_object(\n          ''status'',v_input_governance->>''status'',''blocking_code'',v_input_governance->>''blocking_code'',''router'',''ACT-0001'',''source'',''SUPABASE'',\n          ''discovery_source'',''public.v_lf_fuente_operativa_busqueda'',\n          ''asset'',case when v_asset_found then jsonb_build_object(''codigo_activo'',v_asset.codigo_activo,''nombre_canonico'',v_asset.nombre_canonico,''tipo_activo'',v_asset.tipo_activo,''subtipo_activo'',v_asset.subtipo_activo,''estado_documental'',v_asset.estado_documental,''estado_operativo'',v_asset.estado_operativo,''version'',v_asset.version) else null end,\n          ''asset_type'',v_type_hint,''action_code'',v_action,''operation_code'',v_operation.operation_code,\n          ''operation_status'',v_operation.status,''operation_applies_to_asset_type'',v_operation.applies_to_asset_type,\n          ''contract_count'',v_contract_count,''contract_refs'',v_contract_refs,''step_count'',v_step_count,''next_step'',v_next_step,\n          ''next_step_ref'',v_operation.operation_code||''/''||(v_next_step->>''step_id''),\n          ''required_policy_count'',v_required_policy_count,''resolved_policy_count'',v_resolved_policy_count,''policy_refs'',v_policy_refs,\n          ''policy_stale_guard'',''public.lf_operation_policy_snapshot_guard_v1'',''adapters'',v_adapters,\n          ''input_governance'',v_input_governance,''downstream_execution_allowed'',false,\n          ''precedence'',jsonb_build_array(''OPERATION_CONTRACT'',''POLICY'',''ADAPTER'',''PROFILE'',''SHELL''),\n          ''composition_order'',jsonb_build_array(''SHELL'',''PROFILE'',''ADAPTER'',''POLICY_AND_CONTRACT_GATES'')\n        );\n      end if;\n    else\n      v_input_governance := null;\n    end if;\n  end if;'
  );

  v_definition := replace(
    v_definition,
    v_tail_anchor,
    E'    ''composition_order'',jsonb_build_array(''SHELL'',''PROFILE'',''ADAPTER'',''POLICY_AND_CONTRACT_GATES'')\n  ) || case when v_input_governance is null then ''{}''::jsonb else jsonb_build_object(''input_governance'',v_input_governance,''downstream_execution_allowed'',true) end;'
  );

  execute v_definition;
end;
$router_patch$;

revoke all on function public.lf_router_resolve_v1(text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.lf_router_resolve_v1(text,text,text,text,text)
  to service_role;

comment on function public.lf_router_resolve_v1(text,text,text,text,text) is
  'ACT-0001 Router resolver. Adapter bindings with live input_governance_receipt_required=true fail closed until INPUT_GOVERNANCE_AGENT has a current READY run; only PASS_ONLY continues.';

update public.lf_activos
set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'input_governance_enforcement_v1', jsonb_build_object(
        'status', 'ACTIVE_ENFORCEMENT',
        'binding_source', 'public.v_lf_router_adapter_bindings.adapter_metadata',
        'resolver', 'programacion.fn_lf_router_input_governance_resolve_v1',
        'runtime_orchestrator', 'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1',
        'continuation_policy', 'PASS_ONLY',
        'contract_resolution', 'LIVE_CURRENT',
        'authority_contract', 'INPUT_READINESS_CONTRACT',
        'no_new_layer', true,
        'activated_at', now()
      )
    ),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-ACT0001-INPUT-GOVERNANCE-20260831-001'
where codigo_activo = 'ACT-0001'
  and archived_at is null;

do $canary$
declare
  v_result jsonb;
begin
  v_result := programacion.fn_lf_router_input_governance_resolve_v1(
    'fixture without governed adapters',
    '[]'::jsonb,
    'STORY_CREATOR'
  );
  if v_result->>'status' <> 'NOT_REQUIRED'
     or coalesce((v_result->>'continuation_allowed')::boolean,false) is not true then
    raise exception 'ROUTER_INPUT_GOVERNANCE_CANARY_F_HELPER_FAILED:%', v_result;
  end if;

  v_result := public.lf_router_resolve_v1(
    'Pídele al UI Architect que evalúe la pantalla ONB_002',
    'PERFIL-UI-ARCHITECT',
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );
  if v_result->>'status' <> 'INPUT_GOVERNANCE_REQUIRED'
     or v_result->>'blocking_code' <> 'BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED'
     or v_result#>>'{input_governance,screen_code}' <> 'ONB_002'
     or v_result#>>'{input_governance,dispatch,runtime_orchestrator}' <> 'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1'
     or coalesce((v_result->>'downstream_execution_allowed')::boolean,true) is not false then
    raise exception 'ROUTER_INPUT_GOVERNANCE_CANARY_A_FAILED:%', v_result;
  end if;

  v_result := public.lf_router_resolve_v1(
    'Pídele al perfil CX Trust que evalúe la pantalla ONB_002',
    'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );
  if v_result->>'status' <> 'READY_TO_EXECUTE'
     or v_result ? 'input_governance'
     or v_result ? 'downstream_execution_allowed' then
    raise exception 'ROUTER_INPUT_GOVERNANCE_CANARY_F_ROUTER_FAILED:%', v_result;
  end if;

  if has_function_privilege('anon', 'programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)', 'execute')
     or has_function_privilege('authenticated', 'programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)', 'execute') then
    raise exception 'ROUTER_INPUT_GOVERNANCE_HELPER_PRIVILEGE_LEAK';
  end if;
end;
$canary$;
