-- PE10 E2 S2 additive method-revision registration.
-- Governance-only metadata + EKB. No checkpoint transition, no runtime activation,
-- no rewrite of C2 evidence, no mutation of original PE10 M01-M32 method rows.
DO $pe10_e2_s2$
DECLARE
  v_exec text;
  v_rows integer;
  v_revision jsonb;
  c_contract_blob constant text := 'b3141ce75c793e1f53f429b89b86d71db99cea2c';
  c_evaluator_blob constant text := '60f2ebfac5d6be647b55ec83f4b4810aeedd16ff';
  c_validator_blob constant text := '6fd481d74f6b2f43175389e7bf38281b31aaf58f';
  c_c2_receipt constant text := 'b8b280740f61ce83624d051bebdda1ee3e52713cb3c7445e7f73a9137d07485e';
  c_contract_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/profile_updater/experiments/pe10_e2/methods/E2_DECISION_RULE_S2_V1.json#git_blob_sha1='||c_contract_blob;
  c_evaluator_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/profile_updater/experiments/pe10_e2/evaluator_only/PE10_E2_S2_VALIDATION_V1.json#git_blob_sha1='||c_evaluator_blob;
BEGIN
  SELECT execution_id INTO v_exec
  FROM public.lf_operation_execution
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND target_type='MIGRATION'
    AND target_code LIKE '%lf_pe10_e2_s2_method_revision_v1%'
    AND status='IN_PROGRESS'
  ORDER BY created_at DESC
  LIMIT 1;
  IF v_exec IS NULL THEN
    RAISE EXCEPTION 'PE10_E2_S2_TRAIN_EXECUTOR_MISSING';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE id=815
        AND work_item_id=1134
        AND unit_code='PE10_B18_B29_E2'
        AND plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
        AND source_event_id=20161
        AND unit_metadata->>'case_ref'='PE10-IG-M107-M109-P0'
        AND unit_metadata->>'source_cutoff_utc'='2026-10-15T00:00:00Z'
        AND unit_metadata->>'original_checkpoints_immutable'='true')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1134
           AND checkpoint_code='PE10_E2_C1'
           AND status='DONE'
           AND assertion_receipt->>'passed'='true')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1134
           AND checkpoint_code='PE10_E2_C2'
           AND status='DONE'
           AND assertion_receipt->>'passed'='true'
           AND assertion_receipt_sha256=c_c2_receipt)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1134
           AND checkpoint_code IN ('PE10_E2_C3','PE10_E2_C4')
           AND status='PENDING'
           AND assertion_receipt IS NULL)<>2
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133
           AND status='DONE'
           AND assertion_receipt->>'passed'='true')<>32
  THEN
    RAISE EXCEPTION 'PE10_E2_S2_PRESTATE_INVALID';
  END IF;

  IF EXISTS(
    SELECT 1 FROM programacion.engineering_plan_units
    WHERE id=815
      AND unit_metadata#>'{method_revisions_v1,E2_S2_V1}' IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'PE10_E2_S2_ALREADY_REGISTERED';
  END IF;

  IF EXISTS(
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='PE10-E2-S2-REACHABILITY-GRADED-CLOSURE-20261020-001'
  ) THEN
    RAISE EXCEPTION 'PE10_E2_S2_EKB_ALREADY_REGISTERED';
  END IF;

  v_revision := jsonb_build_object(
    'schema','PE10_E2_METHOD_REVISION_REGISTRATION_V1',
    'revision_code','E2_S2_V1',
    'status','VALIDATED_CANDIDATE_NOT_ACTIVATED',
    'case_ref','PE10-IG-M107-M109-P0',
    'source_cutoff_utc','2026-10-15T00:00:00Z',
    'contract_ref',c_contract_ref,
    'contract_blob_sha1',c_contract_blob,
    'evaluator_ref',c_evaluator_ref,
    'evaluator_blob_sha1',c_evaluator_blob,
    'validator_path','sandbox/lf_contract_gate_test/pe10_e2/decision_rule_s2_validator_v1.py',
    'validator_blob_sha1',c_validator_blob,
    'local_regression_cases',15,
    'local_regression_passed',15,
    'falsification_rounds',2,
    'applies_to',jsonb_build_array('PE10_M18_E2','PE10_M29_E2'),
    'decision_set',jsonb_build_array(
      'MEASURE_FIRST','CLEAR_NO_ACTION','VERIFY_MINOR','VERIFY_CRITICAL','REPAIR_REQUIRED'
    ),
    'requires_reachability_for_critical',true,
    'security_definer_requires_effective_callability',true,
    'edge_requires_deployment_attestation',true,
    'repair_requires_demonstrated_defect',true,
    'producer_may_read_rule',true,
    'producer_may_read_evaluator_receipt',false,
    'c2_historical_receipt_unchanged',true,
    'c3_checkpoint_state_unchanged',true,
    'c4_checkpoint_state_unchanged',true,
    'original_32_methods_unchanged',true,
    'runtime_activation',false,
    'registered_by_execution_id',v_exec
  );

  UPDATE programacion.engineering_plan_units
  SET unit_metadata = jsonb_set(
    jsonb_set(
      unit_metadata,
      '{method_revisions_v1}',
      coalesce(unit_metadata->'method_revisions_v1','{}'::jsonb),
      true
    ),
    '{method_revisions_v1,E2_S2_V1}',
    v_revision,
    true
  )
  WHERE id=815 AND work_item_id=1134;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 THEN
    RAISE EXCEPTION 'PE10_E2_S2_METADATA_WRITE_FAILED';
  END IF;

  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) VALUES (
    gen_random_uuid(),
    'PE10-E2-S2-REACHABILITY-GRADED-CLOSURE-20261020-001',
    'PROFILE_EVOLUTION',
    'E2 closure must grade measured exposure by reachability before repair',
    'The prior terminal rule could force VERIFY_FIRST or REPAIR_REQUIRED from drift/external consumers without distinguishing an unreachable exposure from a measured path to the subject.',
    'Exposure class presence and inventory drift were not separated from demonstrated reachability, effective callability, deployment attestation, and concrete defect evidence.',
    'EXPOSURE_CLASS_OR_DRIFT_PROMOTED_WITHOUT_REACHABILITY',
    'Require both hash/census measurement, then require a measured route to the subject for VERIFY_CRITICAL; Edge also needs deployment attestation, SECURITY DEFINER needs effective callability, and REPAIR_REQUIRED needs concrete defect evidence.',
    'Two read-only falsification rounds plus 15 deterministic local cases passed. CURRENT replay: 38 hashes reconcile 16 equal/22 modified; job 45 reaches the subject while eight other active cron jobs do not; 377 enabled user triggers yielded zero subject-reaching paths; SECURITY DEFINER plus proacl NULL did not make anon/authenticated/service_role effectively callable through schema programacion. These CURRENT observations are not P0 historical certification.',
    'HIGH',
    1,
    now(),
    now(),
    'PEVO-PE10-E2-S2-20261020',
    'ACTIVO',
    c_evaluator_ref,
    now(),
    now(),
    'VALIDATION',
    ARRAY['PROFILE_EVOLUTION','ENGINEERING_GOVERNANCE']::text[],
    'R4_NO_CUESTIONA',
    'PROCESS_DEPENDENT',
    'PE10 E2 additive S2 method revision; evaluator evidence withheld from producers until RAW freeze',
    c_contract_ref
  );

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1134
        AND checkpoint_code='PE10_E2_C2'
        AND status='DONE'
        AND assertion_receipt_sha256=c_c2_receipt)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1134
           AND checkpoint_code IN ('PE10_E2_C3','PE10_E2_C4')
           AND status='PENDING'
           AND assertion_receipt IS NULL)<>2
     OR (SELECT count(*) FROM programacion.engineering_plan_units
         WHERE id=815
           AND unit_metadata#>>'{method_revisions_v1,E2_S2_V1,status}'='VALIDATED_CANDIDATE_NOT_ACTIVATED'
           AND unit_metadata#>>'{method_revisions_v1,E2_S2_V1,contract_blob_sha1}'=c_contract_blob
           AND unit_metadata#>>'{method_revisions_v1,E2_S2_V1,evaluator_blob_sha1}'=c_evaluator_blob
           AND unit_metadata#>>'{method_revisions_v1,E2_S2_V1,validator_blob_sha1}'=c_validator_blob)<>1
     OR (SELECT count(*) FROM public.lf_error_knowledge
         WHERE codigo='PE10-E2-S2-REACHABILITY-GRADED-CLOSURE-20261020-001'
           AND estado='ACTIVO')<>1
  THEN
    RAISE EXCEPTION 'PE10_E2_S2_POST_READBACK_FAILED';
  END IF;
END
$pe10_e2_s2$;
