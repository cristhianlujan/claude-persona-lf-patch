-- PE10_C5: initialize the existing six-step independent assurance operation
-- for the exact native-chat SOURCE_SNAPSHOT, and execute only the deterministic
-- route_bind + target_currentness steps. No semantic verdict, review decision,
-- C5 PASS, cutover event or production activation is created here.
BEGIN;

DO $pe10_c5_review$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_checkpoint constant text := 'PE10_C5';
  v_subject_type constant text := 'PROFILE_NATIVE_CHAT_MATERIAL_REVIEW';
  v_subject_ref constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5';
  v_subject_sha constant text := 'dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde';
  v_source_head constant text := '8b3b41c20d77125cf4767c79487bc13d752c01a1';
  v_source_receipt constant uuid := '731e93ae-a230-4172-ad6c-f2fb4c9024d6'::uuid;
  v_source_orch constant text := 'EXEC-PE10C5-SOURCE-ORCH-e804d71999bbdcad';
  v_source_producer constant text := 'EXEC-PE10C5-SOURCE-PRODUCER-e804d71999bbdcad';
  v_source_ledger constant text := 'EXEC-PE10C5-SOURCE-LEDGER-e804d71999bbdcad';
  v_plan_digest constant text := 'e804d71999bbdcadc72e8c680b15f7b7661c35adfe26377a581f32da2901b7cf';

  v_work bigint;
  v_meta jsonb;
  v_source_meta jsonb;
  v_cap_sha text;
  v_review_id text;
  v_review_manifest jsonb;
  v_review_sha text;
  v_scope jsonb;
  v_dispatch jsonb;
  v_begin jsonb;
  v_step1 jsonb;
  v_step2 jsonb;
  v_next jsonb;
  v_event_payload jsonb;
  v_event_id bigint;
  v_source_row private.lf_evidence_ledger_v1%rowtype;
