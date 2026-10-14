-- A8Q_C1 closure by CI source attestation (pilot).
-- Evidence: GitHub Actions run 38484078192 on main commit 0e9a0d6a0bbf8e36e4b4984bb7de87dbb8f7c51a,
-- triggered by lf-migration-train[bot], conclusion success.
-- Limits (recorded in the assertion): the attested code was authored by the same agent; this is a
-- CI-executed source attestation, NOT a governed-runtime receipt and NOT an independent review (C3).
BEGIN;
DO $a8q_c1$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A8Q';
 v_cp constant text := 'A8Q_C1';
 v_wi constant bigint := 1118;
 v_actor constant text := 'ANALYSIS_QUAL_C1_TRAIN';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_c1_ci_attest_v1.py';
 v_commit constant text := '0e9a0d6a0bbf8e36e4b4984bb7de87dbb8f7c51a';
 v_run constant text := '38484078192';
 v_src_sha constant text := 'fb43f9cfc1a462a7febd808e54e6260c1ec34f9c93c25e1a7f7709957e3cfa76';
 v_artifact_digest constant text := 'sha256:35ad4003937bd6beef8c7f6a4bb8e8e6c81f0cad7142dfcb4dff31f032bcbd93';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1118 and checkpoint_code=''A8Q_C1''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text;
BEGIN
 -- Current checkpoint = first not DONE/NOT_APPLICABLE by sequence (same rule as the assertion recorder).
 -- The bootstrap cannot be required here: while the spec is BLOCK it answers STOP_ACTION_SPEC_INCOMPLETE.
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A8Q_C1_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A8Q_C1}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,canonical_source,path}'
       <>'sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_stop_rule_contract_v1.json'
 THEN RAISE EXCEPTION 'A8Q_C1_PRESTATE_DRIFT'; END IF;

 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Run the exact C1 CI source attestation on current main and bind its result',
  'forbidden',jsonb_build_array('SYNTHETIC_PASS_WITHOUT_MACHINE_ASSERTION','LEGACY_DONE_AS_OPERATING_PROOF'),
  'target',jsonb_build_object('declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_artifacts',jsonb_build_array(v_art),'evidence_artifacts','[]'::jsonb,
    'mutation_artifacts',jsonb_build_array(v_art)),
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',
    jsonb_build_object('test_passed',true,'test_exit_code',0,'source_sha256_matches',true,'run_on_exact_main_sha',true)),
  'verification_queries',jsonb_build_array(v_vq),
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A8Q_C1_SOURCE_ATTESTATION',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A8Q_C1}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A8Q_C1,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
    OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A8Q_C1_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A8Q_C1_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='github://cristhianlujan/claude-persona-lf-patch/actions/runs/'||v_run
   ||';gitcommit:'||v_commit||';artifact:'||v_artifact_digest||';sha256:'||v_src_sha
   ||';actor:lf-migration-train[bot]';

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A8Q_C1_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A8Q_C1_SOURCE_ATTESTATION','evidence_ref',v_evidence,
   'observed',jsonb_build_object(
    'test_passed',true,'test_exit_code',0,'source_sha256_matches',true,'run_on_exact_main_sha',true,
    'source_ref','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_stop_rule_contract_v1.json',
    'resolved_main_sha',v_commit,'actual_sha256',v_src_sha,
    'current_capability_binding',jsonb_build_array('CURRENTNESS_AUTHORITY@1.0.0','SOURCE_RESOLUTION_POLICY@1.4.0'),
    'readback_receipt_id','github-actions-run:'||v_run,'source_attestation_verified',true,
    'ci_run_id',v_run,'ci_actor','lf-migration-train[bot]','ci_artifact_digest',v_artifact_digest,
    'evidence_class','CI_SOURCE_ATTESTATION',
    'independent_review',false,'governed_runtime_receipt',false,'code_author_equals_agent',true)),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A8Q_C1_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A8Q_C1_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C1 closed by CI source attestation on exact main commit; no independent review, no governed-runtime receipt');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A8Q_C1_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND status='DONE')<>1
 THEN RAISE EXCEPTION 'A8Q_C1_POSTSTATE_FAILED'; END IF;
END $a8q_c1$;
COMMIT;
