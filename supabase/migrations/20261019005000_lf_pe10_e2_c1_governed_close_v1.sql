-- PE10 E2 C1: evaluator-only causal diagnosis, same frozen P0.
-- Evidence document is frozen in the same PR; C3 must exclude evaluator-only materials from producer input.
-- Governed checkpoint transition only via ACTUALIZACION_DB_LF / Merge Train.
DO $pe10_e2_c1$
DECLARE
 v_exec text;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/fd693728675f9b568aecbe0bd803bda76514f34e/docs/profile_updater/experiments/pe10_e2/evaluator_only/PE10_E2_C1_CAUSAL_DIAGNOSIS_V1.json#git_blob_sha=fccc8d4312c2b55d0cf8adcf965285619d12afb4';
 v_spec jsonb;
 v_contract jsonb;
 v_result jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_receipt_sha text;
 v_n integer;
BEGIN
 SELECT execution_id INTO v_exec
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
   AND target_type='MIGRATION'
   AND target_code LIKE '%lf_pe10_e2_c1_governed_close_v1'
   AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_E2_C1_TRAIN_EXECUTOR_MISSING'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_items
     WHERE id=1134 AND work_code='PEVO-PE10-B18-B29-E2-P0'
       AND parent_work_item_id=1103 AND status IN ('BACKLOG','READY','IN_PROGRESS'))<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE id=815 AND work_item_id=1134
       AND plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
       AND unit_code='PE10_B18_B29_E2'
       AND source_event_id=20161
       AND unit_metadata->>'case_ref'='PE10-IG-M107-M109-P0'
       AND unit_metadata->>'source_cutoff_utc'='2026-10-15T00:00:00Z'
       AND unit_metadata->>'original_checkpoints_immutable'='true'
       AND unit_metadata->>'runtime_activation'='false')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND status='DONE'
       AND evidence_ref IS NOT NULL AND assertion_receipt->>'passed'='true')<>32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133)<>32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1134 AND checkpoint_code='PE10_E2_C1'
       AND sequence_no=1 AND status='PENDING'
       AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1134 AND sequence_no BETWEEN 2 AND 4
       AND status='PENDING' AND assertion_receipt IS NULL)<>3
 THEN RAISE EXCEPTION 'PE10_E2_C1_PRESTATE_NOT_VERIFIED'; END IF;

 SELECT unit_metadata#>'{action_specs_v1,PE10_E2_C1}' INTO v_spec
 FROM programacion.engineering_plan_units
 WHERE id=815;
 IF v_spec->>'status'<>'BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION'
 OR v_spec#>>'{assertion_contract,pass_when,checkpoint_identity}'<>'PE10_E2_C1'
 OR v_spec#>>'{assertion_contract,pass_when,case_ref}'<>'PE10-IG-M107-M109-P0'
 THEN RAISE EXCEPTION 'PE10_E2_C1_ACTION_SPEC_PRESTATE_FAILED'; END IF;

 v_spec:=jsonb_set(v_spec,'{status}','"READY"'::jsonb,true);
 v_spec:=jsonb_set(v_spec,'{evidence_ref}',to_jsonb(v_ref),true);
 v_spec:=jsonb_set(v_spec,'{precision}','"PE10_E2_C1_EVALUATOR_ONLY_FROZEN_CAUSAL_EVIDENCE_V1"'::jsonb,true);
 v_spec:=jsonb_set(v_spec,'{evidence_metadata}',jsonb_build_object(
  'git_blob_sha','fccc8d4312c2b55d0cf8adcf965285619d12afb4',
  'original_unchanged',true,'case_ref','PE10-IG-M107-M109-P0',
  'frozen_p0_event_id',20161,
  'findings',5,'read_only_observations',5,'negative_falsifiers',6,
  'runtime_modified',false,'producer_method_rerun',false,
  'evaluator_only','C1_DIAGNOSIS_NOT_C3_INPUT'
 ),true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_E2_C1}',v_spec,true)
 WHERE id=815 AND work_item_id=1134;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'PE10_E2_C1_ACTION_SPEC_WRITE_FAILED'; END IF;

 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
  'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2','PE10_E2_C1',
  programacion.fn_engineering_checkpoint_action_spec_v3(
   'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2','PE10_E2_C1')
 );
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 OR v_contract#>>'{pass_when,checkpoint_identity}'<>'PE10_E2_C1'
 THEN RAISE EXCEPTION 'PE10_E2_C1_ASSERTION_CONTRACT_NOT_READY'; END IF;

 v_result:=jsonb_build_object(
 'status','PASS','observed',jsonb_build_object(
  'checkpoint_identity','PE10_E2_C1',
  'case_ref','PE10-IG-M107-M109-P0',
  'original_work_unchanged',true,
  'source_cutoff_unchanged',true,
  'material_evidence_verified',true,
  'read_only_observations',5,
  'evidence_findings',5,
  'negative_falsifiers',6,
  'git_blob_sha','fccc8d4312c2b55d0cf8adcf965285619d12afb4',
  'evaluator_only',true,
  'method_producers_executed',false,
  'production_modified',false
 ),'evidence_ref',v_ref,
 'validation_kind','E2_C1_CAUSAL_DIAGNOSIS_ORIGINAL_FROZEN_AND_CURRENT_DISTINGUISHED',
 'runtime_modified',false,'method_repair_implemented',false
 );

 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
  'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2',
  'PE10_E2_C1',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' THEN RAISE EXCEPTION 'PE10_E2_C1_ASSERTION_NOT_PASSED'; END IF;
 v_receipt_sha:=v_assertion->>'assertion_receipt_sha256';

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
  'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2',
  'PE10_E2_C1','DONE',v_ref,v_exec,
  'Evaluator-only causal diagnosis frozen; 5 read-only observations, 6 falsifiers; C2 remains pending'
 );
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'PE10_E2_C1_TRANSITION_FAILED'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{done_procedures_v1,PE10_E2_C1}',jsonb_build_object(
   'status','EVIDENCE_COMPLETED',
   'closure_route','ACTUALIZACION_DB_LF_MERGE_TRAIN',
   'evidence_ref',v_ref,
   'blob_sha','fccc8d4312c2b55d0cf8adcf965285619d12afb4',
   'assertion_receipt_sha256',v_receipt_sha,
   'source_cutoff_utc','2026-10-15T00:00:00Z',
   'original_methods_untouched',true,
   'next_checkpoint','PE10_E2_C2',
   'c3_producer_input_exclusion_required',true
 ),true)
 WHERE id=815;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'PE10_E2_C1_DONE_PROCEDURE_FAILED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE id=1657 AND work_item_id=1134 AND status='DONE'
       AND evidence_ref=v_ref AND completed_at IS NOT NULL
       AND assertion_receipt->>'passed'='true'
       AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
       AND assertion_receipt_sha256=v_receipt_sha)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1134 AND status='PENDING')<>3
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND status='DONE'
       AND evidence_ref IS NOT NULL AND assertion_receipt->>'passed'='true')<>32
 OR (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE id=815 AND source_event_id=20161
       AND unit_metadata->>'case_ref'='PE10-IG-M107-M109-P0')<>1
 THEN RAISE EXCEPTION 'PE10_E2_C1_POST_READBACK_FAILED'; END IF;
END
$pe10_e2_c1$;
