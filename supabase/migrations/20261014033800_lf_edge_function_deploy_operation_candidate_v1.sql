-- Candidate-only LF Operation for existing Supabase Edge Functions.
-- Operational change is a governed runtime effect, NOT a DB migration effect.
-- This SQL registers authority (via Train); it never deploys, activates, promotes,
-- creates Edge secrets, executes Input Governance, or writes a CP2 receipt.

DO $edge$
DECLARE
  v_actor constant text := 'EXEC-BOOTSTRAP-EDGE-FUNCTION-OP-20261014-001';
  v_op constant text := 'DEPLOY_SUPABASE_EDGE_FUNCTION_LF';
  v_sha constant text := '58995a9bc71074f0a0f1854ee0b4674d85112d910192747dcf2130174d739836';
  v_path constant text := 'sandbox/lf_contract_gate_test/edge_function_operation/edge_deploy_guard_v1.py';
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_operation_registry WHERE operation_code=v_op) THEN
    RAISE EXCEPTION 'EDGE_OPERATION_ALREADY_REGISTERED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_router_action_registry
             WHERE asset_type='SUPABASE_EDGE_FUNCTION' AND action_code='EDGE_FUNCTION_DEPLOY') THEN
    RAISE EXCEPTION 'EDGE_OPERATION_ROUTER_ACTION_ALREADY_REGISTERED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos a
    WHERE a.codigo_activo='OPERATION_EFFECT_GUARD' AND a.estado_operativo='ACTIVO'
      AND a.metadata#>>'{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
  ) THEN
    RAISE EXCEPTION 'EDGE_OPERATION_TRANSVERSAL_EFFECT_GUARD_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM lf_ops.estados_catalogo WHERE state_code='OP_CANDIDATE') THEN
    RAISE EXCEPTION 'EDGE_OPERATION_CANDIDATE_STATE_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_registry
                 WHERE operation_code='VULNERABILITY_COVERAGE_REPAIR_LF') THEN
    RAISE EXCEPTION 'EDGE_OPERATION_BOOTSTRAP_CARRIER_MISSING';
  END IF;

  INSERT INTO public.lf_operation_execution(
     execution_id,operation_code,target_type,target_code,status,manifest,
     created_by_execution_id,updated_by_execution_id
  ) VALUES (
     v_actor,'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR',
     v_op,'IN_PROGRESS',
     jsonb_build_object('mode','EDGE_OPERATION_GOVERNANCE_BOOTSTRAP',
       'governance_bootstrap',true,'candidate_only',true,
       'production_allowed',false,'edge_deploy_executed',false,
       'no_release_promotion',true,'source_contract_sha256',v_sha),
     v_actor,v_actor
  );

  INSERT INTO public.lf_operation_registry(
    operation_code,version,status,source_model,source_repo,source_paths,notes,
    operation_family,operation_domain,operation_type,applies_to_asset_type,
    lifecycle_state_code,created_by_execution_id,updated_by_execution_id
  ) VALUES (
    v_op,'v1.0-candidate','CANDIDATO_READ_ONLY',
    'SUPABASE_OPERATIONAL_AUTHORITY_WITH_GIT_MIRROR',
    'cristhianlujan/claude-persona-lf-patch',
    jsonb_build_array(v_path,'sandbox/lf_contract_gate_test/edge_function_operation/README.md'),
    'Candidate-only generic single-function Edge deploy. R17, signed runtime authority, exact main+rollback, existing effect guard, independent readback. No automatic activation.',
    'TRANSVERSAL_RUNTIME_OPERATIONS','SUPABASE_EDGE_FUNCTION',
    'EDGE_FUNCTION_DEPLOY','SUPABASE_EDGE_FUNCTION',
    'OP_CANDIDATE',v_actor,v_actor
  );

  INSERT INTO public.lf_operation_contracts(
    operation_code,contract_code,contract_path,contract_sha,
    required_before_write,allowed,blocked,required_after_write,status,
    created_by_execution_id,updated_by_execution_id
  ) VALUES (
    v_op,'CONTRACT-DEPLOY-SUPABASE-EDGE-FUNCTION-LF-v1',v_path,v_sha,
    jsonb_build_object(
      'exact_main_sha_required',true,
      'target_isolation_required',true,
      'deployed_rollback_source_parity_required',true,
      'jwt_mode_preservation_required',true,
      'r17_canonical_event_required',true,
      'signed_human_runtime_authorization_required',true,
      'operation_current_qualification_required',true,
      'operation_effect_guard_reserved_exact_required',true
    ),
    jsonb_build_object(
      'asset_type','SUPABASE_EDGE_FUNCTION',
      'target_count_max',1,
      'deployment_transport','GOVERNED_SUPABASE_EDGE_MANAGEMENT_API',
      'runtime_effect_enabled',false,
      'auto_release_promotion',false,
      'auto_cp2_execution',false,
      'sql_write_from_deployer',false
    ),
    jsonb_build_array(
      'SOURCE_NOT_EXACT_MAIN','UNAUTHORIZED_RUNTIME_EFFECT',
      'OPERATION_NOT_QUALIFIED','EFFECT_GUARD_NOT_RESERVED',
      'R17_PREFLIGHT_NOT_PASSED','ROLLBACK_NOT_LIVE_VERIFIED',
      'OTHER_FUNCTION_DELTA','JWT_MODE_DRIFT','SOURCE_DEPLOY_MISMATCH'
    ),
    jsonb_build_object(
      'independent_supabase_deployed_files_readback',true,
      'source_version_and_sha_reconciled',true,
      'single_real_oidc_preflight',true,
      'effect_receipt_required',true,
      'rollback_on_failure',true,
      'no_release_promotion',true
    ),
    'CANDIDATE_READ_ONLY',v_actor,v_actor
  );

  INSERT INTO public.lf_router_action_registry(
    asset_type,action_code,operation_code,operation_resolution,
    requires_existing_target,requires_missing_target,write_allowed,status,notes,
    created_by_execution_id,updated_by_execution_id
  ) VALUES (
    'SUPABASE_EDGE_FUNCTION','EDGE_FUNCTION_DEPLOY',v_op,'STATIC',
    true,false,false,'CANDIDATO_READ_ONLY',
    'Candidate route only; write=false pending authenticated Operations runner, R17 and independent readback.',
    v_actor,v_actor
  );

  INSERT INTO public.lf_operation_policy_bindings(
    operation_code,policy_code,policy_role,required,distribution_modes,binding_status,
    created_by_execution_id,updated_by_execution_id
  ) VALUES
    (v_op,'POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor),
    (v_op,'POL-LF-POLICY-CONSUMPTION','POLICY_CONSUMPTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor),
    (v_op,'POL-LF-SOURCE-RESOLUTION','SOURCE_RESOLUTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor),
    (v_op,'POL-LF-STATE-MODEL','STATE_MODEL',true,ARRAY['ROUTER','DIRECT'],'ACTIVE',v_actor,v_actor);

  INSERT INTO public.lf_operation_steps(
    operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
    active,execution_order,created_by_execution_id,updated_by_execution_id
  ) VALUES
    (v_op,0,'init_execution',true,'execution_id,target_code',v_path,v_sha,true,0,v_actor,v_actor),
    (v_op,10,'source_baseline',true,'exact_main_sha,rollback_sha,live_source_parity',v_path,v_sha,true,10,v_actor,v_actor),
    (v_op,20,'r17_preflight',true,'r17_event_id,timing,rollback_drill,idempotency',v_path,v_sha,true,20,v_actor,v_actor),
    (v_op,30,'human_authority',true,'signed_receipt,operation_current,scope_exact',v_path,v_sha,true,30,v_actor,v_actor),
    (v_op,40,'effect_guard',true,'effect_scope,request_sha256,reservation_receipt',v_path,v_sha,true,40,v_actor,v_actor),
    (v_op,50,'edge_deploy',true,'deploy_execution_id,provider_receipt,source_sha',v_path,v_sha,true,50,v_actor,v_actor),
    (v_op,60,'independent_readback',true,'deployed_source,oidc_probe,rollback_state',v_path,v_sha,true,60,v_actor,v_actor),
    (v_op,70,'close',true,'effect_guard_receipt,parity,open_blockers',v_path,v_sha,true,70,v_actor,v_actor);

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code=v_op AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE'
  ) OR EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
    WHERE asset_type='SUPABASE_EDGE_FUNCTION' AND action_code='EDGE_FUNCTION_DEPLOY'
      AND (status<>'CANDIDATO_READ_ONLY' OR write_allowed)
  ) THEN
    RAISE EXCEPTION 'EDGE_OPERATION_CANDIDATE_READBACK_FAILED';
  END IF;
END $edge$;
