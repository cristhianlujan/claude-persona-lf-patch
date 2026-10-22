-- RW1-05_C3: governed full-tier blind-capture close, without changing runtime/ACL.
-- Requires exact-main CI positive+negative evidence and existing C1/C2 receipts.
-- Capture provenance remains owner-provided; NOT provider-attested or provably isolated.
-- Authoritative DB effect: ACTUALIZACION_DB_LF / LF Migration Merge Train ONLY.
BEGIN;
DO $rw105_c3_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C3';
  v_work constant bigint := 1131;
  v_actor constant text := 'MIGRATION_VIA_MERGE_TRAIN_RW1_05_C3_GOVERNED_CLOSE';
  v_prior_md5 constant text := 'abe51125a70364259c62c7415b2b3531';
  v_packet_blob constant text := 'ea7de94aa6f8395cf79595f2a571aa98b9347590';
  v_capture_blob constant text := 'da02bc075aa45f0ef5f3c81dfc310c6488b3ab63';
  v_validator_blob constant text := '1dbc24660c164d2edaf308f855a3a560ad8cee8f';
  v_workflow_blob constant text := '039807b1d98bb4937ac815181d4a2842c7a09ce2';
  v_output_sha constant text := '14da228f8ec6cb17afc97042398693530a96685d90033f386f3bf33001a43051';
  v_main_sha constant text := '2e6432600a905bdbc7c10e63de56758c4d27d326';
  v_run constant text := '39701466501';
  v_job constant text := '119571440311';
  v_terminal_sha constant text := 'sha256:caa55730e62d8c921b1e0f7032b55e382b11d22a3ed7bf77ed150434e89d762d';
  v_evidence constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C3_REVIEW_CAPTURE_V1.json#blob:da02bc075aa45f0ef5f3c81dfc310c6488b3ab63';
  v_old jsonb;
  v_capture jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_contract jsonb;
  v_contract_sha text;
  v_bootstrap jsonb;
  v_terminal jsonb;
  v_shadow jsonb;
  v_train jsonb;
  v_handoff jsonb;
  v_native jsonb;
  v_remote jsonb;
  v_double_req jsonb;
  v_good_body jsonb;
  v_good_result jsonb;
  v_good_validation jsonb;
  v_bad_body jsonb;
  v_bad_result jsonb;
  v_bad_validation jsonb;
  v_obs jsonb;
  v_negative jsonb;
  v_receipt jsonb;
  v_transition jsonb;
  v_err text;
  v_trial integer;
  v_count integer;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
    FROM programacion.engineering_plan_units
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work
     AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
   FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_items
       WHERE id=v_work AND work_code='ROUTER-W1-05') IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND status='DONE'
         AND checkpoint_code IN ('RW1-05_C1','RW1-05_C2'))<>2
     OR NOT EXISTS (
       SELECT 1 FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_work AND checkpoint_code=v_cp AND status='PENDING'
          AND assertion_receipt_sha256 IS NULL AND evidence_ref IS NULL
     )
     OR (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints
          WHERE work_item_id=v_work AND checkpoint_code='RW1-05_C2')
          IS DISTINCT FROM '1c52dfda25a901715395d32740a3947d663929b92b9d7f26b0680c15c8d568a5'
     OR v_old#>>'{gpt_native_packets_v1,RW1-05_C3,packet_git_blob}' IS DISTINCT FROM v_packet_blob
     OR v_old#>>'{gpt_native_c3_keys_v1,RW1-05_C3,real_item_id}' IS DISTINCT FROM 'ITEM_A'
     OR v_old#>>'{gpt_native_c3_keys_v1,RW1-05_C3,decoy_item_id}' IS DISTINCT FROM 'ITEM_B'
     OR v_old#>'{gpt_native_captures_v1,RW1-05_C3}' IS NOT NULL
     OR jsonb_array_length(coalesce(
       v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C3,missing_typed}','[]'::jsonb))<>0
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_PRESTATE_OR_SOURCE_DRIFT'; END IF;

  -- The generic checkpoint close candidate is not an active writable operation.
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
     WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
       AND status='CANDIDATO_READ_ONLY' AND lifecycle_state_code='OP_CANDIDATE'
  )
  OR NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
     WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
       AND asset_type='ENGINEERING_CHECKPOINT' AND action_code='CHECKPOINT_CLOSE'
       AND status='CANDIDATO_READ_ONLY' AND write_allowed=false
  )
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_GENERIC_PROVIDER_AUTHORITY_DRIFT'; END IF;

  v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_bootstrap->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
    OR v_bootstrap#>>'{execution_readiness,status}' IS DISTINCT FROM 'READY'
    OR v_bootstrap#>>'{execution_readiness,execution_ready}' IS DISTINCT FROM 'true'
    OR v_bootstrap#>>'{state,open_blockers}' IS DISTINCT FROM '0'
    OR v_bootstrap#>>'{state,unmet_deps}' IS DISTINCT FROM '0'
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_BOOTSTRAP_NOT_READY'; END IF;

  SELECT payload INTO STRICT v_handoff FROM public.lf_eventos
   WHERE id=21453 AND evento_tipo='HANDOFF_DEEP_CONTEXT'
     AND payload->>'packet_git_blob'=v_packet_blob
     AND payload->>'separate_chat_required'='true'
     AND payload->>'acceptance_declared'='false';
  IF v_handoff->>'provider_attested' IS DISTINCT FROM 'false'
     OR v_handoff->>'independent_review' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_HANDOFF_CLAIMS_DRIFT'; END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(
    'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001'
  );
  IF v_terminal->>'status' IS DISTINCT FROM 'READY'
    OR v_terminal->>'terminal_authority_receipt_sha256' IS DISTINCT FROM v_terminal_sha
    OR v_terminal#>>'{terminal_authority_receipt,router_authority_receipt,status}'
      IS DISTINCT FROM 'READY_TO_EXECUTE'
    OR v_terminal#>>'{terminal_authority_receipt,authority_rule}'
      IS DISTINCT FROM 'ROUTER_AND_OPERATION_EVIDENCE_ONLY_NO_SPECIALIST_EFFECT_AUTHORITY'
    OR v_terminal#>>'{terminal_authority_receipt,canonical_judge_readback,required_steps_pass}'
      IS DISTINCT FROM '11'
    OR v_terminal#>>'{terminal_authority_receipt,canonical_judge_readback,judge_result}'
      IS DISTINCT FROM 'PASS'
    OR v_terminal#>>'{terminal_authority_receipt,report_output_receipt,no_write_performed}'
      IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_TERMINAL_AUTHORITY_DRIFT'; END IF;

  SELECT payload INTO STRICT v_shadow FROM public.lf_eventos
   WHERE id=21414 AND evento_tipo='STEP_EVIDENCE'
     AND entidad_codigo='RW1-05_C2';
  IF v_shadow#>>'{resume_validator_readback,resume_validator_code}' IS DISTINCT FROM 'VALID'
    OR v_shadow#>>'{resume_validator_readback,next_action}'
      IS DISTINCT FROM 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
    OR v_shadow#>>'{resume_route_summary,status}' IS DISTINCT FROM 'ROUTER_REDERIVED'
    OR v_shadow#>>'{semantic_result,clarification_question}' IS NOT NULL
    OR jsonb_array_length(coalesce(
      v_shadow#>'{semantic_result,material_ambiguities}','[]'::jsonb))<>0
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_QUESTION_OR_RESUME_DRIFT'; END IF;

  SELECT payload INTO STRICT v_train FROM public.lf_eventos
   WHERE id=21451 AND evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
     AND payload#>>'{receipt,pr}'='3052';
  IF v_train#>>'{receipt,terminal_status}' IS DISTINCT FROM 'COMPLETED'
    OR v_train#>>'{receipt,write_ahead,reserved_at}' IS NULL
    OR v_train#>>'{receipt,effect,phase}' IS DISTINCT FROM 'SUCCEEDED'
    OR v_train#>>'{receipt,parity,migration_source_parity}' IS DISTINCT FROM 'PASS'
    OR v_train#>>'{receipt,merge,in_main}' IS DISTINCT FROM 'true'
    OR v_train#>>'{receipt,ledger_readback,matches_target}' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_TRAIN_LIFECYCLE_DRIFT'; END IF;

  v_native:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','GPT_NATIVE');
  v_remote:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','REMOTE_API');
  IF v_native->>'admitted' IS DISTINCT FROM 'true'
    OR v_native->>'remote_runtime_required' IS DISTINCT FROM 'false'
    OR v_remote->>'admitted' IS DISTINCT FROM 'false'
    OR v_remote->>'code'
      IS DISTINCT FROM 'PROFILE_EXECUTION_REMOTE_RUNTIME_STATE_NOT_AUTHORIZED'
    OR (SELECT write_allowed FROM public.lf_router_action_registry
      WHERE asset_type='PERFIL' AND action_code='PROFILE_EXECUTION'
        AND status='ACTIVE' LIMIT 1) IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_READ_ONLY_PERMISSION_DRIFT'; END IF;

  -- Revalidate the two-object positive and third-object widening negative.
  v_double_req:=public.lf_router_intent_handoff_v2(
    'RW1-05_C3 double-object assurance probe: evaluate two profile subjects without widening scope.',
    jsonb_build_array(
      jsonb_build_object('asset_code','PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','asset_type','PERFIL'),
      jsonb_build_object('asset_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','asset_type','PERFIL')
    ),'CANONICAL_ASSET','[]'::jsonb,'{}'::jsonb
  );
  v_good_body:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',v_double_req->>'request_sha256','decision','RESOLVED',
    'positive_target_refs',jsonb_build_array(
      'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'),
    'excluded_target_refs','[]'::jsonb,
    'allowed_scope',jsonb_build_array(
      'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'),
    'forbidden_scope','[]'::jsonb,
    'conditions','[]'::jsonb,'material_ambiguities','[]'::jsonb,
    'clarification_question',null
  );
  v_good_result:=v_good_body||jsonb_build_object(
    'semantic_receipt_sha256',
    encode(extensions.digest(convert_to(v_good_body::text,'UTF8'),'sha256'),'hex')
  );
  v_good_validation:=public.lf_router_semantic_resume_validate_v1(v_double_req,v_good_result);
  v_bad_body:=jsonb_set(
    jsonb_set(v_good_body,'{positive_target_refs}',
      jsonb_build_array('PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
                        'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','PERFIL-UNDECLARED-DECOY')),
    '{allowed_scope}',jsonb_build_array('PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
                        'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','PERFIL-UNDECLARED-DECOY')
  );
  v_bad_result:=v_bad_body||jsonb_build_object(
    'semantic_receipt_sha256',
    encode(extensions.digest(convert_to(v_bad_body::text,'UTF8'),'sha256'),'hex')
  );
  v_bad_validation:=public.lf_router_semantic_resume_validate_v1(v_double_req,v_bad_result);
  IF v_double_req->>'request_sha256' IS DISTINCT FROM
       'ff0541fbba32f65d29bb52b4fd7235c201dfd79c6b6c3c444d1d1ebfe4e5bd97'
    OR v_good_validation->>'status' IS DISTINCT FROM 'VALID'
    OR v_good_validation->>'next_action'
       IS DISTINCT FROM 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
    OR v_bad_validation->>'status' IS DISTINCT FROM 'BLOCKED'
    OR v_bad_validation->>'router_resume_allowed' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_DOUBLE_OBJECT_VALIDATOR_DRIFT'; END IF;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    v_plan,v_unit,v_cp,v_spec);
  IF v_spec->>'status' IS DISTINCT FROM 'READY'
    OR v_spec->>'precision' IS DISTINCT FROM 'EXACT_RW105_C3_FULL_GPT_NATIVE_BLIND_REVIEW_V1'
    OR v_contract->>'status' IS DISTINCT FROM 'READY'
    OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_ASSERTION_CONTRACT_NOT_READY'; END IF;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);

  -- Exact-main runner receipt was inspected before authoring:
  -- run 39701466501 / job 119571440311 / main 2e643260...:
  -- RW105_C3_CAPTURE_PASS and RW105_C3_NEGATIVE_SELFTEST_PASS.
  v_capture:=jsonb_build_object(
    'schema','RW105_C3_GPT_NATIVE_CAPTURE_LEDGER_V1',
    'subject_ref',v_plan||'/'||v_unit||'/'||v_cp,
    'packet_git_blob',v_packet_blob,'capture_git_blob',v_capture_blob,
    'validator_git_blob',v_validator_blob,'workflow_git_blob',v_workflow_blob,
    'normalized_output_sha256',v_output_sha,
    'capture_method','USER_PROVIDED_DIRECT_COPY_FROM_SEPARATE_GPT_NATIVE_CHAT',
    'evidence_tier','FULL_GPT_NATIVE_BLIND_REVIEW',
    'owner_provided_capture',true,'separate_chat_required',true,
    'separate_chat_reference_verified',false,'isolation_provable',false,
    'provider_attested',false,'real_execution_receipt',false,
    'independent_review',false,'runtime_activation',false,'production_activation',false,
    'real_item_pass',true,'decoy_item_fail',true,
    'real_checks_passed',5,'decoy_checks_failed',5,
    'runner_run_id',v_run,'runner_job_id',v_job,'runner_main_sha',v_main_sha,
    'positive_validator_status','RW105_C3_CAPTURE_PASS',
    'negative_validator_status','RW105_C3_NEGATIVE_SELFTEST_PASS'
  );
  v_new:=jsonb_set(v_old,'{gpt_native_captures_v1}',
    coalesce(v_old->'gpt_native_captures_v1','{}'::jsonb)
       ||jsonb_build_object(v_cp,v_capture),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW105_C3_CLOSE_METADATA_CAS_FAILED'; END IF;

  v_obs:=jsonb_build_object(
    'capture_verified',true,'evidence_tier','FULL_GPT_NATIVE_BLIND_REVIEW',
    'packet_git_blob',v_packet_blob,'validator_git_blob',v_validator_blob,
    'real_item_pass',true,'decoy_item_fail',true,
    'real_checks_passed',5,'decoy_checks_failed',5,
    'no_bypass_verified',true,'double_object_verified',true,
    'question_discipline_verified',true,'train_lifecycle_verified',true,
    'read_only_permissions_verified',true,
    'multi_object_good_valid',true,'multi_object_widening_blocked',true,
    'handoff_event_verified',true,'owner_decision_recorded',true,
    'owner_provided_capture',true,'separate_chat_required',true,
    'separate_chat_reference_verified',false,'isolation_provable',false,
    'provider_attested',false,'real_execution_receipt',false,
    'independent_review',false,'runtime_activation',false,
    'production_activation',false,
    'real_python_runner_receipt',true,'source_snapshot_verified',true,
    'material_source_currentness_verified',true,
    'capture_git_blob',v_capture_blob,
    'normalized_output_sha256',v_output_sha,
    'github_run_id',v_run,'github_job_id',v_job,'resolved_main_sha',v_main_sha
  );
  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_OBSERVED_NOT_MATCHING_CONTRACT'; END IF;

  -- Negative assertion must reject a falsified real-item outcome, no residue.
  BEGIN
    v_negative:=jsonb_build_object(
      'status','PASS','evidence_ref',v_evidence,
      'observed',jsonb_set(v_obs,'{real_checks_passed}','4'::jsonb,true));
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_negative,v_actor||'_NEGATIVE');
    RAISE EXCEPTION 'RW105_C3_CLOSE_FORGED_4_OF_5_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
    THEN RAISE EXCEPTION 'RW105_C3_CLOSE_NEGATIVE_UNEXPECTED:%',v_err; END IF;
  END;
  IF EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_cp
        AND assertion_receipt_sha256 IS NOT NULL)
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_NEGATIVE_LEFT_RESIDUE'; END IF;

  -- Positive rehearsal with guaranteed rollback, then authoritative apply.
  FOR v_trial IN 1..2 LOOP
    BEGIN
      v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
      IF v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
        OR v_bootstrap->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
      THEN RAISE EXCEPTION 'RW105_C3_CLOSE_NOT_CURRENT_BEFORE_TRIAL'; END IF;

      v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
        v_plan,v_unit,v_cp,
        jsonb_build_object('status','PASS','test_code',
          'ENG_RW105_C3_FULL_GPT_NATIVE_BLIND_CAPTURE',
          'evidence_ref',v_evidence,'observed',v_obs),
        v_actor
      );
      IF v_receipt->>'passed' IS DISTINCT FROM 'true'
        OR v_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
        OR coalesce(v_receipt->>'assertion_receipt_sha256','') !~ '^[0-9a-f]{64}$'
      THEN RAISE EXCEPTION 'RW105_C3_CLOSE_ASSERTION_RECEIPT_INVALID'; END IF;

      v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
        v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
        'RW1-05_C3: owner-provided blind review A PASS 5/5, B FAIL 5/5; exact-main validator and negative self-test PASS; material source and Train C2 readback verified. NOT provider-attested, NOT cryptographically independent, no T3/cutover/production.'
      );
      IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
      THEN RAISE EXCEPTION 'RW105_C3_CLOSE_TRANSITION_NOT_APPLIED'; END IF;

      IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
           WHERE work_item_id=v_work AND status='DONE')<>3
        OR NOT EXISTS (
          SELECT 1 FROM programacion.engineering_work_checkpoints
           WHERE work_item_id=v_work AND checkpoint_code=v_cp
             AND status='DONE' AND evidence_ref=v_evidence
             AND completed_at IS NOT NULL
             AND assertion_contract_sha256=v_contract_sha
             AND assertion_receipt_sha256=v_receipt->>'assertion_receipt_sha256'
             AND assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(assertion_receipt)
        )
        OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
            IS DISTINCT FROM 'DONE'
      THEN RAISE EXCEPTION 'RW105_C3_CLOSE_TRIAL_READBACK_FAILED'; END IF;

      IF v_trial=1 THEN
        RAISE EXCEPTION 'RW105_C3_CLOSE_POSITIVE_ROLLBACK_SENTINEL'
          USING ERRCODE='PZ089';
      END IF;
    EXCEPTION WHEN SQLSTATE 'PZ089' THEN
      IF v_trial<>1 THEN
        RAISE EXCEPTION 'RW105_C3_CLOSE_UNEXPECTED_ROLLBACK_SENTINEL'; END IF;
    END;
    IF v_trial=1 THEN
      IF (SELECT status FROM programacion.engineering_work_checkpoints
           WHERE work_item_id=v_work AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
        OR EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
           WHERE work_item_id=v_work AND checkpoint_code=v_cp
             AND assertion_receipt_sha256 IS NOT NULL)
      THEN RAISE EXCEPTION 'RW105_C3_CLOSE_ROLLBACK_LEFT_RESIDUE'; END IF;
    END IF;
  END LOOP;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
       IS DISTINCT FROM 'DONE'
  THEN RAISE EXCEPTION 'RW105_C3_CLOSE_FINAL_WORK_ITEM_NOT_DONE'; END IF;
END
$rw105_c3_close$;
COMMIT;
