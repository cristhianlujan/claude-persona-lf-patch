-- RW1-01_C2: bind only the exact material test contract; no checkpoint closure.
BEGIN;
DO $rw101_c2$
DECLARE
 v_plan constant text:='LF_ROUTER_ARCHITECTURE_WAVE_V1';
 v_unit constant text:='RW1-01';
 v_prior_md5 constant text:='7903d2b26f61d6c82c2e0d16e40234f4';
 v_spec jsonb:='{"status":"READY","schema_version":"ENGINEERING_ACTION_SPEC_V3","checkpoint_code":"RW1-01_C2","contract_source":"EXPLICIT_ACTION_SPEC","contract_family":"BOUNDED_CHECKPOINT_TEST","precision":"EXACT_ROUTER_REQUIREMENTS_ORACLE_C2","action_kind":"BOUNDED_CHECKPOINT_TEST_AUTHORING","recipe_mode":"AUTHOR_AND_RUN_CHECKPOINT_TEST","mutation_policy":"TEST_ARTIFACT_ONLY","requires_material_execution":true,"expected":"Execute the 30-case requirements-first oracle and Python self-test, preserve all 12 requirements, 9 families and detect both semantic and effect-authorization false passes. No live Router PASS or E2E claim.","target":{"checkpoint":"RW1-01_C2","declared_assets":["ACT-0001"],"declared_events":[21263],"declared_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","supabase_migrations.schema_migrations"],"declared_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py","role":"MUTATION_TARGET","purpose":"CHECKPOINT_TEST_ARTIFACT","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json","role":"EVIDENCE","purpose":"REQUIREMENTS_ORACLE","target_kind":"EXACT_EXISTING_FILE"}],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_ORACLE_REVIEW_EXECUTED_V1.md","role":"EVIDENCE","purpose":"SEPARATE_JS_STRUCTURAL_REVIEW_NOT_PYTHON_RUN","target_kind":"EXACT_EXISTING_FILE"}],"mutation_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py","role":"MUTATION_TARGET","purpose":"CHECKPOINT_TEST_ARTIFACT","target_kind":"EXACT_EXISTING_FILE"}]},"forbidden":["CLAIM_ROUTER_WORKS_FROM_FIXTURES","CLAIM_PYTHON_RAN_WITHOUT_RUNNER_RECEIPT","CLAIM_E2E_FROM_JSON_SHAPE","INFER_AUTHORITY_FROM_TARGET_HINT","MUTATE_ROUTER_OR_TRAIN","REOPEN_C1","MERGE_WITHOUT_CI_PASE_TRAIN"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"test_passed":true,"test_exit_code":0,"corpus_cases":30,"requirements_covered":12,"families_covered":9,"negative_probes_detected_at_least":12,"source_sha256_matches":true,"real_python_runner_receipt":true,"no_authority_effect":true,"no_e2e_claim":true}},"verification_queries":["SELECT c.checkpoint_code,c.status,u.unit_code,w.status work_status FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_items w ON w.id=u.work_item_id JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id WHERE u.plan_code=''LF_ROUTER_ARCHITECTURE_WAVE_V1'' AND u.unit_code=''RW1-01'' ORDER BY c.sequence_no","SELECT version,name,idempotency_key FROM supabase_migrations.schema_migrations WHERE name IN (''lf_router_wave_rw101_c1_source_bind_v1'',''lf_router_rw101_c1_governed_close_v1'') ORDER BY version"],"test_execution_contract":{"mode":"AUTHORED_NEGATIVE","test_code":"ENG_RW101_C2_REQUIREMENTS_ORACLE","test_path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py","synthetic_pass":"FORBIDDEN","declared_objects":["programacion.engineering_work_checkpoints","supabase_migrations.schema_migrations"],"declared_queries":["SELECT c.checkpoint_code,c.status,u.unit_code,w.status work_status FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_items w ON w.id=u.work_item_id JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id WHERE u.plan_code=''LF_ROUTER_ARCHITECTURE_WAVE_V1'' AND u.unit_code=''RW1-01'' ORDER BY c.sequence_no","SELECT version,name,idempotency_key FROM supabase_migrations.schema_migrations WHERE name IN (''lf_router_wave_rw101_c1_source_bind_v1'',''lf_router_rw101_c1_governed_close_v1'') ORDER BY version"],"negative_required":true,"authoring_required":false,"semantic_authority":"CANONICAL_PLAN_EXIT_CRITERION","fallback_case_discovery":"FORBIDDEN","canonical_exit_criterion":"Matriz de necesidades completa y adversarial, oráculos versionados, ningún requisito derivado de un bloqueo observado por sí solo.","checkpoint_title_context":"RW1-01_C2"},"action_steps":["VERIFY_CURRENT_SHA_OF_CORPUS_AND_VALIDATOR","RUN_PYTHON_COMPILE_AND_CORPUS_CHECK","RUN_PYTHON_SELFTEST_NEGATIVE","ASSERT_30_CASE_12_NEED_9_FAMILY_COVERAGE","REJECT_FAKE_CI_RECEIPTS_AND_E2E_CLAIMS","PERSIST_ASSERTION_RECEIPT_ONLY_FROM_REAL_RUNNER","PERSIST_C2_DONE_ONLY_AFTER_RECEIPT_READBACK"],"evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json"}'::jsonb;
 v_source jsonb:='{"inputs":{"assets":["ACT-0001"],"events":[21263],"queries":["SELECT c.checkpoint_code,c.status,u.unit_code,w.status work_status FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_items w ON w.id=u.work_item_id JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id WHERE u.plan_code=''LF_ROUTER_ARCHITECTURE_WAVE_V1'' AND u.unit_code=''RW1-01'' ORDER BY c.sequence_no","SELECT version,name,idempotency_key FROM supabase_migrations.schema_migrations WHERE name IN (''lf_router_wave_rw101_c1_source_bind_v1'',''lf_router_rw101_c1_governed_close_v1'') ORDER BY version"],"db_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","supabase_migrations.schema_migrations"],"artifacts":["docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json","sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py","docs/programming-agent/router_wave/RW1_01_ORACLE_REVIEW_EXECUTED_V1.md"]},"missing":[],"missing_typed":[],"expected_result":"Material test execution of frozen 30-case corpus with 12 requirements and real Python negative probes, not just synthetic JSON assertions.","verification_boundary":"RW101_C2_TEST_CORPUS_MATERIAL_ONLY_NOT_ROUTER_LIVE_E2E"}'::jsonb;
 v_new jsonb;
 v_count integer;
