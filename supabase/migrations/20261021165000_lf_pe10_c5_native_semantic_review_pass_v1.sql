-- PE10_C5: complete the already-initialized independent review for the exact
-- frozen GPT_NATIVE material. Scope is NATIVE_MATERIAL_CONTENT_ONLY.
-- This migration records a real semantic verdict and canonical review receipts;
-- it does NOT set PE10_C5 DONE, emit PROFILE_EVOLUTION_CUTOVER_ADMITTED,
-- activate v0.2, change profile sources, or grant runtime authority.
BEGIN;

DO $pe10_c5_semantic$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_checkpoint constant text := 'PE10_C5';
  v_review constant text := 'EXEC-PE10C5-INDEP-d288c5ee8b3335e4';
  v_ledger constant text := 'EXEC-PE10C5-SOURCE-LEDGER-e804d71999bbdcad';
  v_source_receipt constant uuid := '731e93ae-a230-4172-ad6c-f2fb4c9024d6'::uuid;
  v_subject_sha constant text := 'dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde';
  v_source_head constant text := '8b3b41c20d77125cf4767c79487bc13d752c01a1';
  v_sem jsonb;
  v_judge jsonb;
  v_readback jsonb;
  v_report jsonb;
  v_final uuid;
  v_decision uuid;
  v_work bigint;
  v_meta jsonb;
