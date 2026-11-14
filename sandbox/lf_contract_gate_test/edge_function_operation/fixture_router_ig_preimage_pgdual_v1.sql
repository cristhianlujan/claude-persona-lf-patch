-- Snapshot of actual current sandbox function bodies at 2026-11-14 12:50 Lima.
-- For isolated, disposable PG17/18 regression only. NEVER deploy this fixture in LF.
CREATE SCHEMA programacion;
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.pantallas (id integer, codigo text, activa boolean);
CREATE SCHEMA extensions;
CREATE TABLE public.lf_activos (codigo_activo text);
CREATE TABLE public.lf_router_action_registry (codigo text);
CREATE TABLE public.lf_operation_registry (operation_code text);
CREATE TABLE public.lf_skill_selector_policy_v1 (
 profile_code text, skill_code text, channels text[],required_operation text,
 allowed_effects text[],selection_mode text,enabled boolean,owner_decision_required boolean,
 applicability_contract jsonb,policy_evidence_ref text,updated_at timestamptz);
CREATE TABLE public.lf_skill_catalog_v1 (skill_code text, status text,effect text);
CREATE TABLE public.lf_skill_selection_registry_v1 (
 skill_code text,descriptor_status text,descriptor jsonb,source_revision text);
INSERT INTO public.lf_skill_catalog_v1 VALUES
 ('INPUT_GOVERNANCE_CONTEXT_PACK','READY','READ_ONLY');
INSERT INTO public.lf_skill_selection_registry_v1 VALUES
 ('INPUT_GOVERNANCE_CONTEXT_PACK','CURRENT',
  '{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1"}'::jsonb,
  'sha256:25dd30f67ed5759209b11a7e7d993d7766bd3c5cedf5f79a61976e25362980dc');
INSERT INTO public.lf_skill_selector_policy_v1
(profile_code,skill_code,channels,required_operation,allowed_effects,selection_mode,
 enabled,owner_decision_required,applicability_contract,policy_evidence_ref,updated_at)
SELECT p,'INPUT_GOVERNANCE_CONTEXT_PACK',
 CASE WHEN p IN ('ACT-0051','PERFIL-UI-ARCHITECT')
        THEN ARRAY['PRODUCTO','PROGRAMACION']::text[]
      WHEN p IN ('PERFIL-QUALITY-PACK','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF')
        THEN ARRAY['PRODUCTO','PROGRAMACION','OPERACIONES']::text[]
      WHEN p='PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF' THEN ARRAY['OPERACIONES']::text[]
      ELSE ARRAY['PRODUCTO']::text[] END,
 'EJECUCION_PERFIL_LF',ARRAY['READ_ONLY']::text[],
 CASE WHEN p='PERFIL-PRODUCT-DIRECTOR-LF' THEN 'SEMANTIC_OPTIONAL' ELSE 'DETERMINISTIC_REQUIRED' END,
 true,false,
 CASE WHEN p='PERFIL-PRODUCT-DIRECTOR-LF' THEN
  '{"source":"OWNER_DUAL_RUN_MANDATE_2026_11_14","evaluation":"PROFILE_OWNED_SEMANTIC_SKILL_SELECTION","only_if_applicable":true,"no_content_block_of_profile":true}'::jsonb
 ELSE '{"evaluation":"EVIDENCE_PAYLOAD","only_if_applicable":true}'::jsonb END,
 'owner://lf/2026-11-14/baseline-fixture',now()
FROM unnest(ARRAY[
 'ACT-0051','PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING',
 'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
 'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
 'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT','PERFIL-PRODUCT-DIRECTOR-LF',
 'PERFIL-QUALITY-PACK','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
 'PERFIL-UI-ARCHITECT',
 'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531']) AS p;

-- EXACT sandbox pg_get_functiondef snapshots:
-- programacion.fn_lf_profile_adapter_input_governance_resolve_v1 md5=99bd5fa7024987dbe6e4018a9e87d81b
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
$function$
;

-- programacion.fn_lf_router_input_governance_derive_v1 md5=4b345c4659c8f7ce4af15064db11b82b
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
$function$
;

