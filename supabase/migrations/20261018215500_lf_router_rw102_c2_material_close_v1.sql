-- RW1-02_C2: bind the exact merged GitHub Actions runner receipt, record assertion, and close C2.
-- Evidence scope is the executable architecture-design benchmark only.
-- No Router runtime, production, latency/cost, GOLDEN, or C3 claim.
BEGIN;
DO $rw102_c2_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-02';
  v_cp constant text := 'RW1-02_C2';
  v_work_item constant bigint := 1128;
  v_actor constant text := 'LF_ROUTER_RW102_C2_MATERIAL_CLOSE_20261018';
  v_prior_md5 constant text := '4e3b30093585f2b2e04c5a50e778c218';

  v_main constant text := 'e8770f89035ad7d80a4d53dc6260503d474d1a9f';
  v_run constant text := '39168605114';
  v_job constant text := '117796748955';
  v_evidence constant text := 'https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39168605114/job/117796748955';

  v_corpus_blob constant text := 'f00a202f5983931d6ae41121fcdfea96808c094b';
  v_result_blob constant text := '1f2b91ff5fe4bb3d0f2b764222425623996c2eac';
  v_validator_blob constant text := '54517132aa0ab890b1e266639a19cbe08f7a5d9a';
  v_workflow_blob constant text := 'b1782a0944868b967fc88de530499266668c2b99';

  v_corpus_sha256 constant text := 'fdc3e3cedf800489c6e635008b5eb16a84c5c343ad0e9820dd1dd131ace853e3';
  v_result_sha256 constant text := 'a0330b552dc182bb853a764ff81c07aa3f1478735300c61eb00974b8d4082006';
  v_validator_sha256 constant text := 'c78bafb242aaf24e50ce170d173799029e652a13ae99ad9a2b8b1421c2704730';
  v_workflow_sha256 constant text := 'f9d5526ddd13939a7b68227cd9f26d72463c777bb0f0c33651cd7c575b4fed5a';

  v_route constant jsonb := jsonb_build_object(
    'provider','GITHUB_ACTIONS',
    'workflow_path','.github/workflows/lf-router-level2-advisory-tests.yml',
    'job_name','router-level2-advisory-contract',
    'check_name','router-level2-advisory-contract'
  );

  v_old jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_contract jsonb;
  v_ready jsonb;
  v_packet jsonb;
  v_bad_packet jsonb;
  v_obs jsonb;
  v_result jsonb;
  v_bad_result jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_count integer;
  v_negative_rejected boolean := false;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit
    AND work_item_id=v_work_item
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_work_item AND work_code='ROUTER-W1-02' AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code='RW1-02_C1'
           AND status='DONE' AND evidence_ref IS NOT NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code='RW1-02_C2'
           AND status='PENDING' AND evidence_ref IS NULL
           AND assertion_receipt IS NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code='RW1-02_C3'
           AND status='PENDING' AND evidence_ref IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_LIFECYCLE_DRIFT'; END IF;

  IF v_old#>>'{action_specs_v1,RW1-02_C2,status}' IS DISTINCT FROM 'READY'
     OR v_old#>>'{action_specs_v1,RW1-02_C2,action_kind}' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
     OR v_old#>>'{action_specs_v1,RW1-02_C2,test_execution_contract,test_code}'
          IS DISTINCT FROM 'ENG_RW102_C2_ARCHITECTURE_COMPETITION'
     OR v_old#>'{action_specs_v1,RW1-02_C2,test_execution_contract,execution_route}' IS NOT NULL
     OR v_old#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C2,source_git_blobs,corpus}' IS DISTINCT FROM v_corpus_blob
     OR v_old#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C2,source_git_blobs,result}' IS DISTINCT FROM v_result_blob
     OR v_old#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C2,source_git_blobs,validator}' IS DISTINCT FROM v_validator_blob
     OR v_old#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C2,source_git_blobs,workflow}' IS DISTINCT FROM v_workflow_blob
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_SOURCE_CONTRACT_DRIFT'; END IF;

  -- Bind only the exact GitHub Actions execution route that produced the merged-main receipt.
  v_new:=jsonb_set(
    v_old,
    '{action_specs_v1,RW1-02_C2,test_execution_contract,execution_route}',
    v_route,
    true
  );

  IF (v_new #- '{action_specs_v1,RW1-02_C2,test_execution_contract,execution_route}')
       IS DISTINCT FROM v_old
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_UNRELATED_METADATA_CHANGED'; END IF;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW102_C2_CLOSE_ROUTE_UPDATE_COUNT:%',v_count; END IF;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_spec);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(v_plan,v_unit,v_cp,v_spec,'{}'::jsonb);

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
     OR v_packet->>'capability_mode' IS DISTINCT FROM 'RUN_EXISTING_DECLARED_CHECKPOINT_TEST'
     OR jsonb_array_length(coalesce(v_packet->'connector_plan','[]'::jsonb))<>3
     OR v_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'RUN_TEST'
     OR v_packet#>>'{connector_plan,1,operation}' IS DISTINCT FROM 'CHECKPOINT_ASSERTION_RECORD'
     OR v_packet#>>'{connector_plan,2,operation}' IS DISTINCT FROM 'CHECKPOINT_TRANSITION'
     OR v_packet#>>'{connector_plan,0,source_contract,ref_mode}' IS DISTINCT FROM 'EXACT_MERGED_SHA'
     OR v_packet#>>'{connector_plan,0,runner_contract,verified_run_id_required}' IS DISTINCT FROM 'true'
     OR v_packet#>>'{connector_plan,0,runner_contract,verified_check_conclusion}' IS DISTINCT FROM 'success'
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_PACKET_OR_READINESS_NOT_READY:spec=% contract=% ready=% packet=%',
       v_spec::text,v_contract::text,v_ready::text,v_packet::text; END IF;

  -- Negative packet control: an incomplete runner route must fail closed.
  v_bad_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    v_plan,v_unit,v_cp,
    jsonb_set(
      v_spec,
      '{test_execution_contract,execution_route}',
      v_route-'check_name',
      true
    ),
    '{}'::jsonb
  );
  IF v_bad_packet->>'status' IS DISTINCT FROM 'BLOCK_RUN_TEST_CI_BINDING_INCOMPLETE'
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_NEGATIVE_PACKET_FALSE_PASS:%',v_bad_packet::text; END IF;

  v_obs:=jsonb_build_object(
    'test_passed',true,
    'test_exit_code',0,
    'corpus_cases',36,
    'requirements_covered',12,
    'candidate_count',4,
    'eligible_candidate_count',3,
    'hard_pass_candidates',2,
    'provisional_selection','A_MIN_ROUTER_SEMANTIC_SPECIALIST',
    'negative_probes_detected_at_least',16,
    'negative_probes_observed',16,
    'result_recomputed_exact',true,
    'source_sha256_matches',true,
    'real_python_runner_receipt',true,
    'baseline_not_eligible',true,
    'actual_latency_measured',false,
    'actual_cost_measured',false,
    'no_router_runtime_claim',true,
    'no_production_mutation',true,
    'github_run_id',v_run,
    'github_job_id',v_job,
    'github_event','push',
    'github_conclusion','success',
    'resolved_main_sha',v_main,
    'corpus_git_blob',v_corpus_blob,
    'result_git_blob',v_result_blob,
    'validator_git_blob',v_validator_blob,
    'workflow_git_blob',v_workflow_blob,
    'corpus_sha256',v_corpus_sha256,
    'result_sha256',v_result_sha256,
    'validator_sha256',v_validator_sha256,
    'workflow_sha256',v_workflow_sha256,
    'test_code','ENG_RW102_C2_ARCHITECTURE_COMPETITION',
    'evidence_scope','EXECUTABLE_DESIGN_CONTRACT_BENCHMARK_ONLY_NOT_ROUTER_RUNTIME_OR_PRODUCTION',
    'c3_independent_review_required',true
  );

  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_RESULT_DOES_NOT_SATISFY_CONTRACT'; END IF;

  v_result:=jsonb_build_object(
    'status','PASS',
    'test_code','ENG_RW102_C2_ARCHITECTURE_COMPETITION',
    'evidence_ref',v_evidence,
    'observed',v_obs
  );

  -- Negative assertion control: making the baseline eligible must fail and leave no receipt.
  v_bad_result:=jsonb_set(v_result,'{observed,baseline_not_eligible}','false'::jsonb,true);
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_bad_result,v_actor||'_NEGATIVE');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
    THEN RAISE; END IF;
    v_negative_rejected:=true;
  END;
  IF NOT v_negative_rejected
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_NEGATIVE_ROLLBACK_NOT_CLEAN'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,v_result,v_actor);
  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
     OR v_assertion->>'evidence_ref' IS DISTINCT FROM v_evidence
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_ASSERTION_RECEIPT_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'RW1-02_C2: exact-main GitHub Actions benchmark PASS; 36 cases cover N01-N12; A/C hard-pass, B eliminated 23 hard failures, current baseline D ineligible; A provisional by declared lexicographic simplicity rule; 16/16 negative probes rejected; no runtime/latency/cost/production claim; C3 independent review remains pending.'
  );
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-02_C1' AND status='DONE')
          OR (checkpoint_code='RW1-02_C2' AND status='DONE'
              AND completed_at IS NOT NULL
              AND evidence_ref=v_evidence
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true'
              AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')
          OR (checkpoint_code='RW1-02_C3'
              AND status='PENDING' AND evidence_ref IS NULL)))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=v_work_item AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'RW102_C2_CLOSE_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw102_c2_close$;
COMMIT;