BEGIN
  SELECT work_item_id,unit_metadata INTO STRICT v_work,v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code='PE10'
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM public.lf_operation_execution
         WHERE execution_id=v_review) IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_review
           AND step_id IN ('route_bind','target_currentness')
           AND status='STEP_PASS_WITH_EVIDENCE') <> 2
     OR EXISTS (
       SELECT 1 FROM public.lf_operation_execution_steps
       WHERE execution_id=v_review
         AND step_id IN ('semantic_review','judge_record','reviewer_readback','report_output')
     )
  THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_REVIEW_PRESTATE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id=v_source_receipt
      AND receipt_kind='SOURCE_SNAPSHOT'
      AND subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
      AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5'
      AND subject_sha256=v_subject_sha
      AND source_head_sha=v_source_head
      AND verification_state='VERIFIED'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_SOURCE_NOT_CURRENT';
  END IF;

  -- Independent semantic determination for the exact frozen material:
  -- PASS only for NATIVE_MATERIAL_CONTENT_ONLY. The RAW correctly distinguishes
  -- selector success from missing operational authority, applies the selected
  -- CAUSAL_ANALYSIS + SELF_REFINE techniques, and explicitly forbids treating
  -- native chat authoring as external-engine certification or cutover evidence.
  v_sem := public.lf_record_independent_review_step_v3(
    v_review,
    'semantic_review',
    'github://cristhianlujan/claude-persona-lf-patch/blob/663683bf2c101651291a89caa5ea56cea8649f32/skills/profile_creator/evals/results/pe10_c6_same_chat_gpt_material_authoring_20261016.json',
    jsonb_build_object(
      'verdict','PASS',
      'review_type','INDEPENDENT_REVIEW',
      'review_context','INDEPENDENT_OPERATION_CONTEXT',
      'rationale_summary',
        'PASS for NATIVE_MATERIAL_CONTENT_ONLY: the frozen response correctly identifies the authority/evidence gap rather than misdiagnosing selector failure, visibly applies CAUSAL_ANALYSIS and SELF_REFINE, proposes a bounded same-chat repair, and preserves explicit no-attestation/no-cutover limits.',
      'evidence_refs',jsonb_build_array(
        'supabase://private/lf_evidence_ledger_v1/'||v_source_receipt::text,
        'github://cristhianlujan/claude-persona-lf-patch/blob/663683bf2c101651291a89caa5ea56cea8649f32/skills/profile_creator/evals/results/pe10_c6_same_chat_gpt_material_authoring_20261016.json',
        'supabase://public/lf_capability_current/METHOD_PACK_REGISTRY/1.0.0',
        'supabase://programacion.engineering_work_checkpoints/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10/PE10_C5',
        'supabase://programacion.engineering_work_checkpoints/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10/PE10_C6'
      ),
      'utility_dimensions_checked',jsonb_build_array('dependency','data','author'),
      'independence_measure',jsonb_build_object(
        'state','INDEPENDENT',
        'dependency_dimension',jsonb_build_object(
          'state','INDEPENDENT',
          'basis','Reviewer execution is distinct from producer execution and consumes the frozen provider-bound source only.'
        ),
        'data_dimension',jsonb_build_object(
          'state','INDEPENDENT',
          'basis','Claims were checked against the exact SOURCE_SNAPSHOT, current Supabase authority/readbacks, and frozen GitHub bytes.'
        ),
        'author_dimension',jsonb_build_object(
          'state','INDEPENDENT',
          'basis','The reviewer did not author or mutate the frozen RAW and cannot alter its hashes or selected-method list.'
        )
      ),
      'positive_controls',jsonb_build_array(
        'causal_chain_separates_selector_from_authority_gap',
        'selected_methods_CAUSAL_ANALYSIS_SELF_REFINE_are_reflected_in_deliverable',
        'repair_is_bounded_to_same_chat_authoring_plus_independent_validation',
        'no_external_engine_certification_claim',
        'no_cutover_or_production_activation_claim'
      ),
      'negative_controls',jsonb_build_array(
        'reject_if_selector_failure_is_claimed_without_evidence',
        'reject_if_native_chat_is_presented_as_provider_attestation',
        'reject_if_C5_C6_are_claimed_DONE',
        'reject_if_v02_activation_is_implied'
      ),
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    null
  );

  IF v_sem->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_sem->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_STEP_NOT_CLEAN:%',v_sem;
  END IF;

  v_judge := public.lf_record_independent_review_step_v3(
    v_review,
    'judge_record',
    'supabase://public/lf_operation_execution/'||v_review||'/semantic_review',
    jsonb_build_object(
      'review_record_ref','PENDING_SERVER_ANCHOR',
      'verdict','PASS',
      'subject_sha256',v_subject_sha,
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    v_ledger
  );

  IF v_judge->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_judge->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_JUDGE_RECORD_NOT_CLEAN:%',v_judge;
  END IF;

  SELECT (checkpoint_payload->>'review_record_receipt_id')::uuid
    INTO v_decision
  FROM public.lf_operation_execution
  WHERE execution_id=v_review;

  IF v_decision IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id=v_decision
      AND execution_id=v_review
      AND receipt_kind='REVIEW_DECISION'
      AND subject_sha256=v_subject_sha
      AND source_head_sha=v_source_head
      AND verification_state='VERIFIED'
      AND receipt_payload->>'verdict'='PASS'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_DECISION_READBACK_FAILED';
  END IF;

  v_readback := public.lf_record_independent_review_step_v3(
    v_review,
    'reviewer_readback',
    'supabase://private/lf_evidence_ledger_v1/'||v_decision::text,
    jsonb_build_object(
      'review_record_ref','supabase://private/lf_evidence_ledger_v1/'||v_decision::text,
      'subject_sha256',v_subject_sha,
      'authority_readback_ref','supabase://private/lf_evidence_ledger_v1/'||v_source_receipt::text,
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    null
  );

  IF v_readback->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_readback->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEWER_READBACK_NOT_CLEAN:%',v_readback;
  END IF;

  v_report := public.lf_record_independent_review_step_v3(
    v_review,
    'report_output',
    'supabase://public/lf_operation_execution/'||v_review||'/report_output',
    jsonb_build_object(
      'review_receipt',jsonb_build_object('pending_server_anchor',true),
      'evidence_refs',jsonb_build_array(
        'supabase://private/lf_evidence_ledger_v1/'||v_source_receipt::text,
        'supabase://private/lf_evidence_ledger_v1/'||v_decision::text
      ),
      'authority_readback',jsonb_build_object(
        'subject_receipt_id',v_source_receipt::text,
        'review_record_receipt_id',v_decision::text
      ),
      'next_gate','PE10_C5_ADMISSION_READBACK',
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    v_ledger
  );

  IF v_report->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_report->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_REPORT_OUTPUT_NOT_CLEAN:%',v_report;
  END IF;

  SELECT receipt_id INTO STRICT v_final
  FROM private.lf_evidence_ledger_v1
  WHERE execution_id=v_review
    AND receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
    AND subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
    AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5'
    AND subject_sha256=v_subject_sha
    AND source_head_sha=v_source_head
    AND verification_state='VERIFIED'
    AND receipt_payload->>'verdict'='PASS'
  ORDER BY created_at DESC
  LIMIT 1;

  IF (SELECT status FROM public.lf_operation_execution
      WHERE execution_id=v_review) IS DISTINCT FROM 'COMPLETED'
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_review
           AND step_id IN ('route_bind','target_currentness','semantic_review',
                           'judge_record','reviewer_readback','report_output')
           AND status='STEP_PASS_WITH_EVIDENCE') <> 6
  THEN
    RAISE EXCEPTION 'PE10_C5_INDEPENDENT_REVIEW_COMPLETION_READBACK_FAILED';
  END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
        jsonb_set(
          unit_metadata,
          '{pe10_c5_native_source_snapshot_v1,status}',
          to_jsonb('INDEPENDENT_REVIEW_PASS_AWAITING_C5_ADMISSION'::text),
          false
        ),
        '{pe10_c5_native_review_v1}',
        coalesce(unit_metadata->'pe10_c5_native_review_v1','{}'::jsonb)
        || jsonb_build_object(
          'status','INDEPENDENT_REVIEW_PASS_AWAITING_C5_ADMISSION',
          'semantic_independent_verdict','PASS',
          'independent_review_receipt_id',v_final::text,
          'review_record_receipt_id',v_decision::text,
          'review_next_step','PE10_C5_ADMISSION_READBACK',
          'six_steps_passed',true,
          'c5_pass',false,
          'cutover_admitted',false,
          'production_activated',false
        ),
        true
      )
  WHERE work_item_id=v_work
    AND unit_metadata=v_meta;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_METADATA_CAS_FAILED';
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR EXISTS (
       SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF'
     )
  THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_POSTSTATE_FALSE_ADMISSION';
  END IF;

  INSERT INTO public.lf_eventos
    (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
     created_by_execution_id,payload)
  VALUES
    ('ARTIFACT_RECONCILED','PROGRAM_PLAN','PE10_C5.NATIVE_SEMANTIC_REVIEW.PASS.V1',
     'PE10 C5 exact native material independent review PASS; C5 admission still pending',
     'INFO','DERIVE_FROM_EXECUTION_ID',v_review,
     jsonb_build_object(
       'evidence_schema_version','operational-event/v2',
       'execution_id',v_review,
       'producer','PE10_C5_NATIVE_SEMANTIC_REVIEW_PASS_V1',
       'purpose','Complete the exact native-material independent review without admitting cutover',
       'occurred_at',clock_timestamp(),
       'checkpoint_code',v_checkpoint,
       'subject_sha256',v_subject_sha,
       'source_head_sha',v_source_head,
       'review_record_receipt_id',v_decision::text,
       'independent_review_receipt_id',v_final::text,
       'semantic_verdict','PASS',
       'six_steps_passed',true,
       'checkpoint_pass',false,
       'cutover_admitted',false,
       'production_activation',false,
       'acceptance_declared',false));

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-SEMANTIC-REVIEW-WAS-PENDING-20261021-001',
    'PROFILE_EVOLUTION',
    'C5 native source was verified but independent semantic review was not completed',
    'The exact GPT Native source and the first two deterministic review steps were present, while semantic_review, judge_record, reviewer_readback and report_output were still absent.',
    'The evidence pipeline was intentionally staged and stopped after source anchoring plus review initialization; C5 could not consume an independent review receipt until the remaining four governed steps were executed.',
    'A verified SOURCE_SNAPSHOT and initialized reviewer are necessary but not sufficient for admission.',
    'After review initialization, execute the semantic verdict in a distinct review context, persist REVIEW_DECISION, read it back, emit INDEPENDENT_REVIEW_RECEIPT, and require all six steps clean before C5 admission.',
    'This migration requires six STEP_PASS_WITH_EVIDENCE rows, COMPLETED reviewer execution, verified PASS final receipt, C5 still PENDING and zero cutover admission events.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'supabase/migrations/20261021165000_lf_pe10_c5_native_semantic_review_pass_v1.sql'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-SEMANTIC-REVIEW-WAS-PENDING-20261021-001'
  );

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-MIGRATION-VERSION-COLLISION-20261021-001',
    'PROFILE_EVOLUTION',
    'C5 semantic review migration version collided with an already applied migration',
    'Merge Train run 39637151193 stopped before APPLY because version 20261021164500 already belonged to lf_ig_m107_native_executor_route_correction_v1 in the Supabase migration ledger.',
    'A fixed timestamp was authored before the Train compared the candidate against the live migration ledger; another concurrent governed migration acquired the same version first.',
    'A syntactically valid new migration can still be inadmissible when its 14-digit version is no longer unique at Train pre-apply time.',
    'On PRE-APPLY identity collision, do not overwrite or replay the applied ledger entry; retimestamp the unapplied candidate to a free version, update bound tests/source refs, and re-run the same Train.',
    'Corrected source uses version 20261021165000; the prior 20261021164500 candidate was never applied and Train reported no DB apply or merge.',
    'MEDIUM',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'github://cristhianlujan/claude-persona-lf-patch/pull/3023'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-MIGRATION-VERSION-COLLISION-20261021-001'
  );
END
$pe10_c5_semantic$;

COMMIT;
