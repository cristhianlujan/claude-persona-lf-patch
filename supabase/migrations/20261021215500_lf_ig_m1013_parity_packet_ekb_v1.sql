-- IG M10.13 / GIT_RUNTIME_PARITY: record verified packet-contract root cause.
-- EKB-only. No checkpoint transitions, tests, runtime or production actions.
-- PR -> CI/PASE -> LF Migration Merge Train -> Supabase readback.
BEGIN;
DO $m1013_ekb_pre$
DECLARE
  v_spec jsonb;
  v_packet jsonb;
BEGIN
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
            WHERE codigo='IG-M1013-REPOSITORY-REPAIR-POLICY-054') THEN
    RAISE EXCEPTION 'IG_M1013_EKB_ALREADY_EXISTS';
  END IF;

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.13','GIT_RUNTIME_PARITY');
  v_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.13','GIT_RUNTIME_PARITY',
    v_spec,'{}'::jsonb);

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
    OR v_spec#>>'{repair_policy,mode}' IS DISTINCT FROM 'NONE'
    OR v_spec->>'transversal_capability_code' IS DISTINCT FROM 'MIGRATION_SOURCE_PARITY'
    OR v_packet->>'status' IS DISTINCT FROM 'READY'
    OR v_packet->>'capability_mode' IS DISTINCT FROM 'REPOSITORY_CAPABILITY'
    OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
                  WHERE work_item_id=474 AND checkpoint_code='GIT_RUNTIME_PARITY'
                    AND status='PENDING')
  THEN
    RAISE EXCEPTION 'IG_M1013_EKB_PRECONDITION_FAILED';
  END IF;
END $m1013_ekb_pre$;

INSERT INTO public.lf_error_knowledge (
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES (
 'IG-M1013-REPOSITORY-REPAIR-POLICY-054',
 'GOVERNANCE',
 'M10.13 CP2: política de reparación de prueba aplicada indebidamente a capability de repositorio',
 'El checkpoint GIT_RUNTIME_PARITY compila action spec READY para MIGRATION_SOURCE_PARITY, pero antes del fix su execution packet devolvía BLOCK_FAILED_TEST_REPAIR_PACKET_INCOMPLETE sin existir un test authored fallido ni targets declarados para reparar.',
 'La clasificación legacy VERIFY_QUERY_ONCE inyectó REPAIR_DECLARED_TARGET_THEN_RETEST en el action spec base. La capacidad transversal REPOSITORY_CAPABILITY_EXECUTION heredó esa política incompatible.',
 'PHANTOM_FAILED_TEST_REPAIR_POLICY_ON_REPOSITORY_CAPABILITY',
 'Para checkpoints de capacidad de repositorio, declarar la clasificación estructural exacta en el action spec del checkpoint, no convertir pruebas no fallidas en flujos de reparación; mantener versión CURRENT/RELEASED dinámica, inputs reales y ejecución material independiente. Nunca contar packet READY como paridad PASS.',
 'Verificación previa: packet BLOCK_FAILED_TEST_REPAIR_PACKET_INCOMPLETE. PR #3050 (merge 321944e8de11efea6808dfd09a61738a89842b72) por LF Merge Train corrige solo el contrato. Supabase readback actual: spec READY, repair_policy NONE, capability MIGRATION_SOURCE_PARITY, packet READY, mode REPOSITORY_CAPABILITY, GIT_RUNTIME_PARITY PENDING. La paridad FULL_CURRENT_STATE material sigue pendiente; sin producción.',
 'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
 'GitHub PR #3050 / commit 321944e8de11efea6808dfd09a61738a89842b72; migration 20261021215000_lf_ig_m1013_parity_packet_contract_v1; live Supabase derived spec and packet readback. CP2 remains PENDING.',
 'GOVERNANCE',ARRAY['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
 'R5_EROSION_PROCESO','LOUD_EARLY','M10.13/GIT_RUNTIME_PARITY',
 'github://cristhianlujan/claude-persona-lf-patch/pull/3050'
);

DO $m1013_ekb_post$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge
     WHERE codigo='IG-M1013-REPOSITORY-REPAIR-POLICY-054'
       AND estado='VERIFICADO') <> 1
 THEN RAISE EXCEPTION 'IG_M1013_EKB_READBACK_FAILED'; END IF;
END $m1013_ekb_post$;
COMMIT;