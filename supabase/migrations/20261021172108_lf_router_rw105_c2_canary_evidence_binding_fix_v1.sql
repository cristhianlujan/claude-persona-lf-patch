-- RW1-05_C2: bind already-persisted GPT_NATIVE canary evidence into source_pack.
-- No new execution, no blocker removal, no checkpoint closure.
BEGIN;

DO $rw105_c2_canary_binding_fix$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_source jsonb;
  v_material jsonb;
  v_event public.lf_eventos%rowtype;
  v_count integer;
BEGIN
  SELECT * INTO STRICT v_event
  FROM public.lf_eventos
  WHERE id=21414
    AND evento_tipo='STEP_EVIDENCE'
    AND created_by_execution_id='RW1-05_C2-GPT-NATIVE-CANARY'
    AND payload->>'evidence_schema_version'='operational-event/v2'
    AND payload->>'schema_version'='RW105_C2_GPT_NATIVE_CANARY_CAPTURE_V1';

  IF v_event.payload->>'request_sha256'
       IS DISTINCT FROM '49832722f69df7d56236ec04c2f3e2e3b961e75d1eac56dd1c706c151b74cd62'
     OR v_event.payload#>>'{producer_capture,raw_output_sha256}'
       IS DISTINCT FROM '262272f9260335ee22e8f8c491467042deef5bf157bd634d6c86893336f82b23'
     OR v_event.payload#>>'{resume_validator_readback,resume_validator_code}'
       IS DISTINCT FROM 'VALID'
     OR v_event.payload#>>'{resume_route_summary,router_status}'
       IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_event.payload#>>'{resume_route_summary,operation_code}'
       IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_event.payload#>>'{resume_route_summary,step_count}' IS DISTINCT FROM '11'
     OR coalesce((v_event.payload#>>'{producer_capture,semantic_pass_claimed}')::boolean,true)
       IS NOT FALSE
     OR coalesce((v_event.payload#>>'{producer_capture,terminal_receipt_claimed}')::boolean,true)
       IS NOT FALSE
  THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_EVENT_DRIFT';
  END IF;

  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
    AND unit_code='RW1-05'
    AND work_item_id=1131
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)='5321b2049f7c3c4aa775cb5680020dd3'
  FOR UPDATE;

  v_source:=v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2}';
  IF v_source IS NULL THEN
    RAISE EXCEPTION 'RW105_C2_SOURCE_PACK_MISSING';
  END IF;

  v_material:=coalesce(v_source->'material_execution_evidence','{}'::jsonb)
    || jsonb_build_object(
      'gpt_native_canary_attempt_v1',
      jsonb_build_object(
        'status','RAW_CAPTURED_QUALITY_PENDING',
        'event_id',21414,
        'event_ref','supabase://public.lf_eventos/21414',
        'executor_mode','GPT_NATIVE',
        'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
        'request_sha256','49832722f69df7d56236ec04c2f3e2e3b961e75d1eac56dd1c706c151b74cd62',
        'raw_output_sha256','262272f9260335ee22e8f8c491467042deef5bf157bd634d6c86893336f82b23',
        't2_shadow_status','ROUTER_REDERIVED_READY_TO_EXECUTE',
        'resume_validator_code','VALID',
        'router_step_count',11,
        'deterministic_profile_validation','NOT_EXECUTED',
        'independent_semantic_review','NOT_EXECUTED',
        'terminal_receipt','NOT_CLAIMED',
        'c2_blockers_preserved',true
      )
    );

  v_source:=jsonb_set(v_source,'{material_execution_evidence}',v_material,true);
  v_new:=jsonb_set(
    v_old,
    '{source_pack_v2,checkpoint_inputs,RW1-05_C2}',
    v_source,
    false
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
     AND unit_code='RW1-05'
     AND work_item_id=1131
     AND disposition='ASSIGNED'
     AND md5(unit_metadata::text)='5321b2049f7c3c4aa775cb5680020dd3';

  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_BINDING_UPDATE_COUNT:%',v_count;
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C2')
     IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_BINDING_CHANGED_CHECKPOINT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
      v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_SEMANTIC_SHADOW_RUN_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
      v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_PROFILE_RUNTIME_CANARY_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) THEN
    RAISE EXCEPTION 'RW105_C2_CANARY_BINDING_BLOCKERS_CHANGED';
  END IF;
END
$rw105_c2_canary_binding_fix$;

COMMIT;
