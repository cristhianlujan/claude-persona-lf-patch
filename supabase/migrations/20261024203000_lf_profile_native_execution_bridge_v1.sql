-- Governed Gate2 -> GPT_NATIVE bridge for EJECUCION_PERFIL_LF.
-- The bridge is service-role/admin only. Read-only callers never receive mutation authority.
BEGIN;

-- PRODUCTO channel hydration creates a second, governed context event.
-- Trust validation must accept that producer in addition to the base preflight producer.
DO $patch_channel_context_trust$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
     )) <> 'b896393013dcf0cf7d4820432d666572' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_TRUST_V1_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef(
    'public.lf_profile_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
  );
  v_old:=E'      where id=event_id and created_by_execution_id=p_execution_id and payload->>''producer''=''fn_lf_router_preflight_v1'';\n';
  v_new:=E'      where id=event_id and created_by_execution_id=p_execution_id\n'
    ||E'        and payload->>''producer'' in (''fn_lf_router_preflight_v1'',''lf_profile_execution_channel_context_v1'');\n';

  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_CONTEXT_TRUST_ANCHOR_MISSING';
  END IF;

  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;
END
$patch_channel_context_trust$;


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_begin_v1(
  p_stage1 jsonb,
  p_semantic_result jsonb,
  p_executor_mode text DEFAULT 'GPT_NATIVE',
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_route jsonb;
  v_request jsonb;
  v_validation jsonb;
  v_materialized jsonb;
  v_actor text;
BEGIN
  IF jsonb_typeof(p_stage1)<>'object'
     OR jsonb_typeof(p_semantic_result)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_INVALID'
    );
  END IF;

  IF upper(coalesce(p_executor_mode,''))<>'GPT_NATIVE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTOR_MODE',
      'required_executor_mode','GPT_NATIVE'
    );
  END IF;

  v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);
  IF v_route->>'paso'<>'PRODUCTO_GATE2_PERFIL'
     OR v_route->>'canal_candidato'<>'PRODUCTO'
     OR v_route->>'negocio_codigo'<>'LF'
     OR jsonb_typeof(v_route->'gate2_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_ROUTE_NOT_READY',
      'route',v_route
    );
  END IF;

  v_request:=v_route->'gate2_request';
  v_validation:=public.lf_router_semantic_resume_validate_v1(
    v_request,p_semantic_result
  );
  IF v_validation->>'status'<>'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_GATE2_INVALID',
      'gate2_validation',v_validation
    );
  END IF;

  v_actor:=coalesce(
    nullif(btrim(p_actor_execution_id),''),
    'PROFILE-NATIVE-BRIDGE-'||upper(substr(v_request->>'request_sha256',1,20))
  );

  v_materialized:=public.lf_router_profile_execution_after_gate2_v1(
    v_request,
    p_semantic_result,
    v_route->>'canal_candidato',
    v_route->>'negocio_codigo',
    v_route->'alcance',
    'GPT_NATIVE',
    v_actor,
    NULL
  );

  IF v_materialized->>'status'<>'NATIVE_EXECUTION_READY' THEN
    RETURN v_materialized||jsonb_build_object(
      'bridge_status','BLOCKED',
      'bridge_stage','GATE2_MATERIALIZATION'
    );
  END IF;

  RETURN v_materialized||jsonb_build_object(
    'bridge_status','READY',
    'bridge_stage','NATIVE_EXECUTION_MATERIALIZED',
    'stage1',p_stage1,
    'gate2_validation',v_validation,
    'router_route_summary',jsonb_build_object(
      'paso',v_route->>'paso',
      'canal_candidato',v_route->>'canal_candidato',
      'negocio_codigo',v_route->>'negocio_codigo',
      'perfil_candidato',v_route->>'perfil_candidato'
    )
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text) IS
'Trusted bridge entrypoint. Re-derives Stage2 from the supplied LF Stage1 packet, validates semantic Gate2, then materializes EJECUCION_PERFIL_LF in GPT_NATIVE mode. Never grants read-only callers execution authority.';


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
  p_execution_id text,
  p_source_revision text,
  p_source_digest text,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
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
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action','EXECUTE_PRODUCT_DIRECTOR_IN_CURRENT_GPT_NATIVE_CONTEXT',
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text) IS
'Advances an already authorized GPT_NATIVE EJECUCION_PERFIL_LF through the seven pre-model steps. It validates handoff/scope, applies task-level Input Governance, hydrates channel context, and never calls a model.';


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_output_v1(
  p_execution_id text,
  p_profile_output jsonb,
  p_validation jsonb,
  p_raw_evidence_ref text,
  p_validator_evidence_ref text,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_context public.lf_operation_execution_steps%rowtype;
  v_baseline public.lf_operation_execution_steps%rowtype;
  v_source public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_candidate_digest text;
  v_raw_sha text;
  v_step jsonb;
  v_clean integer;
  v_source_refs jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_profile_output)<>'object'
     OR jsonb_typeof(p_validation)<>'object'
     OR coalesce((p_validation->>'valid')::boolean,false) IS NOT TRUE
     OR (
       jsonb_typeof(p_validation->'blocking_codes')='array'
       AND jsonb_array_length(p_validation->'blocking_codes')<>0
     )
     OR nullif(btrim(coalesce(p_raw_evidence_ref,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_validator_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_INPUT_INVALID'
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
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_EXECUTION_INVALID'
    );
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_source
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='profile_source_read'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context.step_id IS NULL
     OR v_baseline.step_id IS NULL
     OR v_source.step_id IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_PREDECESSOR_NOT_CLEAN'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_candidate_digest:='sha256:'||encode(
    extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
    'hex'
  );
  v_raw_sha=substr(v_candidate_digest,8);
  v_source_refs:=jsonb_build_array(
    v_source.evidence_payload->>'profile_source_ref',
    v_context.evidence_payload->>'context_receipt_ref'
  );

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'execute_profile',
      p_raw_evidence_ref,
      jsonb_build_object(
        'context_receipt_digest',v_context.evidence_payload->>'context_receipt_digest',
        'context_receipt_ref',v_context.evidence_payload->>'context_receipt_ref',
        'context_transport',jsonb_build_object(
          'profile_source_mode','JIT_BY_REF',
          'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
          'jit_only',true,
          'policy_payloads',false,
          'full_ekb_entries',false,
          'full_readmes',false,
          'full_prefetch_count',0,
          'hydrated_refs','[]'::jsonb
        ),
        'profile_output',p_profile_output,
        'candidate_digest',v_candidate_digest,
        'raw_output_sha256',v_raw_sha,
        'research_baseline_digest',
          v_baseline.evidence_payload#>>'{research_baseline_binding,baseline_digest}',
        'research_baseline_ref',v_baseline.evidence_payload->>'baseline_receipt_ref',
        'source_refs',v_source_refs
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTE_PROFILE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'output_validate',
      p_validator_evidence_ref,
      jsonb_build_object(
        'output_contract_result','PASS',
        'deterministic_validation',
          p_validation||jsonb_build_object(
            'status','PASS',
            'candidate_digest',v_candidate_digest
          ),
        'raw_output_sha256',v_raw_sha
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_VALIDATE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>9 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_POST_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',9
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_PRODUCER_VALIDATED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'candidate_digest',v_candidate_digest,
    'raw_output_sha256',v_raw_sha,
    'clean_step_count',v_clean,
    'next_step','semantic_judge',
    'next_action','RUN_INDEPENDENT_SEMANTIC_JUDGE',
    'independent_semantic_judge_required',true,
    'producer_may_self_authorize',false,
    'terminal_authority_ready',false,
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_record_output_v1(
  text,jsonb,jsonb,text,text,text
) FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_record_output_v1(
  text,jsonb,jsonb,text,text,text
) TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_record_output_v1(
  text,jsonb,jsonb,text,text,text
) IS
'Records the current-chat GPT_NATIVE producer RAW plus deterministic profile validation. It deliberately stops at 9/11 and requires an independent semantic judge; the producer cannot self-authorize terminal PASS.';


DO $postcheck$
DECLARE
  v_trust text;
BEGIN
  v_trust:=pg_get_functiondef(
    'public.lf_profile_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
  );

  IF position('lf_profile_execution_channel_context_v1' in v_trust)=0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_TRUST_NOT_INSTALLED';
  END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_READ_ONLY_EXECUTION_GRANT_FORBIDDEN';
  END IF;

  IF NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_SERVICE_ROLE_GRANT_MISSING';
  END IF;
END
$postcheck$;

COMMIT;
