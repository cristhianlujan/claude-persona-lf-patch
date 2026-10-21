-- RW1-05_C3 explicit full-assurance contract + blind handoff.
-- C3 remains PENDING. No Router/runtime/profile/ACL/production mutation.
BEGIN;

DO $rw105_c3_contract$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C3';
  v_wi constant bigint := 1131;
  v_prior_md5 constant text := 'e1369366fdbdc03384be5654cbe6eb32';

  v_packet_path constant text := 'docs/programming-agent/router_wave/RW1_05_C3_BLIND_REVIEW_PACKET_V1.json';
  v_packet_blob constant text := 'ea7de94aa6f8395cf79595f2a571aa98b9347590';
  v_handoff_path constant text := 'docs/programming-agent/router_wave/RW1_05_C3_BLIND_REVIEW_HANDOFF_V1.md';
  v_handoff_blob constant text := 'b9fa8996b63563198fc49837204dfcf03ee97b8e';
  v_validator_path constant text := 'sandbox/lf_contract_gate_test/router_wave/validate_rw105_c3_capture_v1.py';
  v_validator_blob constant text := '1dbc24660c164d2edaf308f855a3a560ad8cee8f';
  v_capture_path constant text := 'docs/programming-agent/router_wave/RW1_05_C3_REVIEW_CAPTURE_V1.json';
  v_wave_blob constant text := '4bb64d568c3f005cf454fb223b4a5ed699c34504';
  v_decision_blob constant text := '9d80848dca36c94ba901028a4c27a1c58e425cb4';
  v_c1_blob constant text := '6494b7b5d40649e629b9c60ec7e751e308e49876';
  v_workflow_blob constant text := 'dd1383c5862789635c6694861b79e6492b7d5521';
  v_c2_receipt constant text := '1c52dfda25a901715395d32740a3947d663929b92b9d7f26b0680c15c8d568a5';
  v_terminal_sha constant text := 'sha256:caa55730e62d8c921b1e0f7032b55e382b11d22a3ed7bf77ed150434e89d762d';
  v_source_snapshot constant text := '8dfe7e833dd09a0a04b253d1b4e533f7be68949c';

  v_exec constant text := 'LF_ROUTER_RW105_C3_GPT_HANDOFF_V1|RW1-05_C3';

  v_old jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_source jsonb;
  v_manifest jsonb;
  v_key jsonb;
  v_terminal jsonb;
  v_shadow jsonb;
  v_train jsonb;
  v_native jsonb;
  v_remote jsonb;

  v_double_req jsonb;
  v_good_body jsonb;
  v_good_result jsonb;
  v_good_validation jsonb;
  v_bad_body jsonb;
  v_bad_result jsonb;
  v_bad_validation jsonb;

  v_event_id bigint;
  v_payload jsonb;
  v_bootstrap jsonb;
  v_compiled_spec jsonb;
  v_assertion jsonb;

  v_instructions text :=
    'Open ONLY the exact packet '||
    'docs/programming-agent/router_wave/RW1_05_C3_BLIND_REVIEW_PACKET_V1.json'||
    ' at git blob ea7de94aa6f8395cf79595f2a571aa98b9347590 in a NEW GPT Native chat separate from the producer context. '||
    'Evaluate both blind items against the five checks and synthetic prompts. Return ONLY the JSON required by output_contract. '||
    'Do not inspect answer keys, producer conversation or validator before emitting the JSON. '||
    'Do not claim provider attestation, production activation or cryptographically proven independence.';
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
        AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5)<>1
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_PRESTATE_DRIFT';
  END IF;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_wi)
       IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-05_C1') IS DISTINCT FROM 'DONE'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-05_C2') IS DISTINCT FROM 'DONE'
     OR (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-05_C2') IS DISTINCT FROM v_c2_receipt
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_LIFECYCLE_DRIFT';
  END IF;

  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
  FOR UPDATE;

  IF v_old#>'{action_specs_v1,RW1-05_C3}' IS NOT NULL
     OR v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C3}' IS NOT NULL
     OR v_old#>'{gpt_native_packets_v1,RW1-05_C3}' IS NOT NULL
     OR v_old#>'{gpt_native_c3_keys_v1,RW1-05_C3}' IS NOT NULL
     OR v_old#>'{gpt_native_captures_v1,RW1-05_C3}' IS NOT NULL
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_ALREADY_BOUND';
  END IF;

  -- Current E2E terminal authority.
  SELECT public.lf_profile_execution_terminal_authority_receipt_v1(
    'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001'
  ) INTO STRICT v_terminal;

  IF v_terminal->>'status' IS DISTINCT FROM 'READY'
     OR v_terminal->>'terminal_authority_receipt_sha256' IS DISTINCT FROM v_terminal_sha
     OR v_terminal#>>'{terminal_authority_receipt,router_authority_receipt,status}' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_terminal#>>'{terminal_authority_receipt,router_authority_receipt,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_terminal#>>'{terminal_authority_receipt,authority_rule}' IS DISTINCT FROM
        'ROUTER_AND_OPERATION_EVIDENCE_ONLY_NO_SPECIALIST_EFFECT_AUTHORITY'
     OR v_terminal#>>'{terminal_authority_receipt,canonical_judge_readback,required_steps}' IS DISTINCT FROM '11'
     OR v_terminal#>>'{terminal_authority_receipt,canonical_judge_readback,required_steps_pass}' IS DISTINCT FROM '11'
     OR v_terminal#>>'{terminal_authority_receipt,canonical_judge_readback,judge_result}' IS DISTINCT FROM 'PASS'
     OR v_terminal#>>'{terminal_authority_receipt,report_output_receipt,no_write_performed}' IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_TERMINAL_DRIFT';
  END IF;

  -- Real semantic shadow + question discipline.
  SELECT payload INTO STRICT v_shadow
  FROM public.lf_eventos WHERE id=21414;

  IF v_shadow#>>'{resume_validator_readback,resume_validator_code}' IS DISTINCT FROM 'VALID'
     OR coalesce((v_shadow#>>'{resume_validator_readback,resume_allowed}')::boolean,false) IS NOT TRUE
     OR v_shadow#>>'{resume_validator_readback,next_action}' IS DISTINCT FROM 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
     OR v_shadow#>>'{resume_route_summary,status}' IS DISTINCT FROM 'ROUTER_REDERIVED'
     OR v_shadow#>>'{resume_route_summary,router_status}' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_shadow#>>'{semantic_result,clarification_question}' IS NOT NULL
     OR jsonb_array_length(coalesce(v_shadow#>'{semantic_result,material_ambiguities}','[]'::jsonb))<>0
     OR v_old#>>'{action_specs_v1,RW1-05_C2,assertion_contract,pass_when,caller_interaction_max_one_question}'
          IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_SEMANTIC_OR_QUESTION_DRIFT';
  END IF;

  -- Train reserve/apply/close/readback.
  SELECT payload INTO STRICT v_train
  FROM public.lf_eventos
  WHERE evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
    AND payload#>>'{receipt,pr}'='3052'
    AND payload#>>'{receipt,terminal_status}'='COMPLETED'
  ORDER BY id DESC LIMIT 1;

  IF v_train#>>'{receipt,write_ahead,reserved_at}' IS NULL
     OR v_train#>>'{receipt,effect,phase}' IS DISTINCT FROM 'SUCCEEDED'
     OR v_train#>>'{receipt,parity,migration_source_parity}' IS DISTINCT FROM 'PASS'
     OR v_train#>>'{receipt,ledger_readback,matches_target}' IS DISTINCT FROM 'true'
     OR v_train#>>'{receipt,merge,in_main}' IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_TRAIN_DRIFT';
  END IF;

  -- Executor-specific read-only permissions.
  v_native:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','GPT_NATIVE'
  );
  v_remote:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','REMOTE_API'
  );

  IF v_native->>'admitted' IS DISTINCT FROM 'true'
     OR v_native->>'remote_runtime_required' IS DISTINCT FROM 'false'
     OR v_remote->>'admitted' IS DISTINCT FROM 'false'
     OR v_remote->>'code' IS DISTINCT FROM 'PROFILE_EXECUTION_REMOTE_RUNTIME_STATE_NOT_AUTHORIZED'
     OR (SELECT write_allowed FROM public.lf_router_action_registry
         WHERE asset_type='PERFIL' AND action_code='PROFILE_EXECUTION' AND status='ACTIVE'
         LIMIT 1) IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_PERMISSION_DRIFT';
  END IF;

  -- Material double-object positive + widening negative on the current validator.
  v_double_req:=public.lf_router_intent_handoff_v2(
    'RW1-05_C3 double-object assurance probe: evaluate two profile subjects without widening scope.',
    jsonb_build_array(
      jsonb_build_object('asset_code','PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','asset_type','PERFIL'),
      jsonb_build_object('asset_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','asset_type','PERFIL')
    ),
    'CANONICAL_ASSET','[]'::jsonb,'{}'::jsonb
  );

  v_good_body:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',v_double_req->>'request_sha256',
    'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array(
      'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
      'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    ),
    'excluded_target_refs','[]'::jsonb,
    'allowed_scope',jsonb_build_array(
      'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
      'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    ),
    'forbidden_scope','[]'::jsonb,
    'conditions','[]'::jsonb,
    'material_ambiguities','[]'::jsonb,
    'clarification_question',null
  );
  v_good_result:=v_good_body||jsonb_build_object(
    'semantic_receipt_sha256',
    encode(extensions.digest(convert_to(v_good_body::text,'UTF8'),'sha256'),'hex')
  );
  v_good_validation:=public.lf_router_semantic_resume_validate_v1(v_double_req,v_good_result);

  v_bad_body:=jsonb_set(
    jsonb_set(
      v_good_body,
      '{positive_target_refs}',
      jsonb_build_array(
        'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
        'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
        'PERFIL-UNDECLARED-DECOY'
      ),
      false
    ),
    '{allowed_scope}',
    jsonb_build_array(
      'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
      'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'PERFIL-UNDECLARED-DECOY'
    ),
    false
  );
  v_bad_result:=v_bad_body||jsonb_build_object(
    'semantic_receipt_sha256',
    encode(extensions.digest(convert_to(v_bad_body::text,'UTF8'),'sha256'),'hex')
  );
  v_bad_validation:=public.lf_router_semantic_resume_validate_v1(v_double_req,v_bad_result);

  IF v_double_req->>'request_sha256' IS DISTINCT FROM
       'ff0541fbba32f65d29bb52b4fd7235c201dfd79c6b6c3c444d1d1ebfe4e5bd97'
     OR v_good_validation->>'status' IS DISTINCT FROM 'VALID'
     OR v_good_validation->>'next_action' IS DISTINCT FROM 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
     OR coalesce((v_good_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE
     OR v_bad_validation->>'status' IS DISTINCT FROM 'BLOCKED'
     OR coalesce((v_bad_validation->>'router_resume_allowed')::boolean,true) IS NOT FALSE
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_DOUBLE_OBJECT_DRIFT good=% bad=%',
      v_good_validation::text,v_bad_validation::text;
  END IF;

  v_manifest:=jsonb_build_object(
    'schema','RW105_C3_GPT_NATIVE_HANDOFF_MANIFEST_V1',
    'subject_ref',v_plan||'/'||v_unit||'/'||v_cp,
    'packet_path',v_packet_path,
    'packet_git_blob',v_packet_blob,
    'handoff_path',v_handoff_path,
    'handoff_git_blob',v_handoff_blob,
    'validator_path',v_validator_path,
    'validator_git_blob',v_validator_blob,
    'source_snapshot_commit',v_source_snapshot,
    'c2_assertion_receipt_sha256',v_c2_receipt,
    'owner_decision_ref','docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md',
    'owner_decision_git_blob',v_decision_blob,
    'evidence_tier','FULL_GPT_NATIVE_BLIND_REVIEW',
    'limits',jsonb_build_object(
      'provider_attested',false,
      'real_execution_receipt',false,
      'independent_review',false,
      'runtime_activation',false,
      'production_activation',false
    ),
    'separate_chat_required',true,
    'acceptance_declared',false
  );

  v_key:=jsonb_build_object(
    'schema','RW105_C3_BLIND_KEY_V1',
    'packet_git_blob',v_packet_blob,
    'real_item_id','ITEM_A',
    'decoy_item_id','ITEM_B',
    'required_checks',jsonb_build_array(
      'NO_BYPASS_AUTHORITY',
      'DOUBLE_OBJECT_SCOPE',
      'QUESTION_DISCIPLINE',
      'TRAIN_LIFECYCLE',
      'READ_ONLY_PERMISSIONS'
    ),
    'reviewer_requirement','SEPARATE_GPT_NATIVE_CHAT',
    'producer_context','RW1-05_C1_C2_AND_C3_CONTRACT_AUTHORING_CURRENT_PROJECT_CHAT',
    'isolation_provable',false
  );

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload
  ) VALUES(
    'HANDOFF_DEEP_CONTEXT',
    'PROGRAM_PLAN',
    v_plan||'.'||v_cp||'.GPT_NATIVE_HANDOFF',
    'Hash-bound full-tier RW1-05_C3 packet handed to a separate GPT Native chat; no acceptance declared.',
    'INFO',
    'DERIVE_FROM_EXECUTION_ID',
    v_exec,
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id',v_exec,
      'producer','LF_ROUTER_RW105_C3_GPT_HANDOFF_V1',
      'purpose','Full-tier independent critique of RW1-05 E2E evidence: no-bypass, double-object, question discipline, Train lifecycle and read-only permissions.',
      'occurred_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"+00:00"'),
      'acceptance_declared',false,
      'subject_ref',v_manifest->>'subject_ref',
      'checkpoint',v_cp,
      'work_item_id',v_wi,
      'packet_path',v_packet_path,
      'packet_git_blob',v_packet_blob,
      'handoff_path',v_handoff_path,
      'handoff_git_blob',v_handoff_blob,
      'validator_path',v_validator_path,
      'validator_git_blob',v_validator_blob,
      'evidence_tier','FULL_GPT_NATIVE_BLIND_REVIEW',
      'provider_attested',false,
      'real_execution_receipt',false,
      'independent_review',false,
      'separate_chat_required',true,
      'instructions_for_gpt',v_instructions,
      'return_instructions','Reply in the NEW chat with ONLY the JSON object, unedited.',
      'limits_note','This handoff is not acceptance and does not close RW1-05_C3.'
    )
  )
  RETURNING id,payload INTO v_event_id,v_payload;

  IF v_payload->>'packet_git_blob' IS DISTINCT FROM v_packet_blob
     OR v_payload->>'acceptance_declared' IS DISTINCT FROM 'false'
     OR v_payload->>'instructions_for_gpt' IS DISTINCT FROM v_instructions
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_HANDOFF_READBACK_FAILED';
  END IF;

  v_spec:=jsonb_build_object(
    'status','READY',
    'schema_version','ENGINEERING_ACTION_SPEC_V3',
    'checkpoint_code',v_cp,
    'contract_source','EXPLICIT_ACTION_SPEC',
    'contract_family','INDEPENDENT_ADVERSARIAL_REVIEW',
    'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING',
    'recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
    'precision','EXACT_RW105_C3_FULL_GPT_NATIVE_BLIND_REVIEW_V1',
    'requires_material_execution',true,
    'mutation_policy','TEST_ARTIFACT_ONLY',
    'expected','A separate GPT Native blind reviewer must PASS the real RW1-05 E2E item and FAIL the decoy across no-bypass, double-object scope, question discipline, Merge Train lifecycle and read-only permissions; deterministic validator and negative self-test must pass before C3 closure.',
    'forbidden',jsonb_build_array(
      'SAME_PRODUCER_REVIEW',
      'OPEN_ANSWER_KEY_BEFORE_CAPTURE',
      'USE_PRODUCER_CHAT_MEMORY',
      'BYPASS_ACT0001',
      'ACCEPT_SCOPE_WIDENING',
      'PASS_REDUNDANT_CLARIFICATION',
      'DIRECT_DB_MUTATION_OUTSIDE_TRAIN',
      'READ_ONLY_IMPLIES_WRITE_AUTHORITY',
      'REMOTE_API_INHERITS_NATIVE_ADMISSION',
      'CLAIM_PROVIDER_ATTESTATION',
      'CLAIM_REAL_EXECUTION_RECEIPT_FOR_C3_REVIEW',
      'CLAIM_INDEPENDENT_REVIEW',
      'CLAIM_PROVABLE_ISOLATION',
      'CLAIM_RUNTIME_ACTIVATION',
      'CLAIM_PRODUCTION_ACTIVATION',
      'CLOSE_WITH_REAL_ITEM_FAIL',
      'CLOSE_WITH_DECOY_PASS',
      'REOPEN_C1_OR_C2',
      'CREATE_UNDECLARED_SHARED_ABSTRACTION'
    ),
    'action_steps',jsonb_build_array(
      'FREEZE_EXACT_PACKET_AND_SOURCE_BINDINGS',
      'START_MATERIALLY_SEPARATE_GPT_NATIVE_CHAT',
      'HIDE_KEY_VALIDATOR_AND_PRODUCER_CONTEXT',
      'REVIEW_BOTH_BLIND_ITEMS',
      'EVALUATE_FIVE_FULL_TIER_CHECKS',
      'EXERCISE_SYNTHETIC_PROMPTS',
      'FREEZE_REVIEW_CAPTURE',
      'RUN_DETERMINISTIC_CAPTURE_VALIDATOR',
      'RUN_NEGATIVE_SELFTEST',
      'REVALIDATE_CURRENT_MATERIAL_SOURCES',
      'PERSIST_ASSERTION_RECEIPT_ONLY_FROM_VALID_CAPTURE',
      'PERSIST_C3_DONE_ONLY_AFTER_ASSERTION_AND_READBACK'
    ),
    'target',jsonb_build_object(
      'checkpoint',v_cp,
      'declared_assets',jsonb_build_array(
        'ACT-0001',
        'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
        'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      ),
      'declared_events',jsonb_build_array(21414,21451,v_event_id),
      'declared_objects',jsonb_build_array(
        'public.lf_router_semantic_resume_validate_v1',
        'public.lf_profile_execution_terminal_authority_receipt_v1',
        'public.lf_profile_execution_executor_admission_v1',
        'public.lf_router_action_registry',
        'public.lf_operation_execution',
        'public.lf_operation_execution_steps',
        'public.v_lf_operation_execution_judge',
        'public.lf_eventos',
        'programacion.engineering_plan_units',
        'programacion.engineering_work_checkpoints'
      ),
      'declared_artifacts',jsonb_build_array(
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_packet_path,'role','EVIDENCE','purpose','BLIND_PACKET','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_handoff_path,'role','EVIDENCE','purpose','BLIND_HANDOFF','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_validator_path,'role','EVIDENCE','purpose','CAPTURE_VALIDATOR','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml','role','EVIDENCE','purpose','DETERMINISTIC_VALIDATOR_RUNNER','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md','role','EVIDENCE','purpose','NORMATIVE_RW105_C3_CRITERION','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md','role','EVIDENCE','purpose','OWNER_FULL_TIER_DECISION','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_capture_path,'role','MUTATION_TARGET','purpose','BLIND_REVIEW_CAPTURE','target_kind','EXACT_FILE')
      ),
      'evidence_artifacts',jsonb_build_array(
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_packet_path,'role','EVIDENCE','purpose','BLIND_PACKET','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_handoff_path,'role','EVIDENCE','purpose','BLIND_HANDOFF','target_kind','EXACT_EXISTING_FILE'),
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_validator_path,'role','EVIDENCE','purpose','CAPTURE_VALIDATOR','target_kind','EXACT_EXISTING_FILE')
      ),
      'mutation_artifacts',jsonb_build_array(
        jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_capture_path,'role','MUTATION_TARGET','purpose','BLIND_REVIEW_CAPTURE','target_kind','EXACT_FILE')
      )
    ),
    'evidence_ref','github://cristhianlujan/claude-persona-lf-patch/'||v_capture_path,
    'assertion_contract',jsonb_build_object(
      'mode','EXPLICIT_PASS_WHEN_SUBSET',
      'pass_when',jsonb_build_object(
        'capture_verified',true,
        'evidence_tier','FULL_GPT_NATIVE_BLIND_REVIEW',
        'packet_git_blob',v_packet_blob,
        'validator_git_blob',v_validator_blob,
        'real_item_pass',true,
        'decoy_item_fail',true,
        'real_checks_passed',5,
        'decoy_checks_failed',5,
        'no_bypass_verified',true,
        'double_object_verified',true,
        'question_discipline_verified',true,
        'train_lifecycle_verified',true,
        'read_only_permissions_verified',true,
        'multi_object_good_valid',true,
        'multi_object_widening_blocked',true,
        'handoff_event_verified',true,
        'owner_decision_recorded',true,
        'owner_provided_capture',true,
        'separate_chat_required',true,
        'separate_chat_reference_verified',false,
        'isolation_provable',false,
        'provider_attested',false,
        'real_execution_receipt',false,
        'independent_review',false,
        'runtime_activation',false,
        'production_activation',false,
        'real_python_runner_receipt',true,
        'source_snapshot_verified',true,
        'material_source_currentness_verified',true
      )
    ),
    'test_execution_contract',jsonb_build_object(
      'mode','AUTHORED_NEGATIVE',
      'test_code','ENG_RW105_C3_FULL_GPT_NATIVE_BLIND_CAPTURE',
      'test_path','cristhianlujan/claude-persona-lf-patch:'||v_validator_path,
      'synthetic_pass','FORBIDDEN',
      'negative_required',true,
      'authoring_required',true,
      'semantic_authority','SEPARATE_GPT_NATIVE_BLIND_REVIEW',
      'separate_chat_required',true,
      'fallback_case_discovery','FORBIDDEN',
      'execution_route',jsonb_build_object(
        'provider','GITHUB_ACTIONS',
        'workflow_path','.github/workflows/lf-router-level2-advisory-tests.yml',
        'job_name','router-level2-advisory-contract',
        'check_name','router-level2-advisory-contract',
        'role','DETERMINISTIC_CAPTURE_VALIDATOR_ONLY'
      ),
      'canonical_exit_criterion','Separate GPT Native review distinguishes the real RW1-05 E2E evidence from a decoy across all five full-tier checks; validator and negative self-test pass; no authority, runtime or production claim is widened.',
      'checkpoint_title_context','RW1-05_C3'
    ),
    'verification_queries',jsonb_build_array(
      'SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1131 ORDER BY sequence_no',
      'SELECT public.lf_profile_execution_terminal_authority_receipt_v1(''EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001'')',
      'SELECT payload FROM public.lf_eventos WHERE id IN (21414,21451)',
      'SELECT public.lf_profile_execution_executor_admission_v1(''PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'',''GPT_NATIVE''),public.lf_profile_execution_executor_admission_v1(''PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'',''REMOTE_API'')'
    )
  );

  v_source:=jsonb_build_object(
    'inputs',jsonb_build_object(
      'assets',jsonb_build_array(
        'ACT-0001',
        'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
        'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      ),
      'events',jsonb_build_array(21414,21451,v_event_id),
      'queries',v_spec->'verification_queries',
      'artifacts',jsonb_build_array(
        v_packet_path,
        v_handoff_path,
        v_validator_path,
        '.github/workflows/lf-router-level2-advisory-tests.yml',
        'docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md',
        'docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md',
        'docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md',
        'docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_INDEPENDENT_SEMANTIC_JUDGE_20261021_V2.json'
      ),
      'db_objects',v_spec#>'{target,declared_objects}'
    ),
    'missing','[]'::jsonb,
    'missing_typed','[]'::jsonb,
    'expected_result','Full-tier blind C3 assurance: real item PASS 5/5, decoy FAIL 5/5, current double-object positive/negative behavior preserved, no redundant question, Train lifecycle complete and read-only permissions fail-closed.',
    'evidence_ref','github://cristhianlujan/claude-persona-lf-patch/'||v_packet_path||'#blob:'||v_packet_blob,
    'source_snapshot_commit',v_source_snapshot,
    'verification_boundary','RW105_C3_FULL_E2E_ASSURANCE_ONLY_NO_T3_CUTOVER_OR_PRODUCTION_ACTIVATION',
    'source_git_blobs',jsonb_build_object(
      'packet',v_packet_blob,
      'handoff',v_handoff_blob,
      'validator',v_validator_blob,
      'wave',v_wave_blob,
      'decision',v_decision_blob,
      'c1_baseline',v_c1_blob,
      'workflow',v_workflow_blob
    ),
    'live_receipts',jsonb_build_object(
      'c2_checkpoint_assertion_receipt_sha256',v_c2_receipt,
      'terminal_authority_receipt_sha256',v_terminal_sha,
      'semantic_shadow_event_id',21414,
      'train_event_id',21451,
      'double_object_request_sha256',v_double_req->>'request_sha256',
      'double_object_good_status',v_good_validation->>'status',
      'double_object_widening_status',v_bad_validation->>'status',
      'native_admission_code',v_native->>'code',
      'remote_admission_code',v_remote->>'code'
    )
  );

  v_new:=v_old;
  v_new:=jsonb_set(
    v_new,'{action_specs_v1}',
    coalesce(v_new->'action_specs_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_spec),
    true
  );
  v_new:=jsonb_set(
    v_new,'{source_pack_v2}',
    coalesce(v_new->'source_pack_v2','{}'::jsonb)||
      jsonb_build_object(
        'checkpoint_inputs',
        coalesce(v_new#>'{source_pack_v2,checkpoint_inputs}','{}'::jsonb)||
          jsonb_build_object(v_cp,v_source)
      ),
    true
  );
  v_new:=jsonb_set(
    v_new,'{gpt_native_packets_v1}',
    coalesce(v_new->'gpt_native_packets_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_manifest),
    true
  );
  v_new:=jsonb_set(
    v_new,'{gpt_native_c3_keys_v1}',
    coalesce(v_new->'gpt_native_c3_keys_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_key),
    true
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
     AND disposition='ASSIGNED'
     AND md5(unit_metadata::text)=v_prior_md5;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_METADATA_CAS_FAILED';
  END IF;

  v_compiled_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_assertion:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    v_plan,v_unit,v_cp,v_compiled_spec
  );
  v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);

  IF v_compiled_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_compiled_spec->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_compiled_spec->>'precision' IS DISTINCT FROM 'EXACT_RW105_C3_FULL_GPT_NATIVE_BLIND_REVIEW_V1'
     OR v_assertion->>'status' IS DISTINCT FROM 'READY'
     OR v_assertion->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
     OR v_bootstrap#>>'{current_checkpoint,status}' IS DISTINCT FROM 'PENDING'
     OR v_bootstrap#>>'{action_spec,status}' IS DISTINCT FROM 'READY'
     OR v_bootstrap->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
     OR v_bootstrap#>>'{execution_readiness,status}' IS DISTINCT FROM 'READY'
     OR coalesce((v_bootstrap#>>'{execution_readiness,execution_ready}')::boolean,false) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_BOOTSTRAP_NOT_READY spec=% assertion=% bootstrap=%',
      v_compiled_spec::text,v_assertion::text,v_bootstrap::text;
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C3_CONTRACT_PREMATURE_CHECKPOINT_CHANGE';
  END IF;
END
$rw105_c3_contract$;

COMMIT;
