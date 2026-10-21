-- RW1-05_C2: close only the real semantic-shadow blocker from already-materialized evidence.
-- Event 21414 proves ACT-0001 -> semantic T2 -> valid resume -> ACT-0001 rederive ->
-- READY_TO_EXECUTE / EJECUCION_PERFIL_LF for the GPT_NATIVE canary request.
-- This migration does NOT close the profile-runtime canary or RW1-05_C2.
BEGIN;

DO $rw105_c2_semantic_shadow_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C2';
  v_wi constant bigint := 1131;
  v_prior_md5 constant text := 'fb6703c688639886754dfc9a0d41e5c3';
  v_event_id constant bigint := 21414;
  v_request_sha constant text := '49832722f69df7d56236ec04c2f3e2e3b961e75d1eac56dd1c706c151b74cd62';
  v_raw_sha constant text := '262272f9260335ee22e8f8c491467042deef5bf157bd634d6c86893336f82b23';

  v_event public.lf_eventos%rowtype;
  v_old jsonb;
  v_new jsonb;
  v_source jsonb;
  v_missing jsonb;
  v_material jsonb;
  v_new_event_id bigint;
  v_acceptance_signal text;
BEGIN
  SELECT * INTO STRICT v_event
  FROM public.lf_eventos
  WHERE id=v_event_id
    AND evento_tipo='STEP_EVIDENCE'
    AND created_by_execution_id='RW1-05_C2-GPT-NATIVE-CANARY'
    AND payload->>'schema_version'='RW105_C2_GPT_NATIVE_CANARY_CAPTURE_V1';

  IF v_event.payload->>'request_sha256' IS DISTINCT FROM v_request_sha
     OR v_event.payload#>>'{producer_capture,raw_output_sha256}' IS DISTINCT FROM v_raw_sha
     OR v_event.payload#>>'{resume_validator_readback,resume_validator_code}' IS DISTINCT FROM 'VALID'
     OR coalesce((v_event.payload#>>'{resume_validator_readback,resume_allowed}')::boolean,false) IS NOT TRUE
     OR v_event.payload#>>'{resume_validator_readback,next_action}' IS DISTINCT FROM 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
     OR v_event.payload#>>'{resume_route_summary,status}' IS DISTINCT FROM 'ROUTER_REDERIVED'
     OR v_event.payload#>>'{resume_route_summary,router_status}' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_event.payload#>>'{resume_route_summary,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_event.payload#>>'{resume_route_summary,asset_code}' IS DISTINCT FROM 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
     OR coalesce((v_event.payload#>>'{resume_route_summary,router_downstream_execution_allowed}')::boolean,false) IS NOT TRUE
     OR coalesce((v_event.payload#>>'{resume_route_summary,step_count}')::integer,0) <> 11
     OR v_event.payload->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_event.payload->>'adapter_id' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR coalesce((v_event.payload->>'native_api_invocation')::boolean,true) IS NOT FALSE
     OR coalesce((v_event.payload->>'native_session_creation')::boolean,true) IS NOT FALSE
     OR v_event.payload->>'remote_api_fallback' IS DISTINCT FROM 'FORBIDDEN'
     OR v_event.payload->>'host_execution' IS DISTINCT FROM 'FORBIDDEN'
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_SHADOW_EVIDENCE_DRIFT';
  END IF;

  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan
    AND unit_code=v_unit
    AND work_item_id=v_wi
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT status
      FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp)
     IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_SHADOW_CHECKPOINT_NOT_PENDING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_SEMANTIC_SHADOW_RUN_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_SHADOW_BLOCKER_NOT_PRESENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_PROFILE_RUNTIME_CANARY_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) THEN
    RAISE EXCEPTION 'RW105_C2_PROFILE_CANARY_BLOCKER_NOT_PRESENT';
  END IF;

  SELECT coalesce(jsonb_agg(x.item ORDER BY x.ord),'[]'::jsonb)
    INTO v_missing
  FROM jsonb_array_elements(
         v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
       ) WITH ORDINALITY x(item,ord)
  WHERE x.item->>'code' <> 'REAL_SEMANTIC_SHADOW_RUN_PENDING';

  IF jsonb_array_length(v_missing)<>1
     OR v_missing#>>'{0,code}' IS DISTINCT FROM 'REAL_PROFILE_RUNTIME_CANARY_PENDING'
     OR coalesce((v_missing#>>'{0,blocking}')::boolean,false) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_SHADOW_POST_BLOCKER_SET_INVALID:%',v_missing::text;
  END IF;

  v_source:=v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2}';
  v_material:=coalesce(v_source->'material_execution_evidence','{}'::jsonb);

  v_material:=jsonb_set(
    v_material,
    '{gpt_native_canary_attempt_v1,status}',
    to_jsonb('SEMANTIC_SHADOW_VERIFIED_PROFILE_RUNTIME_PENDING'::text),
    true
  );

  v_material:=jsonb_set(
    v_material,
    '{gpt_native_canary_attempt_v1,semantic_shadow_verification}',
    jsonb_build_object(
      'status','PASS',
      'event_id',v_event_id,
      'event_ref','supabase://public.lf_eventos/'||v_event_id::text,
      'request_sha256',v_request_sha,
      'raw_output_sha256',v_raw_sha,
      'resume_validator_code','VALID',
      'resume_allowed',true,
      'next_action','ACT0001_REDERIVE_ROUTE_AND_AUTHORITY',
      'resume_route_status','ROUTER_REDERIVED',
      'router_status','READY_TO_EXECUTE',
      'operation_code','EJECUCION_PERFIL_LF',
      'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'router_step_count',11,
      'executor_mode','GPT_NATIVE',
      'adapter_id','chatgpt-native-current-context-v1',
      'remote_api_fallback','FORBIDDEN',
      'host_execution','FORBIDDEN'
    ),
    true
  );

  v_source:=jsonb_set(v_source,'{missing_typed}',v_missing,true);
  v_source:=jsonb_set(v_source,'{material_execution_evidence}',v_material,true);
  v_new:=jsonb_set(
    v_old,
    '{source_pack_v2,checkpoint_inputs,RW1-05_C2}',
    v_source,
    false
  );

  v_acceptance_signal:=private.fn_lf_event_acceptance_signal_v2(
    'STEP_EVIDENCE',
    v_cp,
    'RW1-05_C2 real semantic shadow verified from event 21414; profile runtime canary remains pending and checkpoint stays open.',
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'schema_version','RW105_C2_SEMANTIC_SHADOW_VERIFIED_V1',
      'checkpoint_code',v_cp,
      'request_sha256',v_request_sha,
      'source_event_id',v_event_id,
      'real_semantic_shadow_run',true,
      'act0001_rederived_after_valid_resume',true,
      'router_status','READY_TO_EXECUTE',
      'operation_code','EJECUCION_PERFIL_LF',
      'executor_mode','GPT_NATIVE',
      'real_profile_runtime_canary',false,
      'checkpoint_effect','PENDING_PRESERVED',
      'production_activation',false,
      'cutover_eligible',false
    )
  );

  IF v_acceptance_signal IS NOT NULL THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_SHADOW_EVENT_ACCEPTANCE_SIGNAL:%',v_acceptance_signal;
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) VALUES (
    'STEP_EVIDENCE',
    'ENGINEERING_WORK_CHECKPOINT',
    v_cp,
    'RW1-05_C2 real semantic shadow verified from event 21414; profile runtime canary remains pending and checkpoint stays open.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'schema_version','RW105_C2_SEMANTIC_SHADOW_VERIFIED_V1',
      'checkpoint_code',v_cp,
      'request_sha256',v_request_sha,
      'source_event_id',v_event_id,
      'source_event_ref','supabase://public.lf_eventos/'||v_event_id::text,
      'real_semantic_shadow_run',true,
      'act0001_rederived_after_valid_resume',true,
      'router_status','READY_TO_EXECUTE',
      'operation_code','EJECUCION_PERFIL_LF',
      'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'executor_mode','GPT_NATIVE',
      'adapter_id','chatgpt-native-current-context-v1',
      'real_profile_runtime_canary',false,
      'remaining_blocker','REAL_PROFILE_RUNTIME_CANARY_PENDING',
      'checkpoint_effect','PENDING_PRESERVED',
      'production_activation',false,
      'cutover_eligible',false
    ),
    'RW1-05_C2-GPT-NATIVE-CANARY'
  )
  RETURNING id INTO v_new_event_id;

  v_new:=jsonb_set(
    v_new,
    '{source_pack_v2,checkpoint_inputs,RW1-05_C2,material_execution_evidence,gpt_native_canary_attempt_v1,semantic_shadow_verification,closure_event_id}',
    to_jsonb(v_new_event_id),
    true
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan
     AND unit_code=v_unit
     AND work_item_id=v_wi
     AND disposition='ASSIGNED'
     AND md5(unit_metadata::text)=v_prior_md5;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_SHADOW_METADATA_UPDATE_FAILED';
  END IF;

  IF (SELECT status
      FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp)
     IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_SHADOW_CHANGED_CHECKPOINT';
  END IF;
END
$rw105_c2_semantic_shadow_close$;

COMMIT;
