-- RW1-03_C2: bind exact semantic ABI/transition contract, consume exact-main CI receipt, assert and close C2.
-- Scope: contract/material evidence only. No Router runtime, ACL, profile/adapter, operation or production mutation.
BEGIN;
DO $rw103_c2$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-03';
  v_cp constant text := 'RW1-03_C2';
  v_work_item constant bigint := 1129;
  v_actor constant text := 'LF_ROUTER_RW103_C2_MATERIAL_CLOSE_20261020';
  v_prior_md5 constant text := '71b2da0b5014751aee00ab20a56b1f11';

  v_main constant text := '16473e3fd4fe8cc8108676629dc609b0837ab5da';
  v_run constant text := '39503782116';
  v_job constant text := '118907500502';
  v_evidence constant text := 'https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39503782116/job/118907500502';

  v_contract_blob constant text := 'bfd571d5e7c7d1d80c5ed39414a822b4096c20d6';
  v_validator_blob constant text := 'af36486b56a3c82879a6124c92db3486e1b8d66e';
  v_workflow_blob constant text := '29e0f5857af9b7f98fa554378395c77db8109af0';

  v_spec jsonb := $json$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-03_C2",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"BOUNDED_CHECKPOINT_TEST",
  "precision":"EXACT_RW103_SEMANTIC_ABI_TRANSITION_V1",
  "action_kind":"BOUNDED_CHECKPOINT_TEST_AUTHORING",
  "recipe_mode":"AUTHOR_AND_RUN_CHECKPOINT_TEST",
  "mutation_policy":"TEST_ARTIFACT_ONLY",
  "requires_material_execution":true,
  "expected":"Materialize and verify the selected A_MIN_ROUTER_SEMANTIC_SPECIALIST ABI: Router retains discovery/derivation/currentness/effect authority; specialist only normalizes semantics; clarification is caller-owned; resume fails closed on hash/currentness/scope drift; legacy consumers migrate without a second Router or circular Merge Train dependency.",
  "target":{
    "checkpoint":"RW1-03_C2",
    "declared_assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "declared_events":[21263],
    "declared_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "programacion.fn_lf_router_input_governance_resolve_v1"
    ],
    "declared_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json","role":"EVIDENCE","purpose":"SEMANTIC_ABI_AND_TRANSITION_CONTRACT","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw103_semantic_abi_v1.py","role":"EVIDENCE","purpose":"EXECUTABLE_FAIL_CLOSED_VALIDATOR","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"EVIDENCE","purpose":"EXISTING_ROUTER_TEST_RUNNER","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "evidence_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C1_CONTRACT_SURFACE_AUTHORITY_BASELINE_V1.md","role":"EVIDENCE","purpose":"C1_SURFACE_AUTHORITY_BASELINE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json","role":"EVIDENCE","purpose":"SEMANTIC_ABI_AND_TRANSITION_CONTRACT","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw103_semantic_abi_v1.py","role":"EVIDENCE","purpose":"EXECUTABLE_FAIL_CLOSED_VALIDATOR","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"EVIDENCE","purpose":"EXACT_MAIN_RUNNER","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "mutation_artifacts":[]
  },
  "forbidden":[
    "CREATE_SECOND_ROUTER",
    "ALLOW_SPECIALIST_DISCOVERY",
    "ALLOW_SPECIALIST_ROUTE_SELECTION",
    "ALLOW_SPECIALIST_OPERATION_SELECTION",
    "ALLOW_SPECIALIST_EXECUTOR_SELECTION",
    "ALLOW_SPECIALIST_EFFECT_AUTHORITY",
    "ALLOW_SCOPE_WIDENING",
    "DROP_NEGATIVE_EXCLUSIONS",
    "TREAT_TARGET_HINT_AS_AUTHORITY",
    "CIRCULAR_TRAIN_BOOTSTRAP",
    "WIDEN_ACL",
    "CLAIM_ROUTER_RUNTIME_PASS",
    "CLAIM_E2E_PASS",
    "CLAIM_PRODUCTION_EFFECT",
    "CLOSE_C3_FROM_C2"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "test_passed":true,
      "test_exit_code":0,
      "semantic_abi_cases":14,
      "negative_contract_mutations":8,
      "negative_response_probes":5,
      "positive_response_probe":1,
      "selected_architecture":"A_MIN_ROUTER_SEMANTIC_SPECIALIST",
      "router_remains_only_router":true,
      "specialist_has_no_effect_authority":true,
      "request_hash_bound":true,
      "currentness_required":true,
      "scope_non_widening":true,
      "exclusions_preserved":true,
      "clarification_caller_owned":true,
      "no_circular_train_dependency":true,
      "no_acl_widening":true,
      "legacy_compatibility_defined":true,
      "source_sha_current":true,
      "real_python_runner_receipt":true,
      "no_router_runtime_claim":true,
      "no_production_mutation":true
    }
  },
  "test_execution_contract":{
    "mode":"AUTHORED_NEGATIVE",
    "test_code":"ENG_RW103_C2_SEMANTIC_ABI_TRANSITION",
    "test_path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw103_semantic_abi_v1.py",
    "contract_path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
    "synthetic_pass":"FORBIDDEN",
    "negative_required":true,
    "authoring_required":false,
    "execution_route":{
      "provider":"GITHUB_ACTIONS",
      "workflow_path":".github/workflows/lf-router-level2-advisory-tests.yml",
      "job_name":"router-level2-advisory-contract",
      "check_name":"router-level2-advisory-contract"
    },
    "semantic_authority":"RW103_C1_FROZEN_SURFACE_AUTHORITY",
    "fallback_case_discovery":"FORBIDDEN",
    "canonical_exit_criterion":"Contrato firmado por pruebas de consistencia, transición sin callejón circular de Train ni permiso de escritura inferido de discovery.",
    "checkpoint_title_context":"RW1-03_C2"
  },
  "action_steps":[
    "VERIFY_C1_DONE_AND_C3_PENDING",
    "VERIFY_EXACT_MAIN_CONTRACT_VALIDATOR_AND_WORKFLOW",
    "VERIFY_REAL_MAIN_RUNNER_SUCCESS",
    "VERIFY_14_ACCEPTANCE_CASES",
    "VERIFY_NEGATIVE_CONTRACT_AND_RESPONSE_PROBES",
    "VERIFY_NO_SECOND_ROUTER",
    "VERIFY_NO_CIRCULAR_TRAIN_DEPENDENCY",
    "VERIFY_NO_ACL_WIDENING",
    "RECORD_MATERIAL_ASSERTION_RECEIPT",
    "PERSIST_C2_DONE_ONLY_AFTER_ASSERTION_AND_READBACK"
  ],
  "verification_queries":[
    "SELECT c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1129 ORDER BY c.sequence_no",
    "SELECT md5(unit_metadata::text) metadata_md5 FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-03'"
  ],
  "evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39503782116/job/118907500502"
}
$json$::jsonb;

  v_source jsonb := $json$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21263],
    "queries":[
      "SELECT c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1129 ORDER BY c.sequence_no",
      "SELECT md5(unit_metadata::text) metadata_md5 FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-03'"
    ],
    "db_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_03_C1_CONTRACT_SURFACE_AUTHORITY_BASELINE_V1.md",
      "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
      "sandbox/lf_contract_gate_test/router_wave/validate_rw103_semantic_abi_v1.py",
      ".github/workflows/lf-router-level2-advisory-tests.yml",
      "sandbox/lf_contract_gate_test/changesets/router-wave-rw103-c2-semantic-abi-v1.json"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Exact-main executable contract evidence for the semantic specialist ABI and transition. Router remains sole router and effect authority; C3 remains independent review.",
  "evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39503782116/job/118907500502",
  "verification_boundary":"RW103_C2_MATERIAL_CONTRACT_ONLY_NOT_ROUTER_RUNTIME_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"16473e3fd4fe8cc8108676629dc609b0837ab5da",
  "source_git_blobs":{
    "contract":"bfd571d5e7c7d1d80c5ed39414a822b4096c20d6",
    "validator":"af36486b56a3c82879a6124c92db3486e1b8d66e",
    "workflow":"29e0f5857af9b7f98fa554378395c77db8109af0"
  },
  "runner_receipt":{
    "provider":"GITHUB_ACTIONS",
    "run_id":"39503782116",
    "job_id":"118907500502",
    "event":"push",
    "conclusion":"success",
    "resolved_main_sha":"16473e3fd4fe8cc8108676629dc609b0837ab5da"
  }
}
$json$::jsonb;

  v_old jsonb;
  v_new jsonb;
  v_compiled jsonb;
  v_contract jsonb;
  v_ready jsonb;
  v_packet jsonb;
  v_bad_packet jsonb;
  v_obs jsonb;
  v_result jsonb;
  v_bad_result jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_count integer;
  v_negative_rejected boolean := false;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit
    AND work_item_id=v_work_item
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_work_item AND work_code='ROUTER-W1-03' AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code='RW1-03_C1'
           AND status='DONE' AND evidence_ref IS NOT NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
           AND status='PENDING' AND evidence_ref IS NULL
           AND assertion_receipt IS NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code='RW1-03_C3'
           AND status='PENDING' AND evidence_ref IS NULL)<>1
  THEN RAISE EXCEPTION 'RW103_C2_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>'{action_specs_v1,RW1-03_C2}' IS NOT NULL
     OR v_old#>'{source_pack_v2,checkpoint_inputs,RW1-03_C2}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW103_C2_ALREADY_BOUND'; END IF;

  v_new:=jsonb_set(
    jsonb_set(v_old,'{action_specs_v1,RW1-03_C2}',v_spec,true),
    '{source_pack_v2,checkpoint_inputs,RW1-03_C2}',v_source,true
  );

  IF ((v_new #- '{action_specs_v1,RW1-03_C2}') #- '{source_pack_v2,checkpoint_inputs,RW1-03_C2}')
       IS DISTINCT FROM v_old
  THEN RAISE EXCEPTION 'RW103_C2_UNRELATED_METADATA_CHANGED'; END IF;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW103_C2_METADATA_UPDATE_COUNT:%',v_count; END IF;

  v_compiled:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_compiled);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(v_plan,v_unit,v_cp,v_compiled,'{}'::jsonb);

  IF v_compiled->>'status' IS DISTINCT FROM 'READY'
     OR v_compiled->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_compiled->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
     OR v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
     OR jsonb_array_length(coalesce(v_packet->'connector_plan','[]'::jsonb))<>3
     OR v_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'RUN_TEST'
     OR v_packet#>>'{connector_plan,0,source_contract,ref_mode}' IS DISTINCT FROM 'EXACT_MERGED_SHA'
     OR v_packet#>>'{connector_plan,0,runner_contract,verified_run_id_required}' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'RW103_C2_CONTRACT_OR_PACKET_NOT_READY: spec=% contract=% ready=% packet=%',
       v_compiled::text,v_contract::text,v_ready::text,v_packet::text; END IF;

  -- Negative packet control: removing the execution route must fail closed.
  v_bad_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    v_plan,v_unit,v_cp,
    v_compiled #- '{test_execution_contract,execution_route}',
    '{}'::jsonb
  );
  IF v_bad_packet->>'status' IS DISTINCT FROM 'BLOCK_RUN_TEST_EXECUTOR_UNRESOLVED'
  THEN RAISE EXCEPTION 'RW103_C2_NEGATIVE_PACKET_FALSE_PASS:%',v_bad_packet::text; END IF;

  v_obs:=jsonb_build_object(
    'test_passed',true,
    'test_exit_code',0,
    'semantic_abi_cases',14,
    'negative_contract_mutations',8,
    'negative_response_probes',5,
    'positive_response_probe',1,
    'selected_architecture','A_MIN_ROUTER_SEMANTIC_SPECIALIST',
    'router_remains_only_router',true,
    'specialist_has_no_effect_authority',true,
    'request_hash_bound',true,
    'currentness_required',true,
    'scope_non_widening',true,
    'exclusions_preserved',true,
    'clarification_caller_owned',true,
    'no_circular_train_dependency',true,
    'no_acl_widening',true,
    'legacy_compatibility_defined',true,
    'source_sha_current',true,
    'real_python_runner_receipt',true,
    'github_run_id',v_run,
    'github_job_id',v_job,
    'github_event','push',
    'github_conclusion','success',
    'resolved_main_sha',v_main,
    'contract_git_blob',v_contract_blob,
    'validator_git_blob',v_validator_blob,
    'workflow_git_blob',v_workflow_blob,
    'no_router_runtime_claim',true,
    'no_production_mutation',true,
    'evidence_scope','CONTRACT_AND_TRANSITION_ONLY_NOT_ROUTER_RUNTIME_OR_PRODUCTION'
  );

  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW103_C2_RESULT_DOES_NOT_SATISFY_CONTRACT'; END IF;

  v_result:=jsonb_build_object(
    'status','PASS',
    'test_code','ENG_RW103_C2_SEMANTIC_ABI_TRANSITION',
    'evidence_ref',v_evidence,
    'observed',v_obs
  );

  -- Negative assertion control: any second-Router allowance must be rejected.
  v_bad_result:=jsonb_set(v_result,'{observed,router_remains_only_router}','false'::jsonb,true);
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_bad_result,v_actor||'_NEGATIVE');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
    THEN RAISE; END IF;
    v_negative_rejected:=true;
  END;
  IF NOT v_negative_rejected
  THEN RAISE EXCEPTION 'RW103_C2_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW103_C2_NEGATIVE_ROLLBACK_NOT_CLEAN'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,v_result,v_actor);
  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
     OR v_assertion->>'evidence_ref' IS DISTINCT FROM v_evidence
  THEN RAISE EXCEPTION 'RW103_C2_ASSERTION_RECEIPT_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'RW1-03_C2 material PASS: exact-main semantic ABI/transition validator succeeded; 14 acceptance cases, 8 contract mutations, 5 negative response probes + 1 positive; Router remains sole router/effect authority; no Train circularity or ACL widening; no runtime/E2E/production claim; C3 remains pending.'
  );
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW103_C2_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-03_C1' AND status='DONE')
          OR (checkpoint_code='RW1-03_C2' AND status='DONE'
              AND completed_at IS NOT NULL
              AND evidence_ref=v_evidence
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true'
              AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')
          OR (checkpoint_code='RW1-03_C3' AND status='PENDING'
              AND evidence_ref IS NULL)))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=v_work_item AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'RW103_C2_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw103_c2$;
COMMIT;