BEGIN
 IF (SELECT count(*) FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
    JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id
    WHERE u.plan_code=v_plan AND u.unit_code=v_unit
      AND md5(u.unit_metadata::text)=v_prior_md5
      AND u.work_item_id=1127 AND u.plan_event_id=21263
      AND u.disposition='ASSIGNED'
      AND w.status='IN_PROGRESS' AND c.checkpoint_code='RW1-01_C1' AND c.status='DONE'
      AND NOT (u.unit_metadata#>'{action_specs_v1,RW1-01_C2}' IS NOT NULL)
      AND NOT (u.unit_metadata#>'{source_pack_v2,checkpoint_inputs,RW1-01_C2}' IS NOT NULL)
      )<>1
 THEN RAISE EXCEPTION 'RW101_C2_PREREQUISITE_OR_SOURCE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1127 AND checkpoint_code IN ('RW1-01_C2','RW1-01_C3')
       AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'RW101_C2_FUTURE_CHECKPOINTS_CHANGED'; END IF;
 v_new:=(SELECT jsonb_set(
    jsonb_set(u.unit_metadata,'{action_specs_v1,RW1-01_C2}',v_spec,true),
    '{source_pack_v2,checkpoint_inputs,RW1-01_C2}',v_source,true)
   FROM programacion.engineering_plan_units u
   WHERE u.plan_code=v_plan AND u.unit_code=v_unit);
 IF v_new#>>'{action_specs_v1,RW1-01_C2,action_kind}' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
    OR coalesce((v_new#>>'{action_specs_v1,RW1-01_C2,requires_material_execution}')::boolean,false) IS NOT TRUE
    OR jsonb_array_length(v_new#>'{source_pack_v2,checkpoint_inputs,RW1-01_C2,inputs,queries}')<>2
 THEN RAISE EXCEPTION 'RW101_C2_MATERIAL_TEST_CONTRACT_INVALID'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
 WHERE plan_code=v_plan AND unit_code=v_unit AND md5(unit_metadata::text)=v_prior_md5;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'RW101_C2_BOUND_ROW_COUNT:%',v_count; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1127 AND checkpoint_code IN ('RW1-01_C2','RW1-01_C3')
       AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'RW101_C2_DID_NOT_PRESERVE_PENDING'; END IF;
END
$rw101_c2$;
COMMIT;
