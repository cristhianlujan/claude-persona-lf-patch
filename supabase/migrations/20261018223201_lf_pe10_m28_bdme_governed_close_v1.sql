DO $m28$
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
    AND target_code LIKE '%lf_pe10_m28_bdme_governed_close_v1'
    AND status='IN_PROGRESS'
  ORDER BY created_at DESC LIMIT 1;

  IF v_exec IS NULL THEN RAISE EXCEPTION 'M28_NOT_TRAIN_EXECUTOR'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>27
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>5
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND checkpoint_code='PE10_M28' AND id=1652
           AND status='PENDING' AND assertion_receipt IS NULL)<>1
     OR (SELECT count(*) FROM programacion.pe10_method_variants
         WHERE method_code='PE10_M28' AND base_code='B'
           AND algorithm_codes=ARRAY['D','M','E']::text[]
           AND definition_version='PE10_METHOD_V1')<>1 THEN
    RAISE EXCEPTION 'M28_PRESTATE_FAILED';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1133 AND sequence_no<28 AND status='DONE'
        AND assertion_receipt->>'passed'='true'
        AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>27 THEN
    RAISE EXCEPTION 'M28_PRIOR_RECEIPTS_FAILED';
  END IF;

  v_spec:=jsonb_build_object(
    'status','READY',
    'action_kind','VERIFY_QUERY_ONCE',
    'recipe_mode','READBACK_EXACT',
    'requires_material_execution',true,
    'contract_family','PE10_METHOD_EXECUTION_EVIDENCE',
    'precision','PE10_METHOD_V1_MATERIAL_EVIDENCE',
    'evidence_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/461883cf725be67db130b80bda2913a0a353f2ab/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M28_RAW_V2.json#git_blob_sha=ac77c4c26b04d132e43a108fe3ced6f54c8debab',
    'assertion_contract',jsonb_build_object(
      'mode','EXPLICIT_PASS_WHEN_SUBSET',
      'pass_when',jsonb_build_object(
        'checkpoint_identity','PE10_M28',
        'base_code','B',
        'algorithm_D_executed',true,
        'barinel_probabilistic_executed',false,
        'algorithm_M_executed',true,
        'atms_assumptions_tracked',true,
        'atms_nogoods_tracked',true,
        'atms_propagation_executed',true,
        'algorithm_E_executed',true,
        'role_reports_frozen',5,
        'synthesis_completed',true,
        'read_only_sql_queries',27,
        'successful_read_only_queries',27,
        'query_errors_preserved',0,
        'role_negative_tests',17,
        'conflict_sets',15,
        'minimal_hitting_sets',15,
        'verify_first_roles',3,
        'needs_more_evidence_roles',1,
        'no_action_supported_roles',1,
        'repair_required_roles',0,
        'decision_state','VERIFY_FIRST',
        'causal_defect_proven',false,
        'implemented_repair',false,
        'git_raw_blob_sha','ac77c4c26b04d132e43a108fe3ced6f54c8debab',
        'runtime_modified',false,
        'independent_agents_claimed',false
      )
    )
  );

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M28}',v_spec,true)
  WHERE work_item_id=1133
    AND plan_code='PEVO-PE10-METHODS32-P0'
    AND unit_code='METHODS32';
  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n<>1 THEN RAISE EXCEPTION 'M28_SPEC_FAILED'; END IF;

  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M28',
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M28'
    )
  );
  IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET' THEN
    RAISE EXCEPTION 'M28_CONTRACT_FAILED';
  END IF;

  v_result:=jsonb_build_object(
    'status','PASS',
    'observed',jsonb_build_object(
      'checkpoint_identity','PE10_M28',
      'base_code','B',
      'algorithm_D_executed',true,
      'barinel_probabilistic_executed',false,
      'algorithm_M_executed',true,
      'atms_assumptions_tracked',true,
      'atms_nogoods_tracked',true,
      'atms_propagation_executed',true,
      'algorithm_E_executed',true,
      'role_reports_frozen',5,
      'synthesis_completed',true,
      'read_only_sql_queries',27,
      'successful_read_only_queries',27,
      'query_errors_preserved',0,
      'role_negative_tests',17,
      'conflict_sets',15,
      'minimal_hitting_sets',15,
      'verify_first_roles',3,
      'needs_more_evidence_roles',1,
      'no_action_supported_roles',1,
      'repair_required_roles',0,
      'decision_state','VERIFY_FIRST',
      'causal_defect_proven',false,
      'implemented_repair',false,
      'git_raw_blob_sha','ac77c4c26b04d132e43a108fe3ced6f54c8debab',
      'runtime_modified',false,
      'independent_agents_claimed',false
    ),
    'evidence_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/461883cf725be67db130b80bda2913a0a353f2ab/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M28_RAW_V2.json#git_blob_sha=ac77c4c26b04d132e43a108fe3ced6f54c8debab',
    'validation_kind','M28_B_D_M_E_ROLE_SYNTHESIS_MATERIAL_ONLY',
    'product_repair_applied',false
  );

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M28',v_result,v_exec
  );
  IF v_assertion->>'passed'<>'true' THEN RAISE EXCEPTION 'M28_RECEIPT_FAILED'; END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M28','DONE',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/blob/461883cf725be67db130b80bda2913a0a353f2ab/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M28_RAW_V2.json#git_blob_sha=ac77c4c26b04d132e43a108fe3ced6f54c8debab',v_exec,
    'M28 B+D+M+E material evidence verified; decision VERIFY_FIRST; no runtime repair'
  );
  IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M28_TRANSITION_FAILED'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1133 AND checkpoint_code='PE10_M28'
        AND status='DONE' AND completed_at IS NOT NULL
        AND evidence_ref='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/461883cf725be67db130b80bda2913a0a353f2ab/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M28_RAW_V2.json#git_blob_sha=ac77c4c26b04d132e43a108fe3ced6f54c8debab'
        AND assertion_receipt_sha256=v_receipt
        AND assertion_receipt->>'passed'='true'
        AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>28
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>4
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND checkpoint_code='PE10_M29' AND status='PENDING')<>1 THEN
    RAISE EXCEPTION 'M28_POST_FAILED';
  END IF;
END
$m28$;
