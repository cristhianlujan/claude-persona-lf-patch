-- RW1-01_C2: source-bounded CI corpus-validator receipt (NOT Router runtime E2E).
-- Provider: GitHub Actions push run 39055242275, job 117461769688, successful.
-- On SHA e453818c3e6098a1d958eed57d6f4131c951d651, 30 cases/12 needs/9 families,
-- 15 negative oracle-validator probes, shape_only=true; no claim of Router operational PASS.
BEGIN;
DO $rw101_c2_material$
DECLARE
 v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
 v_unit constant text := 'RW1-01';
 v_cp constant text := 'RW1-01_C2';
 v_actor constant text := 'LF_ROUTER_RW101_C2_TRAIN_MATERIAL_RECEIPT_20261017';
 v_work_item constant bigint := 1127;
 v_expected_md5 constant text := '0f6627aa6eabbbd4c20a2b0ae51853cf';
 v_run constant text := '39055242275';
 v_job constant text := '117461769688';
 v_commit constant text := 'e453818c3e6098a1d958eed57d6f4131c951d651';
 v_corpus_blob constant text := '58884d37d74f1c784dfb5920ed2ac548781bfe18';
 v_validator_blob constant text := '2605fc675448104f69deef8a27210fc0047ea6fb';
 v_corpus_sha256 constant text := '0592fbfec256d18014a8362d2f7ebf116793b6039da0516a00bbf85285fc5d94';
 v_validator_sha256 constant text := 'e5fc3aa3f1097b8a60d5e1a7259c8242ef3aaba8e02909cab3ba752705434620';
 v_evidence constant text := 'https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39055242275/job/117461769688';
 v_spec jsonb;
 v_contract jsonb;
 v_ready jsonb;
 v_packet jsonb;
 v_obs jsonb;
 v_result jsonb;
 v_bad_result jsonb;
 v_receipt jsonb;
 v_transition jsonb;
 v_negative_rejected boolean := false;
BEGIN
 IF (SELECT count(*) FROM programacion.engineering_plan_units
       WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work_item
         AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_expected_md5)<>1
 THEN RAISE EXCEPTION 'RW101_C2_MATERIAL_SOURCE_METADATA_DRIFT'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_items
       WHERE id=v_work_item AND work_code='ROUTER-W1-01' AND status='IN_PROGRESS')<>1
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work_item AND checkpoint_code='RW1-01_C1' AND status='DONE')<>1
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work_item AND checkpoint_code IN ('RW1-01_C2','RW1-01_C3')
         AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'RW101_C2_MATERIAL_PRESTATE_DRIFT'; END IF;

 IF (SELECT checkpoint_code FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work_item AND status NOT IN ('DONE','NOT_APPLICABLE')
       ORDER BY sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'RW101_C2_NOT_CURRENT_CHECKPOINT'; END IF;

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
    OR jsonb_array_length(coalesce(v_packet->'connector_plan','[]'::jsonb))<>3
    OR v_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'RUN_TEST'
    OR v_packet#>>'{connector_plan,0,source_contract,ref_mode}' IS DISTINCT FROM 'EXACT_MERGED_SHA'
    OR v_packet#>>'{connector_plan,0,runner_contract,verified_run_id_required}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'RW101_C2_MATERIAL_READY_OR_RECEIPT_CONTRACT_MISSING'; END IF;

 IF v_spec#>>'{test_execution_contract,execution_route,provider}' IS DISTINCT FROM 'GITHUB_ACTIONS'
    OR v_spec#>>'{test_execution_contract,execution_route,workflow_path}'
       IS DISTINCT FROM '.github/workflows/lf-router-level2-advisory-tests.yml'
    OR v_spec#>>'{test_execution_contract,execution_route,job_name}'
       IS DISTINCT FROM 'router-level2-advisory-contract'
    OR v_spec#>>'{test_execution_contract,execution_route,check_name}'
       IS DISTINCT FROM 'router-level2-advisory-contract'
 THEN RAISE EXCEPTION 'RW101_C2_MATERIAL_RUNNER_IDENTITY_DRIFT'; END IF;

 v_obs:=jsonb_build_object(
     'test_passed',true,
     'test_exit_code',0,
     'corpus_cases',30,
     'requirements_covered',12,
     'families_covered',9,
     'negative_probes_detected_at_least',12,
     'negative_probes_observed',15,
     'source_sha256_matches',true,
     'real_python_runner_receipt',true,
     'no_authority_effect',true,
     'no_e2e_claim',true,
     'shape_only',true,
     'checkpoint_done_from_ci',false,
     'github_run_id',v_run,
     'github_job_id',v_job,
     'github_event','push',
     'github_conclusion','success',
     'github_actor','lf-migration-train[bot]',
     'resolved_main_sha',v_commit,
     'corpus_git_blob',v_corpus_blob,
     'validator_git_blob',v_validator_blob,
     'corpus_sha256',v_corpus_sha256,
     'validator_sha256',v_validator_sha256,
     'test_code','ENG_RW101_C2_REQUIREMENTS_ORACLE',
     'evidence_scope','CI_CORPUS_AND_VALIDATOR_ONLY_NOT_ROUTER_E2E'
 );

 IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'RW101_C2_RESULT_DOES_NOT_SATISFY_CONTRACT'; END IF;

 v_result:=jsonb_build_object(
    'status','PASS','test_code','ENG_RW101_C2_REQUIREMENTS_ORACLE',
    'evidence_ref',v_evidence,'observed',v_obs);

 -- Negative control in a subtransaction: a source mismatch must not record PASS.
 v_bad_result:=jsonb_set(v_result,'{observed,source_sha256_matches}','false'::jsonb,true);
 BEGIN
   PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_bad_result,v_actor||'_NEGATIVE');
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
   THEN RAISE; END IF;
   v_negative_rejected:=true;
 END;
 IF NOT v_negative_rejected
 THEN RAISE EXCEPTION 'RW101_C2_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
         AND assertion_receipt IS NULL AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'RW101_C2_NEGATIVE_ROLLBACK_NOT_CLEAN'; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,v_result,v_actor);
 IF v_receipt->>'passed' IS DISTINCT FROM 'true'
    OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
    OR v_receipt->>'evidence_ref' IS DISTINCT FROM v_evidence
 THEN RAISE EXCEPTION 'RW101_C2_STRUCTURED_RECEIPT_FAILED'; END IF;

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'C2: exact-main CI corpus+Python validator passed 30 cases/12 requirements/9 families, 15 negatives; shape-only, no Router E2E, C3 remains pending');
 IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'RW101_C2_TRANSITION_NOT_APPLIED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-01_C1' AND status='DONE')
          OR (checkpoint_code='RW1-01_C2' AND status='DONE'
              AND evidence_ref=v_evidence
              AND assertion_contract_sha256 IS NOT NULL
              AND assertion_receipt_sha256 IS NOT NULL
              AND assertion_receipt->>'passed'='true')
          OR (checkpoint_code='RW1-01_C3' AND status='PENDING')))<>3
    OR (SELECT count(*) FROM programacion.engineering_work_items
          WHERE id=v_work_item AND status='IN_PROGRESS')<>1
 THEN RAISE EXCEPTION 'RW101_C2_READBACK_NOT_CONSISTENT'; END IF;
END
$rw101_c2_material$;
COMMIT;
