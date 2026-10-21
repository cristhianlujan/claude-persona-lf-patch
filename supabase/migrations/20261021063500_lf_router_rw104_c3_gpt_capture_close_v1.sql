-- RW1-04_C3: admit owner-provided GPT Native blind-review capture and close checkpoint.
-- Evidence tier remains explicitly limited:
-- provider_attested=false, real_execution_receipt=false, independent_review=false,
-- separate_chat_reference_verified=false, isolation_provable=false.
-- No Router runtime, ACL, operation, Input Governance, Merge Train or production mutation.
BEGIN;
DO $rw104_c3_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-04';
  v_cp constant text := 'RW1-04_C3';
  v_wi constant bigint := 1130;
  v_prior_md5 constant text := '4cc757eddac1dd669df952990c794910';
  v_actor constant text := 'LF_ROUTER_RW104_C3_TIER_ACCEPTANCE_20261021';
  v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
  v_main constant text := '8d74c01ec5c0c6fe265d1246c004a92623e7e0fd';
  v_run constant text := '39555142733';
  v_job constant text := '119073062698';
  v_packet_blob constant text := '7a5c0e9048ebd3029efe258ade9a352ddaacc7ee';
  v_capture_blob constant text := 'db235d865dd2e11869426c34a1e6db0baef1e618';
  v_validator_blob constant text := '2dddbdedb5fa8ce796de177715052440a8f59ccb';
  v_workflow_blob constant text := '173eb46b13fcf4d784fcafc83e684b6696dab3b1';
  v_decision_blob constant text := '9d80848dca36c94ba901028a4c27a1c58e425cb4';
  v_output_sha constant text := 'cc6682cafa121634e797b9465bff38c8f35c3f89a21ad13e0c774daeea1a3fd5';
  v_evidence constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_04_C3_REVIEW_CAPTURE_V1.json#blob:db235d865dd2e11869426c34a1e6db0baef1e618';

  v_spec jsonb := $spec$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-04_C3",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"BOUNDED_CHECKPOINT_TEST",
  "precision":"EXACT_RW104_C3_GPT_NATIVE_BLIND_REVIEW_CAPTURE_V1",
  "action_kind":"BOUNDED_CHECKPOINT_TEST_AUTHORING",
  "recipe_mode":"AUTHOR_AND_RUN_CHECKPOINT_TEST",
  "mutation_policy":"TEST_ARTIFACT_ONLY",
  "requires_material_execution":true,
  "expected":"Admit one owner-provided GPT Native blind review against the frozen RW1-04 packet: real item PASS 5/5, decoy item FAIL 5/5, with an exact-main deterministic validator receipt; preserve provider_attested=false, real_execution_receipt=false, independent_review=false, separate_chat_reference_verified=false and isolation_provable=false.",
  "target":{
    "checkpoint":"RW1-04_C3",
    "declared_assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "declared_events":[21368],
    "declared_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_eventos"
    ],
    "declared_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_04_C3_BLIND_REVIEW_PACKET_V1.json","role":"EVIDENCE","purpose":"BLIND_PACKET","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_04_C3_REVIEW_CAPTURE_V1.json","role":"EVIDENCE","purpose":"REVIEW_CAPTURE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw104_c3_capture_v1.py","role":"EVIDENCE","purpose":"CAPTURE_VALIDATOR","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"EVIDENCE","purpose":"EXACT_MAIN_RUNNER","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md","role":"EVIDENCE","purpose":"OWNER_TIER_DECISION","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "evidence_artifacts":[],
    "mutation_artifacts":[]
  },
  "forbidden":[
    "CLAIM_PROVIDER_ATTESTATION",
    "CLAIM_REAL_EXECUTION_RECEIPT",
    "CLAIM_INDEPENDENT_REVIEW",
    "CLAIM_PUBLIC_CHAT_REFERENCE_VERIFIED",
    "CLAIM_PROVABLE_ISOLATION",
    "CLAIM_ROUTER_RUNTIME_PASS",
    "CLAIM_E2E_PASS",
    "CLAIM_PRODUCTION_PASS",
    "CLOSE_WITH_REAL_ITEM_FAIL",
    "CLOSE_WITH_DECOY_PASS",
    "OPEN_RW1_05_FROM_THIS_CHECKPOINT"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "capture_verified":true,
      "real_item_pass":true,
      "decoy_item_fail":true,
      "real_checks_passed":5,
      "decoy_checks_failed":5,
      "packet_git_blob":"7a5c0e9048ebd3029efe258ade9a352ddaacc7ee",
      "capture_git_blob":"db235d865dd2e11869426c34a1e6db0baef1e618",
      "normalized_output_sha256":"cc6682cafa121634e797b9465bff38c8f35c3f89a21ad13e0c774daeea1a3fd5",
      "owner_provided_capture":true,
      "separate_chat_required":true,
      "separate_chat_reference_verified":false,
      "isolation_provable":false,
      "handoff_event_verified":true,
      "owner_decision_recorded":true,
      "evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT",
      "provider_attested":false,
      "real_execution_receipt":false,
      "independent_review":false,
      "real_python_runner_receipt":true,
      "source_sha_current":true,
      "runtime_activation":false,
      "production_activation":false
    }
  },
  "test_execution_contract":{
    "mode":"AUTHORED_NEGATIVE",
    "test_code":"ENG_RW104_C3_GPT_NATIVE_BLIND_CAPTURE",
    "test_path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw104_c3_capture_v1.py",
    "synthetic_pass":"FORBIDDEN",
    "negative_required":true,
    "authoring_required":false,
    "execution_route":{
      "provider":"GITHUB_ACTIONS",
      "workflow_path":".github/workflows/lf-router-level2-advisory-tests.yml",
      "job_name":"router-level2-advisory-contract",
      "check_name":"router-level2-advisory-contract"
    },
    "semantic_authority":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT",
    "fallback_case_discovery":"FORBIDDEN",
    "canonical_exit_criterion":"Blind review distinguishes the real implementation evidence from the seeded decoy across design/code alignment, authority, currentness/ACL, rollback/legacy and no-regression controls, without claiming provider attestation, independent assurance, public-share verification, E2E or production.",
    "checkpoint_title_context":"RW1-04_C3"
  },
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_04_C3_REVIEW_CAPTURE_V1.json#blob:db235d865dd2e11869426c34a1e6db0baef1e618"
}
$spec$::jsonb;

  v_source jsonb := $source$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21368],
    "queries":[
      "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1130 ORDER BY sequence_no",
      "SELECT payload->>'packet_git_blob' packet_git_blob,payload->>'separate_chat_required' separate_chat_required,payload->>'acceptance_declared' acceptance_declared FROM public.lf_eventos WHERE id=21368"
    ],
    "db_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_eventos"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_04_C3_BLIND_REVIEW_PACKET_V1.json",
      "docs/programming-agent/router_wave/RW1_04_C3_REVIEW_CAPTURE_V1.json",
      "sandbox/lf_contract_gate_test/router_wave/validate_rw104_c3_capture_v1.py",
      ".github/workflows/lf-router-level2-advisory-tests.yml",
      "docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Exact-main deterministic validation of the owner-provided GPT Native blind-review capture, with real PASS 5/5 and decoy FAIL 5/5 while preserving explicitly limited evidence claims.",
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_04_C3_REVIEW_CAPTURE_V1.json#blob:db235d865dd2e11869426c34a1e6db0baef1e618",
  "verification_boundary":"RW104_C3_IMPLEMENTATION_REVIEW_ONLY_NOT_RUNTIME_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"8d74c01ec5c0c6fe265d1246c004a92623e7e0fd",
  "source_git_blobs":{
    "packet":"7a5c0e9048ebd3029efe258ade9a352ddaacc7ee",
    "capture":"db235d865dd2e11869426c34a1e6db0baef1e618",
    "validator":"2dddbdedb5fa8ce796de177715052440a8f59ccb",
    "workflow":"173eb46b13fcf4d784fcafc83e684b6696dab3b1",
    "decision":"9d80848dca36c94ba901028a4c27a1c58e425cb4"
  },
  "runner_receipt":{
    "provider":"GITHUB_ACTIONS",
    "run_id":"39555142733",
    "job_id":"119073062698",
    "event":"push",
    "conclusion":"success",
    "specific_step":"Execute RW1-04 C3 blind review capture",
    "resolved_main_sha":"8d74c01ec5c0c6fe265d1246c004a92623e7e0fd"
  }
}
$source$::jsonb;

  v_capture jsonb := jsonb_build_object(
    'schema','RW104_C3_GPT_NATIVE_CAPTURE_LEDGER_V1',
    'subject_ref',v_plan||'/'||v_unit||'/'||v_cp,
    'packet_git_blob',v_packet_blob,
    'capture_git_blob',v_capture_blob,
    'normalized_output_sha256',v_output_sha,
    'capture_method','USER_PROVIDED_DIRECT_COPY_FROM_SEPARATE_GPT_NATIVE_CHAT',
    'owner_provided_capture',true,
    'separate_chat_required',true,
    'separate_chat_reference_verified',false,
    'isolation_provable',false,
    'evidence_tier',v_tier,
    'provider_attested',false,
    'real_execution_receipt',false,
    'independent_review',false,
    'runtime_activation',false,
    'production_activation',false,
    'real_item_pass',true,
    'decoy_item_fail',true,
    'real_checks_passed',5,
    'decoy_checks_failed',5,
    'runner_run_id',v_run,
    'runner_job_id',v_job,
    'runner_main_sha',v_main
  );

  v_old jsonb;
  v_new jsonb;
  v_compiled jsonb;
  v_contract jsonb;
  v_ready jsonb;
  v_obs jsonb;
  v_bad jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_negative_rejected boolean := false;
  v_count integer;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
    AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND work_code='ROUTER-W1-04' AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C1' AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C2' AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code=v_cp AND status='PENDING'
           AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW104_C3_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>>'{gpt_native_packets_v1,RW1-04_C3,packet_git_blob}' IS DISTINCT FROM v_packet_blob
     OR v_old#>>'{gpt_native_c3_keys_v1,RW1-04_C3,real_item_id}' IS DISTINCT FROM 'ITEM_A'
     OR v_old#>>'{gpt_native_c3_keys_v1,RW1-04_C3,decoy_item_id}' IS DISTINCT FROM 'ITEM_B'
     OR v_old#>'{gpt_native_captures_v1,RW1-04_C3}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW104_C3_PACKET_OR_CAPTURE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_eventos
      WHERE id=21368
        AND evento_tipo='HANDOFF_DEEP_CONTEXT'
        AND payload->>'packet_git_blob'=v_packet_blob
        AND payload->>'separate_chat_required'='true'
        AND payload->>'acceptance_declared'='false')<>1
  THEN RAISE EXCEPTION 'RW104_C3_HANDOFF_EVENT_DRIFT'; END IF;

  v_new:=v_old;
  v_new:=jsonb_set(v_new,'{action_specs_v1,RW1-04_C3}',v_spec,true);
  v_new:=jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-04_C3}',v_source,true);
  v_new:=jsonb_set(
    v_new,
    '{gpt_native_captures_v1}',
    coalesce(v_new->'gpt_native_captures_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_capture),
    true
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW104_C3_METADATA_UPDATE_COUNT:%',v_count; END IF;

  v_compiled:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_compiled);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);

  IF v_compiled->>'status' IS DISTINCT FROM 'READY'
     OR v_compiled->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
  THEN RAISE EXCEPTION 'RW104_C3_CONTRACT_NOT_READY: spec=% contract=% ready=%',
       v_compiled::text,v_contract::text,v_ready::text; END IF;

  v_obs:=jsonb_build_object(
    'capture_verified',true,
    'real_item_pass',true,
    'decoy_item_fail',true,
    'real_checks_passed',5,
    'decoy_checks_failed',5,
    'packet_git_blob',v_packet_blob,
    'capture_git_blob',v_capture_blob,
    'normalized_output_sha256',v_output_sha,
    'owner_provided_capture',true,
    'separate_chat_required',true,
    'separate_chat_reference_verified',false,
    'isolation_provable',false,
    'handoff_event_verified',true,
    'owner_decision_recorded',true,
    'evidence_tier',v_tier,
    'provider_attested',false,
    'real_execution_receipt',false,
    'independent_review',false,
    'real_python_runner_receipt',true,
    'source_sha_current',true,
    'github_run_id',v_run,
    'github_job_id',v_job,
    'resolved_main_sha',v_main,
    'runtime_activation',false,
    'production_activation',false
  );

  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW104_C3_RESULT_DOES_NOT_SATISFY_CONTRACT'; END IF;

  -- Negative admission control: a decoy marked as safe must fail the assertion contract.
  v_bad:=jsonb_set(v_obs,'{decoy_item_fail}','false'::jsonb,true);
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,
      jsonb_build_object('status','PASS','test_code','ENG_RW104_C3_GPT_NATIVE_BLIND_CAPTURE',
                         'evidence_ref',v_evidence,'observed',v_bad),
      v_actor||'_NEGATIVE'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%' THEN RAISE; END IF;
    v_negative_rejected:=true;
  END;
  IF NOT v_negative_rejected THEN RAISE EXCEPTION 'RW104_C3_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

  IF (SELECT assertion_receipt FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS NOT NULL
  THEN RAISE EXCEPTION 'RW104_C3_NEGATIVE_LEFT_RECEIPT'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,
    jsonb_build_object(
      'status','PASS',
      'test_code','ENG_RW104_C3_GPT_NATIVE_BLIND_CAPTURE',
      'evidence_ref',v_evidence,
      'observed',v_obs
    ),
    v_actor
  );

  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
  THEN RAISE EXCEPTION 'RW104_C3_ASSERTION_RECEIPT_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'RW1-04_C3 PASS under owner-approved GPT Native in-chat equivalent: frozen packet linked by blob; owner-provided separate-chat capture has real item PASS 5/5 and seeded decoy FAIL 5/5; exact-main deterministic validator receipt recorded. Evidence remains provider_attested=false, real_execution_receipt=false, independent_review=false, separate_chat_reference_verified=false and isolation_provable=false; no runtime/E2E/production claim.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW104_C3_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi
        AND ((checkpoint_code='RW1-04_C1' AND status='DONE')
          OR (checkpoint_code='RW1-04_C2' AND status='DONE')
          OR (checkpoint_code='RW1-04_C3' AND status='DONE'
              AND completed_at IS NOT NULL
              AND evidence_ref=v_evidence
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true')))<>3
  THEN RAISE EXCEPTION 'RW104_C3_POST_READBACK_NOT_CONSISTENT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND status='DONE')<>1
  THEN RAISE EXCEPTION 'RW104_C3_UNIT_NOT_CLOSED'; END IF;
END
$rw104_c3_close$;
COMMIT;
