-- RW1-04_C1: freeze current Router source/regressions and minimal D1-D4 implementation diff.
-- Governance metadata/readback only. No Router runtime, ACL, operation or production mutation.
BEGIN;
DO $rw104_c1$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-04';
  v_cp constant text := 'RW1-04_C1';
  v_wi constant bigint := 1130;
  v_prior_md5 constant text := 'ce0bb45298d955755d0eb3454e379b12';
  v_actor constant text := 'LF_ROUTER_RW104_C1_SOURCE_FREEZE_20261020';
  v_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md#blob:ab2f5232ad429b5d78fd8a943ac94be76830b943';

  v_spec jsonb := $spec$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-04_C1",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"READ_ONLY_EVIDENCE",
  "precision":"EXACT_RW104_SOURCE_REGRESSION_DIFF_FREEZE_V1",
  "action_kind":"READBACK_ONCE",
  "recipe_mode":"READBACK_EXACT",
  "mutation_policy":"NO_DOMAIN_MUTATION",
  "requires_material_execution":false,
  "expected":"Freeze exact main/ledger/function identities and regression blobs, then persist only the minimal D1-D4 implementation delta required by the approved RW1-03 semantic ABI without altering architecture to fit tests.",
  "target":{
    "checkpoint":"RW1-04_C1",
    "declared_assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "declared_events":[21263],
    "declared_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "programacion.fn_lf_router_input_governance_resolve_v1",
      "public.lf_router_action_registry",
      "supabase_migrations.schema_migrations"
    ],
    "declared_artifacts":[],
    "evidence_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md","role":"EVIDENCE","purpose":"SOURCE_REGRESSION_DIFF_BASELINE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json","role":"EVIDENCE","purpose":"APPROVED_ARCHITECTURE_CONTRACT","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C3_REVIEW_CAPTURE_V1.json","role":"EVIDENCE","purpose":"C3_REVIEW_CAPTURE","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "mutation_artifacts":[]
  },
  "forbidden":[
    "IMPLEMENT_D1_D4_IN_C1",
    "ALTER_ROUTER_RUNTIME",
    "WIDEN_ACL",
    "CHANGE_OPERATION_REGISTRY",
    "CHANGE_MERGE_TRAIN",
    "REWRITE_REGRESSION_TESTS_TO_FIT_IMPLEMENTATION",
    "OPEN_RW1_04_C2_BY_SIDE_EFFECT",
    "CLAIM_RUNTIME_PASS",
    "CLAIM_E2E_PASS",
    "CLAIM_PRODUCTION_PASS"
  ],
  "action_steps":[
    "VERIFY_RW103_DONE_3_OF_3",
    "FREEZE_MAIN_SHA",
    "VERIFY_ROUTER_HANDOFF_IG_FUNCTION_HASHES",
    "VERIFY_ROUTER_LEDGER_VERSIONS",
    "VERIFY_REGRESSION_BLOBS",
    "VERIFY_RW103_CONTRACT_AND_C3_RECEIPT",
    "PERSIST_MINIMAL_DIFF_D1_D4",
    "ASSERT_C2_C3_STILL_PENDING",
    "PERSIST_C1_DONE_ONLY_AFTER_READBACK"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "rw103_done_3_of_3":true,
      "source_sha_current":true,
      "router_source_md5_matches":true,
      "handoff_source_md5_matches":true,
      "ig_source_md5_matches":true,
      "router_ledger_versions_verified":3,
      "regression_blobs_verified":5,
      "approved_contract_blob_matches":true,
      "c3_capture_blob_matches":true,
      "c3_assertion_receipt_matches":true,
      "minimal_diff_items":4,
      "c2_c3_pending":true,
      "no_runtime_mutation":true,
      "no_acl_change":true,
      "no_production_mutation":true
    }
  },
  "verification_queries":[
    "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1130 ORDER BY sequence_no",
    "SELECT version,name FROM supabase_migrations.schema_migrations WHERE version IN ('20261017034602','20261017035500','20261017040500') ORDER BY version",
    "SELECT count(*) active_routes,count(*) FILTER (WHERE write_allowed) write_routes,count(*) FILTER (WHERE NOT write_allowed) nonwrite_routes FROM public.lf_router_action_registry WHERE status='ACTIVE'"
  ],
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md#blob:ab2f5232ad429b5d78fd8a943ac94be76830b943"
}
$spec$::jsonb;

  v_source jsonb := $source$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21263],
    "queries":[
      "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1130 ORDER BY sequence_no",
      "SELECT version,name FROM supabase_migrations.schema_migrations WHERE version IN ('20261017034602','20261017035500','20261017040500') ORDER BY version",
      "SELECT count(*) active_routes,count(*) FILTER (WHERE write_allowed) write_routes,count(*) FILTER (WHERE NOT write_allowed) nonwrite_routes FROM public.lf_router_action_registry WHERE status='ACTIVE'"
    ],
    "db_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_router_action_registry",
      "supabase_migrations.schema_migrations"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md",
      "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
      "docs/programming-agent/router_wave/RW1_03_C3_REVIEW_CAPTURE_V1.json",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_exact_identity_source_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_unstructured_intent_source_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_explicit_target_and_catalog_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/router_intent_semantic_contract_v1.py",
      "sandbox/lf_contract_gate_test/canonical_route_guard/test_router_intent_semantic_contract_v1.py"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Verified-current source baseline and minimal D1-D4 implementation diff for RW1-04_C2, preserving existing Router regression behavior and RW1-03 authority boundaries.",
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md#blob:ab2f5232ad429b5d78fd8a943ac94be76830b943",
  "verification_boundary":"RW104_C1_SOURCE_FREEZE_ONLY_NOT_IMPLEMENTATION_RUNTIME_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"6d26bdf36ebf1ae1f718157654941be466bc2b41",
  "source_git_blobs":{
    "baseline":"ab2f5232ad429b5d78fd8a943ac94be76830b943",
    "rw103_contract":"bfd571d5e7c7d1d80c5ed39414a822b4096c20d6",
    "rw103_capture":"4e9648a5ff8202aa1094001bc398b41fb3b67637",
    "router_exact_identity_migration":"d97ac62da84b728706ceed34598853bb52ad0c4f",
    "router_unstructured_migration":"2c67ffe2c98c7022a79dd6f687a67e1be789db1f",
    "router_explicit_target_migration":"23acf59f2afcee2cf81d10e05c6d31ec4c23ebf2",
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
  v_contract jsonb;
  v_ready jsonb;
  v_preflight jsonb;
  v_transition jsonb;
  v_count integer;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND work_code='ROUTER-W1-04' AND status='BACKLOG')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND status='PENDING')<>3
  THEN RAISE EXCEPTION 'RW104_C1_LIFECYCLE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
      WHERE u.plan_code=v_plan AND u.unit_code='RW1-03' AND c.status='DONE')<>3
  THEN RAISE EXCEPTION 'RW104_C1_RW103_NOT_DONE_3_OF_3'; END IF;

  IF (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1129 AND checkpoint_code='RW1-03_C3')
     IS DISTINCT FROM 'f4edb9722cfd1ff7e278897934c63b50343a50515d256ab160bc14b950b96216'
  THEN RAISE EXCEPTION 'RW104_C1_RW103_C3_RECEIPT_DRIFT'; END IF;

  IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
       IS DISTINCT FROM 'd45f5bddb693791b6459bbe3acfd4ed3'
     OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v1(text,jsonb,text)'::regprocedure))
       IS DISTINCT FROM '540bc1b60caf2e3f9d81461f99c509ef'
     OR md5(pg_get_functiondef('programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure))
       IS DISTINCT FROM '72e153a7fbfe7b10a8c9ae694a61b334'
  THEN RAISE EXCEPTION 'RW104_C1_FUNCTION_SOURCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
      WHERE (version,name) IN (
        ('20261017034602','lf_router_exact_identity_structured_discovery_v1'),
        ('20261017035500','lf_router_unstructured_mutation_fail_closed_v1'),
        ('20261017040500','lf_router_explicit_target_semantic_admission_v1')
      ))<>3
  THEN RAISE EXCEPTION 'RW104_C1_LEDGER_SOURCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE')<>35
     OR (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE' AND write_allowed)<>26
     OR (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE' AND NOT write_allowed)<>9
  THEN RAISE EXCEPTION 'RW104_C1_ROUTE_REGISTRY_DRIFT'; END IF;

  IF v_old ? 'action_specs_v1' AND v_old#>'{action_specs_v1,RW1-04_C1}' IS NOT NULL
     OR v_old ? 'source_pack_v2' AND v_old#>'{source_pack_v2,checkpoint_inputs,RW1-04_C1}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW104_C1_ALREADY_BOUND'; END IF;

  v_new:=jsonb_set(v_old,'{action_specs_v1}',coalesce(v_old->'action_specs_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_spec),true);
  v_new:=jsonb_set(v_new,'{source_pack_v2}',coalesce(v_new->'source_pack_v2','{}'::jsonb)||jsonb_build_object(
    'checkpoint_inputs',
    coalesce(v_new#>'{source_pack_v2,checkpoint_inputs}','{}'::jsonb)||jsonb_build_object(v_cp,v_source)
  ),true);

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW104_C1_METADATA_UPDATE_COUNT:%',v_count; END IF;

  v_action:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_action);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  v_preflight:=programacion.fn_engineering_checkpoint_source_query_preflight_v1(v_plan,v_unit,v_cp);

  IF v_action->>'status' IS DISTINCT FROM 'READY'
     OR v_action->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
     OR v_action->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_contract->>'status' IS DISTINCT FROM 'NOT_REQUIRED'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
     OR v_preflight->>'status' IS DISTINCT FROM 'PASS'
  THEN RAISE EXCEPTION 'RW104_C1_CONTRACT_OR_SOURCE_NOT_READY: action=% contract=% ready=% preflight=%',
       v_action::text,v_contract::text,v_ready::text,v_preflight::text; END IF;

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_ref,v_actor,
    'RW1-04_C1 verified-current source freeze: main, three Router function hashes, three ledger source migrations, five regression artifacts, RW1-03 contract/review and minimal D1-D4 implementation delta frozen. No runtime, ACL, operation or production mutation.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW104_C1_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi
        AND ((checkpoint_code='RW1-04_C1' AND status='DONE' AND evidence_ref=v_ref)
          OR (checkpoint_code IN ('RW1-04_C2','RW1-04_C3') AND status='PENDING' AND evidence_ref IS NULL)))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=v_wi AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'RW104_C1_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw104_c1$;
COMMIT;
