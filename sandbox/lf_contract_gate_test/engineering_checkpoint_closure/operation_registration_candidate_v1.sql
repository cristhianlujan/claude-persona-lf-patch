-- CANDIDATE DATA SCRIPT: do not run without governed initial installation.
-- Registers no ACTIVE route and grants no privileges.
BEGIN;
INSERT INTO public.lf_operation_registry
(operation_code,version,status,source_model,source_repo,source_paths,notes,
 operation_family,operation_domain,operation_type,applies_to_asset_type,
 lifecycle_state_code,created_by_execution_id)
SELECT
 'CIERRE_CHECKPOINT_INGENIERIA_LF','v0.1','CANDIDATO_READ_ONLY',
 'SUPABASE_STRUCTURED_OPERATION',
 'cristhianlujan/claude-persona-lf-patch',
 jsonb_build_array(
  'docs/operations/CIERRE_CHECKPOINT_INGENIERIA_LF_CONTRACT_V1.md',
  'sandbox/lf_contract_gate_test/engineering_checkpoint_closure/operation_candidate_v1.sql',
  'sandbox/lf_contract_gate_test/engineering_checkpoint_closure/ig_m105_cp2_provider_candidate_v1.sql'),
 'Administrative engineering checkpoint close only; not a DB migration transport or production admission',
 'ENGINEERING_GOVERNANCE','ENGINEERING_CHECKPOINT_LIFECYCLE',
 'CONTROLLED_ADMINISTRATIVE_TRANSITION','ENGINEERING_CHECKPOINT',
 'OP_CANDIDATE','EXEC-CANDIDATE-ENGINEERING-CHECKPOINT-CLOSURE-V1'
WHERE NOT EXISTS (SELECT 1 FROM public.lf_operation_registry
 WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF');

INSERT INTO public.lf_router_action_registry
(asset_type,action_code,operation_code,operation_resolution,
 requires_existing_target,requires_missing_target,
 write_allowed,status,notes,created_by_execution_id)
SELECT 'ENGINEERING_CHECKPOINT','CHECKPOINT_CLOSE',
 'CIERRE_CHECKPOINT_INGENIERIA_LF','STATIC',
 false,false,false,'CANDIDATE',
 'Router action candidate only; no write until downstream authority consumer, op contracts and effect guard admitted',
 'EXEC-CANDIDATE-ENGINEERING-CHECKPOINT-CLOSURE-V1'
WHERE NOT EXISTS (SELECT 1 FROM public.lf_router_action_registry
 WHERE asset_type='ENGINEERING_CHECKPOINT' AND action_code='CHECKPOINT_CLOSE');

DO $admission$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_registry
  WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
    AND status='CANDIDATO_READ_ONLY' AND lifecycle_state_code='OP_CANDIDATE')
 THEN RAISE EXCEPTION 'CHECKPOINT_CLOSURE_CANDIDATE_REGISTRY_NOT_ISOLATED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_router_action_registry
  WHERE asset_type='ENGINEERING_CHECKPOINT' AND action_code='CHECKPOINT_CLOSE'
    AND operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
    AND status='CANDIDATE' AND write_allowed=false)
 THEN RAISE EXCEPTION 'CHECKPOINT_CLOSURE_CANDIDATE_ROUTER_NOT_ISOLATED'; END IF;
END $admission$;
COMMIT;
