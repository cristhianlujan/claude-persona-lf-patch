-- Bind an existing, merged CI runner to RW1-01_C2 (NO C2 closure).
-- Source: PR #2879 merged by Train, commit e453818c3e6098a1d958eed57d6f4131c951d651.
-- Guard all scope, source, currentness and effects. Only the action-spec execution_route changes.
BEGIN;
DO $rw101_c2_bind$
DECLARE
 v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
 v_unit constant text := 'RW1-01';
 v_cp constant text := 'RW1-01_C2';
 v_md5 constant text := 'b3e6207a136d808173e39a6d9a1f1c94';
 v_route constant jsonb := jsonb_build_object(
   'provider','GITHUB_ACTIONS',
   'workflow_path','.github/workflows/lf-router-level2-advisory-tests.yml',
   'job_name','router-level2-advisory-contract',
   'check_name','router-level2-advisory-contract');
 v_old jsonb;
 v_new jsonb;
 v_spec jsonb;
 v_ready jsonb;
 v_packet jsonb;
 v_bad_packet jsonb;
 v_count int;
BEGIN
 SELECT unit_metadata INTO STRICT v_old FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code=v_unit
   AND work_item_id=1127 AND disposition='ASSIGNED'
   AND md5(unit_metadata::text)=v_md5
 FOR UPDATE;

 IF (SELECT count(*) FROM programacion.engineering_work_items
     WHERE id=1127 AND work_code='ROUTER-W1-01' AND status='IN_PROGRESS')<>1
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1127 AND checkpoint_code='RW1-01_C1' AND status='DONE')<>1
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1127 AND checkpoint_code IN ('RW1-01_C2','RW1-01_C3') AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'RW101_C2_BIND_WRONG_LIFECYCLE'; END IF;

 IF v_old#>>'{action_specs_v1,RW1-01_C2,status}' IS DISTINCT FROM 'READY'
    OR v_old#>>'{action_specs_v1,RW1-01_C2,action_kind}' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
    OR v_old#>>'{action_specs_v1,RW1-01_C2,test_execution_contract,authoring_required}' IS DISTINCT FROM 'false'
    OR v_old#>>'{action_specs_v1,RW1-01_C2,test_execution_contract,test_code}' IS DISTINCT FROM 'ENG_RW101_C2_REQUIREMENTS_ORACLE'
    OR v_old#>>'{action_specs_v1,RW1-01_C2,test_execution_contract,test_path}'
       IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py'
    OR v_old#>'{action_specs_v1,RW1-01_C2,test_execution_contract,execution_route}' IS NOT NULL
    OR v_old#>>'{source_pack_v2,checkpoint_inputs,RW1-01_C2,verification_boundary}'
       IS DISTINCT FROM 'RW101_C2_TEST_CORPUS_MATERIAL_ONLY_NOT_ROUTER_LIVE_E2E'
 THEN RAISE EXCEPTION 'RW101_C2_BIND_SOURCE_CONTRACT_DRIFT'; END IF;

 v_new:=jsonb_set(v_old,
   '{action_specs_v1,RW1-01_C2,test_execution_contract,execution_route}',v_route,true);
 IF (v_new #- '{action_specs_v1,RW1-01_C2,test_execution_contract,execution_route}') IS DISTINCT FROM v_old
 THEN RAISE EXCEPTION 'RW101_C2_BIND_UNRELATED_METADATA_CHANGED'; END IF;

 UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
 WHERE plan_code=v_plan AND unit_code=v_unit AND md5(unit_metadata::text)=v_md5;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'RW101_C2_BIND_UPDATE_COUNT:%',v_count; END IF;

 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(v_plan,v_unit,v_cp,v_spec,'{}'::jsonb);
 IF v_spec->>'status' IS DISTINCT FROM 'READY'
    OR v_ready->>'status' IS DISTINCT FROM 'READY'
    OR v_packet->>'status' IS DISTINCT FROM 'READY'
    OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
    OR v_packet->>'capability_mode' IS DISTINCT FROM 'RUN_EXISTING_DECLARED_CHECKPOINT_TEST'
    OR jsonb_array_length(coalesce(v_packet->'connector_plan','[]'::jsonb))<>3
    OR v_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'RUN_TEST'
    OR v_packet#>>'{connector_plan,1,operation}' IS DISTINCT FROM 'CHECKPOINT_ASSERTION_RECORD'
    OR v_packet#>>'{connector_plan,2,operation}' IS DISTINCT FROM 'CHECKPOINT_TRANSITION'
    OR v_packet#>>'{connector_plan,0,source_contract,ref_mode}' IS DISTINCT FROM 'EXACT_MERGED_SHA'
    OR v_packet#>>'{connector_plan,0,runner_contract,verified_run_id_required}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'RW101_C2_BIND_COMPILATION_OR_READINESS_NOT_READY'; END IF;

 v_bad_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
  v_plan,v_unit,v_cp,jsonb_set(v_spec,'{test_execution_contract,execution_route}',
    v_route-'check_name',true),'{}'::jsonb);
 IF v_bad_packet->>'status' IS DISTINCT FROM 'BLOCK_RUN_TEST_CI_BINDING_INCOMPLETE'
 THEN RAISE EXCEPTION 'RW101_C2_BIND_NEGATIVE_CHECK_MISSING_FALSE_PASS'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1127 AND checkpoint_code='RW1-01_C1' AND status='DONE')<>1
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1127 AND checkpoint_code IN ('RW1-01_C2','RW1-01_C3') AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'RW101_C2_BIND_CHECKPOINT_CHANGED'; END IF;
END
$rw101_c2_bind$;
COMMIT;
