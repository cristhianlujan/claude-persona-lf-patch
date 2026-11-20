-- LF IG: contenido fallido => hallazgo READ_ONLY; contrato/transporte/fuente/autoridad => bloqueo de flujo.
-- Source-first exact pg_get_functiondef preimages from sandbox PG17.6; no writes to historical RUNs.
-- Protected handoff, handoff validator, authority packet and result classifier remain unchanged.
BEGIN;
DO $preflight$ BEGIN
IF md5(pg_get_functiondef('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure)) <> '142364e102b48d353d6e3b56816183ee' THEN
  RAISE EXCEPTION 'SOURCE_STATE_DRIFT:fn_lf_profile_adapter_input_governance_resolve_v1'; END IF;
IF md5(pg_get_functiondef('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure)) <> 'ab091d641cc1d3d923d20c0db96d9bc5' THEN
  RAISE EXCEPTION 'SOURCE_STATE_DRIFT:fn_lf_profile_input_governance_resolve_v1'; END IF;
IF md5(pg_get_functiondef('programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)'::regprocedure)) <> '06f024f37c34030f02291b44d4463bda' THEN
  RAISE EXCEPTION 'SOURCE_STATE_DRIFT:fn_lf_router_input_governance_derive_v1'; END IF;
END $preflight$;

-- fn_lf_profile_adapter_input_governance_resolve_v1: preimage=142364e102b48d353d6e3b56816183ee; content_branches=6
CREATE OR REPLACE FUNCTION programacion.fn_lf_profile_adapter_input_governance_resolve_v1(p_request_text text, p_adapters jsonb, p_consumer text DEFAULT 'STORY_CREATOR'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- Consumer identity is authority-bearing. Resolve the current allowlist from
  -- INPUT_GOVERNANCE_EXECUTION_CONTRACT and fail closed on unknown callers.
  if not coalesce((
    select (c.especificacion->'allowed_consumers') ? btrim(coalesce(p_consumer, ''))
    from programacion.contratos c
    where c.contrato_codigo = 'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      and c.estado = 'defined'
    order by c.id desc
    limit 1
  ), false) then
    return jsonb_build_object(
      'applicable', true,
      'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED',
      'decision', 'BLOCKED',
      'continuation_allowed', false,
      'consumer', p_consumer,
      'required_by_adapters', v_required_adapters
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
      'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',
      'remediation_action','RESOLVE_SCREEN_IN_PROFILE_WITH_SOURCE_EVIDENCE',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
      'required_by_adapters', v_required_adapters,
      'dispatch', jsonb_build_object(
        'runtime_orchestrator', 'POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1',
        'required_input', jsonb_build_array('pantalla_id'),
        'consumer', p_consumer,
        'resume_via', case when p_consumer='CONTEXT_PACK' then 'EJECUCION_PERFIL_LF/input_validate' else 'public.lf_router_resolve_v1' end
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

  v_worker_spec := public.fn_input_governance_worker_spec(v_pantalla_id, p_consumer);

  if nullif(v_worker_spec->>'current_run_id', '') is null then
    return jsonb_build_object(
      'applicable', true,
      'status', 'INPUT_GOVERNANCE_REQUIRED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED',
      'decision', 'PENDING',
      'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED',
      'remediation_action','CURATE_CURRENT_RUN_FROM_CANONICAL_SOURCE',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
      'required_by_adapters', v_required_adapters,
      'pantalla_id', v_pantalla_id,
      'screen_code', v_screen_code,
      'worker_spec', v_worker_spec,
      'dispatch', jsonb_build_object(
        'runtime_orchestrator', coalesce(v_worker_spec->>'runtime_orchestrator', 'POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1'),
        'runtime_action', v_worker_spec->>'runtime_action',
        'required_role', v_worker_spec->>'required_role',
        'consumer', p_consumer,
        'resume_via', case when p_consumer='CONTEXT_PACK' then 'EJECUCION_PERFIL_LF/input_validate' else 'public.lf_router_resolve_v1' end
      )
    );
  end if;

  v_agent_result := programacion.fn_input_governance_execute(v_pantalla_id, p_consumer);
  IF v_agent_result->>'remediation_state'='ACTION_AUTHORIZATION_GATE' THEN
    RETURN jsonb_build_object('applicable',true,'status','BLOCKED',
      'blocking_code','BLOCK_INPUT_GOVERNANCE_EFFECT_AUTHORITY',
      'decision','BLOCKED','continuation_allowed',false,
      'flow_block_cause','AUTHORITY_INVALID',
      'consumer',p_consumer,'pantalla_id',v_pantalla_id,
      'required_by_adapters',v_required_adapters);
  END IF;

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
      and public.fn_input_readiness_run_is_current(r.id);

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
        'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_INPUT_GOVERNANCE_RECEIPT_STALE',
      'remediation_action','RECURATE_STALE_RUN_SOURCE_FIRST',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
        'required_by_adapters', v_required_adapters,
        'pantalla_id', v_pantalla_id,
        'screen_code', v_screen_code,
        'worker_spec', public.fn_input_governance_worker_spec(v_pantalla_id, p_consumer)
      );
    end if;

    v_receipt := jsonb_build_object(
      'governance_agent_used', true,
      'governance_agent', 'ig-direct-sql-worker-v1',
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
      'contract_snapshot_sha256', v_contract_snapshot_sha256,
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
      'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',
      'remediation_action','REQUEST_OWNER_DECISION_NO_PRODUCTION_AUTHORITY',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
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
      'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_INPUT_GOVERNANCE',
      'remediation_action','RECURATE_IG_FROM_CURRENT_CANONICAL_SOURCES',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
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
    'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_INPUT_GOVERNANCE_RUNTIME_REQUIRED',
      'remediation_action','COMPLETE_GOVERNED_CURATOR_VALIDATOR_AND_RETRY_SKILL',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
    'required_by_adapters', v_required_adapters,
    'pantalla_id', v_pantalla_id,
    'screen_code', v_screen_code,
    'worker_spec', public.fn_input_governance_worker_spec(v_pantalla_id, p_consumer),
    'agent_status', v_agent_result->>'status'
  );
exception when others then
  IF split_part(SQLERRM,':',1) IN ('INPUT_GOVERNANCE_EKB_BLOCKED','INPUT_GOVERNANCE_CURRENT_RUN_FRESHNESS_GATE_FAILED','INPUT_GOVERNANCE_CURATOR_UNIVERSE_INCOMPLETE','INPUT_GOVERNANCE_VALIDATOR_NOT_FULL_AUTHORIZED_PASS','INPUT_GOVERNANCE_CURRENT_EVALUATION_NOT_TERMINAL') THEN
    RETURN jsonb_build_object('applicable',true,'status','BLOCKED',
      'blocking_code','BLOCK_INPUT_GOVERNANCE_CONTENT_EXCEPTION',
      'decision','FINDING','continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code',split_part(SQLERRM,':',1),
      'remediation_action','RECURATE_AND_REVALIDATE_CURRENT_SOURCE',
      'analysis_only',true,'production_authorized',false,
      'promotion_authorized',false,
      'required_by_adapters',coalesce(v_required_adapters,'[]'::jsonb));
  END IF;
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

-- fn_lf_profile_input_governance_resolve_v1: preimage=ab091d641cc1d3d923d20c0db96d9bc5; content_branches=3
CREATE OR REPLACE FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(p_request_text text, p_profile_code text, p_scope jsonb DEFAULT NULL::jsonb, p_consumer text DEFAULT 'CONTEXT_PACK'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops'
AS $function$
DECLARE
  v_ig_exception_code text;
  v_bound boolean:=false;
  v_screen_count integer:=0;
  v_pantalla_id integer;
  v_screen_code text:=nullif(btrim(coalesce(p_scope->>'resolved_screen_code','')),'');
  v_screen_request jsonb:=p_scope->'screen_selection_request';
  v_screen_result jsonb:=p_scope->'screen_selection_result';
  v_screen_validation jsonb;
  v_result jsonb;
  v_worker jsonb;
BEGIN
  SELECT EXISTS(
    SELECT 1
    FROM public.lf_activo_relaciones r
    JOIN public.lf_activos a
      ON a.codigo_activo=r.codigo_activo
     AND a.archived_at IS NULL
     AND a.tipo_activo='PERFIL'
    WHERE r.codigo_activo=p_profile_code
      AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND r.relacion_tipo='GOBERNADO_POR'
      AND a.metadata->>'input_governance_binding_mode'='DIRECT_PROFILE'
      AND a.metadata->>'input_governance_consumer'=p_consumer
  ) INTO v_bound;

  IF NOT v_bound THEN
    RETURN jsonb_build_object(
      'applicable',false,
      'status','NOT_REQUIRED',
      'decision','N/A',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'binding_mode','NO_DIRECT_PROFILE_BINDING',
      'router_reentry_required',false
    );
  END IF;

  IF upper(coalesce(p_scope->>'resolution_status',''))<>'RESOLVED'
     OR p_scope->>'resolution_method'<>'DETERMINISTIC_SHORTLIST_THEN_SEMANTIC'
     OR v_screen_code IS NULL
     OR v_screen_request IS NULL
     OR v_screen_result IS NULL
     OR jsonb_typeof(v_screen_request)<>'object'
     OR jsonb_typeof(v_screen_result)<>'object'
     OR v_screen_request->>'literal_request' IS DISTINCT FROM p_request_text
  THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_NOT_SEMANTICALLY_RESOLVED',
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'router_reentry_required',false
    );
  END IF;

  v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
    v_screen_request,v_screen_result
  );

  IF v_screen_validation->>'status'<>'VALID'
     OR v_screen_result->>'decision'<>'SELECTED'
     OR v_screen_result->>'selected_screen_code' IS DISTINCT FROM v_screen_code
  THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_SEMANTIC_RECEIPT_INVALID',
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'screen_selection_validation',v_screen_validation,
      'router_reentry_required',false
    );
  END IF;

  SELECT count(*),min(id),min(codigo)
    INTO v_screen_count,v_pantalla_id,v_screen_code
  FROM lf_ops.pantallas
  WHERE activa
    AND upper(codigo)=upper(v_screen_code);

  IF v_screen_count<>1 THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code',case
        when v_screen_count=0 then 'BLOCK_PROFILE_INPUT_GOVERNANCE_CANONICAL_SCREEN_NOT_FOUND'
        else 'BLOCK_PROFILE_INPUT_GOVERNANCE_CANONICAL_SCREEN_AMBIGUOUS'
      end,
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'router_reentry_required',false
    );
  END IF;

  BEGIN
    v_result:=programacion.fn_input_governance_execute(v_pantalla_id,p_consumer);
  EXCEPTION WHEN OTHERS THEN
    v_ig_exception_code:=split_part(SQLERRM,':',1);
    IF v_ig_exception_code IN ('INPUT_GOVERNANCE_EKB_BLOCKED','INPUT_GOVERNANCE_CURRENT_RUN_FRESHNESS_GATE_FAILED','INPUT_GOVERNANCE_CURATOR_UNIVERSE_INCOMPLETE','INPUT_GOVERNANCE_VALIDATOR_NOT_FULL_AUTHORIZED_PASS','INPUT_GOVERNANCE_CURRENT_EVALUATION_NOT_TERMINAL') THEN
      v_result:=jsonb_build_object('status','BLOCKED',
        'remediation_state','IG_CONTENT_CHECK_NOT_READY','content_cause',v_ig_exception_code,
        'production_authorized',false,'promotion_authorized',false);
    ELSE RAISE; END IF;
  END;
  -- Effect authority remains hard flow boundary.
  IF v_result->>'remediation_state'='ACTION_AUTHORIZATION_GATE' THEN
    RETURN jsonb_build_object('applicable',true,'status','BLOCKED',
      'blocking_code','BLOCK_INPUT_GOVERNANCE_EFFECT_AUTHORITY','decision','BLOCKED',
      'continuation_allowed',false,'flow_block_cause','AUTHORITY_INVALID',
      'profile_code',p_profile_code,'consumer',p_consumer,
      'governance_result',v_result,'router_reentry_required',false);
  END IF;

  IF v_result->>'status'='READY' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','READY',
      'blocking_code',null,
      'decision','PASS',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
      'run_id',v_result->'run_id',
      'governance_output_sha256',v_result->'output_sha256',
      'context_manifest',v_result->'context_manifest',
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status' IN ('CURATOR_RUNTIME_REQUIRED','VALIDATOR_RUNTIME_REQUIRED') THEN
    v_worker:=coalesce(
      v_result->'worker_spec',
      public.fn_input_governance_worker_spec(v_pantalla_id,p_consumer)
    );
    RETURN jsonb_build_object(
      'applicable',true,
      'status','INPUT_GOVERNANCE_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_REQUIRED',
      'decision','PENDING',
      'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_REQUIRED',
      'remediation_action','COMPLETE_GOVERNED_CURATOR_VALIDATOR_AND_RETRY_SKILL',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
      'agent_status',v_result->>'status',
      'worker_spec',v_worker,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status'='HUMAN_DECISION_REQUIRED' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','HUMAN_DECISION_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',
      'decision','PARTIAL',
      'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_PROFILE_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',
      'remediation_action','REQUEST_OWNER_DECISION_NO_PRODUCTION_AUTHORITY',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  RETURN jsonb_build_object(
    'applicable',true,
    'status','BLOCKED',
    'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE',
    'decision','BLOCKED',
    'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_PROFILE_INPUT_GOVERNANCE',
      'remediation_action','RECURATE_IG_FROM_CURRENT_CANONICAL_SOURCES',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
    'profile_code',p_profile_code,
    'consumer',p_consumer,
    'binding_mode','DIRECT_PROFILE',
    'pantalla_id',v_pantalla_id,
    'screen_code',v_screen_code,
    'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
    'governance_result',v_result,
    'resume_via','EJECUCION_PERFIL_LF/input_validate',
    'router_reentry_required',false
  );
END
$function$;

-- fn_lf_router_input_governance_derive_v1: preimage=06f024f37c34030f02291b44d4463bda; content_branches=2
CREATE OR REPLACE FUNCTION programacion.fn_lf_router_input_governance_derive_v1(p_request_text text, p_adapters jsonb, p_consumer text DEFAULT 'STORY_CREATOR'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_adapters jsonb := '[]'::jsonb;
  v_required_count integer := 0;
  v_invalid_contract_count integer := 0;
  v_request_norm text;
  v_screen_count integer := 0;
  v_pantalla_id integer;
  v_screen_code text;
  v_screen_matches jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(coalesce(p_adapters, '[]'::jsonb)) <> 'array' then
    return jsonb_build_object(
      'applicable', true, 'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_ADAPTER_METADATA_INVALID',
      'decision', 'BLOCKED', 'continuation_allowed', false
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
      'applicable', false, 'status', 'NOT_REQUIRED', 'blocking_code', null,
      'decision', 'N/A', 'continuation_allowed', true, 'required_by_adapters', '[]'::jsonb
    );
  end if;

  -- IG is owned by the profile. The Router never evaluates it, for any other consumer.
  if p_consumer is distinct from 'CONTEXT_PACK' then
    return jsonb_build_object(
      'applicable', true, 'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_PROFILE_ONLY',
      'decision', 'BLOCKED', 'continuation_allowed', false,
      'consumer', p_consumer, 'required_by_adapters', v_required_adapters
    );
  end if;

  if not coalesce((
    select (c.especificacion->'allowed_consumers') ? btrim(coalesce(p_consumer, ''))
    from programacion.contratos c
    where c.contrato_codigo = 'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      and c.estado = 'defined'
    order by c.id desc
    limit 1
  ), false) then
    return jsonb_build_object(
      'applicable', true, 'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED',
      'decision', 'BLOCKED', 'continuation_allowed', false,
      'consumer', p_consumer, 'required_by_adapters', v_required_adapters
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
      'applicable', true, 'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_ADAPTER_CONTRACT_INVALID',
      'decision', 'BLOCKED', 'continuation_allowed', false,
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
      'applicable', true, 'status', 'INPUT_GOVERNANCE_REQUIRED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',
      'decision', 'PENDING', 'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',
      'remediation_action','RESOLVE_SCREEN_IN_PROFILE_WITH_SOURCE_EVIDENCE',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
      'required_by_adapters', v_required_adapters,
      'consumer', p_consumer, 'derived_only', true,
      'resume_via', 'EJECUCION_PERFIL_LF/input_validate'
    );
  end if;

  if v_screen_count > 1 then
    return jsonb_build_object(
      'applicable', true, 'status', 'BLOCKED',
      'blocking_code', 'BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS',
      'decision', 'BLOCKED', 'continuation_allowed', false,
      'required_by_adapters', v_required_adapters,
      'screen_matches', v_screen_matches
    );
  end if;

  -- Derivation result: IG is required and the profile (EJECUCION_PERFIL_LF/input_validate) owns the gate.
  return jsonb_build_object(
    'applicable', true, 'status', 'INPUT_GOVERNANCE_REQUIRED',
    'blocking_code', null, 'decision', 'PENDING', 'continuation_allowed',true,
      'finding_class','INPUT_GOVERNANCE_CONTENT',
      'finding_code','INPUT_GOVERNANCE_PROFILE_DEPENDENCY',
      'remediation_action','PROFILE_OWNS_OPTIONAL_READ_ONLY_SKILL',
      'analysis_only',true,'production_authorized',false,'promotion_authorized',false,
    'required_by_adapters', v_required_adapters,
    'pantalla_id', v_pantalla_id, 'screen_code', v_screen_code,
    'consumer', p_consumer, 'derived_only', true,
    'resume_via', 'EJECUCION_PERFIL_LF/input_validate'
  );
end;
$function$;

-- Five causal EKB records start CANDIDATO: readback/testing required for verification.
INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,estado,lote_origen,source_ref)
 SELECT 'LF-IG-STEP40-RESOLVER-COUPLING-20261114-001','PROFILE_EXECUTION','Step40 acoplado a IG','IG quedaba obligatorio en el resolver_ref del paso 40.','Acoplar skill opcional a validacion contractual del perfil.','Seleccionar IG por politica de skills; error de contenido solo hallazgo.','PR3897; verificar 0-80 con/sin skill.','CANDIDATO','LF_IG_FLOW_ONLY_20261114','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3897'
 WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='LF-IG-STEP40-RESOLVER-COUPLING-20261114-001');

INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,estado,lote_origen,source_ref)
 SELECT 'LF-IG-V58-VALIDATOR-EXECUTION-ID-409-20261114-001','INPUT_GOVERNANCE','409 Validator execution_id requerido','VALIDATOR_EXECUTION_ID_REQUIRED impidio cierre de evaluacion V58.','Intento de validar sin recibo de identidad del Validator.','Usar Validator gobernado con execution_id; no forjar PASS; registrar hallazgo en perfil.','Prueba guard V58 PG17/18.','CANDIDATO','LF_IG_FLOW_ONLY_20261114','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/supabase/migrations/20261114145300_lf_ig_v58_validator_negative_guard_handoff_v1.sql'
 WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='LF-IG-V58-VALIDATOR-EXECUTION-ID-409-20261114-001');

INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,estado,lote_origen,source_ref)
 SELECT 'LF-IG-SCOPE-HASH-MISMATCH-20261114-001','PROFILE_EXECUTION','Hash de alcance divergente','Hash de scope no coincide con el paquete autorizado.','Canonizacion inconsistente del paquete de alcance.','Conservar payload canonico y revalidar digest; transporte invalido bloquea flujo.','Prueba negativa hash alterado pendiente.','CANDIDATO','LF_IG_FLOW_ONLY_20261114','supabase://public.lf_operation_execution_steps/input_validate'
 WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='LF-IG-SCOPE-HASH-MISMATCH-20261114-001');

INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,estado,lote_origen,source_ref)
 SELECT 'LF-IG-RAW-SEMANTIC-FIELDS-20261114-001','INPUT_GOVERNANCE','Campos semanticos en RAW','semantic_receipt_sha256, catalog_sha256, request_sha256 no pertenecen al cuerpo RAW.','Mezcla entre datos originales y recibos derivados.','Guarda determinista de campo prohibido antes de cada despacho.','Rollback por campo pendiente.','CANDIDATO','LF_IG_FLOW_ONLY_20261114','supabase://programacion.contratos/INPUT_GOVERNANCE_EXECUTION_CONTRACT'
 WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='LF-IG-RAW-SEMANTIC-FIELDS-20261114-001');

INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,estado,lote_origen,source_ref)
 SELECT 'LF-IG-90S-SYNCHRONOUS-TIMEOUT-20261114-001','INPUT_GOVERNANCE','Timeout sincronico de 90s','Agotamiento de espera puede bloquear el paso 40.','Dependencia sincrona con presupuesto excesivo.','Aplicar 12s Edge y 18s cliente, ticket agotado como hallazgo.','Prueba timeout offline; PR3897.','CANDIDATO','LF_IG_FLOW_ONLY_20261114','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3897'
 WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='LF-IG-90S-SYNCHRONOUS-TIMEOUT-20261114-001');
COMMIT;