-- public.lf_router_resolve_core_v1 md5=ebb137df72e52c016e0e66c24035aeaf
CREATE OR REPLACE FUNCTION public.lf_router_resolve_core_v1(p_request_text text, p_target_hint text DEFAULT NULL::text, p_action_hint text DEFAULT NULL::text, p_asset_type_hint text DEFAULT NULL::text, p_distribution_mode text DEFAULT 'ROUTER'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_req text;
  v_executor_candidates jsonb := '[]'::jsonb;
  v_screen_subjects jsonb := '[]'::jsonb;
  v_screen_subject_count integer := 0;
  v_target_norm text;
  v_action text;
  v_type_hint text;
  v_candidate_code text;
  v_asset public.lf_activos%rowtype;
  v_asset_found boolean := false;
  v_rule public.lf_router_action_registry%rowtype;
  v_operation public.lf_operation_registry%rowtype;
  v_target_operation public.lf_operation_registry%rowtype;
  v_contract_refs jsonb := '[]'::jsonb;
  v_next_step jsonb := null;
  v_policy_refs jsonb := '[]'::jsonb;
  v_adapters jsonb := '[]'::jsonb;
  v_required_policy_count integer := 0;
  v_resolved_policy_count integer := 0;
  v_contract_count integer := 0;
  v_step_count integer := 0;
  v_input_governance jsonb := null;
  v_exact_asset_candidates jsonb := '[]'::jsonb;
  v_exact_asset_count integer := 0;
  v_artifact_discovery jsonb := null;
  v_discovery_count integer := 0;
  v_semantic_resume_internal boolean := false;
begin
  v_semantic_resume_internal := (
    current_user = 'postgres'
    and current_setting('lf.router_semantic_resume_request_sha',true) = encode(extensions.digest(convert_to(coalesce(p_request_text,''),'UTF8'),'sha256'),'hex')
    and lower(coalesce(current_setting('lf.router_semantic_resume_target',true),'')) = lower(btrim(coalesce(p_target_hint,'')))
    and upper(coalesce(current_setting('lf.router_semantic_resume_action',true),'')) = upper(btrim(coalesce(p_action_hint,'')))
    and upper(coalesce(current_setting('lf.router_semantic_resume_asset_type',true),'')) = upper(btrim(coalesce(p_asset_type_hint,'')))
  );
  if btrim(coalesce(p_request_text,''))='' then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_EMPTY_REQUEST','router','ACT-0001');
  end if;

  v_req := regexp_replace(translate(lower(coalesce(p_request_text,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');
  v_req := regexp_replace(v_req,'\s+',' ','g');
  v_target_norm := regexp_replace(translate(lower(coalesce(p_target_hint,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');

  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint,'')),''));
  if v_type_hint is null then
    if v_req ~ '(^| )(perfil|profile)( |$)' or v_req ~ '(^| )pidele (al|a|el) ' then v_type_hint := 'PERFIL';
    elsif v_req ~ '(^| )skill( |$)' then v_type_hint := 'SKILL';
    elsif v_req ~ '(^| )adapter( |$)' then v_type_hint := 'ADAPTER';
    elsif v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)' and v_req ~ '(^| )(regla|policy)( |$)' and v_req ~ '(^| )(pantalla|screen)( |$)' then v_type_hint := 'REGLA_PANTALLA_RELATION';
    elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then v_type_hint := 'REGLA';
    elsif v_req ~ '(^| )(estrategia|strategy)( |$)' then v_type_hint := 'STRATEGY';
    elsif v_req ~ '(^| )(doc|documento)( |$)' then v_type_hint := 'DOC';
    end if;
  end if;

  if v_target_norm<>'' then
    if v_type_hint='OPERATION_CODE' then
      select r.* into v_target_operation
      from public.lf_operation_registry r
      where lower(r.operation_code)=lower(btrim(coalesce(p_target_hint,'')))
      order by r.operation_code
      limit 1;
      v_asset_found := found;
      if v_asset_found then v_candidate_code := v_target_operation.operation_code; end if;
    else
      select b.codigo_activo into v_candidate_code
    from public.v_lf_fuente_operativa_busqueda b
    where (v_type_hint is null or b.tipo_activo=v_type_hint)
      and (
        regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        or regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        or exists (
          select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
          where regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        )
      )
      order by b.codigo_activo limit 1;
      v_asset_found := found;
    end if;
  else
    -- Match complete registry identities only; never promote token similarity
    -- or keyword scores into a canonical asset identity.
    select coalesce(jsonb_agg(jsonb_build_object(
             'asset_code',x.codigo_activo,'asset_type',x.tipo_activo
           ) order by x.codigo_activo),'[]'::jsonb), count(*)::integer
      into v_exact_asset_candidates,v_exact_asset_count
    from (
      select distinct b.codigo_activo,b.tipo_activo
      from public.v_lf_fuente_operativa_busqueda b
      where (
          (length(btrim(b.codigo_activo))>=6
            and position(
              ' '||btrim(regexp_replace(translate(lower(b.codigo_activo),
                  'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' ')>0)
          or ((v_type_hint is null or b.tipo_activo=v_type_hint)
              and (length(btrim(b.nombre_canonico))>=8
            and position(
              ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),
                  'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' ')>0))
          or ((v_type_hint is null or b.tipo_activo=v_type_hint)
              and exists (
            select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
            where length(btrim(al))>=8
              and position(
                ' '||btrim(regexp_replace(translate(lower(al),
                    'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
                in ' '||v_req||' ')>0
          ))
        )
    ) x;

    if v_exact_asset_count>1 then
      return jsonb_build_object(
        'router','ACT-0001','source','SUPABASE','status','BLOCKED',
        'asset_type',null,'action_code',null,'operation_code',null,
        'blocking_code','BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE',
        'subject_binding_state','AMBIGUOUS',
        'subject_candidates',v_exact_asset_candidates,
        'semantic_handoff',public.lf_router_intent_handoff_v1(
          p_request_text,v_exact_asset_candidates,'CANONICAL_ASSET'),
        'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
          p_request_text,v_exact_asset_candidates,'CANONICAL_ASSET'),
        'semantic_gap_code','POSITIVE_NEGATIVE_TARGET_ROLES_UNATTESTED',
        'semantic_resolution_required',true,
        'request_sha256',encode(extensions.digest(
          convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
        'downstream_execution_allowed',false
      );
    elsif v_exact_asset_count=1 then
      v_candidate_code:=v_exact_asset_candidates->0->>'asset_code';
      v_asset_found:=true;
    end if;
  end if;

  if v_asset_found then
    if v_type_hint='OPERATION_CODE' then
      v_asset.codigo_activo := v_target_operation.operation_code;
      v_asset.nombre_canonico := v_target_operation.operation_code;
      v_asset.tipo_activo := 'OPERATION_CODE';
      v_asset.subtipo_activo := v_target_operation.operation_type;
      v_asset.estado_documental := v_target_operation.lifecycle_state_code;
      v_asset.estado_operativo := v_target_operation.status;
      v_asset.version := v_target_operation.version;
    else
      select a.* into v_asset from public.lf_activos a
      where a.codigo_activo=v_candidate_code and a.archived_at is null limit 1;
      if not found then
        return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_MASTER_ASSET_HYDRATION_FAILED','router','ACT-0001','asset_code',v_candidate_code);
      end if;
      v_type_hint := v_asset.tipo_activo;
    end if;
  end if;

  v_action := upper(nullif(btrim(coalesce(p_action_hint,'')),''));
  if v_action is null then
    if v_req ~ '(^| )(consulta|consultar|estado|metadata|existe)( |$)' then v_action:='ASSET_INSPECTION';
    elsif v_type_hint='REGLA_PANTALLA_RELATION' and v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)' then v_action:='REGLA_PANTALLA_LINK';
    elsif v_type_hint='CAPABILITY'
      and v_asset_found
      and v_asset.codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|realiza|realizar)( |$)'
      then v_action:='INPUT_GOVERNANCE_EXECUTION';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|continua|continuar|retoma|retomar)( |$)' then v_action:='STRATEGY_EXECUTION';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(cierra|cerrar|cierre|finaliza|finalizar)( |$)' then v_action:='STRATEGY_CLOSE';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then v_action:='STRATEGY_CREATE';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then v_action:='STRATEGY_UPDATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_CREATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_UPDATE';
    elsif v_type_hint='PERFIL' and v_asset_found then v_action:='PROFILE_EXECUTION';
    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; elsif v_type_hint='REGLA' then v_action:='REGLA_CREATE'; else v_action:='CREATE'; end if;
    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE'; elsif v_type_hint='REGLA' then v_action:='REGLA_UPDATE'; else v_action:='UPDATE'; end if;
    else v_action:='ASSET_INSPECTION'; end if;
  end if;

  -- Repository paths are working subjects, never profile/skill executors.
  -- Read only the exact governed checkpoint artifact declarations.
  if nullif(btrim(coalesce(p_target_hint,'')),'') is null
     and p_request_text ~ '[[:alnum:]_.-]+(/[[:alnum:]_.-]+)+[.][[:alnum:]_-]+'
  then
    v_artifact_discovery:=public.lf_router_declared_artifact_candidates_v1(
      p_request_text
    );
    v_discovery_count:=coalesce((v_artifact_discovery->>'match_count')::integer,0);
    return jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code',case
        when v_discovery_count=1 then 'BLOCK_ARTIFACT_CONSUMER_UNATTESTED'
        when v_discovery_count>1 then 'BLOCK_MULTIPLE_ARTIFACT_TARGETS'
        else 'BLOCK_EXACT_ARTIFACT_BINDING_UNRESOLVED' end,
      'asset_type',null,'subject_type','REPOSITORY_ARTIFACT',
      'action_code',v_action,'operation_code',null,
      'subject_binding_state',case when v_discovery_count=1 then 'RESOLVED'
        when v_discovery_count>1 then 'AMBIGUOUS' else 'UNRESOLVED' end,
      'subject_candidates',v_artifact_discovery->'matches',
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,v_artifact_discovery->'matches','REPOSITORY_ARTIFACT'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,v_artifact_discovery->'matches','REPOSITORY_ARTIFACT'),
      'subject_resolution_source','programacion.engineering_plan_units.action_specs_v1',
      'next_governance_entrypoint',case when v_discovery_count=1 then
        'programacion.fn_engineering_unit_bootstrap_v3' else null end,
      'executor_selection_state','NOT_SELECTED',
      'semantic_gap_code','EXECUTOR_AND_REQUEST_SCOPE_UNATTESTED',
      'semantic_resolution_required',true,
      'request_sha256',encode(extensions.digest(
        convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false
    );
  end if;

  -- ACT-0001 target identity is NOT user intent/authorization. The only
  -- reliable path for an explicit mutation target is an independently governed
  -- operation binding. Caller-supplied target/action/type/mode are NOT evidence.
  -- No keyword-based semantic inference or alternate ROUTER mode can bypass.
  if not v_semantic_resume_internal
     and nullif(btrim(coalesce(p_target_hint,'')),'') is not null
     and v_action not in ('ASSET_INSPECTION')
     and v_action in (
       select distinct ar.action_code
       from public.lf_router_action_registry ar
       where ar.requires_existing_target or ar.requires_missing_target
     )
  then
    return jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED',
      'asset_type',null,'action_code',null,'operation_code',null,
      'candidate_asset_type',v_type_hint,
      'candidate_action_code',v_action,
      'subject_binding_state',case when v_asset_found then 'CANDIDATE'
                                   else 'UNRESOLVED' end,
      'subject_candidates',case when v_asset_found then
        jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,
          'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,case when v_asset_found then
          jsonb_build_array(jsonb_build_object(
            'asset_code',v_asset.codigo_activo,
            'asset_type',v_asset.tipo_activo))
          else '[]'::jsonb end,'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,case when v_asset_found then
          jsonb_build_array(jsonb_build_object(
            'asset_code',v_asset.codigo_activo,
            'asset_type',v_asset.tipo_activo))
          else '[]'::jsonb end,'CANONICAL_ASSET')
        || jsonb_build_object(
          'router_action_binding',
          public.lf_router_action_binding_snapshot_v1(p_request_text,v_type_hint,v_action)
        ),
      'semantic_resolution_required',true,
      'semantic_gap_code','EXPLICIT_TARGET_IS_NOT_SCOPE_AUTHORITY',
      'siguiente_paso',jsonb_build_object(
        'tipo','REPETIR_SOLO_CON_TEXTO_LITERAL',
        'llamada_correcta','lf_router_resolve_v1(<texto literal del usuario>)',
        'input_literal',p_request_text,
        'instruccion_es','No envies target, accion ni tipo de activo: el Router no los usa como evidencia. Repite la llamada con SOLO el texto literal del usuario; el Router resuelve la pantalla/activo y el perfil por si mismo y te devuelve el siguiente paso.'),
      'executor_selection_state','NOT_SELECTED',
      'request_sha256',encode(extensions.digest(
        convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false
    );
  end if;

  -- Actor-role guard after canonical discovery, before operation resolution.
  -- A screen / subject change does not update a profile, skill or adapter.
  -- Lexical matches are evidence candidates, never execution authority.
  IF nullif(btrim(coalesce(p_target_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_asset_type_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_action_hint,'')),'') IS NULL
     AND (
       v_type_hint IN ('PERFIL','SKILL','ADAPTER')
       OR (
         v_type_hint is null
         and v_req ~ '(^| )(pantalla|screen)( |$)'
       )
     )
     AND v_req ~ '^(por favor )?(cambiar|cambia|modificar|modifica|actualizar|actualiza|corregir|corrige|ajustar|ajusta|editar|edita|reemplazar|reemplaza|renombrar|renombra)( |$)'
     AND NOT v_req ~ '(^| )(perfil|profile|skill|adapter)( |$)'
     AND NOT EXISTS (
       SELECT 1 FROM public.v_lf_fuente_operativa_busqueda b
       WHERE b.codigo_activo=v_asset.codigo_activo
         AND (
           position(' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR position(' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
               WHERE length(btrim(al))>=8
                 AND position(' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0)
         )
     )
  THEN
    SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.keyword_match_count DESC,c.asset_code),'[]'::jsonb)
      INTO v_executor_candidates
    FROM (
      SELECT b.codigo_activo AS asset_code, b.tipo_activo AS asset_type,
             b.estado_operativo AS operational_status,
             count(DISTINCT kw.keyword) AS keyword_match_count,
             jsonb_agg(DISTINCT kw.keyword) AS matching_keywords
      FROM public.v_lf_fuente_operativa_busqueda b
      CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw(keyword)
      WHERE b.tipo_activo IN ('PERFIL','SKILL')
        AND length(btrim(kw.keyword))>=3
        AND position(' '||btrim(regexp_replace(translate(lower(kw.keyword),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
      GROUP BY b.codigo_activo,b.tipo_activo,b.estado_operativo
      ORDER BY count(DISTINCT kw.keyword) DESC,b.codigo_activo
      LIMIT 5
    ) c;
    -- Subject discovery is not executor selection. Match canonical screen
    -- names as complete normalized phrases, not individual lexical keywords.
    SELECT count(*),
           coalesce(jsonb_agg(jsonb_build_object(
             'screen_code',p.codigo,
             'pantalla_id',p.id,
             'screen_name',p.nombre,
             'screen_state',p.estado,
             'module_code',p.module_code
           ) ORDER BY p.codigo),'[]'::jsonb)
      INTO v_screen_subject_count,v_screen_subjects
    FROM lf_ops.pantallas p
    WHERE p.activa
      AND length(btrim(p.nombre))>=8
      AND position(
        ' '||btrim(regexp_replace(
          translate(lower(p.nombre),'áéíóúüñ','aeiouun'),
          '[^a-z0-9_]+',' ','g'
        ))||' '
        IN ' '||v_req||' '
      )>0;

    RETURN jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_EXECUTOR_CAPABILITY_UNATTESTED',
      'asset_type',NULL,'action_code','UPDATE','operation_code',NULL,
      'subject_binding_state',case
        when v_screen_subject_count=1 then 'RESOLVED'
        when v_screen_subject_count>1 then 'AMBIGUOUS'
        else 'UNRESOLVED'
      end,
      'subject_candidates',v_screen_subjects,
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,v_screen_subjects,'CANONICAL_SCREEN'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,v_screen_subjects,'CANONICAL_SCREEN'),
      'executor_selection_state','CANDIDATES_ONLY_NOT_AUTHORIZED',
      'executor_candidates',v_executor_candidates,
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'semantic_resolution_required',true,
      'semantic_gap_code','TARGET_VS_EXECUTOR_ROLE_UNATTESTED',
      'siguiente_paso',case
        when v_screen_subject_count=1 and jsonb_array_length(v_executor_candidates)>0 then jsonb_build_object(
          'operation_code','EJECUCION_PERFIL_LF',
          'entrypoint','ROUTER_ONLY',
          'flujo',jsonb_build_array('ACT-0001','EJECUCION_PERFIL_LF',v_executor_candidates->0->>'asset_code'),
          'executor_mode','GPT_NATIVE',
          'read_only',true,
          'no_write',true,
          'profile_source_mode','JIT_BY_REF',
          'input_literal',p_request_text,
          'alcance_permitido',(SELECT coalesce(jsonb_agg(s->>'screen_code'),'[]'::jsonb) FROM jsonb_array_elements(v_screen_subjects) s),
          'nota_es','BLOQUEADO significa que el Router no autoriza efectos; no impide que el perfil trabaje en solo lectura. Abrir esta operacion con la frase literal: el perfil devuelve una propuesta y no escribe. Aplicar el cambio es otra operacion que autoriza el usuario.')
        else null end,
      'downstream_execution_allowed',false
    );
  END IF;

  -- Negative/exclusion expressions are a trigger for independent semantic
  -- resolution, NEVER a classifier or authority to accept/reject a target.
  -- This also applies when callers give explicit typed hints: hints cannot
  -- override the literal user's forbidden scope.
  if not v_semantic_resume_internal
     and v_action <> 'ASSET_INSPECTION'
     and v_req ~ '(^| )(sin|no|excepto|excluye|excluir|excluyendo|excluido|excluida)( |$)'
  then
    return jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_SCOPE_SEMANTICS_UNATTESTED',
      'action_code',v_action,'asset_type',v_type_hint,
      'operation_code',null,
      'subject_binding_state',case when v_asset_found then 'CANDIDATE'
                                   else 'UNRESOLVED' end,
      'subject_candidates',case when v_asset_found then
        jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,
          'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,case when v_asset_found then
          jsonb_build_array(jsonb_build_object(
            'asset_code',v_asset.codigo_activo,
            'asset_type',v_asset.tipo_activo))
          else '[]'::jsonb end,'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,case when v_asset_found then
          jsonb_build_array(jsonb_build_object(
            'asset_code',v_asset.codigo_activo,
            'asset_type',v_asset.tipo_activo))
          else '[]'::jsonb end,'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','POSITIVE_NEGATIVE_SCOPE_NOT_BOUND',
      'request_sha256',encode(extensions.digest(
        convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'executor_selection_state','NOT_SELECTED',
      'downstream_execution_allowed',false
    );
  end if;

  -- Guard EVERY unstructured mutation before any operation can become READY.
  -- The inferred verb/type is ONLY a candidate; not independent intent or
  -- scope authority. Fully typed callers retain existing downstream gates.
  if v_action <> 'ASSET_INSPECTION'
     and (
       nullif(btrim(coalesce(p_target_hint,'')),'') is null
       or nullif(btrim(coalesce(p_action_hint,'')),'') is null
       or nullif(btrim(coalesce(p_asset_type_hint,'')),'') is null
     )
  then
    return jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED',
      'asset_type',null,'action_code',null,'operation_code',null,
      'candidate_asset_type',v_type_hint,
      'candidate_action_code',v_action,
      'subject_binding_state',case when v_asset_found then 'CANDIDATE'
                                   else 'UNRESOLVED' end,
      'subject_candidates',case when v_asset_found then
        jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,
          'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,
        case when v_asset_found then jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
        'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,
        case when v_asset_found then jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
        'CANONICAL_ASSET'),
      'semantic_gap_code','NATURAL_LANGUAGE_ACTION_SCOPE_NOT_ATTESTED',
      'route_proposal',public.lf_router_route_proposal_v1(p_request_text,v_type_hint,v_action),
      'semantic_resolution_required',true,
      'next_governance_entrypoint','GOVERNED_SEMANTIC_CONSUMER_REQUIRED',
      'request_sha256',encode(extensions.digest(
        convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false
    );
  end if;

  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE') and v_asset_found and v_target_norm='' then
    if not exists (
      select 1 from public.v_lf_fuente_operativa_busqueda b
      where b.codigo_activo=v_asset.codigo_activo
        and (
          position(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
          or position(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
          or exists (select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0)
        )
    ) then v_asset_found := false; end if;
  end if;

  -- ACT-0001 R5: lexical candidate discovery is not identity evidence.
  -- Fail closed for inferred updates and existing-target operations lacking identity
  -- mention. A governed semantic consumer may resolve a gap and resubmit
  -- explicit typed inputs; this SQL never manufactures semantic authority.
  if v_target_norm=''
     and nullif(btrim(coalesce(p_asset_type_hint,'')),'') is null
     and (
       v_action in ('UPDATE','PROFILE_UPDATE','SKILL_UPDATE','ADAPTER_UPDATE',
                    'REGLA_UPDATE','STRATEGY_UPDATE','APP_SHELL_UPDATE',
                    'RUNTIME_UPDATE')
       or (
         v_asset_found and exists (
           select 1 from public.lf_router_action_registry action_route
           where action_route.asset_type=v_type_hint
             and action_route.action_code=v_action
             and action_route.status='ACTIVE'
             and action_route.requires_existing_target
         )
       )
     )
  then
    if not v_asset_found or not exists (
      select 1
      from public.v_lf_fuente_operativa_busqueda b
      where b.codigo_activo=v_asset.codigo_activo
        and (
          position(
            ' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or position(
            ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or exists (
            select 1
            from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
            where length(btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g')))>=8
              and btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g')) <> lower(b.tipo_activo)
              and position(
                ' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
                in ' '||v_req||' '
              )>0
          )
        )
    ) then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED',
        'router','ACT-0001',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'candidate_asset_code',case when v_asset_found then v_asset.codigo_activo else null end,
        'semantic_gap_code','NON_DERIVABLE_TARGET_IDENTITY',
        'semantic_resolution_required',true,
        'downstream_execution_allowed',false
      );
    end if;
  end if;
  if v_type_hint is null then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action,
      'subject_binding_state','UNRESOLVED','subject_candidates',public.lf_router_lexical_candidates_v1(p_request_text),
      'candidate_basis','LEXICAL_TOKEN_OVERLAP_NOT_IDENTITY_NOT_AUTHORITY',
      'semantic_handoff',public.lf_router_intent_handoff_v1(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','ASSET_TYPE_UNRESOLVED_NEEDS_SEMANTIC_RESOLUTION',
      'clarification_policy','AT_MOST_ONE_MATERIAL_QUESTION_ONLY_IF_SEMANTIC_LAYER_CANNOT_INFER',
      'executor_selection_state','NOT_SELECTED',
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false);
  end if;

  select * into v_rule from public.lf_router_action_registry where asset_type=v_type_hint and action_code=v_action and status='ACTIVE';
  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_NOT_REGISTERED','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset_code',case when v_asset_found then v_asset.codigo_activo else null end);
  end if;
  if v_rule.requires_existing_target and not v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_NOT_FOUND','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,
      'subject_binding_state','UNRESOLVED','subject_candidates',public.lf_router_lexical_candidates_v1(p_request_text),
      'candidate_basis','LEXICAL_TOKEN_OVERLAP_NOT_IDENTITY_NOT_AUTHORITY',
      'semantic_handoff',public.lf_router_intent_handoff_v1(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','ASSET_NOT_FOUND_NEEDS_SEMANTIC_RESOLUTION',
      'clarification_policy','AT_MOST_ONE_MATERIAL_QUESTION_ONLY_IF_SEMANTIC_LAYER_CANNOT_INFER',
      'executor_selection_state','NOT_SELECTED',
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false); end if;
  if v_rule.requires_missing_target and v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_TARGET_ALREADY_EXISTS','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset_code',v_asset.codigo_activo); end if;

  if v_rule.operation_resolution='NONE' then
    if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;
    return jsonb_build_object('status','READY_INSPECTION','router','ACT-0001','source','SUPABASE','discovery_source',case when v_type_hint='OPERATION_CODE' then 'public.lf_operation_registry' else 'public.v_lf_fuente_operativa_busqueda' end,'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,'asset_type',v_type_hint,'action_code',v_action,'operation_code',null,'adapters',v_adapters,'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'));
  end if;

  select * into v_operation from public.lf_operation_registry where operation_code=v_rule.operation_code;
  if not found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_REGISTRY_MISSING','router','ACT-0001','operation_code',v_rule.operation_code); end if;
  if v_operation.applies_to_asset_type is not null and v_operation.applies_to_asset_type<>v_type_hint then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_ASSET_TYPE_MISMATCH','router','ACT-0001','asset_type',v_type_hint,'operation_code',v_operation.operation_code,'applies_to_asset_type',v_operation.applies_to_asset_type); end if;

  if exists (
    select 1 from public.lf_test_requirement_bindings b
    where b.subject_type='OPERATION' and b.subject_code=v_operation.operation_code
      and b.status='ACTIVE' and b.required and b.effective_from<=clock_timestamp()
  ) then
    if v_operation.lifecycle_state_code is distinct from public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION') then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_NOT_OPERATIONAL','router','ACT-0001','operation_code',v_operation.operation_code,'operation_lifecycle_state',v_operation.lifecycle_state_code);
    end if;
    if v_operation.operation_code<>'EJECUCION_ESTRATEGIA_LF'
       and not public.lf_qualification_current_v1('OPERATION',v_operation.operation_code,public.lf_operation_revision_sha256_v1(v_operation.operation_code)) then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_QUALIFICATION_REQUIRED','router','ACT-0001','operation_code',v_operation.operation_code,'operation_revision_sha256',public.lf_operation_revision_sha256_v1(v_operation.operation_code));
    end if;
  end if;

  -- Strategy26 G-A: the profile asset itself must be runtime-authorized before
  -- EJECUCION_PERFIL_LF can proceed. Runtime capability is not authority.
  if v_operation.operation_code = 'EJECUCION_PERFIL_LF' and v_asset_found then
    if nullif(btrim(coalesce(v_asset.runtime_estado, '')), '') is null
       or nullif(btrim(coalesce(v_asset.estado_operativo, '')), '') is null
       or nullif(btrim(coalesce(v_asset.estado_documental, '')), '') is null then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_STATE_INCOMPLETE',
        'router','ACT-0001',
        'source','SUPABASE',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'operation_code',v_operation.operation_code,
        'asset_code',v_asset.codigo_activo,
        'downstream_execution_allowed',false
      );
    end if;

    -- runtime_estado is executor-mode compatibility, not lifecycle authority.
    -- Mode-specific admission is enforced by lf_profile_execution_begin_v1.
    if upper(v_asset.estado_operativo) in ('BLOQUEADO','ELIMINADO')
       or upper(v_asset.estado_documental) = 'ELIMINADO' then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED',
        'router','ACT-0001',
        'source','SUPABASE',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'operation_code',v_operation.operation_code,
        'asset_code',v_asset.codigo_activo,
        'profile_state',jsonb_build_object(
          'estado_documental',v_asset.estado_documental,
          'estado_operativo',v_asset.estado_operativo,
          'runtime_estado',v_asset.runtime_estado,
          'impacto_automatico',v_asset.impacto_automatico
        ),
        'downstream_execution_allowed',false
      );
    end if;
  end if;

  select count(*), coalesce(jsonb_agg(jsonb_build_array(c.contract_code,c.contract_sha) order by c.contract_code),'[]'::jsonb)
    into v_contract_count,v_contract_refs
  from public.lf_operation_contracts c
  where c.operation_code=v_operation.operation_code and c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_contract_count=0 then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_CONTRACT_MISSING','router','ACT-0001','operation_code',v_operation.operation_code); end if;

  select count(*) into v_step_count from public.lf_operation_step_contracts s
  where s.operation_code=v_operation.operation_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_step_count=0 then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_STEPS_MISSING','router','ACT-0001','operation_code',v_operation.operation_code); end if;

  select jsonb_build_object(
      'step_id',s.step_id,'execution_order',s.execution_order,'contract_code',s.contract_code,
      'blocking_code',s.blocking_code,'status',s.status,'resolver_ref',s.resolver_ref,
      'required_evidence_keys',s.required_evidence_keys,'next_if_pass',s.next_if_pass,'next_if_blocked',s.next_if_blocked
    ) into v_next_step
  from public.lf_operation_step_contracts s
  where s.operation_code=v_operation.operation_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
  order by coalesce(s.execution_order,s.step_order),s.step_id limit 1;

  select count(*) filter (where p.required) into v_required_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));

  select count(*) filter (where p.required and p.policy_sha is not null) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));
  if v_required_policy_count>v_resolved_policy_count then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_REQUIRED_POLICY_MISSING','router','ACT-0001','operation_code',v_operation.operation_code,'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count);
  end if;

  select coalesce(jsonb_agg(jsonb_build_array(p.policy_code,p.policy_version,p.policy_sha) order by p.policy_role,p.policy_code),'[]'::jsonb) into v_policy_refs
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));

  if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;

  if exists (select 1 from jsonb_array_elements(v_adapters) e(value) left join public.v_lf_fuente_operativa f on f.codigo_activo=e.value->>'adapter_code' where lower(coalesce(e.value#>>'{adapter_metadata,router_discoverable}','false'))='true' and (lower(coalesce(e.value#>>'{adapter_metadata,runtime_enabled}','false'))<>'true' or f.codigo_activo is null or upper(coalesce(f.runtime_estado,''))='NO_HABILITADO')) then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ADAPTER_RUNTIME_NOT_AUTHORIZED','router','ACT-0001','source','SUPABASE','asset_type',v_type_hint,'action_code',v_action,'operation_code',v_operation.operation_code,'adapters',v_adapters,'adapter_runtime_authority_source','public.v_lf_fuente_operativa','downstream_execution_allowed',false);
  end if;

  if jsonb_array_length(v_adapters)>0
     and v_operation.operation_code is distinct from 'ACTUALIZACION_PERFIL_LF' then
    v_input_governance := programacion.fn_lf_router_input_governance_derive_v1(
      p_request_text,
      v_adapters,
      case when v_operation.operation_code = 'EJECUCION_PERFIL_LF' then 'CONTEXT_PACK' else 'STORY_CREATOR' end
    );

    -- PROFILE_EXECUTION is strictly read-only. If the reviewed subject is not a canonical screen,
    -- keep the same Router/Input Governance path but switch governance to advisory artifact mode.
    -- Exact artifact identity remains mandatory downstream; this does not create or promote canon.
    if v_operation.operation_code = 'EJECUCION_PERFIL_LF'
       and v_operation.status = 'PRODUCCION_CONTROLADA_READ_ONLY'
       and coalesce(v_input_governance->>'blocking_code','') = 'BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED' then
      v_input_governance := jsonb_build_object(
        'applicable',true,
        'status','ADVISORY_READ_ONLY',
        'blocking_code',null,
        'decision','ADVISORY',
        'continuation_allowed',true,
        'subject_mode','NON_CANONICAL_ARTIFACT',
        'required_by_adapters',coalesce(v_input_governance->'required_by_adapters','[]'::jsonb),
        'required_artifact_binding',jsonb_build_array('artifact_ref','artifact_sha256','dimensions'),
        'constraints',jsonb_build_object(
          'operation_must_equal','EJECUCION_PERFIL_LF',
          'read_only',true,
          'no_write',true,
          'no_promotion',true,
          'canonical_registration_required',false,
          'artifact_binding_required_before_profile_execution',true
        ),
        'resume_via','EJECUCION_PERFIL_LF/input_validate'
      );
    end if;

    if v_input_governance is null or not (v_input_governance ? 'applicable') then
      v_input_governance := jsonb_build_object('applicable',true,'status','BLOCKED','blocking_code','BLOCK_INPUT_GOVERNANCE_RESOLUTION_INVALID','decision','BLOCKED','continuation_allowed',false);
    end if;
    if coalesce((v_input_governance->>'applicable')::boolean,false) then
      if v_operation.operation_code='EJECUCION_PERFIL_LF'
         and v_input_governance->>'status'='INPUT_GOVERNANCE_REQUIRED'
         and v_input_governance->>'decision'='PENDING' then
        v_input_governance:=v_input_governance||jsonb_build_object(
          'execution_gate_owner','EJECUCION_PERFIL_LF/input_validate',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      elsif not coalesce((v_input_governance->>'continuation_allowed')::boolean,false) then
        return jsonb_build_object(
          'status',v_input_governance->>'status','blocking_code',v_input_governance->>'blocking_code','router','ACT-0001','source','SUPABASE',
          'discovery_source',case when v_type_hint='OPERATION_CODE' then 'public.lf_operation_registry' else 'public.v_lf_fuente_operativa_busqueda' end,
          'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,
          'asset_type',v_type_hint,'action_code',v_action,'operation_code',v_operation.operation_code,
          'operation_status',v_operation.status,'operation_lifecycle_state',v_operation.lifecycle_state_code,'operation_applies_to_asset_type',v_operation.applies_to_asset_type,
          'contract_count',v_contract_count,'contract_refs',v_contract_refs,'step_count',v_step_count,'next_step',v_next_step,
          'next_step_ref',v_operation.operation_code||'/'||(v_next_step->>'step_id'),
          'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count,'policy_refs',v_policy_refs,
          'policy_stale_guard','public.lf_operation_policy_snapshot_guard_v1','adapters',v_adapters,
          'input_governance',v_input_governance,'downstream_execution_allowed',false,
          'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'),
          'composition_order',jsonb_build_array('SHELL','PROFILE','ADAPTER','POLICY_AND_CONTRACT_GATES')
        );
      end if;
    else
      v_input_governance := null;
    end if;
  end if;

  return jsonb_build_object(
    'status','READY_TO_EXECUTE','router','ACT-0001','source','SUPABASE','discovery_source',case when v_type_hint='OPERATION_CODE' then 'public.lf_operation_registry' else 'public.v_lf_fuente_operativa_busqueda' end,
    'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,
    'asset_type',v_type_hint,'action_code',v_action,'operation_code',v_operation.operation_code,
    'operation_status',v_operation.status,'operation_lifecycle_state',v_operation.lifecycle_state_code,'operation_applies_to_asset_type',v_operation.applies_to_asset_type,
    'contract_count',v_contract_count,'contract_refs',v_contract_refs,
    'step_count',v_step_count,'next_step',v_next_step,'next_step_ref',v_operation.operation_code||'/'||(v_next_step->>'step_id'),
    'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count,'policy_refs',v_policy_refs,
    'policy_stale_guard','public.lf_operation_policy_snapshot_guard_v1','adapters',v_adapters,
    'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'),
    'composition_order',jsonb_build_array('SHELL','PROFILE','ADAPTER','POLICY_AND_CONTRACT_GATES'),
    'downstream_execution_allowed',true
  ) || case when v_input_governance is null then '{}'::jsonb else jsonb_build_object('input_governance',v_input_governance) end;
end;
$function$
;

-- 1f9881b62d53a44994e108b7ee197cbe programacion.fn_lf_profile_input_governance_resolve_v1 (current preimage)
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
$function$
;
