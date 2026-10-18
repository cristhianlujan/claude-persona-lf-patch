-- RW1-02_C3: bind exact independent-review contract and frozen source pack only.
-- No checkpoint closure. C3 remains PENDING until a materially separate judge returns a valid terminal verdict.
BEGIN;
DO $rw102_c3_bind$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-02';
  v_cp constant text := 'RW1-02_C3';
  v_work_item constant bigint := 1128;
  v_prior_md5 constant text := '081e9a1e21d7b0050df66731561eef31';
  v_spec jsonb := $rw102c3spec${"status":"READY","schema_version":"ENGINEERING_ACTION_SPEC_V3","checkpoint_code":"RW1-02_C3","contract_source":"EXPLICIT_ACTION_SPEC","contract_family":"INDEPENDENT_ADVERSARIAL_REVIEW","precision":"EXACT_RW102_C3_INDEPENDENT_ARCHITECTURE_REVIEW_V1","action_kind":"MATERIALIZE_DECLARED_DELIVERABLE","recipe_mode":"EXECUTE_DECLARED_DELIVERABLE","mutation_policy":"TEST_ARTIFACT_ONLY","requires_material_execution":true,"expected":"A materially separate GPT Native judge independently recomputes the RW1-02 architecture competition before opening the producer result, executes at least 24 novel adversarial mutations, and returns PASS only if one valid final selection is supported by evidence with zero material blockers. No Router runtime, production, latency/cost, or GOLDEN claim.","target":{"checkpoint":"RW1-02_C3","declared_assets":["ACT-0001"],"declared_events":[21263],"declared_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","public.lf_error_knowledge","supabase_migrations.schema_migrations"],"declared_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_BLIND_JUDGE_HANDOFF_V1.md","role":"EVIDENCE","purpose":"BLIND_INDEPENDENT_JUDGE_PROTOCOL","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","role":"EVIDENCE","purpose":"NORMATIVE_WAVE_EXIT_CRITERION","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","role":"EVIDENCE","purpose":"NEUTRAL_SOURCE_BASELINE","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","role":"EVIDENCE","purpose":"COMPETITION_CORPUS","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py","role":"EVIDENCE","purpose":"COMPETITION_VALIDATOR","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"EVIDENCE","purpose":"MERGED_RUNNER","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json","role":"EVIDENCE","purpose":"PRODUCER_RESULT_POST_RAW1_ONLY","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V1.json","role":"MUTATION_TARGET","purpose":"INDEPENDENT_TERMINAL_VERDICT","target_kind":"EXACT_FILE"}],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_BLIND_JUDGE_HANDOFF_V1.md","role":"EVIDENCE","purpose":"BLIND_INDEPENDENT_JUDGE_PROTOCOL","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","role":"EVIDENCE","purpose":"NORMATIVE_WAVE_EXIT_CRITERION","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","role":"EVIDENCE","purpose":"NEUTRAL_SOURCE_BASELINE","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","role":"EVIDENCE","purpose":"COMPETITION_CORPUS","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py","role":"EVIDENCE","purpose":"COMPETITION_VALIDATOR","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-router-level2-advisory-tests.yml","role":"EVIDENCE","purpose":"MERGED_RUNNER","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json","role":"EVIDENCE","purpose":"PRODUCER_RESULT_POST_RAW1_ONLY","target_kind":"EXACT_EXISTING_FILE"}],"mutation_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V1.json","role":"MUTATION_TARGET","purpose":"INDEPENDENT_TERMINAL_VERDICT","target_kind":"EXACT_FILE"}]},"forbidden":["SAME_PRODUCER_REVIEW","OPEN_PRODUCER_RESULT_BEFORE_RAW1","OPEN_PR2924_OR_PR2925_CONTEXT_BEFORE_RAW1","USE_PRODUCER_CHAT_MEMORY","USE_RFC2872_CONTENT_AS_AUTHORITY","COPY_C2_SELECTION_WITHOUT_INDEPENDENT_RECOMPUTATION","CLAIM_ROUTER_RUNTIME_PASS","CLAIM_PRODUCTION_EFFECT","INVENT_LATENCY_OR_COST","SELECT_ARCHITECTURE_WITH_UNRESOLVED_MATERIAL_BLOCKER","DIRECT_DB_MUTATION_OUTSIDE_TRAIN","MERGE_WITHOUT_CI_PASE_TRAIN","REOPEN_C1_OR_C2","CREATE_UNDECLARED_SHARED_ABSTRACTION"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"blind_verdict":"PASS","independent_judge_attested":true,"judge_identity_ref_present":true,"source_freeze_verified":true,"producer_result_hidden_until_raw1":true,"independent_recomputation_completed":true,"public_case_count":36,"requirements_n01_n12_covered":true,"candidate_count":4,"eligible_candidate_count":3,"adversarial_mutations_at_least_24":true,"a_mutations_at_least_6":true,"c_mutations_at_least_6":true,"selection_policy_mutations_at_least_4":true,"novel_falsifiers_at_least_2":true,"all_semantically_invalid_mutations_rejected":true,"material_blockers":0,"final_selection_present":true,"final_selection_valid":true,"selection_supported_by_evidence":true,"raw1_frozen":true,"raw2_created":true,"raw1_unchanged_after_reveal":true,"latency_cost_not_invented":true,"no_router_runtime_claim":true,"no_production_mutation":true}},"verification_queries":["SELECT c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1128 ORDER BY c.sequence_no","SELECT md5(unit_metadata::text) metadata_md5, unit_metadata#>'{action_specs_v1,RW1-02_C3}' c3_spec FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-02'"],"action_steps":["FREEZE_EXACT_MAIN_AND_AUTHORIZED_SOURCE_BLOBS","START_MATERIALLY_SEPARATE_GPT_NATIVE_JUDGE","HIDE_PRODUCER_RESULT_UNTIL_RAW1","INDEPENDENTLY_RECOMPUTE_COMPETITION","EXECUTE_AT_LEAST_24_INDEPENDENT_ADVERSARIAL_MUTATIONS","FREEZE_RAW1_WITH_SHA256","OPEN_AND_CONTRAST_PRODUCER_RESULT_AND_EXACT_MAIN_RECEIPT","VERIFY_RAW1_UNCHANGED","MATERIALIZE_INDEPENDENT_VERDICT","PERSIST_ASSERTION_RECEIPT_ONLY_FROM_REAL_INDEPENDENT_PASS","PERSIST_C3_DONE_ONLY_AFTER_ASSERTION_AND_READBACK"],"evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V1.json"}$rw102c3spec$::jsonb;
  v_source jsonb := $rw102c3source${"inputs":{"assets":["ACT-0001"],"events":[21263],"queries":["SELECT c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1128 ORDER BY c.sequence_no","SELECT md5(unit_metadata::text) metadata_md5, unit_metadata#>'{action_specs_v1,RW1-02_C3}' c3_spec FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-02'"],"db_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","public.lf_error_knowledge","supabase_migrations.schema_migrations"],"artifacts":["docs/programming-agent/router_wave/RW1_02_C3_BLIND_JUDGE_HANDOFF_V1.md","docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py",".github/workflows/lf-router-level2-advisory-tests.yml","docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json"]},"missing":[],"missing_typed":[],"expected_result":"Materially separate independent architecture review with producer result hidden until frozen RAW1, at least 24 independent adversarial mutations, and a defensible final selection or a fail-closed REVISE/INSUFFICIENT_EVIDENCE.","verification_boundary":"RW102_C3_INDEPENDENT_ARCHITECTURE_ASSURANCE_ONLY_NOT_ROUTER_RUNTIME_OR_PRODUCTION","source_snapshot_commit":"5d7f30580d4c6bb557e51943693c4b95e192900e","source_git_blobs":{"handoff":"8a17094dbf09664ed4a720f24cbe8012cf039a00","wave":"4bb64d568c3f005cf454fb223b4a5ed699c34504","c1_baseline":"470979c9b9a0dd9a728601b6ec5f577d7445f8b5","c2_corpus":"f00a202f5983931d6ae41121fcdfea96808c094b","c2_result":"1f2b91ff5fe4bb3d0f2b764222425623996c2eac","c2_validator":"54517132aa0ab890b1e266639a19cbe08f7a5d9a","workflow":"b1782a0944868b967fc88de530499266668c2b99"},"c2_material_receipt":{"run_id":"39168605114","job_id":"117796748955","exact_main_sha":"e8770f89035ad7d80a4d53dc6260503d474d1a9f","conclusion":"success","assertion_receipt_sha256":"003a55b9fbaba17fbc1921ff60b31961562acc9f2ffc31f9d7f9af8a749abbed"}}$rw102c3source$::jsonb;
  v_old jsonb;
  v_new jsonb;
  v_compiled jsonb;
  v_contract jsonb;
  v_ready jsonb;
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
         WHERE work_item_id=v_work_item
           AND ((checkpoint_code='RW1-02_C1' AND status='DONE')
             OR (checkpoint_code='RW1-02_C2' AND status='DONE'
                 AND assertion_receipt->>'passed'='true'
                 AND assertion_receipt_sha256='003a55b9fbaba17fbc1921ff60b31961562acc9f2ffc31f9d7f9af8a749abbed')
             OR (checkpoint_code='RW1-02_C3' AND status='PENDING'
                 AND evidence_ref IS NULL AND assertion_receipt IS NULL)))<>3
  THEN RAISE EXCEPTION 'RW102_C3_BIND_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>'{action_specs_v1,RW1-02_C3}' IS NOT NULL
     OR v_old#>'{source_pack_v2,checkpoint_inputs,RW1-02_C3}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW102_C3_BIND_ALREADY_PRESENT'; END IF;

  v_new:=jsonb_set(
    jsonb_set(v_old,'{action_specs_v1,RW1-02_C3}',v_spec,true),
    '{source_pack_v2,checkpoint_inputs,RW1-02_C3}',v_source,true
  );

  IF ((v_new #- '{action_specs_v1,RW1-02_C3}') #- '{source_pack_v2,checkpoint_inputs,RW1-02_C3}')
       IS DISTINCT FROM v_old
  THEN RAISE EXCEPTION 'RW102_C3_BIND_UNRELATED_METADATA_CHANGED'; END IF;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW102_C3_BIND_UPDATE_COUNT:%',v_count; END IF;

  v_compiled:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_compiled);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);

  IF v_compiled->>'status' IS DISTINCT FROM 'READY'
     OR v_compiled->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready->>'execution_capability' IS DISTINCT FROM 'WRITE_GIT'
  THEN RAISE EXCEPTION 'RW102_C3_BIND_COMPILED_CONTRACT_NOT_READY:spec=% contract=% ready=%',
       v_compiled::text,v_contract::text,v_ready::text; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C3_BIND_MUST_PRESERVE_PENDING'; END IF;
END
$rw102_c3_bind$;
COMMIT;
