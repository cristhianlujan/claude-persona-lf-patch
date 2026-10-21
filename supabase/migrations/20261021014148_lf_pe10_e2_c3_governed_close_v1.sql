-- Governed PE10 same-P0 C3 frozen-run evidence. NO P0/RAW/runtime modification, no grading.
-- One migration through the authorized LF Merge Train, no manual SQL.
DO $e2_c3$
DECLARE
 v_exec text;
 v_ref text := 'https://github.com/cristhianlujan/claude-persona-lf-patch/blob/405a195ebbfd6db68c0ebb5028a1334cb12e3721/docs/profile_updater/experiments/pe10_e2/c3_cleanroom/frozen_run/C3_FROZEN_RUN_RECEIPT_V1.json#git_blob_sha=11f43bab040e7aba4bf807994af90220d8896530';
 v_spec jsonb;
 v_result jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_receipt_sha text;
 v_rows int;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
   AND target_code LIKE '%lf_pe10_e2_c3_governed_close_v1'
   AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_E2_C3_TRAIN_EXECUTOR_MISSING'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE id=815 AND work_item_id=1134 AND unit_code='PE10_B18_B29_E2'
      AND plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
      AND source_event_id=20161
      AND unit_metadata->>'case_ref'='PE10-IG-M107-M109-P0'
      AND unit_metadata->>'source_cutoff_utc'='2026-10-15T00:00:00Z'
      AND unit_metadata->>'original_checkpoints_immutable'='true'
      AND unit_metadata->>'runtime_activation'='false')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1134 AND checkpoint_code IN ('PE10_E2_C1','PE10_E2_C2')
      AND status='DONE' AND assertion_receipt->>'passed'='true')<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1134 AND checkpoint_code='PE10_E2_C3'
      AND status='PENDING' AND assertion_receipt IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1134 AND checkpoint_code='PE10_E2_C4'
      AND status='PENDING' AND assertion_receipt IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1133 AND status='DONE'
      AND evidence_ref IS NOT NULL AND assertion_receipt->>'passed'='true')<>32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133)<>32
 THEN RAISE EXCEPTION 'PE10_E2_C3_PRESTATE_INVALID'; END IF;

 SELECT unit_metadata#>'{action_specs_v1,PE10_E2_C3}' INTO STRICT v_spec
 FROM programacion.engineering_plan_units WHERE id=815;
 IF v_spec->>'status'<>'BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION'
 OR v_spec#>>'{assertion_contract,pass_when,checkpoint_identity}'<>'PE10_E2_C3'
 OR v_spec#>>'{assertion_contract,pass_when,case_ref}'<>'PE10-IG-M107-M109-P0'
 THEN RAISE EXCEPTION 'PE10_E2_C3_SPEC_PRESTATE_INVALID'; END IF;

 v_spec := jsonb_set(v_spec,'{status}','"READY"'::jsonb,true);
 v_spec := jsonb_set(v_spec,'{evidence_ref}',to_jsonb(v_ref),true);
 v_spec := jsonb_set(v_spec,'{evidence_metadata}',jsonb_build_object(
  'schema','PE10_E2_C3_FROZEN_RUN_RECEIPT_V1',
  'receipt_blob_sha','11f43bab040e7aba4bf807994af90220d8896530',
  'manifest_blob_sha','a0c7de39bfad249c7defa82472dbf3dd2d091e27',
  'manifest_sha256','db33d741b27bf76ae54b9d03229879b6c66da51f74d56d68ce9ca6673d864a21',
  'validator_blob_sha','e204e1306c26926ed72c31dcf80b21671be8c931',
  'validator_test_blob_sha','74b833caf6ef370d126749ad9179660c0a93dc00',
  'validator_tests_executed',5,'validator_tests_failed',0,
  'arms',jsonb_build_array('B18','B29'),
  'raw_files_per_arm',5,'synthesis_files',2,
  'output_state','RAW_FROZEN_UNGRADED',
  'same_common_p0_envelope',true,
  'common_envelope_sha256','93d4f5cba4564ddb0cc46f731375d5d83d81b724e195dfc213b2d98fc9ebc090',
  'provider_isolation_attested',false,
  'known_denylist_exposure','B29 relay Q8 (coordinator error; producer excluded it from evidence)',
  'grading_performed',false,
  'runtime_modified',false
 ),true);
 UPDATE programacion.engineering_plan_units SET
   unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_E2_C3}',v_spec,true)
 WHERE id=815 AND work_item_id=1134;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'PE10_E2_C3_SPEC_WRITE_FAILED'; END IF;

 IF (programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2','PE10_E2_C3',
 programacion.fn_engineering_checkpoint_action_spec_v3(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2','PE10_E2_C3'
 ))->>'status')<>'READY'
 THEN RAISE EXCEPTION 'PE10_E2_C3_ASSERTION_NOT_READY'; END IF;

 v_result:=jsonb_build_object(
  'status','PASS',
  'evidence_ref',v_ref,
  'observed',jsonb_build_object(
    'checkpoint_identity','PE10_E2_C3',
    'case_ref','PE10-IG-M107-M109-P0',
    'source_cutoff_unchanged',true,
    'original_work_unchanged',true,
    'material_evidence_verified',true,
    'arms_frozen',2,
    'five_role_raw_per_arm',true,
    'synthesis_per_arm',true,
    'output_state','RAW_FROZEN_UNGRADED',
    'same_common_p0_envelope',true,
    'validator_tests_passed',5,
    'validator_tests_failed',0,
    'provider_isolation_attested',false,
    'denylist_exposure_disclosed',true,
    'grading_performed',false,
    'source_blob_sha','11f43bab040e7aba4bf807994af90220d8896530',
    'runtime_modified',false
  )
 );
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2',
 'PE10_E2_C3',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 THEN RAISE EXCEPTION 'PE10_E2_C3_RECEIPT_FAILED'; END IF;
 v_receipt_sha:=v_assertion->>'assertion_receipt_sha256';

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2',
 'PE10_E2_C3','DONE',v_ref,v_exec,
 'B18 and B29 RAW frozen ungraded on the same P0 with validator PASS; provider isolation not attested; C4 not executed');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'PE10_E2_C3_TRANSITION_FAILED'; END IF;

 UPDATE programacion.engineering_plan_units SET
 unit_metadata=jsonb_set(unit_metadata,'{done_procedures_v1,PE10_E2_C3}',
 jsonb_build_object(
  'status','EVIDENCE_COMPLETED',
  'closure_route','ACTUALIZACION_DB_LF_MERGE_TRAIN',
  'evidence_ref',v_ref,
  'evidence_blob_sha','11f43bab040e7aba4bf807994af90220d8896530',
  'assertion_receipt_sha256',v_receipt_sha,
  'next_checkpoint','PE10_E2_C4',
  'same_p0',true,
  'provider_isolation_attested',false,
  'raw_state','RAW_FROZEN_UNGRADED'
 ),true)
 WHERE id=815 AND work_item_id=1134;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'PE10_E2_C3_DONE_PROC_FAILED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=1134 AND checkpoint_code IN ('PE10_E2_C1','PE10_E2_C2','PE10_E2_C3')
    AND status='DONE' AND assertion_receipt->>'passed'='true'
    AND assertion_receipt_sha256 IS NOT NULL)<>3
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=1134 AND checkpoint_code='PE10_E2_C4'
    AND status='PENDING' AND assertion_receipt IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=1133 AND status='DONE' AND assertion_receipt->>'passed'='true')<>32
 THEN RAISE EXCEPTION 'PE10_E2_C3_POST_READBACK_FAILED'; END IF;
END
$e2_c3$;
