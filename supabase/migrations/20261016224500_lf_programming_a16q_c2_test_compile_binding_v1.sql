-- A16Q_C2: compile the existing BOUNDED_CHECKPOINT_TEST pipeline, not a new executor.
-- Authoring is Git-only; executable proof still requires real authorized consumer.
-- ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
BEGIN;
DO $a16q_c2_test$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_test jsonb := $payload${"mode":"AUTHORED_NEGATIVE","test_code":"ENG_A16Q_C2_ROUTER_CONSUMER_E2E","test_path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/a16q/a16q_c2_router_consumer_trace.py","synthetic_pass":"FORBIDDEN","negative_required":true,"authoring_required":true,"semantic_authority":"CANONICAL_PLAN_EXIT_CRITERION","fallback_case_discovery":"FORBIDDEN","canonical_exit_criterion":"Demostración de consumo real extremo a extremo, no solo diagrama","checkpoint_title_context":"A16Q_C2","declared_queries":["SELECT checkpoint_code,status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1126 ORDER BY sequence_no","SELECT operation_code,step_id,resolver_ref FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_PERFIL_LF' ORDER BY execution_order","SELECT status,count(*) FROM private.lf_profile_runtime_queue_v1 GROUP BY status ORDER BY status"],"declared_objects":["public.lf_router_resolve_v1","public.lf_operation_execution","public.lf_operation_execution_steps","private.lf_profile_runtime_queue_v1","programacion.engineering_work_checkpoints"]}$payload$::jsonb;
 v_target jsonb := $payload${"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/a16q/a16q_c2_router_consumer_trace.py","role":"MUTATION_TARGET","purpose":"CHECKPOINT_TEST_ARTIFACT","target_kind":"EXACT_NEW_OR_UPDATE_FILE"}$payload$::jsonb;
 v_meta jsonb;
 v_spec jsonb;
 v_new_spec jsonb;
 v_packet jsonb;
 v_ready jsonb;
BEGIN
 SELECT unit_metadata INTO STRICT v_meta
   FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code='A16Q' AND id=807 AND work_item_id=1126
  FOR UPDATE;
 v_spec:=v_meta#>'{action_specs_v1,A16Q_C2}';
 IF v_spec IS NULL OR v_spec->>'status'<>'READY'
    OR v_spec->>'action_kind'<>'BOUNDED_CHECKPOINT_TEST_AUTHORING'
    OR v_spec->>'requires_material_execution'<>'true'
    OR v_spec->>'contract_family'<>'BOUNDED_CHECKPOINT_TEST'
    OR v_spec ? 'test_execution_contract'
    OR v_meta#>>'{a16q_c2_baseline_v1,state}' <> 'GAP_UNPROVEN_MATERIAL_E2E'
    OR coalesce(jsonb_array_length(v_meta#>'{action_specs_v1,A16Q_C2,cases}'),0)<>3
    OR coalesce(jsonb_array_length(v_meta#>'{action_specs_v1,A16Q_C2,mandatory_trace}'),0)<>13
    OR v_meta->>'production_activation'<>'false'
    OR v_meta->>'golden_promoted'<>'false'
 THEN RAISE EXCEPTION 'A16Q_C2_TEST_BINDING_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1126 AND checkpoint_code='A16Q_C1' AND status='DONE')<>1
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1126 AND checkpoint_code IN ('A16Q_C2','A16Q_C3') AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'A16Q_C2_TEST_BINDING_CHECKPOINT_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_spec#>'{target,mutation_artifacts}','[]'::jsonb)) a(value))
 THEN RAISE EXCEPTION 'A16Q_C2_UNEXPECTED_MUTATION_TARGET'; END IF;
 v_new_spec:=jsonb_set(v_spec,'{test_execution_contract}',v_test,true);
 v_new_spec:=jsonb_set(v_new_spec,'{target,mutation_artifacts}',jsonb_build_array(v_target),true);
 v_new_spec:=jsonb_set(v_new_spec,'{target,declared_artifacts}',jsonb_build_array(v_target),true);
 v_packet:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v(
    jsonb_build_object('status','READY'),v_plan,'A16Q','A16Q_C2',v_new_spec);
 IF v_packet->>'status'<>'READY'
   OR v_packet->>'execution_capability'<>'RUN_TEST'
   OR v_packet->>'execution_allowed'<>'true'
   OR coalesce(jsonb_array_length(v_packet->'connector_plan'),0)<>4
 THEN RAISE EXCEPTION 'A16Q_C2_TEST_COMPILER_NOT_READY:%',v_packet->>'status'; END IF;
 UPDATE programacion.engineering_plan_units
    SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,A16Q_C2}',v_new_spec,true)
  WHERE id=807 AND unit_code='A16Q' AND work_item_id=1126;

 IF (SELECT count(*) FROM programacion.engineering_plan_units
       WHERE id=807
         AND unit_metadata#>>'{action_specs_v1,A16Q_C2,test_execution_contract,test_code}'='ENG_A16Q_C2_ROUTER_CONSUMER_E2E'
         AND unit_metadata#>>'{action_specs_v1,A16Q_C2,test_execution_contract,canonical_exit_criterion}'='Demostración de consumo real extremo a extremo, no solo diagrama'
         AND unit_metadata#>>'{action_specs_v1,A16Q_C2,target,mutation_artifacts,0,path}'=v_target->>'path'
         AND unit_metadata#>>'{a16q_c2_baseline_v1,state}'='GAP_UNPROVEN_MATERIAL_E2E'
         AND unit_metadata#>'{action_specs_v1,A16Q_C3}' IS NULL
         AND unit_metadata->>'production_activation'='false'
         AND unit_metadata->>'golden_promoted'='false')<>1
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=1126 AND checkpoint_code='A16Q_C2' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'A16Q_C2_TEST_BINDING_POSTWRITE_DRIFT'; END IF;
END;
$a16q_c2_test$;
COMMIT;
