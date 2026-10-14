-- LF Operations: eight individual, deterministic Edge-function deployment step judges.
-- Governed registration only; operation remains CANDIDATO_READ_ONLY and write_allowed=false.
-- Does NOT deploy Edge, change credentials, approve runtime, or execute CP2.

DO $edge_steps$
DECLARE
  v_op constant text := 'DEPLOY_SUPABASE_EDGE_FUNCTION_LF';
  v_actor constant text := 'EXEC-BOOTSTRAP-EDGE-FUNCTION-OP-20261014-001';
  v_path constant text := 'sandbox/lf_contract_gate_test/edge_function_operation/edge_operation_step_judges_v1.py';
  v_sha constant text := '319bfe3f34e0d86840c7c6d1ecd3a164c1dd4aa57017202b6635e1746ca21a3a';
  v_contract constant text := 'CONTRACT-DEPLOY-SUPABASE-EDGE-FUNCTION-LF-v1';
  s record;
  v_keys jsonb;
  v_judge text;
  v_assertion text;
  v_purpose text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code=v_op AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
    WHERE asset_type='SUPABASE_EDGE_FUNCTION' AND action_code='EDGE_FUNCTION_DEPLOY'
      AND operation_code=v_op AND status='CANDIDATO_READ_ONLY' AND write_allowed=false
  ) THEN
    RAISE EXCEPTION 'EDGE_STEPS_OPERATION_NOT_CANDIDATE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id=v_actor
      AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
      AND status='IN_PROGRESS' AND manifest->>'governance_bootstrap'='true'
      AND manifest->>'bootstrap_operation_code'=v_op
      AND manifest->>'bootstrap_status_ceiling'='SANDBOX_ACTIVE'
  ) THEN
    RAISE EXCEPTION 'EDGE_STEPS_PROVENANCE_AUTHORITY_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code=v_op AND contract_code=v_contract
      AND status='CANDIDATE_READ_ONLY'
  ) THEN
    RAISE EXCEPTION 'EDGE_STEPS_OPERATION_CONTRACT_MISSING';
  END IF;
  IF (SELECT count(*) FROM public.lf_operation_steps
      WHERE operation_code=v_op AND required=true AND active=true) <> 8
     OR EXISTS (
       SELECT 1 FROM public.lf_operation_step_contracts WHERE operation_code=v_op
     ) OR EXISTS (
       SELECT 1 FROM public.lf_operation_step_judge_bindings WHERE operation_code=v_op
     ) OR EXISTS (
       SELECT 1 FROM public.lf_operation_judges WHERE operation_code=v_op
     ) THEN
    RAISE EXCEPTION 'EDGE_STEPS_INVALID_OR_PREEXISTING';
  END IF;

  -- Genuine transaction rollback smoke of the three existing authority tables.
  -- This subtransaction is always rolled back before registering the real rows.
  BEGIN
    INSERT INTO public.lf_operation_judges(
      operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
      created_by_execution_id,updated_by_execution_id
    ) VALUES (
      v_op,'MINI_JUDGE_EDGE_DEPLOY_ROLLBACK_PROBE_V1',v_path,v_sha,
      '["edge_rollback_probe_verified"]'::jsonb,
      '["server_validation_failed"]'::jsonb,
      '["STEP_PASS_WITH_EVIDENCE","BLOCKED_STEP_NOT_CLEAN","RETURN_TO_ROUTER"]'::jsonb,
      'ACTIVE_ENFORCEMENT',v_actor,v_actor
    );
    RAISE EXCEPTION 'EDGE_STEPS_ROLLBACK_SENTINEL' USING ERRCODE='PZ083';
  EXCEPTION WHEN SQLSTATE 'PZ083' THEN
    NULL;
  END;
  IF EXISTS (
    SELECT 1 FROM public.lf_operation_judges
    WHERE operation_code=v_op AND judge_code='MINI_JUDGE_EDGE_DEPLOY_ROLLBACK_PROBE_V1'
  ) THEN
    RAISE EXCEPTION 'EDGE_STEPS_ROLLBACK_RESIDUE';
  END IF;

  FOR s IN
    SELECT st.step_order,st.step_id,st.evidence_required,
           lead(st.step_id) OVER (ORDER BY st.step_order) as next_step
    FROM public.lf_operation_steps st
    WHERE st.operation_code=v_op AND st.required=true AND st.active=true
    ORDER BY st.step_order
  LOOP
    v_keys := to_jsonb(regexp_split_to_array(s.evidence_required,'\s*,\s*'));
    v_judge := 'MINI_JUDGE_EDGE_DEPLOY_'||upper(s.step_id)||'_V1';
    v_assertion := 'edge_'||s.step_id||'_verified';
    v_purpose := CASE s.step_id
      WHEN 'init_execution' THEN 'Cross-bind real operation execution identity and one exact Edge target.'
      WHEN 'source_baseline' THEN 'Verify exact Git main, live deployed bytes against rollback Git source, target isolation and JWT state.'
      WHEN 'r17_preflight' THEN 'Require independently sourced R17 event, rollback drill, idempotency and measured latency within budget.'
      WHEN 'human_authority' THEN 'Require real SUPER_ADMIN signed authorization, operational status and exact scoped writable route.'
      WHEN 'effect_guard' THEN 'Require existing Operation effect guard RESERVED exact request and permitted dispatch.'
      WHEN 'edge_deploy' THEN 'Bind one real provider deploy receipt, operation execution id, target and exact Git source SHA.'
      WHEN 'independent_readback' THEN 'Verify independent Edge source/JWT, genuine OIDC test, rollback and zero unintended CP2 jobs.'
      WHEN 'close' THEN 'Close only with matching successful effect receipt, independent source parity and zero open blockers/promotion.'
      ELSE NULL
    END;
    IF v_purpose IS NULL OR jsonb_typeof(v_keys)<>'array' OR jsonb_array_length(v_keys)<2 THEN
      RAISE EXCEPTION 'EDGE_STEPS_UNKNOWN_OR_INVALID_STEP:%',s.step_id;
    END IF;

    INSERT INTO public.lf_operation_step_contracts(
      operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
      output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,
      required_evidence_keys,next_if_pass,next_if_blocked,status,notes,
      created_by_execution_id,updated_by_execution_id
    ) VALUES (
      v_op,s.step_id,s.step_order,s.step_order,v_contract,v_purpose,'[]'::jsonb,
      'AUTHENTICATED_EDGE_OPERATION_TRUST_READBACK_V1',
      v_keys,
      jsonb_build_object('server_verified_assertion',v_assertion,
        'validator_source',v_path,'validator_sha256',v_sha),
      jsonb_build_object('missing_required_evidence',true,
        'independent_readback_mismatch',true,'server_validation_failed',true),
      'BLOCKED_EDGE_DEPLOY_'||upper(s.step_id)||'_NOT_CLEAN',
      v_judge,v_keys,s.next_step,'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
      'Operation candidate; active step schema does not authorize effect or assert execution.',
      v_actor,v_actor
    );

    INSERT INTO public.lf_operation_judges(
      operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
      created_by_execution_id,updated_by_execution_id
    ) VALUES (
      v_op,v_judge,v_path,v_sha,
      jsonb_build_array(v_assertion),
      jsonb_build_array('server_validation_failed','edge_'||s.step_id||'_mismatch'),
      jsonb_build_array('STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER'),
      'ACTIVE_ENFORCEMENT',v_actor,v_actor
    );

    INSERT INTO public.lf_operation_step_judge_bindings(
      operation_code,step_order,step_id,judge_code,
      clean_result_value,blocked_result_value,return_result_value,
      required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
    ) VALUES (
      v_op,s.step_order,s.step_id,v_judge,
      'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
      v_keys,'ACTIVE_ENFORCEMENT',v_actor,v_actor
    );
  END LOOP;

  IF (SELECT count(*) FROM public.lf_operation_step_contracts
      WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>8
  OR (SELECT count(*) FROM public.lf_operation_judges
      WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>8
  OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings
      WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>8
  OR EXISTS (
      SELECT 1 FROM public.lf_operation_steps st
      LEFT JOIN public.lf_operation_step_contracts c
        ON c.operation_code=st.operation_code AND c.step_id=st.step_id
       AND c.step_order=st.step_order
      LEFT JOIN public.lf_operation_step_judge_bindings b
        ON b.operation_code=st.operation_code AND b.step_id=st.step_id
       AND b.step_order=st.step_order
      LEFT JOIN public.lf_operation_judges j
        ON j.operation_code=b.operation_code AND j.judge_code=b.judge_code
      WHERE st.operation_code=v_op AND
        (c.step_id IS NULL OR b.step_id IS NULL OR j.judge_code IS NULL
          OR c.mini_judge_code IS DISTINCT FROM b.judge_code
          OR c.required_evidence_keys IS DISTINCT FROM b.required_evidence_keys
          OR j.pass_if IS DISTINCT FROM jsonb_build_array('edge_'||st.step_id||'_verified'))
  )
  OR EXISTS (
      SELECT 1 FROM public.lf_router_action_registry
      WHERE asset_type='SUPABASE_EDGE_FUNCTION' AND action_code='EDGE_FUNCTION_DEPLOY'
        AND (write_allowed IS DISTINCT FROM false OR status<>'CANDIDATO_READ_ONLY')
  ) THEN
    RAISE EXCEPTION 'EDGE_STEPS_JUDGE_BINDING_READBACK_FAILED';
  END IF;
END $edge_steps$;
