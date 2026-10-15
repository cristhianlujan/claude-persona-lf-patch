-- Candidate-only binding of six independent Engineering checkpoint closure judges.
-- Git source and tests have been verified: 14/14 offline PASS, byte-identical
-- to main. Not an executor grant, production promotion or checkpoint closure.
DO $cp_judges$
DECLARE
 v_op constant text := 'CIERRE_CHECKPOINT_INGENIERIA_LF';
 v_actor constant text := 'EXEC-CHECKPOINT-OP-BOOTSTRAP-20261014-001';
 v_ref constant text := 'sandbox/lf_contract_gate_test/engineering_checkpoint_closure/checkpoint_step_judges_v1.py';
 v_sha constant text := '8000f82c1d95ce9c7fa13bbcfae1d1a01b296cbb5aa8041f94fac8e308eda8bb';
 v_contract constant text := 'CONTRACT-ENGINEERING-CHECKPOINT-CLOSE-v1';
 s record;
 v_keys jsonb;
 v_judge text;
 v_assertion text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code=v_op AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE')
 OR NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry
    WHERE operation_code=v_op AND asset_type='ENGINEERING_CHECKPOINT'
      AND action_code='CHECKPOINT_CLOSE'
      AND status='CANDIDATO_READ_ONLY' AND write_allowed=false)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id=v_actor
      AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
      AND status='IN_PROGRESS' AND target_code=v_op
      AND manifest->>'governance_bootstrap'='true'
      AND manifest->>'bootstrap_status_ceiling'='SANDBOX_ACTIVE')
 THEN RAISE EXCEPTION 'CP_JUDGES_GOVERNED_CANDIDATE_NOT_READY'; END IF;
 IF v_sha !~ '^[a-f0-9]{64}$'
 OR to_regprocedure('programacion.fn_engineering_checkpoint_close_governed_v1(text,text,text,text)') IS NULL
 OR EXISTS(SELECT 1 FROM public.lf_operation_contracts WHERE operation_code=v_op)
 OR EXISTS(SELECT 1 FROM public.lf_operation_steps WHERE operation_code=v_op)
 OR EXISTS(SELECT 1 FROM public.lf_operation_judges WHERE operation_code=v_op)
 OR EXISTS(SELECT 1 FROM public.lf_operation_step_judge_bindings WHERE operation_code=v_op)
 OR EXISTS(SELECT 1 FROM public.lf_operation_step_contracts WHERE operation_code=v_op)
 OR EXISTS(SELECT 1 FROM public.lf_operation_policy_bindings WHERE operation_code=v_op)
 THEN RAISE EXCEPTION 'CP_JUDGES_DRIFT_OR_PREEXISTING_BINDING'; END IF;

 -- Test actual guarded insert in a rollback subtransaction first.
 BEGIN
  INSERT INTO public.lf_operation_contracts
  (operation_code,contract_code,contract_path,contract_sha,status,
   created_by_execution_id,updated_by_execution_id)
  VALUES(v_op,'CP_JUDGES_ROLLBACK_PROBE',v_ref,v_sha,
    'CANDIDATE_READ_ONLY',v_actor,v_actor);
  RAISE EXCEPTION 'CP_JUDGES_REVERSIBLE_PROBE' USING ERRCODE='PZ087';
 EXCEPTION WHEN SQLSTATE 'PZ087' THEN NULL;
 END;
 IF EXISTS (SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code=v_op AND contract_code='CP_JUDGES_ROLLBACK_PROBE')
 THEN RAISE EXCEPTION 'CP_JUDGES_ROLLBACK_LEFT_RESIDUE'; END IF;

 INSERT INTO public.lf_operation_contracts
 (operation_code,contract_code,contract_path,contract_sha,required_before_write,
  allowed,blocked,required_after_write,status,created_by_execution_id,updated_by_execution_id)
 VALUES (v_op,v_contract,v_ref,v_sha,
  jsonb_build_object('router_signed_execution',true,'authenticated_runner',true,
   'owner_role','SUPER_ADMIN','exact_checkpoint_scope',true,
   'provider_current',true,'effect_guard_reserved',true,
   'assertion_contract_current',true),
  jsonb_build_object('target_count_max',1,'runtime_effect_enabled',false,
   'checkpoint_close_operation',true,'production_promotion',false,
   'executed_via_train',false),
  jsonb_build_array('UNAUTHENTICATED_CALL','STALE_SOURCE','FORGED_RECEIPT',
   'OTHER_CHECKPOINT_WRITE','MISSING_ROUTER_AUTHORITY',
   'MISSING_GUARD','PRODUCTION_PROMOTION','WRONG_OWNER_ROLE'),
  jsonb_build_object('receipt_sha256_verified',true,'done_guard_enforced',true,
   'effect_scope_exact',true,'readback_canonical',true),
  'CANDIDATE_READ_ONLY',v_actor,v_actor);

 INSERT INTO public.lf_operation_policy_bindings
 (operation_code,policy_code,policy_role,required,distribution_modes,binding_status,
  created_by_execution_id,updated_by_execution_id)
 VALUES
 (v_op,'POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor),
 (v_op,'POL-LF-POLICY-CONSUMPTION','POLICY_CONSUMPTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor),
 (v_op,'POL-LF-SOURCE-RESOLUTION','SOURCE_RESOLUTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor),
 (v_op,'POL-LF-STATE-MODEL','STATE_MODEL',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor);

 INSERT INTO public.lf_operation_steps
 (operation_code,step_order,step_id,required,evidence_required,source_path,
  source_sha,active,execution_order,created_by_execution_id,updated_by_execution_id)
 VALUES
 (v_op,0,'init_execution',true,'execution_id,target_code',v_ref,v_sha,true,0,v_actor,v_actor),
 (v_op,10,'router_authority',true,'router_receipt,operation_revision_sha256',v_ref,v_sha,true,10,v_actor,v_actor),
 (v_op,20,'provider_readback',true,'provider_ref,source_current,proof_sha256',v_ref,v_sha,true,20,v_actor,v_actor),
 (v_op,30,'material_assertion',true,'assertion_contract_sha256,assertion_receipt_sha256',v_ref,v_sha,true,30,v_actor,v_actor),
 (v_op,40,'checkpoint_transition',true,'from_status,to_status,effect_guard_receipt',v_ref,v_sha,true,40,v_actor,v_actor),
 (v_op,50,'independent_readback',true,'checkpoint_status,receipt_sha,next_checkpoint',v_ref,v_sha,true,50,v_actor,v_actor);

 FOR s IN
  SELECT st.step_order,st.step_id,st.evidence_required,
   lead(st.step_id) OVER (ORDER BY st.step_order) next_step
  FROM public.lf_operation_steps st
  WHERE st.operation_code=v_op AND st.required=true AND st.active=true
  ORDER BY st.step_order
 LOOP
  v_keys:=to_jsonb(regexp_split_to_array(s.evidence_required,'\s*,\s*'));
  v_judge:='MINI_JUDGE_CHECKPOINT_CLOSE_'||upper(s.step_id)||'_V1';
  v_assertion:='checkpoint_close_'||s.step_id||'_verified';
  IF jsonb_array_length(v_keys)<2
  THEN RAISE EXCEPTION 'CP_JUDGE_INVALID_EVIDENCE_KEYS:%',s.step_id; END IF;

  INSERT INTO public.lf_operation_step_contracts
  (operation_code,step_id,step_order,execution_order,contract_code,purpose,
   input_required,resolver_ref,output_payload,pass_condition,block_condition,
   blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,
   next_if_blocked,status,notes,created_by_execution_id,updated_by_execution_id)
  VALUES(v_op,s.step_id,s.step_order,s.step_order,v_contract,
    'Independently compare checkpoint '||s.step_id||' with trusted canonical readback.',
    '[]'::jsonb,'AUTHENTICATED_CHECKPOINT_OPERATION_READBACK_V1',
    v_keys,
    jsonb_build_object('server_verified_assertion',v_assertion,
      'validator_source',v_ref,'validator_sha256',v_sha),
    jsonb_build_object('missing_required_evidence',true,
      'untrusted_authority',true,'readback_mismatch',true),
    'BLOCKED_CHECKPOINT_CLOSE_'||upper(s.step_id)||'_NOT_CLEAN',
    v_judge,v_keys,s.next_step,'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
    'Judge ACTIVE_ENFORCEMENT does not activate the parent operation.',
    v_actor,v_actor);

  INSERT INTO public.lf_operation_judges
  (operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,
   result_values,status,created_by_execution_id,updated_by_execution_id)
  VALUES(v_op,v_judge,v_ref,v_sha,
   jsonb_build_array(v_assertion),
   jsonb_build_array('server_validation_failed','checkpoint_close_'||s.step_id||'_mismatch'),
   jsonb_build_array('STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER'),
   'ACTIVE_ENFORCEMENT',v_actor,v_actor);

  INSERT INTO public.lf_operation_step_judge_bindings
  (operation_code,step_order,step_id,judge_code,clean_result_value,
   blocked_result_value,return_result_value,required_evidence_keys,status,
   created_by_execution_id,updated_by_execution_id)
  VALUES(v_op,s.step_order,s.step_id,v_judge,
   'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
   v_keys,'ACTIVE_ENFORCEMENT',v_actor,v_actor);
 END LOOP;

 IF (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code=v_op AND active=true AND required=true)<>6
 OR (SELECT count(*) FROM public.lf_operation_step_contracts WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>6
 OR (SELECT count(*) FROM public.lf_operation_judges WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>6
 OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>6
 OR (SELECT count(*) FROM public.lf_operation_policy_bindings WHERE operation_code=v_op AND required AND binding_status='ACTIVE')<>4
 OR EXISTS(
  SELECT 1 FROM public.lf_operation_steps st
  LEFT JOIN public.lf_operation_step_contracts c ON c.operation_code=st.operation_code AND c.step_id=st.step_id AND c.step_order=st.step_order
  LEFT JOIN public.lf_operation_step_judge_bindings b ON b.operation_code=st.operation_code AND b.step_id=st.step_id AND b.step_order=st.step_order
  LEFT JOIN public.lf_operation_judges j ON j.operation_code=b.operation_code AND j.judge_code=b.judge_code
  WHERE st.operation_code=v_op AND (c.step_id IS NULL OR b.step_id IS NULL OR j.judge_code IS NULL OR c.mini_judge_code IS DISTINCT FROM b.judge_code)
 )
 OR EXISTS(SELECT 1 FROM public.lf_router_action_registry WHERE operation_code=v_op AND write_allowed=true)
 OR EXISTS(SELECT 1 FROM public.lf_operation_registry WHERE operation_code=v_op AND status<>'CANDIDATO_READ_ONLY')
 OR EXISTS(SELECT 1 FROM programacion.engineering_checkpoint_closure_providers_v1 WHERE binding_state<>'CANDIDATE')
 OR has_function_privilege('service_role','programacion.fn_engineering_checkpoint_close_governed_v1(text,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'CP_JUDGES_READBACK_NOT_ISOLATED'; END IF;
END $cp_judges$;
