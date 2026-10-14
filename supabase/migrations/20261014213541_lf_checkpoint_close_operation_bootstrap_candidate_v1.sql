-- Initial governed candidate registration for CIERRE_CHECKPOINT_INGENIERIA_LF.
-- NO activation, NO GRANT, NO checkpoint mutation. Migration Train only.
-- Uses existing VULNERABILITY_COVERAGE_REPAIR_LF provenance bootstrap pattern.
DO $ck$
DECLARE
 v_op constant text := 'CIERRE_CHECKPOINT_INGENIERIA_LF';
 v_actor constant text := 'EXEC-CHECKPOINT-OP-BOOTSTRAP-20261014-001';
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_registry
   WHERE operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
   AND lifecycle_state_code='OP_OPERATIONAL')
 OR EXISTS(SELECT 1 FROM public.lf_operation_registry WHERE operation_code=v_op)
 OR EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_actor)
 OR EXISTS(SELECT 1 FROM public.lf_router_action_registry
   WHERE asset_type='ENGINEERING_CHECKPOINT' AND action_code='CHECKPOINT_CLOSE')
 THEN RAISE EXCEPTION 'CHECKPOINT_OP_BOOTSTRAP_PRECONDITION_FAILED'; END IF;
 IF to_regprocedure('programacion.fn_engineering_checkpoint_close_governed_v1(text,text,text,text)') IS NULL
 OR NOT EXISTS (SELECT 1 FROM programacion.engineering_checkpoint_closure_providers_v1
    WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5'
      AND checkpoint_code='NEW_RUNS_VNEXT' AND binding_state='CANDIDATE')
 THEN RAISE EXCEPTION 'CHECKPOINT_OP_CANDIDATE_NOT_INSTALLED'; END IF;
 -- Run native provenance guard under a reversible subtransaction.
 BEGIN
   INSERT INTO public.lf_operation_execution
    (execution_id,operation_code,target_type,target_code,status,manifest,
     created_by_execution_id,updated_by_execution_id)
   VALUES(v_actor,'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR',
      v_op,'IN_PROGRESS',jsonb_build_object('governance_bootstrap',true,
      'bootstrap_operation_code',v_op,'bootstrap_status_ceiling','SANDBOX_ACTIVE',
      'candidate_only',true,'production_allowed',false),v_actor,v_actor);
   INSERT INTO public.lf_operation_registry
    (operation_code,version,status,source_model,source_repo,source_paths,notes,
     operation_family,operation_domain,operation_type,applies_to_asset_type,
     lifecycle_state_code,created_by_execution_id,updated_by_execution_id)
   VALUES(v_op,'v1.0-candidate','CANDIDATO_READ_ONLY',
     'SUPABASE_OPERATIONAL_AUTHORITY_WITH_GIT_MIRROR',
     'cristhianlujan/claude-persona-lf-patch',
     jsonb_build_array('docs/operations/CIERRE_CHECKPOINT_INGENIERIA_LF_CONTRACT_V1.md'),
     'Candidate engineering checkpoint close; no effects authorized.',
     'ENGINEERING_GOVERNANCE','ENGINEERING_CHECKPOINT_LIFECYCLE',
     'CONTROLLED_ADMINISTRATIVE_TRANSITION','ENGINEERING_CHECKPOINT',
     'OP_CANDIDATE',v_actor,v_actor);
   RAISE EXCEPTION 'ROLLBACK_CHECKPOINT_BOOTSTRAP_PROBE' USING ERRCODE='PZ086';
 EXCEPTION WHEN SQLSTATE 'PZ086' THEN NULL;
 END;
 IF EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_actor)
 OR EXISTS(SELECT 1 FROM public.lf_operation_registry WHERE operation_code=v_op)
 THEN RAISE EXCEPTION 'CHECKPOINT_BOOTSTRAP_PROBE_LEFT_RESIDUE'; END IF;
 -- Persist a scope-checked *candidate* only.
 INSERT INTO public.lf_operation_execution
  (execution_id,operation_code,target_type,target_code,status,manifest,
   created_by_execution_id,updated_by_execution_id)
 VALUES(v_actor,'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR',
   v_op,'IN_PROGRESS',jsonb_build_object('governance_bootstrap',true,
   'bootstrap_operation_code',v_op,'bootstrap_status_ceiling','SANDBOX_ACTIVE',
   'candidate_only',true,'production_allowed',false),v_actor,v_actor);
 INSERT INTO public.lf_operation_registry
  (operation_code,version,status,source_model,source_repo,source_paths,notes,
   operation_family,operation_domain,operation_type,applies_to_asset_type,
   lifecycle_state_code,created_by_execution_id,updated_by_execution_id)
 VALUES(v_op,'v1.0-candidate','CANDIDATO_READ_ONLY',
   'SUPABASE_OPERATIONAL_AUTHORITY_WITH_GIT_MIRROR',
   'cristhianlujan/claude-persona-lf-patch',
   jsonb_build_array('docs/operations/CIERRE_CHECKPOINT_INGENIERIA_LF_CONTRACT_V1.md',
     'sandbox/lf_contract_gate_test/engineering_checkpoint_closure/operation_candidate_v1.sql'),
   'Candidate checkpoint administrative closure. Router/effects still disabled.',
   'ENGINEERING_GOVERNANCE','ENGINEERING_CHECKPOINT_LIFECYCLE',
   'CONTROLLED_ADMINISTRATIVE_TRANSITION','ENGINEERING_CHECKPOINT',
   'OP_CANDIDATE',v_actor,v_actor);
 INSERT INTO public.lf_router_action_registry
  (asset_type,action_code,operation_code,operation_resolution,
   requires_existing_target,requires_missing_target,write_allowed,status,notes,
   created_by_execution_id,updated_by_execution_id)
 VALUES('ENGINEERING_CHECKPOINT','CHECKPOINT_CLOSE',v_op,'STATIC',
    false,false,false,'CANDIDATO_READ_ONLY',
    'No write. Requires Router qualification and separate explicit admission.',
    v_actor,v_actor);
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code=v_op AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE')
 OR NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry
    WHERE asset_type='ENGINEERING_CHECKPOINT' AND action_code='CHECKPOINT_CLOSE'
      AND status='CANDIDATO_READ_ONLY' AND write_allowed=false)
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=477 AND checkpoint_code='NEW_RUNS_VNEXT'
      AND status='PENDING' AND assertion_receipt_sha256 IS NULL)
 THEN RAISE EXCEPTION 'CHECKPOINT_CANDIDATE_READBACK_FAILED'; END IF;
END $ck$;
