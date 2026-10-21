-- RW1-05_C2: persist independent GPT_NATIVE semantic review and fail-closed ACT-0001 route readback.
-- This migration does not create the canonical EJECUCION_PERFIL_LF ledger execution because
-- ACT-0001 rederivation did not authorize PROFILE_EXECUTION for the frozen literal.
BEGIN;

DO $rw105_c2_gpt_native_semantic_review$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C2';
  v_wi constant bigint := 1131;
  v_prior_md5 constant text := 'fb6703c688639886754dfc9a0d41e5c3';
  v_run constant text := 'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001';
  v_input_sha constant text := '81a55cf5c0ff80bfea428b775f1cfc2b0fa70e907a89b81619d158061276833e';
  v_raw_sha constant text := '86cc34048f8436479acff5fe0830b03cc0a8bbaf6f98acfeb31e7d1c094def07';
  v_receipt_sha constant text := '4141757d868556dfdce3c9007bab9b9da1b8bc12959ac0599bafd103f3ac2e30';
  v_receipt_blob constant text := 'af05409793a90821a7274ee1057e8029dc298f54';
  v_receipt_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_INDEPENDENT_SEMANTIC_REVIEW_V1.json#blob:af05409793a90821a7274ee1057e8029dc298f54';

  v_old jsonb;
  v_new jsonb;
  v_source jsonb;
  v_material jsonb;
  v_event_payload jsonb;
  v_acceptance_signal text;
  v_event_id bigint;
BEGIN
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
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_REVIEW_CHECKPOINT_NOT_PENDING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
      v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_PROFILE_RUNTIME_CANARY_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
      v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_SEMANTIC_SHADOW_RUN_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_REVIEW_BLOCKER_BASELINE_DRIFT';
  END IF;

  v_event_payload:=jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'schema_version','RW105_C2_GPT_NATIVE_INDEPENDENT_SEMANTIC_REVIEW_V1',
    'execution_id',v_run,
    'checkpoint_code',v_cp,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code','PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
    'executor_mode','GPT_NATIVE',
    'provider','OPENAI_CHATGPT_NATIVE',
    'input_sha256',v_input_sha,
    'raw_output_sha256',v_raw_sha,
    'semantic_review',jsonb_build_object(
      'status','PASS',
      'verdict','PASS_INDEPENDENT_SEMANTIC',
      'validator_status','PASS',
      'reviewer_is_producer',false,
      'producer_independence_proven',true,
      'model_call_count',1,
      'unsupported_claims','[]'::jsonb,
      'blocking_codes','[]'::jsonb,
      'receipt_ref',v_receipt_ref,
      'receipt_git_blob',v_receipt_blob,
      'receipt_sha256',v_receipt_sha
    ),
    'router_readback',jsonb_build_object(
      'semantic_resume_validation_status','VALID',
      'semantic_resume_next_action','ACT0001_REDERIVE_ROUTE_AND_AUTHORITY',
      'router_resume_allowed',true,
      'rederived_status','BLOCKED',
      'blocking_code','BLOCK_SEMANTIC_RESUME_ROUTER_PROBE_UNEXPECTED',
      'router_probe_status','READY_INSPECTION',
      'router_probe_action_code','ASSET_INSPECTION',
      'router_probe_operation_code',null,
      'expected_operation_code','EJECUCION_PERFIL_LF',
      'downstream_execution_allowed',false
    ),
    'checkpoint_effect','PENDING_PRESERVED',
    'runtime_canary_blocker_removed',false,
    'semantic_shadow_blocker_changed',false,
    'production_activation',false,
    'cutover_eligible',false
  );

  v_acceptance_signal:=private.fn_lf_event_acceptance_signal_v2(
    'STEP_EVIDENCE',
    v_cp,
    'RW1-05_C2 GPT_NATIVE independent semantic PASS; ACT-0001 rederive blocks canonical profile execution, so 11/11 and terminal receipt remain unmaterialized.',
    v_event_payload
  );

  IF v_acceptance_signal IS NOT NULL THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_REVIEW_EVENT_ACCEPTANCE_SIGNAL:%',v_acceptance_signal;
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) VALUES (
    'STEP_EVIDENCE',
    'ENGINEERING_WORK_CHECKPOINT',
    v_cp,
    'RW1-05_C2 GPT_NATIVE independent semantic PASS; ACT-0001 rederive blocks canonical profile execution, so 11/11 and terminal receipt remain unmaterialized.',
    'WARN',
    v_event_payload,
    v_run
  ) RETURNING id INTO v_event_id;

  v_source:=v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2}';
  v_material:=coalesce(v_source->'material_execution_evidence','{}'::jsonb);

  v_material:=jsonb_set(
    v_material,
    '{gpt_native_independent_semantic_review_v1}',
    jsonb_build_object(
      'status','SEMANTIC_PASS_ROUTER_BLOCKED',
      'execution_id',v_run,
      'event_id',v_event_id,
      'event_ref','supabase://public.lf_eventos/'||v_event_id::text,
      'receipt_ref',v_receipt_ref,
      'receipt_git_blob',v_receipt_blob,
      'receipt_sha256',v_receipt_sha,
      'semantic_verdict','PASS_INDEPENDENT_SEMANTIC',
      'deterministic_validation','PASS',
      'router_resume_validation','VALID',
      'router_rederive_status','BLOCKED',
      'router_blocking_code','BLOCK_SEMANTIC_RESUME_ROUTER_PROBE_UNEXPECTED',
      'router_probe_status','READY_INSPECTION',
      'router_probe_action_code','ASSET_INSPECTION',
      'expected_operation_code','EJECUCION_PERFIL_LF',
      'downstream_execution_allowed',false,
      'canonical_execution_materialized',false,
      'terminal_receipt','NOT_CLAIMED',
      'c2_blockers_preserved',true
    ),
    true
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
   WHERE plan_code=v_plan
     AND unit_code=v_unit
     AND work_item_id=v_wi
     AND disposition='ASSIGNED'
     AND md5(unit_metadata::text)=v_prior_md5;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_REVIEW_METADATA_UPDATE_FAILED';
  END IF;

  IF (SELECT status
      FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp)
     IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_REVIEW_CHANGED_CHECKPOINT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
      v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_PROFILE_RUNTIME_CANARY_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
      v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
    ) x(item)
    WHERE x.item->>'code'='REAL_SEMANTIC_SHADOW_RUN_PENDING'
      AND coalesce((x.item->>'blocking')::boolean,false)
  ) THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_REVIEW_PREMATURE_BLOCKER_CHANGE';
  END IF;
END
$rw105_c2_gpt_native_semantic_review$;

COMMIT;
