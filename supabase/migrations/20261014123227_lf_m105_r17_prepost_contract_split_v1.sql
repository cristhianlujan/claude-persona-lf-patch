-- M10.5/R17: only correct the impossible provider-proof-before-provider-deploy cycle.
-- Runtime, Router and release stay DISABLED. Train is the only SQL apply route.
DO $m105_r17$
DECLARE
  v_op constant text := 'DEPLOY_SUPABASE_EDGE_FUNCTION_LF';
  v_actor constant text := 'EXEC-IG-M105-R17-SEQUENCE-REPAIR-20261014-001';
  v_old_judge constant text := '319bfe3f34e0d86840c7c6d1ecd3a164c1dd4aa57017202b6635e1746ca21a3a';
  v_new_judge constant text := 'fa8cb9ab58d41092ef40e37dfc466de38452255cadefbebeda7287467b8c2337';
  v_old_guard constant text := '58995a9bc71074f0a0f1854ee0b4674d85112d910192747dcf2130174d739836';
  v_new_guard constant text := '68027b42b080843e0c3917b10ce5a01d47a4bd45e416280e5c97f8e0154a607e';
  v_judge_path constant text := 'sandbox/lf_contract_gate_test/edge_function_operation/edge_operation_step_judges_v1.py';
  v_guard_path constant text := 'sandbox/lf_contract_gate_test/edge_function_operation/edge_deploy_guard_v1.py';
  v_before jsonb := '["r17_event_id","timing","offline_bundle_receipt","offline_rollback","offline_idempotency"]'::jsonb;
  v_after jsonb := '["deployed_source","oidc_probe","rollback_state","provider_rollback_receipt","provider_idempotency_receipt"]'::jsonb;
  v_count integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_registry
                 WHERE operation_code=v_op AND lifecycle_state_code='OP_CANDIDATE'
                   AND status='CANDIDATO_READ_ONLY')
  OR NOT EXISTS (SELECT 1 FROM public.lf_router_action_registry
                 WHERE operation_code=v_op AND action_code='EDGE_FUNCTION_DEPLOY'
                   AND asset_type='SUPABASE_EDGE_FUNCTION'
                   AND write_allowed=false AND status='CANDIDATO_READ_ONLY')
  OR EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE operation_code=v_op)
  THEN RAISE EXCEPTION 'M105_R17_WRITE_AUTHORITY_OR_OPERATION_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_step_contracts
      WHERE operation_code=v_op AND pass_condition->>'validator_sha256'=v_old_judge
        AND pass_condition->>'validator_source'=v_judge_path)<>8
  OR (SELECT count(*) FROM public.lf_operation_judges
      WHERE operation_code=v_op AND judge_sha=v_old_judge AND judge_path=v_judge_path
        AND status='ACTIVE_ENFORCEMENT')<>8
  OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings
      WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>8
  OR (SELECT count(*) FROM public.lf_operation_steps
      WHERE operation_code=v_op AND active=true AND required=true)<>8
  OR NOT EXISTS (SELECT 1 FROM public.lf_operation_contracts
      WHERE operation_code=v_op AND contract_code='CONTRACT-DEPLOY-SUPABASE-EDGE-FUNCTION-LF-v1'
        AND contract_sha=v_old_guard AND contract_path=v_guard_path
        AND status='CANDIDATE_READ_ONLY')
  THEN RAISE EXCEPTION 'M105_R17_STEP_BINDING_OR_SHA_DRIFT'; END IF;

  UPDATE public.lf_operation_steps
  SET evidence_required=CASE step_id
      WHEN 'r17_preflight' THEN 'r17_event_id,timing,offline_bundle_receipt,offline_rollback,offline_idempotency'
      WHEN 'independent_readback' THEN 'deployed_source,oidc_probe,rollback_state,provider_rollback_receipt,provider_idempotency_receipt'
      END, updated_by_execution_id=v_actor, updated_at=clock_timestamp()
  WHERE operation_code=v_op AND step_id IN ('r17_preflight','independent_readback');
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>2 THEN RAISE EXCEPTION 'M105_R17_STEP_UPDATE_COUNT'; END IF;

  UPDATE public.lf_operation_step_contracts
  SET required_evidence_keys=CASE step_id WHEN 'r17_preflight' THEN v_before ELSE v_after END,
      output_payload=CASE step_id WHEN 'r17_preflight' THEN v_before ELSE v_after END,
      purpose=CASE step_id
        WHEN 'r17_preflight' THEN 'Verify offline predeploy bundle/rollback/replay and provider GET timing WITHOUT claiming a provider effect.'
        ELSE 'Postdeploy: demand real provider rollback and replay receipts, restored exact source, independent OIDC/JWT readback and zero unexpected CP2 jobs.' END,
      updated_by_execution_id=v_actor, updated_at=clock_timestamp()
  WHERE operation_code=v_op AND step_id IN ('r17_preflight','independent_readback');
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>2 THEN RAISE EXCEPTION 'M105_R17_CONTRACT_UPDATE_COUNT'; END IF;

  UPDATE public.lf_operation_step_judge_bindings
  SET required_evidence_keys=CASE step_id WHEN 'r17_preflight' THEN v_before ELSE v_after END,
      updated_by_execution_id=v_actor, updated_at=clock_timestamp()
  WHERE operation_code=v_op AND step_id IN ('r17_preflight','independent_readback');
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>2 THEN RAISE EXCEPTION 'M105_R17_BINDING_UPDATE_COUNT'; END IF;

  UPDATE public.lf_operation_step_contracts
  SET pass_condition=jsonb_set(pass_condition,'{validator_sha256}',to_jsonb(v_new_judge)),
      updated_by_execution_id=v_actor, updated_at=clock_timestamp()
  WHERE operation_code=v_op AND pass_condition->>'validator_sha256'=v_old_judge;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>8 THEN RAISE EXCEPTION 'M105_R17_JUDGE_CONTRACT_SHA_COUNT'; END IF;

  UPDATE public.lf_operation_judges
  SET judge_sha=v_new_judge,updated_by_execution_id=v_actor,updated_at=clock_timestamp()
  WHERE operation_code=v_op AND judge_sha=v_old_judge AND judge_path=v_judge_path;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>8 THEN RAISE EXCEPTION 'M105_R17_JUDGE_SOURCE_SHA_COUNT'; END IF;

  UPDATE public.lf_operation_contracts
  SET contract_sha=v_new_guard,
      required_after_write=required_after_write ||
        '{"provider_rollback_drill_receipt_required":true,"provider_idempotency_receipt_required":true,"restored_source_readback_required":true}'::jsonb,
      updated_by_execution_id=v_actor,updated_at=clock_timestamp()
  WHERE operation_code=v_op AND contract_code='CONTRACT-DEPLOY-SUPABASE-EDGE-FUNCTION-LF-v1'
    AND contract_sha=v_old_guard AND contract_path=v_guard_path;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'M105_R17_GUARD_SHA_COUNT'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_operation_step_contracts c
    JOIN public.lf_operation_step_judge_bindings b
      ON b.operation_code=c.operation_code AND b.step_id=c.step_id
    JOIN public.lf_operation_judges j
      ON j.operation_code=b.operation_code AND j.judge_code=b.judge_code
    WHERE c.operation_code=v_op AND
      (c.required_evidence_keys IS DISTINCT FROM b.required_evidence_keys
       OR c.pass_condition->>'validator_sha256' IS DISTINCT FROM j.judge_sha
       OR j.judge_sha<>v_new_judge))
  OR EXISTS (SELECT 1 FROM public.lf_router_action_registry
    WHERE operation_code=v_op AND (write_allowed IS DISTINCT FROM false OR status<>'CANDIDATO_READ_ONLY'))
  OR EXISTS (SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code=v_op AND lifecycle_state_code<>'OP_CANDIDATE')
  THEN RAISE EXCEPTION 'M105_R17_POST_READBACK_OR_AUTHORITY_DRIFT'; END IF;
END $m105_r17$;
