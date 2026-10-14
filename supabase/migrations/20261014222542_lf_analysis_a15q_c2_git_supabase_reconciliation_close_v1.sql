-- A15Q_C2 closure by a REAL Git<->Supabase reconciliation executed inside this transaction (owner decision: docs/programming-agent/ANALYSIS_A15_C2_C3_OWNER_DECISION_V1.md).
-- Git-side fingerprints are recomputed from the checked-out bytes (analysis_a15q_c2_reconciliation_v1.py) and embedded below; the same comparison
-- runs here against the live rows. Any disagreement raises and rolls back. Not a model execution, not provider-attested, not an independent review.
BEGIN;
DO $a15q_c2$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A15Q';
 v_cp constant text := 'A15Q_C2';
 v_wi constant bigint := 1125;
 v_actor constant text := 'ANALYSIS_QUAL_C2_RECONCILIATION';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_a15q_c2_reconciliation_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_A15_C2_C3_OWNER_DECISION_V1.md';
 v_decision_sha constant text := 'c516d915c8caf5809723ae9335c7edfd184efa5a0ddc374a99ada4dacaa6d792';
 v_git_fp constant text := 'e082580ffdb447b8638d9a2d7f68cade1a113b0ced21f5a1ce779fcb6ae080bd';
 v_exp_c1 constant jsonb := '{"A1": "b47d9b77d63fece5df1c7a1b24936c6398e96d13ff6b020b2b572c8f43eb2744", "A10": "31176b292230d03150ef6033e001379a0c38242ebe25feff574067bcdae29a23", "A11": "31176b292230d03150ef6033e001379a0c38242ebe25feff574067bcdae29a23", "A12": "74e9536d0aaec9000a246141b78720afb4ec1c75f0803e0e06f34961ffcd43c5", "A13": "7b5fba945f110d084df963ddda5ffcdab5e7eb140a08c4abed136016cb5ed0d8", "A14": "189d67bcd30ec3ba89ab92e6a3d9b2f9b8f65debc5f1215a0a292da09d055d1b", "A2": "7360cc4f81ddf3e9d80f87382219858b3c2e4e1895f2c85cc3bdd5db0d29cc04", "A3": "b2ca8318f6bd4a9f8cd28f44dc0f228cd25cf7392fd14d9c4148b82d9dac4f83", "A4": "8dbe08a396ce375094d11d77dee4dc80cfe180a3e7703ea5af549399b8231765", "A5": "b09ce629e7a7078e10738c48348f197361854a26f997aa1a3c12b774f3847be1", "A6": "487715da22c498da0ebd1d551dffd788316fa3fdd088db331f130d882233d0ae", "A7": "5cc5234ab6c9a44efa4ffa7a1286975cf400b2daa8366ec19dd6f1ce46cbc0b8", "A8": "fb43f9cfc1a462a7febd808e54e6260c1ec34f9c93c25e1a7f7709957e3cfa76", "A9": "90b41ca8fe9163bb2299bb4acf51f31fe9a6abdde936a645d3155f17bbd946df"}'::jsonb;
 v_exp_manifest constant text := '4ecb0fc2664bbfce80892d15d828d2344b45c09628b35b07f3db1597837d26c1';
 v_pg01_blob constant text := '56e561a72f8cfd9d085dd8087b854ff2ac740b1b';
 v_pg01_md5 constant text := 'aa527bec9207b5cb275ec4a2e4e2bcdf';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1125 and checkpoint_code=''A15Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_out jsonb; v_receipt jsonb; v_evidence text; v_pass jsonb;
 v_k text; v_ev text; v_n int; v_bad text; v_fn_md5 text; v_fn_count int;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE') ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A15Q_C2_NOT_CURRENT'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A15Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A15Q/A15Q_C2'
    OR v_old#>>'{validator_contract,criterion}'<>'Reconciliación Git-Supabase/juez/PG-01 con huellas actuales'
 THEN RAISE EXCEPTION 'A15Q_C2_PRESTATE_DRIFT'; END IF;

 -- RECONCILIATION (live rows vs Git-side fingerprints)
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE checkpoint_code ~ '^A[0-9]+Q_C[123]$')<>45 THEN RAISE EXCEPTION 'A15Q_C2_RECON_CHECKPOINT_ROWS_NOT_45'; END IF;
 SELECT count(*) INTO v_n FROM programacion.engineering_work_checkpoints WHERE checkpoint_code ~ '^A([1-9]|1[0-4])Q_C[123]$' AND status='DONE';
 IF v_n<>42 THEN RAISE EXCEPTION 'A15Q_C2_RECON_A1_A14_NOT_ALL_DONE:%',v_n; END IF;
 FOR v_k IN SELECT jsonb_object_keys(v_exp_c1) LOOP
  SELECT assertion_receipt->>'evidence_ref' INTO v_ev FROM programacion.engineering_work_checkpoints WHERE checkpoint_code=v_k||'Q_C1' AND status='DONE';
  IF (regexp_match(coalesce(v_ev,''),'sha256:([0-9a-f]{64});actor'))[1] IS DISTINCT FROM v_exp_c1->>v_k THEN RAISE EXCEPTION 'A15Q_C2_RECON_C1_SHA_MISMATCH:%',v_k; END IF;
 END LOOP;
 SELECT string_agg(x.cp,',' ORDER BY x.cp) INTO v_bad FROM (
   SELECT c.checkpoint_code cp,
          (regexp_match(c.assertion_receipt->>'evidence_ref','raw_sha256:([0-9a-f]{64})'))[1] ev_raw,
          (SELECT encode(sha256(convert_to(u.unit_metadata#>>array['gpt_native_captures_v1',c.checkpoint_code,'raw_output_text'],'UTF8')),'hex')
             FROM programacion.engineering_plan_units u WHERE u.plan_code=v_plan AND u.unit_code=substring(c.checkpoint_code from '^(A[0-9]+Q)_')) stored_raw
   FROM programacion.engineering_work_checkpoints c WHERE c.checkpoint_code ~ '^A([1-9]|1[0-4])Q_C[23]$') x
  WHERE x.ev_raw IS NULL OR x.stored_raw IS NULL OR x.ev_raw<>x.stored_raw;
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'A15Q_C2_RECON_RAW_SHA_MISMATCH:%',v_bad; END IF;
 SELECT assertion_receipt->>'evidence_ref' INTO v_ev FROM programacion.engineering_work_checkpoints WHERE checkpoint_code='A15Q_C1' AND status='DONE';
 IF (regexp_match(coalesce(v_ev,''),'sha256:([0-9a-f]{64});actor'))[1] IS DISTINCT FROM v_exp_manifest THEN RAISE EXCEPTION 'A15Q_C2_RECON_A15_C1_MANIFEST_MISMATCH'; END IF;
 SELECT count(*), max(md5(pg_get_functiondef(p.oid))) INTO v_fn_count, v_fn_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_analysis_pg01_exact_receipt_guard_v1';
 IF v_fn_count<>1 OR v_fn_md5 IS DISTINCT FROM v_pg01_md5 THEN RAISE EXCEPTION 'A15Q_C2_RECON_PG01_GUARD_FINGERPRINT:%:%',v_fn_count,v_fn_md5; END IF;

 v_pass:=jsonb_build_object('reconciliation_executed_in_transaction',true,'git_side_fingerprint_sha256',v_git_fp,'checkpoints_a1_a14_done',42,
   'c1_sources_reconciled',14,'c2_c3_raw_hashes_reconciled',28,'a15_c1_manifest_reconciled',true,'pg01_contract_blob',v_pg01_blob,'pg01_guard_fingerprint_matched',true,
   'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Reconcile the Git fingerprints of A1-A15 sources, the PG-01 contract and the judge dossier against the live Supabase receipts, and bind the result',
  'expected_evidence_class','RECONCILIATION_EXECUTED_IN_DB_AT_APPLY',
  'owner_decision',jsonb_build_object('decision_ref',v_decision_doc||'@'||v_decision_sha,'replaces_expected_evidence_class','REAL_EXECUTION_RECEIPT','scope','C2_ONLY','criterion_modified',false,
    'limits',jsonb_build_object('provider_attested',false,'model_execution',false,'independent_review',false)),
  'target',jsonb_build_object('declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints','programacion.engineering_plan_units'),
    'declared_artifacts',jsonb_build_array(v_art),'evidence_artifacts','[]'::jsonb,'mutation_artifacts',jsonb_build_array(v_art)),
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',v_pass),
  'verification_queries',jsonb_build_array(v_vq),
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A15Q_C2_GIT_SUPABASE_RECONCILIATION',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN','declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints','programacion.engineering_plan_units'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A15Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A15Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A15Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true' THEN RAISE EXCEPTION 'A15Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_work_checkpoints#git-supabase-reconciliation;git_fingerprint_sha256:'||v_git_fp
   ||';a15_manifest_sha256:'||v_exp_manifest||';pg01_contract_blob:'||v_pg01_blob||';pg01_guard_md5:'||v_pg01_md5
   ||';decision:'||v_decision_doc||'@'||v_decision_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A15Q_C2_HEARTBEAT_START:%',v_out; END IF;
 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A15Q_C2_GIT_SUPABASE_RECONCILIATION','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object('evidence_class','RECONCILIATION_EXECUTED_IN_DB_AT_APPLY','owner_decision_ref',v_decision_doc||'@'||v_decision_sha,
    'provider_attested',false,'model_execution',false,'governed_runtime_receipt',false,'independent_review',false,
    'attestation_scope','FINGERPRINT_AGREEMENT_AT_APPLY_TIME',
    'not_verified_by_this_assertion',jsonb_build_array('that_any_model_ran','provider_runtime_identity','independent_review','empirical_gates_rerun'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL THEN RAISE EXCEPTION 'A15Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A15Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed by a real Git-Supabase reconciliation executed in the transaction under the owner decision; fingerprint agreement only; no model execution, no provider attestation, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A15Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A15Q_C1:DONE,A15Q_C2:DONE,A15Q_C3:PENDING' THEN RAISE EXCEPTION 'A15Q_C2_POSTSTATE_FAILED'; END IF;
END $a15q_c2$;
COMMIT;
