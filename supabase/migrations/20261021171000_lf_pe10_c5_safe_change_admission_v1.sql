-- PE10_C5: classify the already-observed v0.2 candidate with the current
-- SAFE_CHANGE_ADMISSION capability and anchor the exact result in Evidence Ledger.
--
-- Inputs are existing evidence only:
--   * frozen PE10 cutover source receipt 37db027e-...
--   * material transactional rollback/negative/readback event 21205
--   * C5 native independent review receipt ae10a7bb-...
--   * current candidate policy v1.4
--
-- This migration does NOT mark PE10_C5 DONE, register or emit
-- PROFILE_EVOLUTION_CUTOVER_ADMITTED, activate v0.2, or mutate profile sources.
BEGIN;

DO $pe10_c5_safe$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_checkpoint constant text := 'PE10_C5';
  v_subject_type constant text := 'PROFILE_EVOLUTION_CUTOVER';
  v_subject_ref constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10';
  v_subject_sha constant text := '73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a';
  v_source_head constant text := '578e15f654dfccaba8c094c5f33121df8f44f216';
  v_source_receipt constant uuid := '37db027e-ad58-4cbb-b4dc-01b7568f6ac2'::uuid;
  v_native_review_receipt constant uuid := 'ae10a7bb-0e99-4589-a7c7-38e61af506b0'::uuid;
  v_tx_event constant bigint := 21205;
  v_policy_sha constant text := '5ae6804ded17dea94a7ec2d8c4ebe588b1017222ab8d92b912bc8607996892b5';
  v_source_test_sha constant text := '2847cb4d960135b0e490180fa5e50dbefae1236f9cb04bf992c385dd284f2f22';

  v_work bigint;
  v_meta jsonb;
  v_safe_sha text;
  v_ledger_sha text;
  v_typed_sha text;
  v_indep_sha text;
  v_request jsonb;
  v_result jsonb;
  v_result_sha text;
  v_plan_digest text;
  v_orch text;
  v_producer text;
  v_ledger text;
  v_res jsonb;
  v_dispatch jsonb;
  v_bind jsonb;
  v_anchor jsonb;
  v_receipt uuid;
  v_next jsonb;
