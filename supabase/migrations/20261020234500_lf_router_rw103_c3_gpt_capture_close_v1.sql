-- RW1-03_C3: admit owner-approved GPT Native blind-review capture and close checkpoint.
-- Evidence tier remains explicitly unattested: provider_attested=false, real_execution_receipt=false, independent_review=false.
-- No Router runtime, ACL, operation, profile/adapter or production mutation.
BEGIN;
DO $rw103_c3_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-03';
  v_cp constant text := 'RW1-03_C3';
  v_wi constant bigint := 1129;
  v_prior_md5 constant text := '6f30d68ead10990a3f1e9357291a1c6e';
  v_actor constant text := 'LF_ROUTER_RW103_C3_TIER_ACCEPTANCE_20261020';
  v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
  v_main constant text := 'f26bb2c07ee8cadce1a538a2c2b5a958ea19c821';
  v_run constant text := '39521127876';
  v_job constant text := '118964943837';
  v_share constant text := 'https://chatgpt.com/share/6ad8053a-46a8-83e8-ab6a-9f8031ca68b0';
  v_evidence constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_03_C3_REVIEW_CAPTURE_V1.json#blob:4e9648a5ff8202aa1094001bc398b41fb3b67637';

  v_spec jsonb := $spec$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-03_C3",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"BOUNDED_CHECKPOINT_TEST",
  "precision":"EXACT_RW103_C3_GPT_NATIVE_BLIND_REVIEW_CAPTURE_V1",
  "action_kind":"BOUNDED_CHECKPOINT_TEST_AUTHORING",
  "recipe_mode":"AUTHOR_AND_RUN_CHECKPOINT_TEST",
  "mutation_policy":"TEST_ARTIFACT_ONLY",
  "requires_material_execution":true,
  "expected":"Admit one owner-approved GPT Native blind review from a separate chat reference: real item PASS 5/5, decoy item FAIL 5/5, while preserving provider_attested=false, real_execution_receipt=false and independent_review=false.",
  "target":{
    "checkpoint":"RW1-03_C3",
    "declared_assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "declared_events":[21354],
    "declared_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_eventos"
    ],
    "declared_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C3_BLIND_REVIEW_PACKET_V2.json","role":"EVIDENCE","purpose":"BLIND_PACKET","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C3_REVIEW_CAPTURE_V1.json","role":"EVIDENCE","purpose":"REVIEW_CAPTURE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw103_c3_capture_v1.py","role":"EVIDENCE","purpose":"CAPTURE_VALIDATOR","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"EVIDENCE","purpose":"EXACT_MAIN_RUNNER","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "evidence_artifacts":[],
    "mutation_artifacts":[]
  },
  "forbidden":[
    "CLAIM_PROVIDER_ATTESTATION",
    "CLAIM_REAL_EXECUTION_RECEIPT",
    "CLAIM_INDEPENDENT_REVIEW",
    "CLAIM_ROUTER_RUNTIME_PASS",
    "CLAIM_E2E_PASS",
    "CLAIM_PRODUCTION_PASS",
    "CLOSE_WITH_REAL_ITEM_FAIL",
    "CLOSE_WITH_DECOY_PASS",
    "OPEN_RW1_04_FROM_THIS_CHECKPOINT"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "capture_verified":true,
      "real_item_pass":true,
      "decoy_item_fail":true,
      "real_checks_passed":5,
      "decoy_checks_failed":5,
      "packet_git_blob":"4654cdab6de895890aedaa0163321cb977a174ac",
      "raw_output_sha256":"77e90f302291b3f00dc4e981d383710e10ce53e3d908490a5d80efce8025aaff",
      "chat_transcript_ref":"https://chatgpt.com/share/6ad8053a-46a8-83e8-ab6a-9f8031ca68b0",
      "separate_chat_reference_verified":true,
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
    "test_code":"ENG_RW103_C3_GPT_NATIVE_BLIND_CAPTURE",
    "test_path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw103_c3_capture_v1.py",
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
    "canonical_exit_criterion":"Blind review distinguishes the real contract from a seeded decoy across Train, stale-source, negative authority and legacy-consumer falsifiers, without claiming provider attestation or independent assurance.",
    "checkpoint_title_context":"RW1-03_C3"
  },
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_03_C3_REVIEW_CAPTURE_V1.json#blob:4e9648a5ff8202aa1094001bc398b41fb3b67637"
}
$spec$::jsonb;

  v_source jsonb := $source$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21354],
    "queries":[
      "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1129 ORDER BY sequence_no",
      "SELECT payload->>'packet_git_blob' packet_git_blob,payload->>'separate_chat_required' separate_chat_required,payload->>'acceptance_declared' acceptance_declared FROM public.lf_eventos WHERE id=21354"
    ],
    "db_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_eventos"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_03_C3_BLIND_REVIEW_PACKET_V2.json",
      "docs/programming-agent/router_wave/RW1_03_C3_REVIEW_CAPTURE_V1.json",
      "sandbox/lf_contract_gate_test/router_wave/validate_rw103_c3_capture_v1.py",
      ".github/workflows/lf-router-level2-advisory-tests.yml",
      "docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Exact-main deterministic validation of the owner-approved GPT Native blind-review capture, with real PASS and decoy FAIL while preserving unattested evidence limits.",
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_03_C3_REVIEW_CAPTURE_V1.json#blob:4e9648a5ff8202aa1094001bc398b41fb3b67637",
  "verification_boundary":"RW103_C3_CONTRACT_REVIEW_ONLY_NOT_RUNTIME_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"f26bb2c07ee8cadce1a538a2c2b5a958ea19c821",
  "source_git_blobs":{
    "packet":"4654cdab6de895890aedaa0163321cb977a174ac",
    "capture":"4e9648a5ff8202aa1094001bc398b41fb3b67637",
    "validator":"686667adbb7e51ebea958e0f8a1fd4de70f3fac4",
    "workflow":"a88e9d260b86b0836222bea9e3bef5fbe87da4c9",
    "decision":"9d80848dca36c94ba901028a4c27a1c58e425cb4"
  },
  "runner_receipt":{
    "provider":"GITHUB_ACTIONS",
    "run_id":"39521127876",
    "job_id":"118964943837",
    "event":"push",
    "conclusion":"success",
    "resolved_main_sha":"f26bb2c07ee8cadce1a538a2c2b5a958ea19c821"
  }
}
$source$::jsonb;

  v_capture jsonb := jsonb_build_object(
    'schema','RW103_C3_GPT_NATIVE_CAPTURE_LEDGER_V1',
    'subject_ref',v_plan||'/'||v_unit||'/'||v_cp,
    'packet_git_blob','4654cdab6de895890aedaa0163321cb977a174ac',
    'capture_git_blob','4e9648a5ff8202aa1094001bc398b41fb3b67637',
    'raw_output_sha256','77e90f302291b3f00dc4e981d383710e10ce53e3d908490a5d80efce8025aaff',
    'chat_transcript_ref',v_share,
    'capture_method','USER_PROVIDED_FROM_PUBLIC_CHAT_SHARE',
    'public_share_access_verified',true,
    'public_share_contains_handoff_reference',true,
    'separate_chat_reference_verified',true,
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
      WHERE id=v_wi AND work_code='ROUTER-W1-03' AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-03_C1' AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-03_C2' AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code=v_cp AND status='PENDING'
           AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW103_C3_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>>'{gpt_native_packets_v1,RW1-03_C3,packet_git_blob}' IS DISTINCT FROM '4654cdab6de895890aedaa0163321cb977a174ac'
     OR v_old#>>'{gpt_native_c3_keys_v1,RW1-03_C3,real_item_id}' IS DISTINCT FROM 'ITEM_A'
     OR v_old#>>'{gpt_native_c3_keys_v1,RW1-03_C3,decoy_item_id}' IS DISTINCT FROM 'ITEM_B'
     OR v_old#>'{gpt_native_captures_v1,RW1-03_C3}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW103_C3_PACKET_OR_CAPTURE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_eventos
      WHERE id=21354
        AND evento_tipo='HANDOFF_DEEP_CONTEXT'
        AND payload->>'packet_git_blob'='4654cdab6de895890aedaa0163321cb977a174ac'
        AND payload->>'separate_chat_required'='true'
        AND payload->>'acceptance_declared'='false')<>1
  THEN RAISE EXCEPTION 'RW103_C3_HANDOFF_EVENT_DRIFT'; END IF;

  v_new:=v_old;
  v_new:=jsonb_set(v_new,'{action_specs_v1,RW1-03_C3}',v_spec,true);
  v_new:=jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-03_C3}',v_source,true);
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
  IF v_count<>1 THEN RAISE EXCEPTION 'RW103_C3_METADATA_UPDATE_COUNT:%',v_count; END IF;

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
  THEN RAISE EXCEPTION 'RW103_C3_CONTRACT_NOT_READY: spec=% contract=% ready=%',
       v_compiled::text,v_contract::text,v_ready::text; END IF;

  v_obs:=jsonb_build_object(
    'capture_verified',true,
    'real_item_pass',true,
    'decoy_item_fail',true,
    'real_checks_passed',5,
    'decoy_checks_failed',5,
    'packet_git_blob','4654cdab6de895890aedaa0163321cb977a174ac',
    'raw_output_sha256','77e90f302291b3f00dc4e981d383710e10ce53e3d908490a5d80efce8025aaff',
    'chat_transcript_ref',v_share,
    'separate_chat_reference_verified',true,
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
  THEN RAISE EXCEPTION 'RW103_C3_RESULT_DOES_NOT_SATISFY_CONTRACT'; END IF;

  -- Negative admission control: decoy PASS must fail the assertion contract.
  v_bad:=jsonb_set(v_obs,'{decoy_item_fail}','false'::jsonb,true);
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,
      jsonb_build_object('status','PASS','test_code','ENG_RW103_C3_GPT_NATIVE_BLIND_CAPTURE',
                         'evidence_ref',v_evidence,'observed',v_bad),
      v_actor||'_NEGATIVE'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%' THEN RAISE; END IF;
    v_negative_rejected:=true;
  END;
  IF NOT v_negative_rejected THEN RAISE EXCEPTION 'RW103_C3_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,
    jsonb_build_object(
      'status','PASS',
      'test_code','ENG_RW103_C3_GPT_NATIVE_BLIND_CAPTURE',
      'evidence_ref',v_evidence,
      'observed',v_obs
    ),
    v_actor
  );

  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
  THEN RAISE EXCEPTION 'RW103_C3_ASSERTION_RECEIPT_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'RW1-03_C3 PASS under owner-approved GPT Native in-chat equivalent: separate public chat reference verified; real item PASS 5/5 and seeded decoy FAIL 5/5; exact-main validator receipt recorded. Evidence remains provider_attested=false, real_execution_receipt=false, independent_review=false; no runtime/E2E/production claim.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW103_C3_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi
        AND ((checkpoint_code='RW1-03_C1' AND status='DONE')
          OR (checkpoint_code='RW1-03_C2' AND status='DONE')
          OR (checkpoint_code='RW1-03_C3' AND status='DONE'
              AND completed_at IS NOT NULL
              AND evidence_ref=v_evidence
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true')))<>3
  THEN RAISE EXCEPTION 'RW103_C3_POST_READBACK_NOT_CONSISTENT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND status='DONE')<>1
  THEN RAISE EXCEPTION 'RW103_C3_UNIT_NOT_CLOSED'; END IF;
END
$rw103_c3_close$;
COMMIT;
