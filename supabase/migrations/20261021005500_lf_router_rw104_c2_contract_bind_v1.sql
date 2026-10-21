-- RW1-04_C2 contract bind only.
-- Binds the implementation checkpoint to the canonical Git-first migration route.
-- Does not implement V2 and does not transition C2.
BEGIN;
DO $rw104_c2_bind$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-04';
  v_cp constant text := 'RW1-04_C2';
  v_wi constant bigint := 1130;
  v_prior_md5 constant text := '70ce1ae439c5a7837ae4498b54980b25';

  v_spec jsonb := $spec$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-04_C2",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"BOUNDED_IMPLEMENTATION_AUTHORING",
  "precision":"EXACT_RW104_SEMANTIC_V2_IMPLEMENTATION_V1",
  "action_kind":"MATERIALIZE_DECLARED_DELIVERABLE",
  "recipe_mode":"GIT_FIRST_MIGRATION",
  "requires_material_execution":true,
  "mutation_policy":"ONLY_DECLARED_TARGETS",
  "expected":"Implement the approved semantic handoff V2 and fail-closed resume validator via one exact governed migration; dual-emit V2 alongside V1 at all six current semantic-gap sites; keep semantic runtime shadow/disabled and preserve Router authority, legacy compatibility and ACL boundaries.",
  "target":{
    "checkpoint":"RW1-04_C2",
    "declared_assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "declared_events":[21263],
    "declared_objects":[
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_router_action_registry",
      "programacion.engineering_work_checkpoints"
    ],
    "declared_artifacts":[
      {
        "path":"cristhianlujan/claude-persona-lf-patch:supabase/migrations/",
        "role":"MUTATION_TARGET",
        "purpose":"RW104_C2_EXACT_MIGRATION",
        "target_kind":"ALLOWED_OUTPUT_ROOT",
        "resolve_concrete_path_before_write":true,
        "naming_contract":"<timestamp>_lf_router_rw104_c2_semantic_v2_implementation_v1.sql"
      },
      {
        "path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/test_rw104_semantic_v2_source_v1.py",
        "role":"MUTATION_TARGET",
        "purpose":"RW104_C2_SOURCE_REGRESSION",
        "target_kind":"EXACT_FILE"
      }
    ],
    "mutation_artifacts":[
      {
        "path":"cristhianlujan/claude-persona-lf-patch:supabase/migrations/",
        "role":"MUTATION_TARGET",
        "purpose":"RW104_C2_EXACT_MIGRATION",
        "target_kind":"ALLOWED_OUTPUT_ROOT",
        "resolve_concrete_path_before_write":true,
        "naming_contract":"<timestamp>_lf_router_rw104_c2_semantic_v2_implementation_v1.sql"
      },
      {
        "path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/test_rw104_semantic_v2_source_v1.py",
        "role":"MUTATION_TARGET",
        "purpose":"RW104_C2_SOURCE_REGRESSION",
        "target_kind":"EXACT_FILE"
      }
    ],
    "evidence_artifacts":[
      {
        "path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md",
        "role":"EVIDENCE",
        "purpose":"C1_FROZEN_BASELINE",
        "target_kind":"EXACT_EXISTING_FILE"
      },
      {
        "path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_04_C1_ERRATUM_HANDOFF_SITE_COUNT_V1.md",
        "role":"EVIDENCE",
        "purpose":"C1_HANDOFF_COUNT_ERRATUM",
        "target_kind":"EXACT_EXISTING_FILE"
      },
      {
        "path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
        "role":"EVIDENCE",
        "purpose":"APPROVED_SEMANTIC_ABI",
        "target_kind":"EXACT_EXISTING_FILE"
      }
    ]
  },
  "verification_queries":[
    "SELECT count(*) FILTER (WHERE p.proname='lf_router_intent_handoff_v2') handoff_v2_functions,count(*) FILTER (WHERE p.proname='lf_router_semantic_resume_validate_v1') resume_validators FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'",
    "SELECT (length(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))-length(replace(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),'lf_router_intent_handoff_v2(','')))/length('lf_router_intent_handoff_v2(') v2_sites,(length(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))-length(replace(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),'lf_router_intent_handoff_v1(','')))/length('lf_router_intent_handoff_v1(') v1_sites",
    "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1130 ORDER BY sequence_no"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "implementation_written":true,
      "git_merged":true,
      "db_applied":true,
      "readback_passed":true,
      "handoff_v2_installed":true,
      "resume_validator_installed":true,
      "router_v1_sites_preserved":6,
      "router_v2_sites":6,
      "positive_contract_probes_passed":true,
      "negative_contract_probes_passed_at_least":10,
      "rollback_fail_closed_verified":true,
      "legacy_v1_preserved":true,
      "acl_not_widened":true,
      "semantic_runtime_activated":false,
      "operation_registry_changed":false,
      "input_governance_changed":false,
      "merge_train_changed":false
    }
  },
  "authoring_contract":{
    "mode":"MIGRATION",
    "concrete_output_path_required_before_write":true,
    "allowed_roots_only":true,
    "git_route":"SCOPED_BRANCH_PR_MERGE",
    "direct_main_write":"FORBIDDEN",
    "synthetic_pass":"FORBIDDEN",
    "post_merge_readback_required":true,
    "runtime_activation":"NOT_IMPLIED",
    "rollback":"MIGRATION_TRANSACTION_FAILS_CLOSED_ON_ANY_ASSERTION"
  },
  "forbidden":[
    "CREATE_SECOND_ROUTER",
    "REWRITE_DISCOVERY",
    "REWRITE_OPERATION_SELECTION",
    "ALLOW_SPECIALIST_EFFECT_AUTHORITY",
    "ALLOW_SPECIALIST_ROUTE_SELECTION",
    "WIDEN_SCOPE",
    "DROP_EXCLUSIONS",
    "WIDEN_ACL",
    "RETIRE_V1_IN_C2",
    "ACTIVATE_SEMANTIC_RUNTIME",
    "CHANGE_INPUT_GOVERNANCE",
    "CHANGE_MERGE_TRAIN",
    "CHANGE_OPERATION_REGISTRY",
    "WEAKEN_EXISTING_REGRESSIONS",
    "CLOSE_C3_FROM_C2"
  ]
}
$spec$::jsonb;

  v_source jsonb := $source$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21263],
    "queries":[
      "SELECT count(*) FILTER (WHERE p.proname='lf_router_intent_handoff_v2') handoff_v2_functions,count(*) FILTER (WHERE p.proname='lf_router_semantic_resume_validate_v1') resume_validators FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'",
      "SELECT (length(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))-length(replace(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),'lf_router_intent_handoff_v2(','')))/length('lf_router_intent_handoff_v2(') v2_sites,(length(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))-length(replace(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),'lf_router_intent_handoff_v1(','')))/length('lf_router_intent_handoff_v1(') v1_sites",
      "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1130 ORDER BY sequence_no"
    ],
    "db_objects":[
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "public.lf_router_action_registry",
      "programacion.engineering_work_checkpoints"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md",
      "docs/programming-agent/router_wave/RW1_04_C1_ERRATUM_HANDOFF_SITE_COUNT_V1.md",
      "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_exact_identity_source_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_unstructured_intent_source_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_explicit_target_and_catalog_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/router_intent_semantic_contract_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_intent_semantic_contract_v1.py"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"One Git-first exact migration plus one bounded source regression test implementing handoff V2 and fail-closed semantic resume without a second Router or authority/ACL widening.",
  "verification_boundary":"RW104_C2_IMPLEMENTATION_ONLY_SHADOW_DISABLED_NOT_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"3a2bae4deb53f8ab9e7ea661708fcbe0cf6ddeb2",
  "source_git_blobs":{
    "c1_baseline":"ab2f5232ad429b5d78fd8a943ac94be76830b943",
    "rw103_contract":"bfd571d5e7c7d1d80c5ed39414a822b4096c20d6",
    "router_source_migration":"23acf59f2afcee2cf81d10e05c6d31ec4c23ebf2",
    "test_exact_identity":"258cd2c56127343d31546bc0ab9c12e7646041a4",
    "test_unstructured":"0ef68a2f54011f93da89946993650eb7a82895b2",
    "test_explicit_target":"5697303692390aef85d387d2134748bd209afe7d",
    "semantic_contract":"9804e804c2ab9d9f651fa53247a97a03a2ca2509",
    "test_semantic_contract":"91b3a9639a6d1d57fdc8ad2a708bc085c24e3174"
  },
  "db_source_md5":{
    "lf_router_resolve_v1":"d45f5bddb693791b6459bbe3acfd4ed3",
    "lf_router_intent_handoff_v1":"540bc1b60caf2e3f9d81461f99c509ef",
    "fn_lf_router_input_governance_resolve_v1":"72e153a7fbfe7b10a8c9ae694a61b334"
  }
}
$source$::jsonb;

  v_old jsonb;
  v_new jsonb;
  v_action jsonb;
  v_packet jsonb;
  v_ready jsonb;
  v_count integer;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
    AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C1' AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code=v_cp AND status='PENDING'
           AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C3' AND status='PENDING')<>1
  THEN RAISE EXCEPTION 'RW104_C2_BIND_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>'{action_specs_v1,RW1-04_C2}' IS NOT NULL
     OR v_old#>'{source_pack_v2,checkpoint_inputs,RW1-04_C2}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW104_C2_BIND_ALREADY_EXISTS'; END IF;

  v_new:=jsonb_set(v_old,'{action_specs_v1,RW1-04_C2}',v_spec,true);
  v_new:=jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-04_C2}',v_source,true);

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW104_C2_BIND_UPDATE_COUNT:%',v_count; END IF;

  v_action:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(v_plan,v_unit,v_cp,v_action,'{}'::jsonb);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);

  IF v_action->>'status' IS DISTINCT FROM 'READY'
     OR v_action->>'action_kind' IS DISTINCT FROM 'MATERIALIZE_DECLARED_DELIVERABLE'
     OR v_action->>'recipe_mode' IS DISTINCT FROM 'GIT_FIRST_MIGRATION'
     OR v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'WRITE_GIT'
     OR jsonb_array_length(coalesce(v_packet->'connector_plan','[]'::jsonb))<>3
     OR v_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'WRITE_GIT'
     OR v_packet#>>'{connector_plan,1,operation}' IS DISTINCT FROM 'WRITE_DB'
     OR v_packet#>>'{connector_plan,1,mode}' IS DISTINCT FROM 'APPLY_MERGED_MIGRATION'
     OR v_packet#>>'{connector_plan,2,operation}' IS DISTINCT FROM 'CHECKPOINT_TRANSITION'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
  THEN RAISE EXCEPTION 'RW104_C2_BIND_PACKET_NOT_READY: action=% packet=% readiness=%',
       v_action::text,v_packet::text,v_ready::text; END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'RW104_C2_BIND_CHANGED_CHECKPOINT'; END IF;
END
$rw104_c2_bind$;
COMMIT;
