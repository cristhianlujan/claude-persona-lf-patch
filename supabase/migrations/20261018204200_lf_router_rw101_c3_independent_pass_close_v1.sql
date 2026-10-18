-- RW1-01_C3: governed close from materially separate independent blind judge PASS.
-- Evidence scope: local checker/oracle contract only; no Router runtime or production claim.
-- RAW1 was frozen before reveal; RAW2 confirms unchanged RAW1 and commitment parity.
BEGIN;
DO $rw101_c3_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-01';
  v_cp constant text := 'RW1-01_C3';
  v_work_item constant bigint := 1127;
  v_actor constant text := 'LF_ROUTER_RW101_C3_INDEPENDENT_PASS_CLOSE_20261018';
  v_evidence constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json';
  v_source_main constant text := 'ed2935b2c900bd9ff9c2cdd5885ea87c266c56c3';
  v_corpus_blob constant text := '55c09eb0fc6ddffa7a41d66eddf9c254e061f566';
  v_checker_blob constant text := '8a3fdcd7118703206bbf73cbc394c30313b8b510';
  v_generator_blob constant text := 'ba48eb61efff3865f13f993e258cbd73741a4981';
  v_verdict_blob constant text := 'b4c1fab848b2d98a56f12bc5475103bddce623bf';
  v_raw1_sha constant text := 'a7fbc77c8500fdb48559fab7112318beaefb3ada658a819ba50e5a6251edc25a';
  v_raw2_sha constant text := 'efcc5ec4f9619ff380649f9fd1741350a17168691c7ee85658ad9a29b73f1714';
  v_commitment constant text := '072e23f12f2cebfb955cae55a228078d150e243dd4992368ec1043cb996b53f1';
  v_manifest constant text := '52d74740d8787c6a9b125e817eab6685e428911d040281701b0c2a15786f4347';
  v_judge_ref constant text := 'gpt-native://rw1-01-c3-blind/raw1-sha256/a7fbc77c8500fdb48559fab7112318beaefb3ada658a819ba50e5a6251edc25a';
  v_spec jsonb;
  v_contract jsonb;
  v_ready jsonb;
  v_obs jsonb;
  v_result jsonb;
  v_bad_result jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_negative_rejected boolean := false;
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_work_item AND work_code='ROUTER-W1-01' AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item
           AND ((checkpoint_code='RW1-01_C1' AND status='DONE')
             OR (checkpoint_code='RW1-01_C2' AND status='DONE')
             OR (checkpoint_code='RW1-01_C3' AND status='PENDING'
                 AND evidence_ref IS NULL AND assertion_receipt IS NULL)))<>3
  THEN RAISE EXCEPTION 'RW101_C3_CLOSE_PRESTATE_DRIFT'; END IF;

  IF (SELECT checkpoint_code FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY sequence_no LIMIT 1) IS DISTINCT FROM v_cp
  THEN RAISE EXCEPTION 'RW101_C3_NOT_CURRENT_CHECKPOINT'; END IF;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_spec);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready->>'execution_capability' IS DISTINCT FROM 'WRITE_GIT'
     OR v_spec#>>'{target,mutation_artifacts,0,path}' IS DISTINCT FROM
        'cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json'
  THEN RAISE EXCEPTION 'RW101_C3_CLOSE_CONTRACT_NOT_READY'; END IF;

  v_obs:=jsonb_build_object(
    'blind_verdict','PASS',
    'independent_judge_attested',true,
    'judge_identity_ref_present',true,
    'judge_identity_ref',v_judge_ref,
    'source_freeze_verified',true,
    'source_main_sha',v_source_main,
    'source_corpus_blob',v_corpus_blob,
    'source_checker_blob',v_checker_blob,
    'source_generator_blob',v_generator_blob,
    'verdict_git_blob',v_verdict_blob,
    'holdout_commitment_verified',true,
    'holdout_revealed_after_raw1',true,
    'public_v2_all_42_good_accepted',true,
    'v2_public_good_cases',42,
    'v2_public_good_cases_accepted',42,
    'holdout_12_good_accepted',true,
    'holdout_good_cases',12,
    'holdout_good_cases_accepted',12,
    'holdout_at_least_24_bad_rejected',true,
    'holdout_bad_cases',218,
    'holdout_bad_cases_rejected',218,
    'holdout_all_bad_rejected',true,
    'novel_falsifiers_at_least_2',true,
    'novel_falsifiers_added',2,
    'material_blockers',0,
    'no_router_runtime_claim',true,
    'no_production_mutation',true,
    'raw1_sha256',v_raw1_sha,
    'raw2_sha256',v_raw2_sha,
    'holdout_commitment_sha256',v_commitment,
    'holdout_manifest_sha256',v_manifest,
    'raw1_label_present',false,
    'blind_verdict_basis','MECHANICALLY_DERIVED_FROM_FROZEN_RAW1_UNDER_PREDECLARED_PASS_CRITERIA',
    'raw1_unchanged_verified_by_raw2',true,
    'evidence_scope','LOCAL_CHECKER_CONTRACT_ONLY_NOT_ROUTER_RUNTIME'
  );

  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW101_C3_CLOSE_RESULT_DOES_NOT_SATISFY_CONTRACT'; END IF;

  v_result:=jsonb_build_object(
    'status','PASS',
    'evidence_ref',v_evidence,
    'observed',v_obs,
    'validation_kind','RW101_C3_INDEPENDENT_BLIND_LOCAL_CONTRACT_PASS'
  );

  -- Negative control: any material blocker must fail assertion and roll back cleanly.
  v_bad_result:=jsonb_set(v_result,'{observed,material_blockers}','1'::jsonb,true);
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_bad_result,v_actor||'_NEGATIVE');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
    THEN RAISE; END IF;
    v_negative_rejected:=true;
  END;
  IF NOT v_negative_rejected
  THEN RAISE EXCEPTION 'RW101_C3_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW101_C3_NEGATIVE_ROLLBACK_NOT_CLEAN'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,v_result,v_actor);
  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
     OR v_assertion->>'evidence_ref' IS DISTINCT FROM v_evidence
  THEN RAISE EXCEPTION 'RW101_C3_ASSERTION_RECEIPT_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'C3 independent blind local-contract review PASS: source freeze verified; 42/42 public, 12/12 holdout, 218/218 negatives, >=2 novel falsifiers, zero material blockers; no Router runtime or production claim');
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW101_C3_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-01_C1' AND status='DONE')
          OR (checkpoint_code='RW1-01_C2' AND status='DONE')
          OR (checkpoint_code='RW1-01_C3' AND status='DONE'
              AND completed_at IS NOT NULL
              AND evidence_ref=v_evidence
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true'
              AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND status='DONE')<>3
  THEN RAISE EXCEPTION 'RW101_C3_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw101_c3_close$;
COMMIT;
