-- A16Q_C2: authoritative source pack and material-consumer test contract only.
-- Routing: ACT-0001 / ACTUALIZACION_DB_LF / Merge Train.
-- Does not close C2, run a model, create a DEMO or activate profiles.
BEGIN;
DO $a16q_c2$
DECLARE
  v_meta jsonb;
  v_next jsonb;
  v_source jsonb := $json${"inputs":{"assets":["ACT-0001","PERFIL-UI-ARCHITECT","ADAPTER-LF-SHELL-PROFILE-20260827","PROFILE_RUNTIME_API_SERVICE","PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],"events":[20302],"queries":["SELECT checkpoint_code,status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1126 ORDER BY sequence_no","SELECT operation_code,step_id,resolver_ref,required_evidence_keys FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_PERFIL_LF' ORDER BY execution_order","SELECT q.request_id,q.status,q.profile_code,length(q.input_literal) input_chars,encode(extensions.digest(convert_to(q.input_literal,'UTF8'),'sha256'),'hex') computed_sha,q.receipt->>'input_sha256' receipt_sha,q.receipt->>'execution_id' runtime_execution_id,q.receipt ? 'router_binding' router_bound,e.execution_id canonical_execution_id,e.manifest->>'input_sha256' manifest_sha FROM private.lf_profile_runtime_queue_v1 q LEFT JOIN public.lf_operation_execution e ON e.execution_id='EXEC-PROFILE-RUNTIME-'||q.request_id::text WHERE q.request_id='152a3d60-02b0-4bbf-b9fa-b83995b295d6'::uuid","SELECT status,count(*) AS n FROM private.lf_profile_runtime_queue_v1 GROUP BY status ORDER BY status","SELECT step_id,status,evidence_ref,evidence_payload->>'context_receipt_digest' context_digest FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-RUNTIME-152a3d60-02b0-4bbf-b9fa-b83995b295d6' ORDER BY step_order","SELECT codigo_activo,tipo_activo,estado_operativo,runtime_estado FROM public.lf_activos WHERE codigo_activo IN ('PERFIL-UI-ARCHITECT','PROFILE_RUNTIME_API_SERVICE','PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1','ACT-0001') ORDER BY codigo_activo"],"artifacts":["docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md","services/profile_runtime_api/profile_runtime_api/engine.py","services/profile_runtime_api/profile_runtime_api/app.py","sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_queue_worker.py","sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_batch_queue_worker.py","sandbox/lf_contract_gate_test/profile_execution_runtime/run_zero_cost_profile_request.py"],"db_objects":["public.lf_router_resolve_v1","public.lf_operation_execution","public.lf_operation_execution_steps","public.lf_operation_step_contracts","private.lf_profile_runtime_queue_v1","programacion.engineering_plan_units","programacion.engineering_work_checkpoints"]},"missing":[],"missing_typed":[],"verification_boundary":"READ_ONLY_HISTORICAL_BASELINE_MATERIAL_E2E_STILL_REQUIRED","expected_result":"For three case families, a single verified real path must bind literal, Router, chosen asset/operation, exclusions, current contracts and guards, actual consumer, model output and ledger receipts. Legacy SUCCEEDED and catalog do not suffice.","evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md"}$json$::jsonb;
  v_spec jsonb := $json${"schema_version":"ENGINEERING_ACTION_SPEC_V3","checkpoint_code":"A16Q_C2","checkpoint_title":"Salida real gobernada","status":"READY","action_kind":"BOUNDED_CHECKPOINT_TEST_AUTHORING","recipe_mode":"AUTHOR_AND_RUN_CHECKPOINT_TEST","contract_family":"BOUNDED_CHECKPOINT_TEST","contract_source":"EXPLICIT_ACTION_SPEC","precision":"EXACT_ROUTER_TO_REAL_CONSUMER_TRACE","requires_material_execution":true,"mutation_policy":"NO_DOMAIN_MUTATION_NONPRODUCTION_CANARY_ONLY","target":{"checkpoint":"A16Q_C2","declared_assets":["ACT-0001","PERFIL-UI-ARCHITECT","ADAPTER-LF-SHELL-PROFILE-20260827","PROFILE_RUNTIME_API_SERVICE","PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],"declared_events":[20302],"declared_objects":["public.lf_router_resolve_v1","public.lf_operation_execution","public.lf_operation_execution_steps","public.lf_operation_step_contracts","private.lf_profile_runtime_queue_v1","programacion.engineering_plan_units","programacion.engineering_work_checkpoints"],"declared_artifacts":[],"mutation_artifacts":[],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md","role":"EVIDENCE","purpose":"HISTORICAL_BASELINE_AND_FUTURE_E2E_CRITERIA","target_kind":"EXACT_EXISTING_FILE"}]},"expected":"Execute the same three request families through the governed Router and real authorized consumer in isolated non-production mode. Require same request/operation/source bindings, real RAW/output validations and canonical receipts. If any capability or consumer is missing, record GAP; never close from the historical baseline.","verification_queries":["SELECT checkpoint_code,status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1126 ORDER BY sequence_no","SELECT operation_code,step_id,resolver_ref,required_evidence_keys FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_PERFIL_LF' ORDER BY execution_order","SELECT q.request_id,q.status,q.profile_code,length(q.input_literal) input_chars,encode(extensions.digest(convert_to(q.input_literal,'UTF8'),'sha256'),'hex') computed_sha,q.receipt->>'input_sha256' receipt_sha,q.receipt->>'execution_id' runtime_execution_id,q.receipt ? 'router_binding' router_bound,e.execution_id canonical_execution_id,e.manifest->>'input_sha256' manifest_sha FROM private.lf_profile_runtime_queue_v1 q LEFT JOIN public.lf_operation_execution e ON e.execution_id='EXEC-PROFILE-RUNTIME-'||q.request_id::text WHERE q.request_id='152a3d60-02b0-4bbf-b9fa-b83995b295d6'::uuid","SELECT status,count(*) AS n FROM private.lf_profile_runtime_queue_v1 GROUP BY status ORDER BY status","SELECT step_id,status,evidence_ref,evidence_payload->>'context_receipt_digest' context_digest FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-RUNTIME-152a3d60-02b0-4bbf-b9fa-b83995b295d6' ORDER BY step_order","SELECT codigo_activo,tipo_activo,estado_operativo,runtime_estado FROM public.lf_activos WHERE codigo_activo IN ('PERFIL-UI-ARCHITECT','PROFILE_RUNTIME_API_SERVICE','PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1','ACT-0001') ORDER BY codigo_activo"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"cases_proven":3,"required_trace_fields_proven":13,"request_literal_sha_verified":true,"router_binding_current":true,"canonical_execution_id_bound":true,"scope_exclusions_preserved":true,"input_governance_current_or_not_applicable":true,"real_consumer_receipt_verified":true,"source_and_output_validator_readback":true,"negative_controls_block_pre_effect":true,"no_unintended_write":true}},"action_steps":["VERIFY_HISTORICAL_LITERAL_DIGEST_WITH_NO_EFFECT","RECORD_ROUTER_READ_ONLY_BASELINE_FOR_THREE_CASE_FAMILIES","OBTAIN_CURRENT_ROUTER_AND_CONSUMER_AUTHORITY_NO_AUTO_ACTIVATION","RUN_THREE_AUTHORIZED_ISOLATED_CONSUMER_TRACES","BIND_CANONICAL_EXECUTION_REQUEST_SOURCE_CONTEXT_RAW_VALIDATOR_AND_RECEIPT","EXERCISE_NEGATIVE_NO_ROUTER_SHA_DRIFT_EXCLUSION_AND_UNAUTHORIZED_PROFILE","RECORD_MATERIAL_ASSERTION_FROM_REAL_PROVIDER_ONLY","TRANSITION_C2_ONLY_AFTER_EXACT_POSTREADBACK"],"forbidden":["FAKE_ROUTER_BINDING_FROM_ADAPTER_ACTIVATION_SOURCE","INFER_FULL_E2E_FROM_HISTORY_OR_COMPLETED_STEPS","CREATE_PARALLEL_ROUTER_OR_ORCHESTRATOR","EXECUTE_HETZNER_LLAMA_OR_PAID_PROVIDER_WITHOUT_USER_RUNTIME_AUTHORITY","ACTIVATE_RUNTIME_OR_PROFILE","IMPLEMENT_DEMO_OR_PROFILE_SELECTION_IN_A16","CHANGE_C1_OR_C3","SYNTHETIC_PASS_WITHOUT_REAL_CONSUMER_RECEIPTS"],"cases":["PARTIAL_SCREEN_DEMO","FULL_SCOPE","TARGETED_MODIFICATION"],"mandatory_trace":["literal_request","router","resolved_asset","action","operation","scope_and_mode","selected_profiles_skills_adapters","input_governance_if_applicable","applicable_contracts_and_guards","real_consumer","authorized_result","receipts","readback"],"evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md"}$json$::jsonb;
  v_observed jsonb := $json${"schema":"PROGRAMMING_A16Q_C2_CONSUMER_TRACE_BASELINE_V1","state":"GAP_UNPROVEN_MATERIAL_E2E","checkpoint_pass":false,"exact_successful_request_id":"152a3d60-02b0-4bbf-b9fa-b83995b295d6","literal_chars":304,"literal_sha256":"d98ba31bb99ab1bf230be579d46479ece5960888b6c077070adc7c11ad4fccca","sha_input_queue_receipt_manifest_equal":true,"runtime_receipt_execution_id":"EJECUCION_PERFIL_LF:152a3d60-02b0-4bbf-b9fa-b83995b295d6","canonical_ledger_execution_id":"EXEC-PROFILE-RUNTIME-152a3d60-02b0-4bbf-b9fa-b83995b295d6","explicit_router_binding_in_success_receipt":false,"explicit_runtime_execution_mapping_attested":false,"material_consumer_end_to_end_proven":false,"case_router_statuses":{"PARTIAL_SCREEN_DEMO":{"status":"BLOCKED","code":"BLOCK_OPERATION_NOT_REGISTERED","type":"AUDIT","action":"CREATE"},"FULL_SCOPE":{"status":"BLOCKED","code":"BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED","type":"SKILL","action":"ASSET_INSPECTION"},"TARGETED_MODIFICATION":{"status":"BLOCKED","code":"BLOCK_EXECUTOR_CAPABILITY_UNATTESTED","candidate":"PERFIL-UI-ARCHITECT"}},"gaps":["A16Q-C2-G01","A16Q-C2-G02","A16Q-C2-G03","A16Q-C2-G04","A16Q-C2-G05","A16Q-C2-G06"],"source_doc":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md","production_activation":false,"golden_promoted":false}$json$::jsonb;
  v_check integer;
  v_literal_digest text;
BEGIN
  SELECT unit_metadata INTO STRICT v_meta
    FROM programacion.engineering_plan_units
   WHERE plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'
     AND unit_code='A16Q' AND id=807 AND work_item_id=1126
   FOR UPDATE;
  IF v_meta->>'schema' <> 'PROGRAMMING_A16Q_ARCHITECTURE_RESEARCH_V1'
     OR v_meta#>>'{action_specs_v1,A16Q_C1,status}' <> 'READY'
     OR v_meta#>'{action_specs_v1,A16Q_C2}' IS NOT NULL
     OR v_meta#>'{source_pack_v2,checkpoint_inputs,A16Q_C2}' IS NOT NULL
     OR v_meta#>'{a16q_c2_baseline_v1}' IS NOT NULL
     OR v_meta->>'production_activation' <> 'false'
     OR v_meta->>'golden_promoted' <> 'false'
  THEN RAISE EXCEPTION 'A16Q_C2_SOURCE_PRESTATE_DRIFT'; END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=1126 AND checkpoint_code='A16Q_C1' AND status='DONE') <> 1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=1126 AND checkpoint_code IN ('A16Q_C2','A16Q_C3') AND status='PENDING') <> 2
  THEN RAISE EXCEPTION 'A16Q_C2_CHECKPOINT_PRESTATE_DRIFT'; END IF;

  SELECT count(*), min(encode(extensions.digest(convert_to(q.input_literal,'UTF8'),'sha256'),'hex'))
    INTO v_check,v_literal_digest
    FROM private.lf_profile_runtime_queue_v1 q
    JOIN public.lf_operation_execution e
      ON e.execution_id='EXEC-PROFILE-RUNTIME-'||q.request_id::text
   WHERE q.request_id='152a3d60-02b0-4bbf-b9fa-b83995b295d6'::uuid
     AND q.status='SUCCEEDED'
     AND q.profile_code='PERFIL-UI-ARCHITECT'
     AND q.receipt->>'input_sha256'=encode(extensions.digest(convert_to(q.input_literal,'UTF8'),'sha256'),'hex')
     AND e.manifest->>'input_sha256'='sha256:'||q.receipt->>'input_sha256'
     AND e.status='COMPLETED';
  IF v_check<>1 OR v_literal_digest IS DISTINCT FROM
       'd98ba31bb99ab1bf230be579d46479ece5960888b6c077070adc7c11ad4fccca'
  THEN RAISE EXCEPTION 'A16Q_C2_HISTORICAL_LITERAL_SHA_DRIFT'; END IF;

  v_next := jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,A16Q_C2}',v_source,true);
  v_next := jsonb_set(v_next,'{action_specs_v1,A16Q_C2}',v_spec,true);
  v_next := jsonb_set(v_next,'{a16q_c2_baseline_v1}',v_observed,true);
  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_next
   WHERE id=807 AND unit_code='A16Q' AND work_item_id=1126;

  IF (SELECT count(*) FROM programacion.engineering_plan_units
       WHERE id=807 AND unit_metadata#>>'{action_specs_v1,A16Q_C2,action_kind}'='BOUNDED_CHECKPOINT_TEST_AUTHORING'
         AND unit_metadata#>>'{action_specs_v1,A16Q_C2,requires_material_execution}'='true'
         AND unit_metadata#>>'{a16q_c2_baseline_v1,state}'='GAP_UNPROVEN_MATERIAL_E2E'
         AND jsonb_array_length(unit_metadata#>'{action_specs_v1,A16Q_C2,cases}')=3
         AND jsonb_array_length(unit_metadata#>'{action_specs_v1,A16Q_C2,mandatory_trace}')=13
         AND unit_metadata#>'{action_specs_v1,A16Q_C3}' IS NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
           WHERE work_item_id=1126 AND checkpoint_code='A16Q_C2' AND status='PENDING')<>1
  THEN RAISE EXCEPTION 'A16Q_C2_SOURCE_POSTWRITE_READBACK_FAILED'; END IF;
END;
$a16q_c2$;
COMMIT;
