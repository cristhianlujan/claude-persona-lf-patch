-- RW1-02_C3: governed close from the V2 independent blind review PASS plus independent GPT Native attestation.
-- Evidence scope: architecture assurance only; no Router runtime, production, latency or cost claim.
-- RAW1 was frozen before reveal; RAW2 confirms unchanged RAW1. The attestation round and its first finding are recorded in the verdict file.
BEGIN;
DO $rw102_c3_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-02';
  v_cp constant text := 'RW1-02_C3';
  v_work_item constant bigint := 1128;
  v_actor constant text := 'LF_ROUTER_RW102_C3_INDEPENDENT_PASS_CLOSE_20261020';
  v_evidence constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json';
  v_verdict_blob constant text := '623c9926d745bf0670156fe1b96d5729f0e4900b';
  v_snapshot constant text := '469089b796cae8de01c9506c52c9ae9b72d97d0d';
  v_raw1_sha constant text := '5789780dbc7e7842bccc1b794ee0f447f266cd8e1ed69f27b23ff1a46b98b831';
  v_raw2_sha constant text := 'ae951406dbf4b8c94f8cdcc1b99a95f142395c79e33cad67f8d83a25af69fc8a';
  v_judge_ref constant text := 'gpt-native://rw1-02-c3-v2-independent-attestation/chat/6ad7d9a4-7f58-83e8-b855-b79a4db66c09';
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
      WHERE id=v_work_item AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item
           AND ((checkpoint_code='RW1-02_C1' AND status='DONE')
             OR (checkpoint_code='RW1-02_C2' AND status='DONE')
             OR (checkpoint_code=v_cp AND status='PENDING'
                 AND evidence_ref IS NULL AND assertion_receipt IS NULL)))<>3
  THEN RAISE EXCEPTION 'RW102_C3_CLOSE_PRESTATE_DRIFT'; END IF;

  IF (SELECT checkpoint_code FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY sequence_no LIMIT 1) IS DISTINCT FROM v_cp
  THEN RAISE EXCEPTION 'RW102_C3_NOT_CURRENT_CHECKPOINT'; END IF;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_spec);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_spec#>>'{target,mutation_artifacts,0,path}' IS DISTINCT FROM
        'cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json'
     OR (SELECT unit_metadata#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C3,source_snapshot_commit}'
         FROM programacion.engineering_plan_units
         WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work_item) IS DISTINCT FROM v_snapshot
  THEN RAISE EXCEPTION 'RW102_C3_CLOSE_CONTRACT_NOT_READY'; END IF;

  v_obs:=jsonb_build_object(
    'blind_verdict','PASS',
    'independent_judge_attested',true,
    'judge_identity_ref_present',true,
    'judge_identity_ref',v_judge_ref,
    'source_freeze_verified',true,
    'source_snapshot_commit',v_snapshot,
    'verdict_git_blob',v_verdict_blob,
    'producer_result_hidden_until_raw1',true,
    'independent_recomputation_completed',true,
    'public_case_count',36,
    'requirements_n01_n12_covered',true,
    'candidate_count',4,
    'eligible_candidate_count',3,
    'adversarial_mutations_total',37,
    'adversarial_mutations_at_least_24',true,
    'a_mutations_at_least_6',true,
    'c_mutations_at_least_6',true,
    'selection_policy_mutations_at_least_4',true,
    'novel_falsifiers_at_least_2',true,
    'all_semantically_invalid_mutations_rejected',true,
    'material_blockers',0,
    'final_selection','A_MIN_ROUTER_SEMANTIC_SPECIALIST',
    'final_selection_present',true,
    'final_selection_valid',true,
    'selection_supported_by_evidence',true,
    'raw1_frozen',true,
    'raw2_created',true,
    'raw1_unchanged_after_reveal',true,
    'raw1_sha256',v_raw1_sha,
    'raw2_sha256',v_raw2_sha,
    'latency_cost_not_invented',true,
    'no_router_runtime_claim',true,
    'no_production_mutation',true,
    'evidence_scope','ARCHITECTURE_ASSURANCE_ONLY_NOT_ROUTER_RUNTIME'
  );

  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW102_C3_CLOSE_RESULT_DOES_NOT_SATISFY_CONTRACT'; END IF;

  v_result:=jsonb_build_object(
    'status','PASS',
    'evidence_ref',v_evidence,
    'observed',v_obs,
    'validation_kind','RW102_C3_V2_INDEPENDENT_BLIND_ARCHITECTURE_PASS'
  );

  -- Negative control: any material blocker must fail the assertion and roll back cleanly.
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
  THEN RAISE EXCEPTION 'RW102_C3_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C3_NEGATIVE_ROLLBACK_NOT_CLEAN'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,v_result,v_actor);
  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
     OR v_assertion->>'evidence_ref' IS DISTINCT FROM v_evidence
  THEN RAISE EXCEPTION 'RW102_C3_ASSERTION_RECEIPT_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'C3 V2 independent blind architecture review PASS: freeze verified; 37 adversarial mutations, zero invalid accepted, zero valid rejected, selection A by frozen lexicographic tiebreak, independent GPT Native attestation, zero material blockers; no Router runtime or production claim');
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW102_C3_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-02_C1' AND status='DONE')
          OR (checkpoint_code='RW1-02_C2' AND status='DONE')
          OR (checkpoint_code=v_cp AND status='DONE'
              AND completed_at IS NOT NULL
              AND evidence_ref=v_evidence
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true'
              AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND status='DONE')<>3
  THEN RAISE EXCEPTION 'RW102_C3_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw102_c3_close$;
COMMIT;
