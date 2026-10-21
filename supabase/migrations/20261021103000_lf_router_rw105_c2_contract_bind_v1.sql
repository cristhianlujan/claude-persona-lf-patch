-- RW1-05_C2 contract/source binding only.
-- Does not close C2 and does not claim material execution while the real runtime host is unavailable.
BEGIN;
DO $rw105_c2_bind$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C2';
  v_wi constant bigint := 1131;
  v_prior_md5 constant text := 'fde7a5e4fda2da92155c0a9ec88d4dfd';
  v_spec jsonb := $spec$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-05_C2",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"BOUNDED_IMPLEMENTATION_AUTHORING",
  "precision":"EXACT_RW105_CONSUMER_E2E_MATERIAL_V1",
  "action_kind":"MATERIALIZE_DECLARED_DELIVERABLE",
  "recipe_mode":"CODE_AND_MIGRATION_THEN_REAL_CANARY",
  "mutation_policy":"ONLY_DECLARED_TARGETS",
  "requires_material_execution":true,
  "expected":"Materialize the shared T2 semantic consumer and caller-interaction boundary, preserve ACT-0001 as resume/rederivation authority, compose a canonical Profile Runtime terminal authority receipt, reconcile terminal queue failures, and close only after real semantic-shadow and zero-cost Profile Runtime canaries produce exact readbacks.",
  "target":{
    "checkpoint":"RW1-05_C2",
    "declared_assets":["ACT-0001","EJECUCION_PERFIL_LF","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "declared_events":[21368],
    "declared_objects":[
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_profile_execution_reconcile_queue_terminal_v1",
      "public.lf_profile_execution_scope_authority_packet_v1",
      "public.lf_profile_execution_terminal_authority_receipt_v1",
      "public.lf_profile_execution_attach_terminal_authority_receipt_v1",
      "public.lf_operation_execution",
      "public.lf_operation_execution_steps",
      "public.v_lf_operation_execution_judge",
      "private.lf_profile_runtime_queue_v1"
    ],
    "declared_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:services/router_semantic_runtime/semantic_consumer.py","role":"MUTATION_TARGET","purpose":"T2_SHARED_SEMANTIC_CONSUMER","target_kind":"EXACT_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:services/router_semantic_runtime/tests/test_semantic_consumer.py","role":"MUTATION_TARGET","purpose":"T2_AUTHORITY_NEGATIVE_TESTS","target_kind":"EXACT_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:services/profile_runtime_api/scripts/hetzner_queue_worker.py","role":"MUTATION_TARGET","purpose":"PROFILE_TERMINAL_RECEIPT_AND_RECONCILIATION","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:services/profile_runtime_api/tests/test_governed_profile_operation_bridge.py","role":"MUTATION_TARGET","purpose":"PROFILE_BRIDGE_REGRESSION_TESTS","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:supabase/migrations/20261021103500_lf_router_rw105_c2_profile_terminal_receipt_v1.sql","role":"MUTATION_TARGET","purpose":"SERVER_OWNED_TERMINAL_RECEIPT","target_kind":"EXACT_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"MUTATION_TARGET","purpose":"EXACT_CI_RUNNER","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "evidence_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md","role":"EVIDENCE","purpose":"C1_CONSUMER_GAP_BASELINE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json","role":"EVIDENCE","purpose":"APPROVED_SEMANTIC_ABI","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "mutation_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:services/router_semantic_runtime/semantic_consumer.py","role":"MUTATION_TARGET","purpose":"T2_SHARED_SEMANTIC_CONSUMER","target_kind":"EXACT_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:services/profile_runtime_api/scripts/hetzner_queue_worker.py","role":"MUTATION_TARGET","purpose":"PROFILE_TERMINAL_RECEIPT_AND_RECONCILIATION","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:supabase/migrations/20261021103500_lf_router_rw105_c2_profile_terminal_receipt_v1.sql","role":"MUTATION_TARGET","purpose":"SERVER_OWNED_TERMINAL_RECEIPT","target_kind":"EXACT_FILE"}
    ]
  },
  "forbidden":[
    "CREATE_SECOND_ROUTER",
    "SPECIALIST_SELECTS_ROUTE",
    "SPECIALIST_SELECTS_OPERATION",
    "SPECIALIST_SELECTS_EXECUTOR",
    "SPECIALIST_AUTHORIZES_EFFECT",
    "WIDEN_SCOPE",
    "DROP_EXCLUSIONS",
    "WIDEN_ACL",
    "RETIRE_V1",
    "ACTIVATE_T3_CUTOVER",
    "CHANGE_INPUT_GOVERNANCE_SELECTION",
    "CHANGE_MERGE_TRAIN",
    "SUBSTITUTE_FIXTURE_FOR_REAL_CANARY",
    "SUBSTITUTE_HISTORICAL_RUN_FOR_REAL_CANARY",
    "CLOSE_WITH_RUNTIME_HOST_OFFLINE",
    "CLOSE_C3_FROM_C2"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "semantic_consumer_shadow_materialized":true,
      "caller_interaction_max_one_question":true,
      "specialist_effect_authority":false,
      "resume_validator_used":true,
      "act0001_rederived_after_valid_resume":true,
      "real_semantic_shadow_run":true,
      "semantic_provider_provenance_receipt":true,
      "profile_terminal_receipt_composed":true,
      "profile_terminal_receipt_attached":true,
      "queue_terminal_reconciliation_verified":true,
      "real_profile_runtime_canary":true,
      "profile_canary_zero_cost_read_only":true,
      "same_request_id_and_execution_id_bound":true,
      "literal_and_hash_bound":true,
      "router_authority_receipt_bound":true,
      "scope_authority_packet_bound":true,
      "profile_source_bound":true,
      "context_receipt_bound":true,
      "raw_output_receipt_bound":true,
      "validator_receipt_bound":true,
      "semantic_judge_receipt_bound":true,
      "canonical_execution_completed":true,
      "profile_required_steps":11,
      "profile_required_steps_pass":11,
      "profile_judge_result":"PASS",
      "merge_train_control_pass":true,
      "input_governance_changed":false,
      "merge_train_changed":false,
      "acl_widened":false,
      "runtime_host_available_for_material_run":true
    }
  },
  "authoring_contract":{
    "mode":"CODE_AND_MIGRATION",
    "git_route":"SCOPED_BRANCH_PR_MERGE",
    "direct_main_write":"FORBIDDEN",
    "allowed_roots_only":true,
    "post_merge_readback_required":true,
    "real_canary_required_after_materialization":true,
    "synthetic_pass":"FORBIDDEN",
    "runtime_activation":"T2_SHADOW_ONLY",
    "t3_cutover":"FORBIDDEN"
  },
  "verification_queries":[
    "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1131 ORDER BY sequence_no",
    "SELECT md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) router_md5,md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure)) resume_md5",
    "SELECT step_order,step_id FROM public.lf_operation_steps WHERE operation_code='EJECUCION_PERFIL_LF' AND active ORDER BY step_order"
  ]
}
$spec$::jsonb;

  v_source jsonb := $source$
{
  "inputs":{
    "assets":["ACT-0001","EJECUCION_PERFIL_LF","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21368],
    "queries":[
      "SELECT md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) router_md5,md5(pg_get_functiondef('public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)'::regprocedure)) handoff_v2_md5,md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure)) resume_md5",
      "SELECT md5(pg_get_functiondef('public.lf_profile_execution_reconcile_queue_terminal_v1(uuid,text)'::regprocedure)) reconcile_md5,md5(pg_get_functiondef('public.lf_profile_execution_scope_authority_packet_v1(text,text,text)'::regprocedure)) scope_md5,md5(pg_get_functiondef('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'::regprocedure)) recorder_md5",
      "SELECT step_order,step_id FROM public.lf_operation_steps WHERE operation_code='EJECUCION_PERFIL_LF' AND active ORDER BY step_order"
    ],
    "db_objects":[
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_profile_execution_reconcile_queue_terminal_v1",
      "public.lf_profile_execution_scope_authority_packet_v1",
      "public.lf_record_profile_execution_step_v1",
      "public.lf_operation_execution",
      "public.lf_operation_execution_steps",
      "public.v_lf_operation_execution_judge",
      "private.lf_profile_runtime_queue_v1"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md",
      "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
      "services/profile_runtime_api/scripts/hetzner_queue_worker.py",
      "services/profile_runtime_api/tests/test_governed_profile_operation_bridge.py"
    ]
  },
  "missing":[],
  "missing_typed":[
    {"code":"REAL_SEMANTIC_SHADOW_RUN_PENDING","kind":"MATERIAL_EXECUTION","blocking":true},
    {"code":"PROFILE_RUNTIME_HOST_OFFLINE","kind":"EXTERNAL_RUNTIME_AVAILABILITY","host_label":"scalora-vps","blocking":true},
    {"code":"REAL_PROFILE_RUNTIME_CANARY_PENDING","kind":"MATERIAL_EXECUTION","blocking":true}
  ],
  "expected_result":"T2 semantic consumer and Profile Runtime receipt/reconciliation support materialized in Git/DB, followed by a real semantic shadow run and a real zero-cost read-only Profile Runtime canary. C2 remains PENDING while either material receipt is absent.",
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md#blob:6494b7b5d40649e629b9c60ec7e751e308e49876",
  "verification_boundary":"RW105_C2_CONSUMER_AND_REAL_CANARY_REQUIRED_NOT_T3_CUTOVER",
  "source_snapshot_commit":"c81f350b91c1df85340da9f54a72e8831fd72540",
  "source_git_blobs":{
    "c1_baseline":"6494b7b5d40649e629b9c60ec7e751e308e49876",
    "rw103_contract":"bfd571d5e7c7d1d80c5ed39414a822b4096c20d6",
    "worker":"ffe6f516c8407d50dec8128b4a4e0680a960a2c6"
  },
  "db_source_md5":{
    "lf_router_resolve_v1":"8cffdd7403c0ae40d5db19890ea4f944",
    "lf_router_intent_handoff_v2":"e6c5df658f322e0c67ee7a2bb5972410",
    "lf_router_semantic_resume_validate_v1":"4dc0dad03d7259009583e2f77f5930fb",
    "lf_profile_execution_reconcile_queue_terminal_v1":"e0c00d5972701bde0ef52d5e4d8091f1",
    "lf_profile_execution_scope_authority_packet_v1":"b17af5a6d0a0fa6341bb1fbc5ce4e0bf",
    "lf_record_profile_execution_step_v1":"7cf717887006e278356a716f3fd80182"
  },
  "runtime_availability_at_bind":{
    "sentinel_host_label":"scalora-vps",
    "connected":false,
    "last_connected_at":"2026-10-20T21:41:56.665917+00:00",
    "material_canary_executed":false
  }
}
$source$::jsonb;

  v_old jsonb;
  v_new jsonb;
  v_count int;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
    AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_wi) IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code='RW1-05_C1') IS DISTINCT FROM 'DONE'
     OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code='RW1-05_C3') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'RW105_C2_CONTRACT_BIND_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>'{action_specs_v1,RW1-05_C2}' IS NOT NULL
     OR v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW105_C2_CONTRACT_ALREADY_BOUND'; END IF;

  v_new:=jsonb_set(
    v_old,'{action_specs_v1}',
    coalesce(v_old->'action_specs_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_spec),true
  );
  v_new:=jsonb_set(
    v_new,'{source_pack_v2}',
    coalesce(v_new->'source_pack_v2','{}'::jsonb)||jsonb_build_object(
      'checkpoint_inputs',
      coalesce(v_new#>'{source_pack_v2,checkpoint_inputs}','{}'::jsonb)||jsonb_build_object(v_cp,v_source)
    ),true
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW105_C2_CONTRACT_BIND_UPDATE_COUNT:%',v_count; END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code=v_cp)
       IS DISTINCT FROM 'PENDING'
     OR (SELECT evidence_ref FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS NOT NULL
     OR (SELECT assertion_receipt FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS NOT NULL
  THEN RAISE EXCEPTION 'RW105_C2_CONTRACT_BIND_CHANGED_CHECKPOINT'; END IF;
END
$rw105_c2_bind$;
COMMIT;
