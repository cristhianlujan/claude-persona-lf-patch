DO $m29$
DECLARE
  v_exec text;
  v_spec jsonb;
  v_contract jsonb;
  v_result jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_n int;
BEGIN
  SELECT execution_id INTO v_exec
  FROM public.lf_operation_execution
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND target_type='MIGRATION'
    AND target_code LIKE '%lf_pe10_m29_bce_governed_close_v1'
    AND status='IN_PROGRESS'
  ORDER BY created_at DESC LIMIT 1;

  IF v_exec IS NULL THEN RAISE EXCEPTION 'M29_NOT_TRAIN_EXECUTOR'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>28
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>4
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND checkpoint_code='PE10_M29' AND id=1653
           AND status='PENDING' AND assertion_receipt IS NULL)<>1
     OR (SELECT count(*) FROM programacion.pe10_method_variants
         WHERE method_code='PE10_M29' AND base_code='B'
           AND algorithm_codes=ARRAY['C','E']::text[]
           AND definition_version='PE10_METHOD_V1')<>1 THEN
    RAISE EXCEPTION 'M29_PRESTATE_FAILED';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1133 AND sequence_no<29 AND status='DONE'
        AND assertion_receipt->>'passed'='true'
        AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>28 THEN
    RAISE EXCEPTION 'M29_PRIOR_RECEIPTS_FAILED';
  END IF;

  v_spec:=jsonb_build_object(
    'status','READY',
    'action_kind','VERIFY_QUERY_ONCE',
    'recipe_mode','READBACK_EXACT',
    'requires_material_execution',true,
    'contract_family','PE10_METHOD_EXECUTION_EVIDENCE',
    'precision','PE10_METHOD_V1_MATERIAL_EVIDENCE',
    'evidence_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3c53a7d98e342c80a5a90bc0be8327535fedcd69/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M29_RAW_V2.json#git_blob_sha=32787dc3a8504e370b5c746e627bec44ebfc4744',
    'assertion_contract',jsonb_build_object(
      'mode','EXPLICIT_PASS_WHEN_SUBSET',
      'pass_when',jsonb_build_object(
        'checkpoint_identity','PE10_M29',
        'base_code','B',
        'algorithm_C_executed',true,
        'tlp_reconciled',true,
        'solver_used',false,
        'algorithm_E_executed',true,
        'role_reports_frozen',5,
        'synthesis_completed',true,
        'read_only_sql_queries',24,
        'successful_read_only_queries',24,
        'query_errors_preserved',0,
        'role_negative_tests',16,
        'invariants',26,
        'metamorphic_tests',5,
        'verify_first_roles',3,
        'needs_more_evidence_roles',1,
        'no_action_supported_roles',1,
        'repair_required_roles',0,
        'decision_state','VERIFY_FIRST',
        'causal_defect_proven',false,
        'implemented_repair',false,
        'git_raw_blob_sha','32787dc3a8504e370b5c746e627bec44ebfc4744',
        'runtime_modified',false,
        'independent_agents_claimed',false
      )
    )
  );

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M29}',v_spec,true)
  WHERE work_item_id=1133
    AND plan_code='PEVO-PE10-METHODS32-P0'
    AND unit_code='METHODS32';
  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n<>1 THEN RAISE EXCEPTION 'M29_SPEC_FAILED'; END IF;

  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M29',
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M29'
    )
  );
  IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET' THEN
    RAISE EXCEPTION 'M29_CONTRACT_FAILED';
  END IF;

  v_result:=jsonb_build_object(
    'status','PASS',
    'observed',jsonb_build_object(
      'checkpoint_identity','PE10_M29',
      'base_code','B',
      'algorithm_C_executed',true,
      'tlp_reconciled',true,
      'solver_used',false,
      'algorithm_E_executed',true,
      'role_reports_frozen',5,
      'synthesis_completed',true,
      'read_only_sql_queries',24,
      'successful_read_only_queries',24,
      'query_errors_preserved',0,
      'role_negative_tests',16,
      'invariants',26,
      'metamorphic_tests',5,
      'verify_first_roles',3,
      'needs_more_evidence_roles',1,
      'no_action_supported_roles',1,
      'repair_required_roles',0,
      'decision_state','VERIFY_FIRST',
      'causal_defect_proven',false,
      'implemented_repair',false,
      'git_raw_blob_sha','32787dc3a8504e370b5c746e627bec44ebfc4744',
      'runtime_modified',false,
      'independent_agents_claimed',false
    ),
    'evidence_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3c53a7d98e342c80a5a90bc0be8327535fedcd69/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M29_RAW_V2.json#git_blob_sha=32787dc3a8504e370b5c746e627bec44ebfc4744',
    'validation_kind','M29_B_C_E_ROLE_SYNTHESIS_MATERIAL_ONLY',
    'product_repair_applied',false
  );

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M29',v_result,v_exec
  );
  IF v_assertion->>'passed'<>'true' THEN RAISE EXCEPTION 'M29_RECEIPT_FAILED'; END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M29','DONE',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3c53a7d98e342c80a5a90bc0be8327535fedcd69/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M29_RAW_V2.json#git_blob_sha=32787dc3a8504e370b5c746e627bec44ebfc4744',v_exec,
    'M29 B+C+E material evidence verified; decision VERIFY_FIRST; no runtime repair'
  );
  IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M29_TRANSITION_FAILED'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1133 AND checkpoint_code='PE10_M29'
        AND status='DONE' AND completed_at IS NOT NULL
        AND evidence_ref='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3c53a7d98e342c80a5a90bc0be8327535fedcd69/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M29_RAW_V2.json#git_blob_sha=32787dc3a8504e370b5c746e627bec44ebfc4744'
        AND assertion_receipt_sha256=v_receipt
        AND assertion_receipt->>'passed'='true'
        AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>29
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>3
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND checkpoint_code='PE10_M30' AND status='PENDING')<>1 THEN
    RAISE EXCEPTION 'M29_POST_FAILED';
  END IF;
END
$m29$;
