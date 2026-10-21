-- RW1-05_C2 material evidence: real T2 semantic shadow + GPT_NATIVE current-chat capture.
-- This migration records evidence only. It does not claim deterministic profile PASS,
-- independent semantic PASS, 11/11 completion, terminal receipt, or C2 closure.
BEGIN;

DO $rw105_c2_native_capture$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C2';
  v_wi constant bigint := 1131;
  v_prior_md5 constant text := '5321b2049f7c3c4aa775cb5680020dd3';
  v_request_sha constant text := '49832722f69df7d56236ec04c2f3e2e3b961e75d1eac56dd1c706c151b74cd62';
  v_semantic_receipt_sha constant text := 'a7ce2c2c458242a49d0f298ca6a0e6811acaeb504c7ee2905b2d2ccf18fee065';
  v_input constant text := 'Analiza como canario read-only la causa raíz de haber tratado la disponibilidad REMOTE_API/VPS como blocker global de EJECUCION_PERFIL_LF cuando GPT_NATIVE y CLAUDE_NATIVE no dependen de ese host. No escribas, no promociones, no habilites runtime y no cambies arquitectura; entrega una reparación sistémica acotada y verificable.';

  v_old jsonb;
  v_new jsonb;
  v_source jsonb;
  v_event_id bigint;
  v_route jsonb;
  v_request jsonb;
  v_result jsonb;
  v_resume jsonb;
  v_resume_route jsonb;
  v_raw jsonb;
  v_raw_sha text;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan
    AND unit_code=v_unit
    AND work_item_id=v_wi
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp)
      IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_CHECKPOINT_NOT_PENDING';
  END IF;

  v_route:=public.lf_router_resolve_v1(
    v_input,
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );

  IF v_route->>'status' IS DISTINCT FROM 'BLOCKED'
     OR v_route->>'blocking_code' IS DISTINCT FROM 'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED'
     OR v_route->>'request_sha256' IS DISTINCT FROM v_request_sha
     OR v_route#>>'{semantic_handoff_v2,schema_version}' IS DISTINCT FROM 'LF_ROUTER_SEMANTIC_REQUEST_V1'
  THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_INITIAL_ROUTER_DRIFT:%',left(v_route::text,1200);
  END IF;

  v_request:=v_route->'semantic_handoff_v2';

  v_result:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',v_request_sha,
    'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'),
    'excluded_target_refs','[]'::jsonb,
    'allowed_scope',jsonb_build_array('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'),
    'forbidden_scope','[]'::jsonb,
    'conditions','[]'::jsonb,
    'material_ambiguities','[]'::jsonb,
    'clarification_question',null,
    'semantic_receipt_sha256',v_semantic_receipt_sha
  );

  v_resume:=public.lf_router_semantic_resume_validate_v1(v_request,v_result);
  v_resume_route:=public.lf_router_semantic_resume_route_v1(v_request,v_result);

  IF v_resume->>'status' IS DISTINCT FROM 'VALID'
     OR v_resume->>'next_action' IS DISTINCT FROM 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
     OR coalesce((v_resume->>'router_resume_allowed')::boolean,false) IS NOT TRUE
     OR v_resume_route->>'status' IS DISTINCT FROM 'ROUTER_REDERIVED'
     OR v_resume_route#>>'{router_result,status}' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_resume_route#>>'{router_result,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_resume_route#>>'{router_result,asset,codigo_activo}' IS DISTINCT FROM 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
     OR coalesce((v_resume_route#>>'{router_result,downstream_execution_allowed}')::boolean,false) IS NOT TRUE
     OR coalesce((v_resume_route#>>'{router_result,step_count}')::integer,0) <> 11
  THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_T2_SHADOW_NOT_READY:%',left(v_resume_route::text,1600);
  END IF;

  -- Actual GPT_NATIVE producer output authored in the current ChatGPT conversation.
  -- It is intentionally captured below the deterministic/semantic acceptance ceiling.
  v_raw:=jsonb_build_object(
    'status','NO_REPAIR_REQUIRED',
    'profile_pack_id','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6',
    'case_mode','INCIDENT_REPAIR',
    'repair_disposition',jsonb_build_object(
      'decision','ALREADY_RESOLVED',
      'rationale','Current governed readback shows the original failure class has already been corrected: REMOTE_API host availability is no longer a global RW1-05_C2 blocker, GPT_NATIVE and CLAUDE_NATIVE are admitted native modes, and the terminal receipt is transport-neutral while the API queue remains transport-specific.',
      'active_failure_present',false,
      'material_repair_justified',false,
      'evidence_refs',jsonb_build_array(
        'supabase://supabase_migrations.schema_migrations/20261021163501',
        'supabase://public.lf_eventos/21391',
        'github://cristhianlujan/claude-persona-lf-patch/pull/3020',
        'github://cristhianlujan/claude-persona-lf-patch/pull/3025'
      ),
      'currentness_refs',jsonb_build_array(
        'supabase://programacion.engineering_plan_units/LF_ROUTER_ARCHITECTURE_WAVE_V1/RW1-05#RW1-05_C2',
        'supabase://pg_proc/public.lf_profile_execution_terminal_authority_receipt_v1(text)'
      ),
      'verification',jsonb_build_object(
        'executable',true,
        'method','Read the current RW1-05_C2 executor-mode contract, the terminal-receipt function and the profile-runtime queue constraint.',
        'expected_result','GPT_NATIVE and CLAUDE_NATIVE remain native admitted modes without host dependency; REMOTE_API stays disabled/not admitted for C2; queue transport remains HETZNER/GITHUB_ACTIONS; no PROFILE_RUNTIME_HOST_OFFLINE blocker exists.',
        'evidence_refs',jsonb_build_array(
          'supabase://programacion.engineering_plan_units/LF_ROUTER_ARCHITECTURE_WAVE_V1/RW1-05#RW1-05_C2',
          'supabase://pg_constraint/lf_profile_runtime_queue_runtime_target_ck'
        )
      )
    ),
    'diagnostic_summary',jsonb_build_object(
      'historical_failure_class','REMOTE_API_HOST_AVAILABILITY_PROMOTED_TO_GLOBAL_EJECUCION_PERFIL_LF_BLOCKER',
      'current_disposition','ALREADY_RESOLVED',
      'new_repair_proposed',false,
      'writes_authorized_by_profile',false,
      'promotion_authorized_by_profile',false,
      'runtime_enablement_authorized_by_profile',false
    ),
    'blocking_codes','[]'::jsonb,
    'next_gate',jsonb_build_object(
      'gate','DETERMINISTIC_PROFILE_VALIDATION_THEN_INDEPENDENT_SEMANTIC_REVIEW',
      'entry_condition','Exact GPT_NATIVE RAW is source/input bound.',
      'exit_condition','Deterministic profile validation passes and an independent non-producer semantic reviewer returns PASS.'
    )
  );

  v_raw_sha:=encode(
    extensions.digest(convert_to(v_raw::text,'UTF8'),'sha256'),
    'hex'
  );

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
  ) VALUES (
    'RW105_C2_GPT_NATIVE_CANARY_CAPTURED',
    'ENGINEERING_WORK_CHECKPOINT',
    v_cp,
    'RW1-05_C2 real T2 semantic shadow and GPT_NATIVE current-chat capture; no deterministic or independent semantic PASS claimed.',
    'INFO',
    jsonb_build_object(
      'schema_version','RW105_C2_GPT_NATIVE_CANARY_CAPTURE_V1',
      'work_item_id',v_wi,
      'checkpoint_code',v_cp,
      'operation_code','EJECUCION_PERFIL_LF',
      'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'executor_mode','GPT_NATIVE',
      'adapter_id','chatgpt-native-current-context-v1',
      'conversation_scope','EXISTING_CONVERSATION_ONLY',
      'native_api_invocation',false,
      'native_session_creation',false,
      'remote_api_fallback','FORBIDDEN',
      'host_execution','FORBIDDEN',
      'request_sha256',v_request_sha,
      'semantic_result',v_result,
      'resume_validation',v_resume,
      'resume_route_summary',jsonb_build_object(
        'status',v_resume_route->>'status',
        'router_status',v_resume_route#>>'{router_result,status}',
        'operation_code',v_resume_route#>>'{router_result,operation_code}',
        'asset_code',v_resume_route#>>'{router_result,asset,codigo_activo}',
        'step_count',(v_resume_route#>>'{router_result,step_count}')::integer,
        'router_downstream_execution_allowed',(v_resume_route#>>'{router_result,downstream_execution_allowed}')::boolean
      ),
      'producer_capture',jsonb_build_object(
        'producer_mode','GPT_NATIVE',
        'producer_transport','CHAT_SESSION_AUTHORING',
        'capture_status','GPT_CHAT_SOURCE_READBACK_BOUND_UNATTESTED',
        'runtime_provider_attested',false,
        'deterministic_profile_validation','NOT_EXECUTED',
        'independent_review_executed',false,
        'semantic_pass_claimed',false,
        'terminal_receipt_claimed',false,
        'downstream_authorized',false,
        'raw_output',v_raw,
        'raw_output_sha256',v_raw_sha
      ),
      'evidence_ceiling','NATIVE_RAW_CAPTURED_T2_SHADOW_REDERIVED__DETERMINISTIC_AND_INDEPENDENT_QUALITY_PENDING'
    ),
    'GPT_NATIVE_CURRENT_CHAT',
    'RW1-05_C2-GPT-NATIVE-CANARY'
  ) RETURNING id INTO v_event_id;

  v_source:=v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2}';
  v_source:=jsonb_set(
    v_source,
    '{material_execution_evidence,gpt_native_canary_attempt_v1}',
    jsonb_build_object(
      'status','RAW_CAPTURED_QUALITY_PENDING',
      'event_id',v_event_id,
      'event_ref','supabase://public.lf_eventos/'||v_event_id::text,
      'executor_mode','GPT_NATIVE',
      'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'request_sha256',v_request_sha,
      'raw_output_sha256',v_raw_sha,
      't2_shadow_status','ROUTER_REDERIVED_READY_TO_EXECUTE',
      'deterministic_profile_validation','NOT_EXECUTED',
      'independent_semantic_review','NOT_EXECUTED',
      'terminal_receipt','NOT_CLAIMED',
      'c2_blockers_preserved',true
    ),
    true
  );

  v_new:=jsonb_set(
    v_old,
    '{source_pack_v2,checkpoint_inputs,RW1-05_C2}',
    v_source,
    false
  );

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_new
  WHERE plan_code=v_plan
    AND unit_code=v_unit
    AND work_item_id=v_wi
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_METADATA_UPDATE_FAILED';
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp)
      IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_CHANGED_CHECKPOINT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_SEMANTIC_SHADOW_RUN_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)=true
  ) OR NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_PROFILE_RUNTIME_CANARY_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)=true
  ) THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_BLOCKERS_PREMATURELY_CHANGED';
  END IF;
END
$rw105_c2_native_capture$;

COMMIT;
