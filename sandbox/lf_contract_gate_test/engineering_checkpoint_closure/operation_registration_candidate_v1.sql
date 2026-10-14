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


-- EKB source will be recorded only by an approved initial installation.
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,
 severidad,estado,lote_origen,source_context,source_ref)
SELECT
 'ENGINEERING-CHECKPOINT-CLOSURE-OPERATION-MISSING-001','ENGINEERING_GOVERNANCE',
 'Resultado funcional de checkpoint sin operación administrativa de cierre',
 'Un readback aprobado no puede cambiar el ledger sin autoridad de escritura.',
 'Se usó una migración puntual de datos para persistir el cierre de un checkpoint.',
 'Separar evidencia de validación y operación de cierre, con Router + S30 + assertion receipt vinculante; no modificar Train ni llamar RPC directa.',
 'Cerrar un checkpoint con un ejecutor autorizado, prueba positiva real, negativos adversariales y readback DONE con hash.',
 'ALTA','ACTIVO','M10.5/CP2',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2657'
WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='ENGINEERING-CHECKPOINT-CLOSURE-OPERATION-MISSING-001');

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
