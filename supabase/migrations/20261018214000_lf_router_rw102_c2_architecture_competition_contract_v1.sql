-- RW1-02_C2: bind executable architecture-competition contract and exact authored artifacts only.
-- C2 remains PENDING until an exact-main GitHub Actions runner receipt is consumed by a later governed close.
BEGIN;
DO $rw102_c2_contract$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-02';
  v_cp constant text := 'RW1-02_C2';
  v_work_item constant bigint := 1128;
  v_prior_md5 constant text := '967a5c755c4a1d108b1f79c27a084f02';
  v_spec jsonb := $rw102c2spec${"status":"READY","schema_version":"ENGINEERING_ACTION_SPEC_V3","checkpoint_code":"RW1-02_C2","contract_source":"EXPLICIT_ACTION_SPEC","contract_family":"BOUNDED_CHECKPOINT_TEST","precision":"EXACT_RW102_ARCHITECTURE_COMPETITION_V1","action_kind":"BOUNDED_CHECKPOINT_TEST_AUTHORING","recipe_mode":"AUTHOR_AND_RUN_CHECKPOINT_TEST","mutation_policy":"TEST_ARTIFACT_ONLY","requires_material_execution":true,"expected":"Execute one neutral 36-case design-contract benchmark against three eligible architectures plus the current baseline. C2 may provisionally select an architecture only from recomputed evidence; C3 remains the independent review. No Router runtime, production, latency or cost claim.","target":{"checkpoint":"RW1-02_C2","declared_assets":["ACT-0001"],"declared_events":[21263],"declared_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","supabase_migrations.schema_migrations"],"declared_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","role":"MUTATION_TARGET","purpose":"ARCHITECTURE_COMPETITION_CORPUS","target_kind":"EXACT_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json","role":"MUTATION_TARGET","purpose":"RECOMPUTED_COMPETITION_RESULT","target_kind":"EXACT_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py","role":"MUTATION_TARGET","purpose":"EXECUTABLE_NEUTRAL_VALIDATOR","target_kind":"EXACT_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"MUTATION_TARGET","purpose":"EXISTING_ROUTER_TEST_RUNNER_EXTENSION","target_kind":"EXACT_EXISTING_FILE"}],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","role":"EVIDENCE","purpose":"C1_NEUTRAL_BASELINE","target_kind":"EXACT_EXISTING_FILE"}],"mutation_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","role":"MUTATION_TARGET","purpose":"ARCHITECTURE_COMPETITION_CORPUS","target_kind":"EXACT_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json","role":"MUTATION_TARGET","purpose":"RECOMPUTED_COMPETITION_RESULT","target_kind":"EXACT_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py","role":"MUTATION_TARGET","purpose":"EXECUTABLE_NEUTRAL_VALIDATOR","target_kind":"EXACT_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"MUTATION_TARGET","purpose":"EXISTING_ROUTER_TEST_RUNNER_EXTENSION","target_kind":"EXACT_EXISTING_FILE"}]},"forbidden":["CLAIM_ROUTER_RUNTIME_PASS","CLAIM_PRODUCTION_EFFECT","INVENT_LATENCY_OR_COST","TREAT_BASELINE_AS_ELIGIBLE_WINNER","USE_WEIGHTED_SCORE_TO_HIDE_HARD_FAILURE","ALLOW_SEMANTIC_SPECIALIST_TO_DISCOVER_ROUTE_OR_AUTHORIZE_EFFECT","SELECT_ARCHITECTURE_WITH_HARD_FAILURE","MUTATE_ROUTER_RUNTIME","REOPEN_C1","CLOSE_C2_WITHOUT_REAL_RUNNER_RECEIPT","CLOSE_C3_FROM_C2","MERGE_WITHOUT_CI_PASE_TRAIN"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"test_passed":true,"test_exit_code":0,"corpus_cases":36,"requirements_covered":12,"candidate_count":4,"eligible_candidate_count":3,"hard_pass_candidates":2,"provisional_selection":"A_MIN_ROUTER_SEMANTIC_SPECIALIST","negative_probes_detected_at_least":16,"result_recomputed_exact":true,"source_sha256_matches":true,"real_python_runner_receipt":true,"baseline_not_eligible":true,"actual_latency_measured":false,"actual_cost_measured":false,"no_router_runtime_claim":true,"no_production_mutation":true}},"verification_queries":["SELECT c.checkpoint_code,c.status,c.evidence_ref,w.status work_status FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_work_items w ON w.id=c.work_item_id WHERE c.work_item_id=1128 ORDER BY c.sequence_no","SELECT md5(unit_metadata::text) metadata_md5, unit_metadata#>'{action_specs_v1,RW1-02_C1}' c1_spec FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-02'"],"test_execution_contract":{"mode":"AUTHORED_NEGATIVE","test_code":"ENG_RW102_C2_ARCHITECTURE_COMPETITION","test_path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py","corpus_path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","result_path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json","synthetic_pass":"FORBIDDEN","declared_objects":["programacion.engineering_work_checkpoints","supabase_migrations.schema_migrations"],"declared_queries":["SELECT c.checkpoint_code,c.status,c.evidence_ref,w.status work_status FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_work_items w ON w.id=c.work_item_id WHERE c.work_item_id=1128 ORDER BY c.sequence_no","SELECT md5(unit_metadata::text) metadata_md5, unit_metadata#>'{action_specs_v1,RW1-02_C1}' c1_spec FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-02'"],"negative_required":true,"authoring_required":false,"semantic_authority":"RW102_C1_FROZEN_NEUTRAL_BASELINE","fallback_case_discovery":"FORBIDDEN","canonical_exit_criterion":"Arquitectura elegida mediante evidencia comparativa y falsificadores, no por conservar código ni por complacer una propuesta previa.","checkpoint_title_context":"RW1-02_C2"},"action_steps":["VERIFY_EXACT_C1_SOURCE_AND_COMPETITION_ARTIFACTS","RUN_PYTHON_COMPILE_AND_EXACT_RECOMPUTATION","RUN_16_NEGATIVE_PROBES","ASSERT_36_CASES_N01_N12_AND_FOUR_CANDIDATES","ASSERT_HARD_FAILURES_ELIMINATE_CANDIDATES","ASSERT_PROVISIONAL_SELECTION_PENDING_C3","REJECT_RUNTIME_LATENCY_COST_AND_PRODUCTION_CLAIMS","PERSIST_ASSERTION_RECEIPT_ONLY_FROM_REAL_RUNNER","PERSIST_C2_DONE_ONLY_AFTER_RECEIPT_READBACK"],"evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json"}$rw102c2spec$::jsonb;
  v_source jsonb := $rw102c2source${"inputs":{"assets":["ACT-0001"],"events":[21263],"queries":["SELECT c.checkpoint_code,c.status,c.evidence_ref,w.status work_status FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_work_items w ON w.id=c.work_item_id WHERE c.work_item_id=1128 ORDER BY c.sequence_no","SELECT md5(unit_metadata::text) metadata_md5, unit_metadata#>'{action_specs_v1,RW1-02_C1}' c1_spec FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-02'"],"db_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","supabase_migrations.schema_migrations"],"artifacts":["docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json","sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py",".github/workflows/lf-router-level2-advisory-tests.yml"]},"missing":[],"missing_typed":[],"expected_result":"Real GitHub Actions execution of the exact merged 36-case architecture-design competition plus 16 negative probes. Provisional winner remains subject to C3 independent review.","verification_boundary":"RW102_C2_EXECUTABLE_DESIGN_BENCHMARK_ONLY_NOT_ROUTER_RUNTIME_OR_PRODUCTION","source_git_blobs":{"c1_baseline":"470979c9b9a0dd9a728601b6ec5f577d7445f8b5","corpus":"f00a202f5983931d6ae41121fcdfea96808c094b","result":"1f2b91ff5fe4bb3d0f2b764222425623996c2eac","validator":"54517132aa0ab890b1e266639a19cbe08f7a5d9a","workflow":"b1782a0944868b967fc88de530499266668c2b99"}}$rw102c2source$::jsonb;
  v_old jsonb;
  v_new jsonb;
  v_compiled jsonb;
  v_contract jsonb;
  v_packet jsonb;
  v_count integer;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit
    AND work_item_id=v_work_item AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_work_item AND work_code='ROUTER-W1-02' AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code='RW1-02_C1'
           AND status='DONE' AND evidence_ref IS NOT NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code IN ('RW1-02_C2','RW1-02_C3')
           AND status='PENDING')<>2
  THEN RAISE EXCEPTION 'RW102_C2_CONTRACT_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>'{action_specs_v1,RW1-02_C2}' IS NOT NULL
     OR v_old#>'{source_pack_v2,checkpoint_inputs,RW1-02_C2}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW102_C2_CONTRACT_ALREADY_BOUND'; END IF;

  v_new:=jsonb_set(
    jsonb_set(v_old,'{action_specs_v1,RW1-02_C2}',v_spec,true),
    '{source_pack_v2,checkpoint_inputs,RW1-02_C2}',v_source,true
  );

  IF ((v_new #- '{action_specs_v1,RW1-02_C2}') #- '{source_pack_v2,checkpoint_inputs,RW1-02_C2}')
       IS DISTINCT FROM v_old
  THEN RAISE EXCEPTION 'RW102_C2_CONTRACT_UNRELATED_METADATA_CHANGED'; END IF;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW102_C2_CONTRACT_UPDATE_COUNT:%',v_count; END IF;

  v_compiled:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_compiled);
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(v_plan,v_unit,v_cp,v_compiled,'{}'::jsonb);

  IF v_compiled->>'status' IS DISTINCT FROM 'READY'
     OR v_compiled->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_packet->>'status' IS DISTINCT FROM 'BLOCK_RUN_TEST_CI_BINDING_INCOMPLETE'
  THEN RAISE EXCEPTION 'RW102_C2_CONTRACT_COMPILE_STATE_UNEXPECTED:spec=% contract=% packet=%',
       v_compiled::text,v_contract::text,v_packet::text; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-02_C1' AND status='DONE')
          OR (checkpoint_code IN ('RW1-02_C2','RW1-02_C3')
              AND status='PENDING' AND evidence_ref IS NULL)))<>3
  THEN RAISE EXCEPTION 'RW102_C2_CONTRACT_CHANGED_CHECKPOINT_STATE'; END IF;
END
$rw102_c2_contract$;
COMMIT;