BEGIN
  SELECT work_item_id,unit_metadata
    INTO STRICT v_work,v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code='PE10'
  FOR UPDATE;

  v_source_meta := v_meta->'pe10_c5_native_source_snapshot_v1';

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR v_source_meta->>'status' IS DISTINCT FROM 'SOURCE_VERIFIED_AWAITING_INDEPENDENT_REVIEW'
     OR v_source_meta->>'source_receipt_id' IS DISTINCT FROM v_source_receipt::text
     OR v_source_meta->>'subject_sha256' IS DISTINCT FROM v_subject_sha
     OR v_source_meta->>'source_head_sha' IS DISTINCT FROM v_source_head
     OR v_source_meta->>'orchestrator_execution_id' IS DISTINCT FROM v_source_orch
     OR v_source_meta->>'producer_execution_id' IS DISTINCT FROM v_source_producer
     OR v_source_meta->>'ledger_execution_id' IS DISTINCT FROM v_source_ledger
     OR v_source_meta->>'plan_digest' IS DISTINCT FROM v_plan_digest
     OR coalesce((v_source_meta->>'c5_pass')::boolean,true) IS NOT FALSE
     OR coalesce((v_source_meta->>'cutover_admitted')::boolean,true) IS NOT FALSE
     OR coalesce((v_source_meta->>'production_activated')::boolean,true) IS NOT FALSE
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_SOURCE_METADATA_PRESTATE_DRIFT';
  END IF;

  SELECT * INTO STRICT v_source_row
  FROM private.lf_evidence_ledger_v1
  WHERE receipt_id=v_source_receipt;

  IF v_source_row.capability_code IS DISTINCT FROM 'EVIDENCE_LEDGER'
     OR v_source_row.receipt_kind IS DISTINCT FROM 'SOURCE_SNAPSHOT'
     OR v_source_row.subject_type IS DISTINCT FROM v_subject_type
     OR v_source_row.subject_ref IS DISTINCT FROM v_subject_ref
     OR v_source_row.subject_sha256 IS DISTINCT FROM v_subject_sha
     OR v_source_row.source_head_sha IS DISTINCT FROM v_source_head
     OR v_source_row.verification_state IS DISTINCT FROM 'VERIFIED'
     OR v_source_row.resolver_id IS DISTINCT FROM 'LF_GITHUB_SOURCE_READBACK_V1'
     OR v_source_row.verification_payload->'provider_readback_verified' IS DISTINCT FROM 'true'::jsonb
     OR v_source_row.verification_payload->'digest_recomputed' IS DISTINCT FROM 'true'::jsonb
     OR v_source_row.receipt_payload->>'handoff_sha256'
          IS DISTINCT FROM 'c07498fa3cd34ad65e296d63536c743a251d90834f4698ecd7ed318db293692a'
     OR v_source_row.receipt_payload->>'capture_sha256'
          IS DISTINCT FROM '944eaa1ce1d7c10ccd80f2f6e1153d657a523ecba875284a8b51a20d4644795a'
     OR v_source_row.receipt_payload->>'source_manifest_sha256'
          IS DISTINCT FROM '673888f8a720aa9167bc558036f0a26d540ae1e3fb664d11621e4a93df709fe3'
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_SOURCE_RECEIPT_NOT_EXACT';
  END IF;

  IF (SELECT status FROM public.lf_operation_execution
      WHERE execution_id=v_source_orch) IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT operation_code FROM public.lf_operation_execution
         WHERE execution_id=v_source_orch) IS DISTINCT FROM 'ORQUESTACION_PIPELINE_LF'
     OR (SELECT status FROM public.lf_operation_execution
         WHERE execution_id=v_source_producer) NOT IN ('IN_PROGRESS','COMPLETED')
     OR (SELECT status FROM public.lf_operation_execution
         WHERE execution_id=v_source_ledger) IS DISTINCT FROM 'IN_PROGRESS'
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_SOURCE_EXECUTION_CONTEXT_STALE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND target_type=v_subject_type
      AND target_code=v_subject_ref
  ) THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_ALREADY_EXISTS_RECONCILE_FIRST';
  END IF;

  SELECT c.manifest_sha256 INTO STRICT v_cap_sha
  FROM public.lf_capability_current c
  JOIN public.lf_capability_registry r USING(capability_code)
  JOIN public.lf_capability_version_registry v
    ON v.capability_code=c.capability_code AND v.version=c.version
  WHERE c.capability_code='INDEPENDENT_ASSURANCE'
    AND c.version='2.0.1'
    AND r.status='ACTIVE'
    AND r.owner_scope='SUPER_ADMIN'
    AND v.release_state='RELEASED'
    AND v.manifest#>>'{contract,subject_contract,mode}'='CONTRACT_DRIVEN_ANY_SUBJECT'
    AND v.manifest#>>'{contract,subject_contract,subject_type_whitelist}'='false';

  IF v_cap_sha IS DISTINCT FROM
     'f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35'
  THEN
    RAISE EXCEPTION 'PE10_C5_INDEPENDENT_ASSURANCE_CURRENTNESS_DRIFT';
  END IF;

  v_review_id := 'EXEC-PE10C5-INDEP-' || substr(encode(extensions.digest(
    convert_to(jsonb_build_object(
      'subject_sha',v_subject_sha,
      'source_head_sha',v_source_head,
      'source_receipt_id',v_source_receipt::text,
      'plan_digest',v_plan_digest,
      'capability_manifest_sha',v_cap_sha,
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY'
    )::text,'UTF8'),'sha256'),'hex'),1,16);

  v_review_manifest := jsonb_build_object(
    'schema','PE10_C5_NATIVE_MATERIAL_INDEPENDENT_REVIEW_V1',
    'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
    'orchestrator_execution_id',v_source_orch,
    'plan_digest',v_plan_digest,
    'capability_code','INDEPENDENT_ASSURANCE',
    'capability_manifest_sha256',v_cap_sha,
    'subject_type',v_subject_type,
    'subject_ref',v_subject_ref,
    'subject_sha256',v_subject_sha,
    'source_head_sha',v_source_head,
    'subject_receipt_id',v_source_receipt::text,
    'producer_execution_id',v_source_producer,
    'reviewer_execution_id',v_review_id,
    'review_required',true,
    'required_dimensions',jsonb_build_array('dependency','data','author'),
    'positive_negative_controls_required',true,
    'runtime_activation',false,
    'production_activation',false,
    'business_effect_allowed',false,
    'cutover_allowed',false);

  v_review_sha := encode(extensions.digest(
    convert_to(v_review_manifest::text,'UTF8'),'sha256'),'hex');

  v_scope := jsonb_build_object(
    'schema','PE10_C5_NATIVE_REVIEW_DISPATCH_V1',
    'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
    'subject_type',v_subject_type,
    'subject_ref',v_subject_ref,
    'subject_sha256',v_subject_sha,
    'source_head_sha',v_source_head,
    'subject_receipt_id',v_source_receipt::text,
    'producer_execution_id',v_source_producer,
    'reviewer_execution_id',v_review_id,
    'authority_role','SUPER_ADMIN',
    'semantic_verdict_present',false,
    'operational_cutover_allowed',false);

  v_dispatch := public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_source_orch,v_review_id,'INDEPENDENT_ASSURANCE',
    v_plan_digest,v_scope,v_source_orch);

  IF NOT coalesce((v_dispatch->>'ready')::boolean,false)
  THEN
    RAISE EXCEPTION 'PE10_C5_INDEPENDENT_DISPATCH_REJECTED:%',v_dispatch;
  END IF;

  v_begin := public.lf_independent_review_begin_v3(
    v_review_id,
    v_subject_type,
    v_subject_ref,
    v_subject_sha,
    v_source_head,
    v_source_receipt,
    v_source_producer,
    v_cap_sha,
    v_plan_digest,
    (v_dispatch->>'receipt_id')::uuid,
    v_review_sha,
    'pe10c5:native-review:'||v_review_sha,
    v_source_orch,
    v_review_manifest);

  IF v_begin->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_begin->>'next_step' IS DISTINCT FROM 'route_bind'
     OR NOT coalesce((v_begin#>>'{capability_binding_receipt,ready}')::boolean,false)
  THEN
    RAISE EXCEPTION 'PE10_C5_INDEPENDENT_REVIEW_NOT_INITIALIZED:%',v_begin;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_binding b
    JOIN public.lf_capability_current c ON c.capability_code=b.capability_code
    WHERE b.execution_id=v_review_id
      AND b.capability_code='INDEPENDENT_ASSURANCE'
      AND b.binding_state='BOUND'
      AND b.bound_version=c.version
      AND b.bound_manifest_sha256=c.manifest_sha256
  ) THEN
    RAISE EXCEPTION 'PE10_C5_INDEPENDENT_BINDING_READBACK_FAILED';
  END IF;

  -- Deterministic step 1: no semantic opinion is supplied by the migration.
  v_step1 := public.lf_record_independent_review_step_v3(
    v_review_id,
    'route_bind',
    'supabase://public/lf_capability_binding/'||v_review_id||'/INDEPENDENT_ASSURANCE',
    jsonb_build_object(
      'source','CURRENT_CAPABILITY_BINDING',
      'verified_source_receipt_id',v_source_receipt::text,
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY'),
    v_review_id,
    null);

  IF v_step1->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_step1->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_ROUTE_BIND_NOT_CLEAN:%',v_step1;
  END IF;

  -- Deterministic step 2: server re-reads the exact verified provider-bound subject.
  v_step2 := public.lf_record_independent_review_step_v3(
    v_review_id,
    'target_currentness',
    'supabase://private/lf_evidence_ledger_v1/'||v_source_receipt::text,
    jsonb_build_object(
      'source','VERIFIED_PROVIDER_BOUND_SNAPSHOT',
      'subject_sha256',v_subject_sha,
      'source_head_sha',v_source_head,
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY'),
    v_review_id,
    null);

  IF v_step2->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_step2->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_TARGET_CURRENTNESS_NOT_CLEAN:%',v_step2;
  END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=v_review_id
        AND step_id IN ('route_bind','target_currentness')
        AND status='STEP_PASS_WITH_EVIDENCE') <> 2
     OR EXISTS (
       SELECT 1 FROM public.lf_operation_execution_steps
       WHERE execution_id=v_review_id
         AND step_id IN ('semantic_review','judge_record','reviewer_readback','report_output')
     )
     OR EXISTS (
       SELECT 1 FROM private.lf_evidence_ledger_v1
       WHERE execution_id=v_review_id
         AND receipt_kind IN ('REVIEW_DECISION','INDEPENDENT_REVIEW_RECEIPT')
     )
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_BOUNDARY_READBACK_FAILED';
  END IF;

  v_next := jsonb_set(
    v_meta,
    '{pe10_c5_native_source_snapshot_v1,status}',
    to_jsonb('INDEPENDENT_REVIEW_AWAITING_SEMANTIC_VERDICT'::text),
    false);
  v_next := jsonb_set(
    v_next,
    '{pe10_c5_native_source_snapshot_v1,independent_review_receipt_id}',
    'null'::jsonb,
    true);
  v_next := jsonb_set(
    v_next,
    '{pe10_c5_native_review_v1}',
    jsonb_build_object(
      'schema','PE10_C5_NATIVE_REVIEW_V1',
      'status','INDEPENDENT_REVIEW_AWAITING_SEMANTIC_VERDICT',
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
      'review_execution_id',v_review_id,
      'review_dispatch_receipt_id',v_dispatch->>'receipt_id',
      'capability_manifest_sha256',v_cap_sha,
      'subject_receipt_id',v_source_receipt::text,
      'subject_sha256',v_subject_sha,
      'source_head_sha',v_source_head,
      'producer_execution_id',v_source_producer,
      'reviewer_execution_id',v_review_id,
      'deterministic_steps_passed',jsonb_build_array('route_bind','target_currentness'),
      'review_next_step','semantic_review',
      'semantic_independent_verdict','NOT_STARTED',
      'positive_negative_controls_required',true,
      'independent_review_receipt_id',null,
      'c5_pass',false,
      'cutover_admitted',false,
      'production_activated',false),
    true);

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_next
  WHERE work_item_id=v_work AND unit_metadata=v_meta;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_METADATA_CAS_FAILED';
  END IF;

  v_event_payload := jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',v_review_id,
    'producer','PE10_C5_NATIVE_INDEPENDENT_REVIEW_INIT_V1',
    'purpose','Initialize exact independent native-material review and execute only deterministic first two steps',
    'occurred_at',clock_timestamp(),
    'plan_code',v_plan,
    'checkpoint_code',v_checkpoint,
    'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
    'review_execution_id',v_review_id,
    'review_dispatch_receipt_id',v_dispatch->>'receipt_id',
    'subject_receipt_id',v_source_receipt::text,
    'subject_sha256',v_subject_sha,
    'source_head_sha',v_source_head,
    'deterministic_steps_passed',jsonb_build_array('route_bind','target_currentness'),
    'semantic_review_executed',false,
    'semantic_verdict','NOT_STARTED',
    'independent_review_receipt_created',false,
    'checkpoint_pass',false,
    'cutover_admitted',false,
    'production_activation',false,
    'acceptance_declared',false);

  IF private.fn_lf_event_acceptance_signal_v2(
       'ARTIFACT_RECONCILED',
       'PE10_C5.NATIVE_INDEPENDENT_REVIEW_INIT.V1',
       'PE10 C5 native material independent review initialized; semantic verdict pending',
       v_event_payload) IS NOT NULL
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_INIT_FALSE_ACCEPTANCE';
  END IF;

  INSERT INTO public.lf_eventos
    (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
     created_by_execution_id,payload)
  VALUES
    ('ARTIFACT_RECONCILED','PROGRAM_PLAN','PE10_C5.NATIVE_INDEPENDENT_REVIEW_INIT.V1',
     'PE10 C5 independent review initialized; deterministic gates passed; semantic review pending',
     'INFO','DERIVE_FROM_EXECUTION_ID',v_review_id,v_event_payload)
  RETURNING id INTO v_event_id;

  IF v_event_id IS NULL
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) <> 'PENDING'
     OR (SELECT status FROM public.lf_operation_execution
         WHERE execution_id=v_review_id) <> 'IN_PROGRESS'
     OR EXISTS (
       SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF')
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_INIT_POSTSTATE_INVALID';
  END IF;
END
$pe10_c5_review$;

COMMIT;
