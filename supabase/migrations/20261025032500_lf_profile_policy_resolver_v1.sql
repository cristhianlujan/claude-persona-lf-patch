BEGIN;

CREATE TABLE IF NOT EXISTS private.lf_reusable_policy_registry_v1 (
  policy_code text PRIMARY KEY,
  status text NOT NULL CHECK (status IN ('VIGENTE','CANDIDATO','DEPRECADO')),
  business_scope text[] NOT NULL DEFAULT ARRAY['GLOBAL']::text[],
  channel_scope text[] NOT NULL DEFAULT ARRAY['GLOBAL']::text[],
  capabilities_any text[] NOT NULL DEFAULT ARRAY[]::text[],
  action_families_any text[] NOT NULL DEFAULT ARRAY[]::text[],
  asset_types_any text[] NOT NULL DEFAULT ARRAY[]::text[],
  semantic_descriptor text NOT NULL,
  execution_constraints jsonb NOT NULL DEFAULT '[]'::jsonb,
  source_ref text NOT NULL,
  priority integer NOT NULL DEFAULT 100,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS private.lf_profile_capability_registry_v1 (
  profile_code text NOT NULL,
  capability_code text NOT NULL,
  status text NOT NULL DEFAULT 'CURRENT' CHECK (status IN ('CURRENT','DEPRECATED')),
  source_ref text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(profile_code,capability_code)
);

INSERT INTO private.lf_reusable_policy_registry_v1(
  policy_code,status,business_scope,channel_scope,capabilities_any,
  action_families_any,asset_types_any,semantic_descriptor,
  execution_constraints,source_ref,priority
) VALUES (
  'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1','VIGENTE',
  ARRAY['LF'],ARRAY['PRODUCTO','PROGRAMACION'],
  ARRAY['DESIGN_TOKENS','VISUAL_DEFINITION','FRONTEND_IMPLEMENTATION','UI_BEHAVIOR'],
  ARRAY['CREATE','UPDATE','REPAIR','DEFINE','IMPLEMENT'],
  ARRAY['PANTALLA','SCREEN','COMPONENT','PROTOTYPE','UI'],
  'Applies when governed visual/UI assets consume Design System values. Preserve canonical token identity instead of persisting resolved literals.',
  jsonb_build_array(
    'PERSIST_CANONICAL_TOKEN_NAME_OR_CODE_NOT_LITERAL_VALUE',
    'FORBID_LITERAL_VISUAL_VALUES_IN_GOVERNED_BINDINGS',
    'DO_NOT_CREATE_DUPLICATE_VALUE_ALIAS_TOKEN',
    'VIGENTE_COMPONENT_REQUIRES_VIGENTE_GOVERNED_TOKENS'
  ),
  'github://cristhianlujan/claude-persona-lf-patch/main/docs/standards/LF_DESIGN_TOKEN_REFERENCE_POLICY_V1.md',
  50
)
ON CONFLICT (policy_code) DO UPDATE SET
  status=excluded.status,business_scope=excluded.business_scope,
  channel_scope=excluded.channel_scope,capabilities_any=excluded.capabilities_any,
  action_families_any=excluded.action_families_any,asset_types_any=excluded.asset_types_any,
  semantic_descriptor=excluded.semantic_descriptor,
  execution_constraints=excluded.execution_constraints,
  source_ref=excluded.source_ref,priority=excluded.priority,updated_at=clock_timestamp();

INSERT INTO private.lf_profile_capability_registry_v1(profile_code,capability_code,source_ref)
VALUES
 ('PERFIL-UI-ARCHITECT','DESIGN_TOKENS','supabase://public.lf_activos/PERFIL-UI-ARCHITECT'),
 ('PERFIL-UI-ARCHITECT','VISUAL_DEFINITION','supabase://public.lf_activos/PERFIL-UI-ARCHITECT'),
 ('PERFIL-UI-ARCHITECT','COMPONENT_DESIGN','supabase://public.lf_activos/PERFIL-UI-ARCHITECT'),
 ('ACT-0051','DESIGN_TOKENS','supabase://public.lf_activos/ACT-0051'),
 ('ACT-0051','FRONTEND_IMPLEMENTATION','supabase://public.lf_activos/ACT-0051'),
 ('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCT_DEFINITION','supabase://public.lf_activos/PERFIL-PRODUCT-DIRECTOR-LF'),
 ('PERFIL-PRODUCT-DIRECTOR-LF','UI_BEHAVIOR','supabase://public.lf_activos/PERFIL-PRODUCT-DIRECTOR-LF'),
 ('PERFIL-PRODUCT-DIRECTOR-LF','DESIGN_TOKENS','supabase://public.lf_activos/PERFIL-PRODUCT-DIRECTOR-LF')
ON CONFLICT (profile_code,capability_code) DO UPDATE SET
 status='CURRENT',source_ref=excluded.source_ref,updated_at=clock_timestamp();

CREATE OR REPLACE FUNCTION public.lf_profile_policy_deterministic_discovery_v1(
  p_profile_code text,p_business text,p_channel text,p_action text,p_asset_type text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private','extensions'
AS $function$
DECLARE
  v_caps text[];
  v_action_family text;
  v_candidates jsonb;
  v_digest text;
BEGIN
  IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL THEN
    RAISE EXCEPTION 'LF_POLICY_DISCOVERY_PROFILE_REQUIRED';
  END IF;

  SELECT coalesce(array_agg(capability_code ORDER BY capability_code),ARRAY[]::text[])
  INTO v_caps
  FROM private.lf_profile_capability_registry_v1
  WHERE profile_code=p_profile_code AND status='CURRENT';

  v_action_family:=split_part(upper(coalesce(p_action,'')),'_',1);

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'policy_code',p.policy_code,
      'priority',p.priority,
      'semantic_descriptor',p.semantic_descriptor,
      'execution_constraints',p.execution_constraints,
      'source_ref',p.source_ref,
      'matched_capabilities',(
        SELECT coalesce(jsonb_agg(c ORDER BY c),'[]'::jsonb)
        FROM unnest(v_caps) c WHERE c=ANY(p.capabilities_any)
      )
    ) ORDER BY p.priority,p.policy_code
  ),'[]'::jsonb)
  INTO v_candidates
  FROM private.lf_reusable_policy_registry_v1 p
  WHERE p.status='VIGENTE'
    AND ('GLOBAL'=ANY(p.business_scope) OR upper(coalesce(p_business,''))=ANY(p.business_scope))
    AND ('GLOBAL'=ANY(p.channel_scope) OR upper(coalesce(p_channel,''))=ANY(p.channel_scope))
    AND (cardinality(p.capabilities_any)=0 OR p.capabilities_any && v_caps)
    AND (cardinality(p.action_families_any)=0 OR v_action_family=ANY(p.action_families_any))
    AND (cardinality(p.asset_types_any)=0 OR upper(coalesce(p_asset_type,''))=ANY(p.asset_types_any));

  v_digest:=encode(extensions.digest(convert_to(v_candidates::text,'UTF8'),'sha256'),'hex');

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_POLICY_DETERMINISTIC_DISCOVERY_V1',
    'selection_mode','DETERMINISTIC_DISCOVERY_ONLY',
    'semantic_selection_performed',false,
    'profile_code',p_profile_code,
    'business',upper(coalesce(p_business,'')),
    'channel',upper(coalesce(p_channel,'')),
    'action',upper(coalesce(p_action,'')),
    'action_family',v_action_family,
    'asset_type',upper(coalesce(p_asset_type,'')),
    'profile_capabilities',to_jsonb(v_caps),
    'candidate_count',jsonb_array_length(v_candidates),
    'candidate_policies',v_candidates,
    'candidate_set_sha256',v_digest
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_policy_selection_prepare_v1(p_execution_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  h jsonb;
  d jsonb;
BEGIN
  SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL' OR e.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_EXECUTION_INVALID');
  END IF;

  h:=e.manifest->'router_profile_handoff';
  d:=public.lf_profile_policy_deterministic_discovery_v1(
    e.target_code,
    coalesce(h->>'business',h->>'negocio_codigo','LF'),
    coalesce(h->>'channel',''),
    coalesce(h#>>'{semantic_request,router_action_binding,profile_task_intent}',h->>'action',''),
    coalesce(h#>>'{scope,target_type}','')
  );

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_POLICY_SEMANTIC_REQUEST_V1',
    'status','READY',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'selection_pipeline',jsonb_build_array('DETERMINISTIC_DISCOVERY','SEMANTIC_SELECTION_OVER_SHORTLIST_ONLY'),
    'candidate_set_sha256',d->>'candidate_set_sha256',
    'candidate_count',(d->>'candidate_count')::integer,
    'candidate_policies',d->'candidate_policies',
    'allowed_decisions',jsonb_build_array('SELECTED','NONE'),
    'semantic_rules',jsonb_build_array(
      'EVALUATE_ONLY_CANDIDATE_POLICIES',
      'DO_NOT_EXPAND_BEYOND_DETERMINISTIC_SHORTLIST',
      'SELECT_ZERO_OR_MORE_MATERIALLY_APPLICABLE_POLICIES',
      'NO_ROUTE_OR_EFFECT_AUTHORITY'
    )
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_policy_selection_finalize_v1(
  p_request jsonb,p_draft jsonb
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_decision text;
  v_selected jsonb;
  v_invalid jsonb;
  v_final jsonb;
BEGIN
  IF p_request->>'schema_version'<>'LF_PROFILE_POLICY_SEMANTIC_REQUEST_V1'
     OR p_request->>'status'<>'READY'
     OR jsonb_typeof(p_draft)<>'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_INPUT_INVALID');
  END IF;

  v_decision:=upper(coalesce(p_draft->>'decision',''));
  v_selected:=coalesce(p_draft->'selected_policy_codes','[]'::jsonb);

  IF v_decision NOT IN ('SELECTED','NONE')
     OR jsonb_typeof(v_selected)<>'array'
     OR nullif(btrim(coalesce(p_draft->>'reason','')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_DRAFT_INVALID');
  END IF;

  SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO v_invalid
  FROM jsonb_array_elements_text(v_selected) x
  WHERE NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_request->'candidate_policies') c
    WHERE c->>'policy_code'=x
  );

  IF jsonb_array_length(v_invalid)>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','POLICY_SELECTION_OUTSIDE_SHORTLIST_FORBIDDEN',
      'invalid_policy_codes',v_invalid
    );
  END IF;

  IF (v_decision='NONE' AND jsonb_array_length(v_selected)<>0)
     OR (v_decision='SELECTED' AND jsonb_array_length(v_selected)=0) THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_CARDINALITY_INVALID');
  END IF;

  SELECT coalesce(jsonb_agg(c ORDER BY c->>'policy_code'),'[]'::jsonb) INTO v_final
  FROM jsonb_array_elements(p_request->'candidate_policies') c
  WHERE c->>'policy_code' IN (SELECT jsonb_array_elements_text(v_selected));

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_POLICY_SEMANTIC_RESULT_V1',
    'status','VALID',
    'decision',v_decision,
    'candidate_set_sha256',p_request->>'candidate_set_sha256',
    'selected_policy_count',jsonb_array_length(v_final),
    'selected_policies',v_final,
    'reason',p_draft->>'reason',
    'shortlist_expansion_allowed',false
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(p_execution_id text, p_source_revision text, p_source_digest text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_handoff jsonb;
  v_valid jsonb;
  v_actor text;
  v_slug text;
  v_source_ref text;
  v_existing text;
  v_step jsonb;
  v_input jsonb;
  v_base_context jsonb;
  v_context jsonb;
  v_baseline jsonb;
  v_clean integer;
  v_policy_selection jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR coalesce(p_source_revision,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_source_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_SOURCE_BINDING_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTION_INVALID'
    );
  END IF;

  v_handoff:=e.manifest->'router_profile_handoff';
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    v_handoff,
    v_handoff->>'literal_request',
    e.target_code
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  SELECT metadata->>'profile_slug' INTO v_slug
  FROM public.lf_activos
  WHERE codigo_activo=e.target_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL;

  IF nullif(v_slug,'') IS NULL
     OR nullif(e.target_repo,'') IS NULL
     OR nullif(e.target_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_UNRESOLVED'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_source_ref:='github://'||e.target_repo||'@'||p_source_revision||'/'||e.target_path;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_resolve';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_resolve',
      'supabase://public.lf_activos/'||e.target_code,
      jsonb_build_object(
        'exact_profile_resolved',true,
        'codigo_activo',e.target_code,
        'profile_slug',v_slug
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_RESOLVE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_source_read';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_source_read',
      v_source_ref,
      jsonb_build_object(
        'profile_source_ref',v_source_ref,
        'source_revision',p_source_revision,
        'profile_source_digest',p_source_digest,
        'profile_source_path',e.target_path
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input IS NULL THEN
    v_input:=public.lf_profile_execution_input_validate_v1(
      p_execution_id,
      v_handoff->>'literal_request',
      v_source_ref,
      v_handoff
    );

    IF v_input->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'input_validate',
      'supabase://public.lf_profile_execution_input_validate_v1/'||p_execution_id,
      v_input,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context IS NULL THEN
    v_base_context:=public.lf_profile_execution_context_admission_v1(p_execution_id);
    IF v_base_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_base_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_BASE_CONTEXT_NOT_READY'
        ),
        'base_context',v_base_context
      );
    END IF;

    v_context:=public.lf_profile_execution_channel_context_v1(
      p_execution_id,
      v_base_context,
      v_handoff
    );
    IF v_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_NOT_READY'
        ),
        'channel_context',v_context
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'context_admission',
      v_context->>'context_receipt_ref',
      v_context,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_baseline IS NULL THEN
    v_baseline:=public.lf_profile_execution_research_baseline_v1(
      p_execution_id,
      NULL,
      v_actor
    );
    IF coalesce(v_baseline->>'outcome','') NOT IN (
         'STEP_RECORDED',
         'STEP_ALREADY_RECORDED'
       )
       AND NOT EXISTS(
         SELECT 1
         FROM public.lf_operation_execution_steps
         WHERE execution_id=p_execution_id
           AND step_id='research_baseline_freeze'
           AND status='STEP_PASS_WITH_EVIDENCE'
       ) THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_BASELINE_NOT_READY',
        'baseline_result',v_baseline
      );
    END IF;

    SELECT evidence_payload INTO v_baseline
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='research_baseline_freeze'
      AND status='STEP_PASS_WITH_EVIDENCE';
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>7 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',7
    );
  END IF;

  v_policy_selection:=public.lf_profile_policy_selection_prepare_v1(p_execution_id);

  IF v_policy_selection->>'status'<>'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_policy_selection->>'blocking_code','BLOCK_PROFILE_POLICY_SELECTION_PREPARE_FAILED'),
      'policy_selection',v_policy_selection
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_MODEL_INPUT_READY',
    'execution_id',p_execution_id,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',e.target_code,
    'profile_slug',v_slug,
    'profile_source_ref',v_source_ref,
    'profile_source_digest',p_source_digest,
    'literal_request',v_handoff->>'literal_request',
    'input_governance',v_input->'input_governance',
    'context_receipt_ref',v_context->>'context_receipt_ref',
    'context_receipt_digest',v_context->>'context_receipt_digest',
    'context_capsule',v_context->'context_capsule',
    'research_baseline',v_baseline,
    'policy_resolution_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
    'policy_selection_request',v_policy_selection,
    'repair_execution_authority',
      e.manifest->'repair_execution_authority',
    'execution_write_mode',
      case
        when coalesce((e.manifest->>'governed_repair_write')::boolean,false)
          then 'GOVERNED_REPAIR_WRITE'
        else 'READ_ONLY'
      end,
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action','EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT',
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$function$
;

COMMIT;
