-- Governed PE10 same-P0 C2 material correction evidence. NO P0/RAW/runtime modification.
-- One migration through the authorized LF Merge Train, no manual SQL.
DO $e2_c2$
DECLARE
 v_exec text;
 v_ref text := 'https://github.com/cristhianlujan/claude-persona-lf-patch/blob/6bb9dda76815870b011c3d68b801afd4caa5347f/docs/profile_updater/experiments/pe10_e2/evaluator_only/PE10_E2_C2_METHOD_VALIDATION_V1.json#git_blob_sha=3651ef6b16d1e11255f3b825bca29e28486e3c06';
 v_spec jsonb;
 v_result jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_receipt_sha text;
 v_rows int;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
   AND target_code LIKE '%lf_pe10_e2_c2_governed_close_v1'
   AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_E2_C2_TRAIN_EXECUTOR_MISSING'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE id=815 AND work_item_id=1134 AND unit_code='PE10_B18_B29_E2'
      AND plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
      AND source_event_id=20161
      AND unit_metadata->>'case_ref'='PE10-IG-M107-M109-P0'
      AND unit_metadata->>'source_cutoff_utc'='2026-10-15T00:00:00Z'
      AND unit_metadata->>'original_checkpoints_immutable'='true'
      AND unit_metadata->>'runtime_activation'='false')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1134 AND checkpoint_code='PE10_E2_C1'
      AND status='DONE' AND assertion_receipt->>'passed'='true')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1134 AND checkpoint_code='PE10_E2_C2'
      AND status='PENDING' AND assertion_receipt IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1134 AND checkpoint_code IN ('PE10_E2_C3','PE10_E2_C4')
      AND status='PENDING' AND assertion_receipt IS NULL)<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1133 AND status='DONE'
      AND evidence_ref IS NOT NULL AND assertion_receipt->>'passed'='true')<>32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133)<>32
 THEN RAISE EXCEPTION 'PE10_E2_C2_PRESTATE_INVALID'; END IF;

 SELECT unit_metadata#>'{action_specs_v1,PE10_E2_C2}' INTO STRICT v_spec
 FROM programacion.engineering_plan_units WHERE id=815;
 IF v_spec->>'status'<>'BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION'
 OR v_spec#>>'{assertion_contract,pass_when,checkpoint_identity}'<>'PE10_E2_C2'
 OR v_spec#>>'{assertion_contract,pass_when,case_ref}'<>'PE10-IG-M107-M109-P0'
 THEN RAISE EXCEPTION 'PE10_E2_C2_SPEC_PRESTATE_INVALID'; END IF;

 v_spec := jsonb_set(v_spec,'{status}','"READY"'::jsonb,true);
 v_spec := jsonb_set(v_spec,'{evidence_ref}',to_jsonb(v_ref),true);
 v_spec := jsonb_set(v_spec,'{evidence_metadata}',jsonb_build_object(
  'schema','PE10_E2_C2_GENERIC_METHOD_CORRECTION_RECEIPT_V1',
  'test_count',19,'test_failures',0,'sql_static_candidate_count',446,
  'evaluator_receipt_blob_sha','3651ef6b16d1e11255f3b825bca29e28486e3c06',
  'generic_helper_blob_sha','5808c220cf169ae6796725b306245660d0c75e9d',
  'generic_sql_blob_sha','93e144f6232dee2e82e2c7f4207a885b089b8685',
  'test_blob_sha','8e9138284117f6cba59a0777fb5a987bb35beb78',
  'methods_modified',jsonb_build_array('PE10_M18_E2','PE10_M29_E2'),
  'benchmark_case_unchanged',true,
  'oracle_in_producer_methods',false,
  'original_method_raw_unchanged',true,
  'current_sql_not_p0_evidence',true,
  'producer_runs_performed',false,
  'runtime_modified',false
 ),true);
 UPDATE programacion.engineering_plan_units SET
   unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_E2_C2}',v_spec,true)
 WHERE id=815 AND work_item_id=1134;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'PE10_E2_C2_SPEC_WRITE_FAILED'; END IF;

 IF (programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2','PE10_E2_C2',
 programacion.fn_engineering_checkpoint_action_spec_v3(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2','PE10_E2_C2'
 ))->>'status')<>'READY'
 THEN RAISE EXCEPTION 'PE10_E2_C2_ASSERTION_NOT_READY'; END IF;

 v_result:=jsonb_build_object(
  'status','PASS',
  'evidence_ref',v_ref,
  'observed',jsonb_build_object(
    'checkpoint_identity','PE10_E2_C2',
    'case_ref','PE10-IG-M107-M109-P0',
    'source_cutoff_unchanged',true,
    'original_work_unchanged',true,
    'material_evidence_verified',true,
    'method_corrections',2,
    'tests_executed',19,
    'tests_passed',19,
    'tests_failed',0,
    'static_census_candidate_count',446,
    'no_oracle_literals_in_producer_method',true,
    'current_replay_not_historical_certification',true,
    'source_blob_sha','3651ef6b16d1e11255f3b825bca29e28486e3c06',
    'runtime_modified',false,
    'producer_executed',false
  )
 );
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2',
 'PE10_E2_C2',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 THEN RAISE EXCEPTION 'PE10_E2_C2_RECEIPT_FAILED'; END IF;
 v_receipt_sha:=v_assertion->>'assertion_receipt_sha256';

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2',
 'PE10_E2_C2','DONE',v_ref,v_exec,
 'Generic method correction tested with 19 cases, read-only graph census; original P0 preserved; C3 not executed');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'PE10_E2_C2_TRANSITION_FAILED'; END IF;

 UPDATE programacion.engineering_plan_units SET
 unit_metadata=jsonb_set(unit_metadata,'{done_procedures_v1,PE10_E2_C2}',
 jsonb_build_object(
  'status','EVIDENCE_COMPLETED',
  'closure_route','ACTUALIZACION_DB_LF_MERGE_TRAIN',
  'evidence_ref',v_ref,
  'evidence_blob_sha','3651ef6b16d1e11255f3b825bca29e28486e3c06',
  'assertion_receipt_sha256',v_receipt_sha,
  'test_count',19,
  'next_checkpoint','PE10_E2_C3',
  'same_p0',true,
  'producer_input_oracle_exclusion_required',true
 ),true)
 WHERE id=815 AND work_item_id=1134;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'PE10_E2_C2_DONE_PROC_FAILED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=1134 AND checkpoint_code IN ('PE10_E2_C1','PE10_E2_C2')
    AND status='DONE' AND assertion_receipt->>'passed'='true'
    AND assertion_receipt_sha256 IS NOT NULL)<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=1134 AND checkpoint_code IN ('PE10_E2_C3','PE10_E2_C4')
    AND status='PENDING' AND assertion_receipt IS NULL)<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=1133 AND status='DONE' AND assertion_receipt->>'passed'='true')<>32
 THEN RAISE EXCEPTION 'PE10_E2_C2_POST_READBACK_FAILED'; END IF;
END
$e2_c2$;