BEGIN
  SELECT work_item_id,unit_metadata INTO STRICT v_work,v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code='PE10'
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code='PE10_C4') IS DISTINCT FROM 'DONE'
     OR EXISTS (
       SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF')
  THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_PRESTATE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id=v_source_receipt
      AND capability_code='EVIDENCE_LEDGER'
      AND receipt_kind='SOURCE_SNAPSHOT'
      AND subject_type=v_subject_type
      AND subject_ref=v_subject_ref
      AND subject_sha256=v_subject_sha
      AND source_head_sha=v_source_head
      AND verification_state='VERIFIED'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_FROZEN_SOURCE_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id=v_native_review_receipt
      AND capability_code='INDEPENDENT_ASSURANCE'
      AND receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
      AND subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
      AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5'
      AND verification_state='VERIFIED'
      AND receipt_payload->>'verdict'='PASS'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='EXEC-PE10C5-INDEP-d288c5ee8b3335e4'
      AND status='COMPLETED'
      AND checkpoint_payload->>'verdict'='PASS'
  ) OR (
    SELECT count(*) FROM public.lf_operation_execution_steps
    WHERE execution_id='EXEC-PE10C5-INDEP-d288c5ee8b3335e4'
      AND step_id IN ('route_bind','target_currentness','semantic_review',
                      'judge_record','reviewer_readback','report_output')
      AND status='STEP_PASS_WITH_EVIDENCE'
  ) <> 6 THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_NATIVE_REVIEW_NOT_VERIFIED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=v_tx_event
      AND evento_tipo='ARTIFACT_RECONCILED'
      AND entidad_codigo='PE10_C6.MATERIAL_TX_PREFLIGHT_PREACTIVATION.V1'
      AND payload->>'plan_code'=v_plan
      AND payload->>'checkpoint_code'='PE10_C6'
      AND payload->>'candidate_policy_sha256'=v_policy_sha
      AND payload->>'source_test_receipt_sha256'=v_source_test_sha
      AND payload->'transactional_rollback_verified'='true'::jsonb
      AND payload->'positive_candidate_structure_verified'='true'::jsonb
      AND payload->'invalid_receipt_rejected'='true'::jsonb
      AND jsonb_array_length(payload->'negative_guard_rejections_observed')>=3
      AND payload->'checkpoint_pass'='false'::jsonb
      AND payload->'cutover_admitted'='false'::jsonb
      AND payload->'production_activation'='false'::jsonb
  ) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_TRANSACTIONAL_EVIDENCE_MISSING';
  END IF;

  IF (SELECT count(*) FROM public.lf_policy_versions
      WHERE policy_code='POL-PROFILE-UPDATE-PASS'
        AND policy_version='v1.4-evolved-routing-candidate'
        AND status='CANDIDATE' AND policy_sha=v_policy_sha) <> 1
  THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_CANDIDATE_POLICY_DRIFT';
  END IF;

  SELECT max(manifest_sha256) FILTER (WHERE capability_code='SAFE_CHANGE_ADMISSION'),
         max(manifest_sha256) FILTER (WHERE capability_code='EVIDENCE_LEDGER'),
         max(manifest_sha256) FILTER (WHERE capability_code='TYPED_EVIDENCE_REGISTRY'),
         max(manifest_sha256) FILTER (WHERE capability_code='INDEPENDENT_ASSURANCE')
    INTO v_safe_sha,v_ledger_sha,v_typed_sha,v_indep_sha
  FROM public.lf_capability_current
  WHERE capability_code IN ('SAFE_CHANGE_ADMISSION','EVIDENCE_LEDGER',
                            'TYPED_EVIDENCE_REGISTRY','INDEPENDENT_ASSURANCE');

  IF v_safe_sha IS DISTINCT FROM '883adadf9117c3ee94de7ade6b9b68c372969eaf58b30d96d4271900118ed61e'
     OR v_ledger_sha IS DISTINCT FROM 'b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982'
     OR v_typed_sha IS DISTINCT FROM '0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da'
     OR v_indep_sha IS DISTINCT FROM 'f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35'
  THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_CAPABILITY_CURRENTNESS_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE capability_code='SAFE_CHANGE_ADMISSION'
      AND subject_ref=v_subject_ref
      AND subject_sha256=v_subject_sha
      AND verification_state='VERIFIED'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_RECEIPT_ALREADY_EXISTS_RECONCILE_FIRST';
  END IF;

  -- Typed evidence is a source-bound summary of the already-persisted material
  -- transactional probe. No synthetic success count is used to replace event 21205.
  v_request := jsonb_build_object(
    'consumer_ref',v_subject_ref,
    'evidence',jsonb_build_object(
      'items',jsonb_build_array(
        jsonb_build_object(
          'schema_version','architecture-gate-test/v1',
          'payload',jsonb_build_object(
            'evidence_schema_version','architecture-gate-test/v1',
            'all_confirmed',true,
            'probe_persistence',true,
            'positive_control_count',2,
            'negative_rejection_count',3,
            'source_event_id',v_tx_event,
            'source_event_ref','supabase://public/lf_eventos/21205',
            'source_test_receipt_sha256',v_source_test_sha,
            'frozen_source_receipt_id',v_source_receipt::text,
            'independent_review_receipt_id',v_native_review_receipt::text,
            'candidate_policy_sha256',v_policy_sha
          )
        )
      )
    ),
    'authority',jsonb_build_object(
      'state','SUFFICIENT',
      'authority_ref','supabase://private/lf_evidence_ledger_v1/'||v_native_review_receipt::text
    ),
    'materiality',jsonb_build_object(
      'change_required',true,
      'scope_bounded',true,
      'level','MEDIUM'
    ),
    'reversibility',jsonb_build_object(
      'state','DEMONSTRATED',
      'negative_proven',true,
      'rollback_proven',true,
      'readback_proven',true
    ),
    'recommendation',jsonb_build_object(
      'state','FAVORABLE',
      'confidence','HIGH'
    )
  );

  IF private.fn_lf_typed_evidence_payload_valid_v3(
       'architecture-gate-test/v1',
       v_request#>'{evidence,items,0,payload}') IS NOT TRUE
  THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_TYPED_EVIDENCE_REJECTED';
  END IF;

  v_result := public.lf_safe_change_admission_classify_v1(v_request);

  IF v_result->>'classification' IS DISTINCT FROM 'AUTOMATIZABLE'
     OR v_result->>'code' IS DISTINCT FROM 'SAFE_ADMISSION_CRITERIA_SATISFIED'
     OR v_result->>'execution_permission' IS DISTINCT FROM 'DOWNSTREAM_EXECUTION_ELIGIBLE'
     OR v_result->'effects_executed' IS DISTINCT FROM 'false'::jsonb
     OR v_result#>>'{authority,state}' IS DISTINCT FROM 'SUFFICIENT'
     OR v_result#>>'{reversibility,state}' IS DISTINCT FROM 'DEMONSTRATED'
     OR v_result#>>'{recommendation,state}' IS DISTINCT FROM 'FAVORABLE'
  THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_CLASSIFIER_NOT_ADMISSIBLE:%',v_result;
  END IF;

  v_result_sha := encode(extensions.digest(
    convert_to(v_result::text,'UTF8'),'sha256'),'hex');

  v_plan_digest := encode(extensions.digest(convert_to(jsonb_build_object(
    'schema','PE10_C5_SAFE_CHANGE_ADMISSION_PLAN_V1',
    'subject_ref',v_subject_ref,
    'subject_sha256',v_subject_sha,
    'source_head_sha',v_source_head,
    'source_receipt_id',v_source_receipt::text,
    'transactional_event_id',v_tx_event,
    'native_review_receipt_id',v_native_review_receipt::text,
    'candidate_policy_sha256',v_policy_sha,
    'safe_change_manifest_sha256',v_safe_sha,
    'evidence_ledger_manifest_sha256',v_ledger_sha,
    'classification_sha256',v_result_sha
  )::text,'UTF8'),'sha256'),'hex');

  v_orch := 'EXEC-PE10C5-SAFE-ORCH-'||substr(v_plan_digest,1,16);
  v_producer := 'EXEC-PE10C5-SAFE-PRODUCER-'||substr(v_plan_digest,1,16);
  v_ledger := 'EXEC-PE10C5-SAFE-LEDGER-'||substr(v_plan_digest,1,16);

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_orch,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
    'pe10c5:safe:orch:'||v_plan_digest,v_plan_digest,v_orch,null,null,
    jsonb_build_object(
      'schema','PE10_C5_SAFE_ORCHESTRATOR_V1',
      'plan_digest',v_plan_digest,
      'capability_code','SAFE_CHANGE_ADMISSION',
      'subject_type',v_subject_type,'subject_ref',v_subject_ref,
      'subject_sha256',v_subject_sha,'source_head_sha',v_source_head,
      'production_activation',false));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_ORCHESTRATOR_RESERVE_FAILED:%',v_res;
  END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_producer,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
    'pe10c5:safe:producer:'||v_plan_digest,v_plan_digest,v_orch,null,null,
    jsonb_build_object(
      'schema','PE10_C5_SAFE_PRODUCER_V1',
      'orchestrator_execution_id',v_orch,
      'plan_digest',v_plan_digest,
      'capability_code','SAFE_CHANGE_ADMISSION',
      'subject_type',v_subject_type,'subject_ref',v_subject_ref,
      'subject_sha256',v_subject_sha,'source_head_sha',v_source_head,
      'classification_sha256',v_result_sha));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_PRODUCER_RESERVE_FAILED:%',v_res;
  END IF;

  v_dispatch := public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch,v_producer,'SAFE_CHANGE_ADMISSION',v_plan_digest,
    jsonb_build_object(
      'subject_type',v_subject_type,'subject_ref',v_subject_ref,
      'subject_sha256',v_subject_sha,'source_head_sha',v_source_head,
      'classifier','public.lf_safe_change_admission_classify_v1',
      'transactional_event_id',v_tx_event,
      'native_review_receipt_id',v_native_review_receipt::text),
    v_orch);
  IF NOT coalesce((v_dispatch->>'ready')::boolean,false) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_DISPATCH_FAILED:%',v_dispatch;
  END IF;

  v_bind := public.fn_lf_capability_bind_from_orchestrator_v1(
    v_producer,'SAFE_CHANGE_ADMISSION',v_safe_sha,v_plan_digest,
    (v_dispatch->>'receipt_id')::uuid,v_orch);
  IF NOT coalesce((v_bind->>'ready')::boolean,false) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_BIND_FAILED:%',v_bind;
  END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_ledger,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
    'pe10c5:safe:ledger:'||v_plan_digest,v_plan_digest,v_orch,null,null,
    jsonb_build_object(
      'schema','PE10_C5_SAFE_LEDGER_V1',
      'orchestrator_execution_id',v_orch,
      'producer_execution_id',v_producer,
      'plan_digest',v_plan_digest,
      'capability_code','EVIDENCE_LEDGER',
      'subject_sha256',v_subject_sha,'source_head_sha',v_source_head));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_LEDGER_RESERVE_FAILED:%',v_res;
  END IF;

  v_dispatch := public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch,v_ledger,'EVIDENCE_LEDGER',v_plan_digest,
    jsonb_build_object(
      'subject_type',v_subject_type,'subject_ref',v_subject_ref,
      'subject_sha256',v_subject_sha,'source_head_sha',v_source_head,
      'producer_execution_id',v_producer,
      'producer_capability_code','SAFE_CHANGE_ADMISSION',
      'resolver_id','LF_SUPABASE_READBACK_V1'),
    v_orch);
  IF NOT coalesce((v_dispatch->>'ready')::boolean,false) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_LEDGER_DISPATCH_FAILED:%',v_dispatch;
  END IF;

  v_bind := public.fn_lf_capability_bind_from_orchestrator_v1(
    v_ledger,'EVIDENCE_LEDGER',v_ledger_sha,v_plan_digest,
    (v_dispatch->>'receipt_id')::uuid,v_orch);
  IF NOT coalesce((v_bind->>'ready')::boolean,false) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_LEDGER_BIND_FAILED:%',v_bind;
  END IF;

  v_anchor := public.fn_lf_evidence_ledger_anchor_v1(
    v_producer,
    'SAFE_CHANGE_ADMISSION',
    'PE10_C5_SAFE_CHANGE_ADMISSION',
    'SAFE_CHANGE_ADMISSION_RESULT',
    v_subject_type,
    v_subject_ref,
    v_subject_sha,
    v_source_head,
    'supabase://private/lf_evidence_ledger_v1/'||v_native_review_receipt::text,
    'LF_SUPABASE_READBACK_V1',
    'SUPABASE',
    'supabase://public/lf_safe_change_admission_classify_v1/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10',
    'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,
      'digest_recomputed',true,
      'classifier_result_sha256',v_result_sha,
      'typed_evidence_validated',true,
      'frozen_source_verified',true,
      'transactional_event_verified',true,
      'independent_review_verified',true,
      'candidate_policy_verified',true),
    jsonb_build_object(
      'schema','PE10_C5_SAFE_CHANGE_ADMISSION_RECEIPT_V1',
      'classification',v_result->>'classification',
      'code',v_result->>'code',
      'execution_permission',v_result->>'execution_permission',
      'effects_executed',false,
      'classifier_result',v_result,
      'classifier_result_sha256',v_result_sha,
      'request_sha256',encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex'),
      'source_receipt_id',v_source_receipt::text,
      'transactional_event_id',v_tx_event,
      'source_test_receipt_sha256',v_source_test_sha,
      'independent_review_receipt_id',v_native_review_receipt::text,
      'candidate_policy_sha256',v_policy_sha,
      'scope','SINGLE_DYNAMIC_PROFILE_UPDATER_V02_PREACTIVATION',
      'cutover_eligible',false,
      'production_activation_authorized',false),
    v_ledger);

  v_receipt := (v_anchor->>'receipt_id')::uuid;

  IF v_receipt IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id=v_receipt
      AND execution_id=v_producer
      AND created_by_execution_id=v_ledger
      AND capability_code='SAFE_CHANGE_ADMISSION'
      AND gate_code='PE10_C5_SAFE_CHANGE_ADMISSION'
      AND receipt_kind='SAFE_CHANGE_ADMISSION_RESULT'
      AND subject_type=v_subject_type
      AND subject_ref=v_subject_ref
      AND subject_sha256=v_subject_sha
      AND source_head_sha=v_source_head
      AND verification_state='VERIFIED'
      AND resolver_id='LF_SUPABASE_READBACK_V1'
      AND provider='SUPABASE'
      AND verification_method='SUPABASE_SQL_READBACK_PLUS_DB_DIGEST'
      AND verification_payload->'provider_readback_verified'='true'::jsonb
      AND verification_payload->'digest_recomputed'='true'::jsonb
      AND receipt_payload->>'classification'='AUTOMATIZABLE'
      AND receipt_payload->>'execution_permission'='DOWNSTREAM_EXECUTION_ELIGIBLE'
      AND receipt_payload->>'independent_review_receipt_id'=v_native_review_receipt::text
      AND (receipt_payload->>'transactional_event_id')::bigint=v_tx_event
  ) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_RECEIPT_READBACK_FAILED';
  END IF;

  v_next := jsonb_set(
    v_meta,
    '{pe10_c5_safe_change_admission_v1}',
    jsonb_build_object(
      'schema','PE10_C5_SAFE_CHANGE_ADMISSION_V1',
      'status','SAFE_CHANGE_VERIFIED_AWAITING_ADMISSION_EVENT',
      'safe_change_receipt_id',v_receipt::text,
      'classification','AUTOMATIZABLE',
      'execution_permission','DOWNSTREAM_EXECUTION_ELIGIBLE',
      'subject_sha256',v_subject_sha,
      'source_head_sha',v_source_head,
      'source_receipt_id',v_source_receipt::text,
      'transactional_event_id',v_tx_event,
      'independent_review_receipt_id',v_native_review_receipt::text,
      'candidate_policy_sha256',v_policy_sha,
      'c5_pass',false,
      'cutover_admitted',false,
      'production_activated',false),
    true);

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_next
  WHERE work_item_id=v_work AND unit_metadata=v_meta;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_METADATA_CAS_FAILED';
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR EXISTS (
       SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF')
  THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_FALSE_ADMISSION';
  END IF;

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-SAFE-CHANGE-RECEIPT-MISSING-20261021-001',
    'PROFILE_EVOLUTION',
    'C5 had rollback and independent review evidence but no SAFE_CHANGE_ADMISSION receipt',
    'PE10 C5 already had benchmark evidence, material transactional rollback/negative/readback proof and an exact independent native-material PASS, while the admission query still had no provider-bound SAFE_CHANGE_ADMISSION receipt for the frozen cutover subject.',
    'The evidence existed in separate governed stores but had not been classified and anchored through the current SAFE_CHANGE_ADMISSION capability.',
    'Evidence completeness across checkpoints does not imply downstream execution eligibility until the canonical admission classifier returns permission and the exact result is bound in Evidence Ledger.',
    'Build one source-bound classifier request from existing typed evidence, require AUTOMATIZABLE plus DOWNSTREAM_EXECUTION_ELIGIBLE, then anchor it via SAFE_CHANGE_ADMISSION and EVIDENCE_LEDGER; never infer permission from benchmark or review PASS alone.',
    'Receipt readback requires exact frozen subject, event 21205, reviewer receipt ae10a7bb..., candidate policy SHA, trusted Supabase resolver, classifier digest and C5 remains PENDING with zero cutover admission events.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'supabase/migrations/20261021171000_lf_pe10_c5_safe_change_admission_v1.sql'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-SAFE-CHANGE-RECEIPT-MISSING-20261021-001'
  );

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-SAFE-CLASSIFIER-CONNECTOR-EXECUTE-DENIED-20261021-001',
    'PROFILE_EVOLUTION',
    'Read-only connector could inspect SAFE_CHANGE_ADMISSION but not execute the classifier',
    'The connector role returned SQLSTATE 42501 for public.lf_safe_change_admission_classify_v1 because EXECUTE is restricted to postgres and service_role.',
    'The capability deliberately exposes no EXECUTE grant to the generic read-only connector, so a preflight SELECT from that transport cannot run the classifier.',
    'A read-only inspection path may verify source and grants yet still be unable to invoke a controlled classifier; this is an authority boundary, not evidence that the classifier is broken.',
    'Run the classifier only inside the governed Migration Train transaction under its authorized principal and fail closed unless its exact result is AUTOMATIZABLE with DOWNSTREAM_EXECUTION_ELIGIBLE.',
    'This migration invokes the current classifier transactionally and rolls back the entire lot if any result or evidence binding differs.',
    'LOW',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'github://cristhianlujan/claude-persona-lf-patch/pull/PENDING'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-SAFE-CLASSIFIER-CONNECTOR-EXECUTE-DENIED-20261021-001'
  );
END
$pe10_c5_safe$;

COMMIT;
