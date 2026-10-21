-- RW1-05_C1: freeze current consumers, post-refactor gaps, and reusable receipts.
-- Evidence/readback closure only. No consumer implementation, runtime activation, ACL, operation,
-- Merge Train, profile execution, or production mutation.
BEGIN;
DO $rw105_c1$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C1';
  v_wi constant bigint := 1131;
  v_prior_md5 constant text := '934e357cc84f75ea58a1eca2f9421e63';
  v_actor constant text := 'LF_ROUTER_RW105_C1_CONSUMER_GAP_FREEZE_20261021';
  v_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md#blob:6494b7b5d40649e629b9c60ec7e751e308e49876';

  v_spec jsonb := $spec$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-05_C1",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"READ_ONLY_EVIDENCE",
  "precision":"EXACT_RW105_CONSUMER_RECEIPT_GAP_FREEZE_V1",
  "action_kind":"READBACK_ONCE",
  "recipe_mode":"READBACK_EXACT",
  "mutation_policy":"NO_DOMAIN_MUTATION",
  "requires_material_execution":false,
  "expected":"Re-read only currently applicable consumers after RW1-04, reuse A16Q_C2 without duplicating its inventory, and freeze which contracts/receipts are healthy, partial or missing before RW1-05_C2.",
  "target":{
    "checkpoint":"RW1-05_C1",
    "declared_assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD","DB_WRITE_TRANSPORT"],
    "declared_events":[],
    "declared_objects":[
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_router_action_registry",
      "public.lf_operation_execution",
      "public.lf_operation_execution_steps",
      "public.lf_operation_step_contracts",
      "public.v_lf_operation_execution_judge",
      "private.lf_profile_runtime_queue_v1",
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints"
    ],
    "declared_artifacts":[],
    "evidence_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md","role":"EVIDENCE","purpose":"CURRENT_CONSUMER_GAP_BASELINE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md","role":"EVIDENCE","purpose":"HISTORICAL_CONSUMER_TRACE_BASELINE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/a16q/a16q_c2_router_consumer_trace.py","role":"EVIDENCE","purpose":"REAL_CONSUMER_FAIL_CLOSED_CONTRACT","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json","role":"EVIDENCE","purpose":"APPROVED_SEMANTIC_ABI","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json","role":"EVIDENCE","purpose":"SELECTED_ARCHITECTURE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:services/profile_runtime_api/scripts/hetzner_queue_worker.py","role":"EVIDENCE","purpose":"CURRENT_PROFILE_CONSUMER","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:services/profile_runtime_api/profile_runtime_api/engine.py","role":"EVIDENCE","purpose":"CURRENT_PROFILE_RUNTIME_ENGINE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py","role":"EVIDENCE","purpose":"CURRENT_TRAIN_CONSUMER_ROUTE","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "mutation_artifacts":[]
  },
  "forbidden":[
    "IMPLEMENT_SEMANTIC_CONSUMER_IN_C1",
    "IMPLEMENT_CALLER_INTERACTION_IN_C1",
    "EXECUTE_PROFILE_RUNTIME_IN_C1",
    "CHANGE_PROFILE_RUNTIME",
    "CHANGE_MERGE_TRAIN",
    "CHANGE_INPUT_GOVERNANCE",
    "CHANGE_OPERATION_REGISTRY",
    "CREATE_SECOND_ROUTER",
    "WIDEN_ACL",
    "ACTIVATE_SEMANTIC_RUNTIME",
    "CLAIM_E2E_PASS",
    "CLAIM_PROFILE_RUNTIME_PASS",
    "CLAIM_PRODUCTION_PASS",
    "OPEN_RW1_05_C2_BY_SIDE_EFFECT"
  ],
  "action_steps":[
    "VERIFY_RW104_DONE_3_OF_3",
    "FREEZE_CURRENT_MAIN_AND_ROUTER_FUNCTION_HASHES",
    "REUSE_A16Q_C2_BASELINE_AND_REAL_EVIDENCE_CONTRACT",
    "CLASSIFY_CURRENT_APPLICABLE_CONSUMERS",
    "REVALIDATE_PROFILE_RUNTIME_PRE_EFFECT_AND_TERMINAL_RECEIPTS",
    "VERIFY_CURRENT_MERGE_TRAIN_AUTHORITY_AND_CLOSURE_CANARY",
    "IDENTIFY_POST_REFACTOR_GAPS_WITHOUT_DUPLICATING_INVENTORY",
    "ASSERT_C2_C3_STILL_PENDING",
    "PERSIST_C1_DONE_ONLY_AFTER_READBACK"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "rw104_done_3_of_3":true,
      "source_sha_current":true,
      "semantic_v2_installed":true,
      "semantic_resume_installed":true,
      "semantic_runtime_activated":false,
      "semantic_consumer_runtime_present":false,
      "caller_interaction_runtime_present":false,
      "profile_consumer_applicable":true,
      "profile_post_refactor_run_count":0,
      "profile_post_refactor_pass_count":0,
      "profile_pre_effect_router_scope_context_present":true,
      "profile_terminal_receipt_complete":false,
      "profile_terminal_lifecycle_reconciled":false,
      "train_consumer_current":true,
      "train_router_authority_bound":true,
      "train_closure_evidence":true,
      "current_gap_count":5,
      "c2_c3_pending":true,
      "no_domain_mutation":true
    }
  },
  "verification_queries":[
    "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1131 ORDER BY sequence_no",
    "SELECT md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) router_md5,md5(pg_get_functiondef('public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)'::regprocedure)) handoff_v2_md5,md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure)) resume_md5",
    "SELECT execution_id,status,manifest ? 'router_authority_receipt' has_router_authority,manifest ? 'closure_evidence' has_closure FROM public.lf_operation_execution WHERE execution_id='EXEC-DB-TRAIN-PR3004-20261021063500-R39555468919'",
    "SELECT execution_id,status FROM public.lf_operation_execution WHERE execution_id='EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6'"
  ],
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md#blob:6494b7b5d40649e629b9c60ec7e751e308e49876"
}
$spec$::jsonb;

  v_source jsonb := $source$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD","DB_WRITE_TRANSPORT"],
    "events":[],
    "queries":[
      "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1131 ORDER BY sequence_no",
      "SELECT md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) router_md5,md5(pg_get_functiondef('public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)'::regprocedure)) handoff_v2_md5,md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure)) resume_md5",
      "SELECT execution_id,status,manifest ? 'router_authority_receipt' has_router_authority,manifest ? 'closure_evidence' has_closure FROM public.lf_operation_execution WHERE execution_id='EXEC-DB-TRAIN-PR3004-20261021063500-R39555468919'",
      "SELECT execution_id,status FROM public.lf_operation_execution WHERE execution_id='EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6'"
    ],
    "db_objects":[
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_router_action_registry",
      "public.lf_operation_execution",
      "public.lf_operation_execution_steps",
      "public.lf_operation_step_contracts",
      "public.v_lf_operation_execution_judge",
      "private.lf_profile_runtime_queue_v1",
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md",
      "docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md",
      "sandbox/lf_contract_gate_test/engineering_checkpoints/a16q/a16q_c2_router_consumer_trace.py",
      "docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json",
      "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
      "supabase/migrations/20261021010500_lf_router_rw104_c2_semantic_v2_implementation_v1.sql",
      "services/profile_runtime_api/scripts/hetzner_queue_worker.py",
      "services/profile_runtime_api/profile_runtime_api/engine.py",
      "sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py",
      "CLAUDE.md",
      "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Verified-current differential consumer baseline: semantic specialist and caller interaction runtime are still absent; Profile Runtime has reusable pre-effect Router/scope/context evidence but no post-RW1-04 E2E receipt; Merge Train is a current governed control with Router authority and closure evidence.",
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C1_CONSUMER_RECEIPT_GAP_BASELINE_V1.md#blob:6494b7b5d40649e629b9c60ec7e751e308e49876",
  "verification_boundary":"RW105_C1_CONSUMER_GAP_FREEZE_ONLY_NOT_IMPLEMENTATION_RUNTIME_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"8c37bd90639fa84cf1a9b7b2858ba780b08f92fb",
  "source_git_blobs":{
    "baseline":"6494b7b5d40649e629b9c60ec7e751e308e49876",
    "a16q_c2_baseline":"72b4e5977c96162ab60c5d76a1b070bd5d70b3eb",
    "a16q_c2_validator":"38ee6371627202a9fc36f17bdbe08a734fdedadd",
    "architecture_competition":"cf22d9889eb008dc7afcf64dd1b3712b9536ec98",
    "rw103_semantic_abi":"bfd571d5e7c7d1d80c5ed39414a822b4096c20d6",
    "rw104_semantic_v2_implementation":"14619e0a883d42db1e9b25f471e85a5800f970d7",
    "profile_worker":"ffe6f516c8407d50dec8128b4a4e0680a960a2c6",
    "profile_engine":"a557646c9bdfa516474a5eccf008545be3a1fe8a",
    "db_write_transport":"feed95e57deb8a01a963207ee6b8bc85f60d9a94",
    "claude_contract":"08fec7351b320d97d802e50c4de7307981ffcc1d",
    "router_consumption_protocol":"06d8905db56f04bf8557ccb0db556a25f704d015"
  },
  "db_source_md5":{
    "lf_router_resolve_v1":"8cffdd7403c0ae40d5db19890ea4f944",
    "lf_router_intent_handoff_v1":"540bc1b60caf2e3f9d81461f99c509ef",
    "lf_router_intent_handoff_v2":"e6c5df658f322e0c67ee7a2bb5972410",
    "lf_router_semantic_resume_validate_v1":"4dc0dad03d7259009583e2f77f5930fb"
  },
  "observed":{
    "semantic_runtime_phase":"T1_INSTALLED_T2_CONSUMER_NOT_PRESENT",
    "semantic_consumer_runtime_present":false,
    "caller_interaction_runtime_present":false,
    "profile_post_refactor_run_count":0,
    "profile_post_refactor_pass_count":0,
    "profile_reference_execution":{
      "execution_id":"EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6",
      "queue_status":"BLOCKED",
      "queue_error_code":"LLAMA_TIMEOUT",
      "canonical_status":"IN_PROGRESS",
      "judge_result":"FAIL",
      "required_steps":11,
      "required_steps_pass":7,
      "terminal_steps_present":0,
      "router_step_pass":true,
      "scope_authority_packet_step_pass":true,
      "context_admission_step_pass":true,
      "manifest_router_authority_receipt":false,
      "terminal_receipt_complete":false,
      "terminal_lifecycle_reconciled":false
    },
    "train_reference_execution":{
      "execution_id":"EXEC-DB-TRAIN-PR3004-20261021063500-R39555468919",
      "status":"COMPLETED",
      "router_authority_receipt":true,
      "closure_evidence":true,
      "parity":"PASS"
    },
    "gap_codes":[
      "RW105-C1-G01",
      "RW105-C1-G02",
      "RW105-C1-G03",
      "RW105-C1-G04",
      "RW105-C1-G05"
    ]
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
      WHERE id=v_wi AND work_code='ROUTER-W1-05' AND status='BACKLOG')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND status='PENDING')<>3
  THEN RAISE EXCEPTION 'RW105_C1_LIFECYCLE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
      WHERE u.plan_code=v_plan AND u.unit_code='RW1-04' AND c.status='DONE')<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=1130 AND status='DONE')<>1
  THEN RAISE EXCEPTION 'RW105_C1_RW104_NOT_DONE_3_OF_3'; END IF;

  IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
       IS DISTINCT FROM '8cffdd7403c0ae40d5db19890ea4f944'
     OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v1(text,jsonb,text)'::regprocedure))
       IS DISTINCT FROM '540bc1b60caf2e3f9d81461f99c509ef'
     OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM 'e6c5df658f322e0c67ee7a2bb5972410'
     OR md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM '4dc0dad03d7259009583e2f77f5930fb'
  THEN RAISE EXCEPTION 'RW105_C1_ROUTER_SOURCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE')<>35
  THEN RAISE EXCEPTION 'RW105_C1_ROUTE_REGISTRY_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='EJECUCION_PERFIL_LF'
        AND created_at >= '2026-10-21 00:00:00+00')<>0
  THEN RAISE EXCEPTION 'RW105_C1_PROFILE_POST_REFACTOR_SOURCE_ADVANCED'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE execution_id='EXEC-DB-TRAIN-PR3004-20261021063500-R39555468919'
        AND operation_code='ACTUALIZACION_DB_LF'
        AND status='COMPLETED'
        AND manifest ? 'router_authority_receipt'
        AND manifest ? 'closure_evidence')<>1
  THEN RAISE EXCEPTION 'RW105_C1_TRAIN_CONTROL_NOT_CURRENT'; END IF;

  IF (SELECT count(*) FROM private.lf_profile_runtime_queue_v1
      WHERE request_id='70641106-60d9-450f-9f2e-4df52adfaec6'::uuid
        AND status='BLOCKED' AND error_code='LLAMA_TIMEOUT')<>1
     OR (SELECT count(*) FROM public.lf_operation_execution
         WHERE execution_id='EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6'
           AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM public.v_lf_operation_execution_judge
         WHERE execution_id='EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6'
           AND judge_result='FAIL' AND required_steps=11 AND required_steps_pass=7 AND fail_count=4)<>1
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id='EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6'
           AND step_id IN ('router','input_validate','context_admission')
           AND status='STEP_PASS_WITH_EVIDENCE')<>3
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id='EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6'
           AND step_id IN ('execute_profile','output_validate','semantic_judge','report_output'))<>0
  THEN RAISE EXCEPTION 'RW105_C1_PROFILE_REFERENCE_DRIFT'; END IF;

  IF (v_old#>'{action_specs_v1,RW1-05_C1}' IS NOT NULL)
     OR (v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C1}' IS NOT NULL)
  THEN RAISE EXCEPTION 'RW105_C1_ALREADY_BOUND'; END IF;

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
  IF v_count<>1 THEN RAISE EXCEPTION 'RW105_C1_METADATA_UPDATE_COUNT:%',v_count; END IF;

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
  THEN RAISE EXCEPTION 'RW105_C1_CONTRACT_OR_SOURCE_NOT_READY: action=% contract=% ready=% preflight=%',
       v_action::text,v_contract::text,v_ready::text,v_preflight::text; END IF;

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_ref,v_actor,
    'RW1-05_C1 verified-current differential consumer baseline. Five current gaps frozen: missing T2 semantic consumer, missing caller interaction, incomplete terminal Profile Runtime authority receipt, no post-RW1-04 Profile Runtime canary, and unreconciled queue/canonical terminal lifecycle. Merge Train is current governed control and requires no C1 repair. No consumer/runtime/ACL/operation/production mutation.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW105_C1_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi
        AND ((checkpoint_code='RW1-05_C1' AND status='DONE' AND evidence_ref=v_ref)
          OR (checkpoint_code IN ('RW1-05_C2','RW1-05_C3') AND status='PENDING' AND evidence_ref IS NULL)))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=v_wi AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'RW105_C1_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw105_c1$;
COMMIT;
