-- PE10 C6 EKB: real CI regression from stale 11->13 planner test floor.
-- Only knowledge registration. No change to checkpoint, operation, CI, policy.
-- Governed SQL transport exclusively through LF Migration Merge Train.
BEGIN;
DO $ekb$
DECLARE
 v_code constant text := 'PE10_C6_DECLARED_PLANNER_TEST_COUNT_DRIFT_V1';
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
  OR NOT EXISTS (
    SELECT 1 FROM public.lf_eventos WHERE id=21504
      AND entidad_codigo='PE10_C6.EXPLICIT_GITHUB_TEST_EXECUTOR_BOUND.V1'
      AND payload->>'checkpoint_pass'='false'
      AND payload->>'test_runner_packet_compiles'='true'
  )
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
  OR (SELECT programacion.fn_engineering_checkpoint_execution_readiness_v1(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C6')->>'status') IS DISTINCT FROM 'READY'
 THEN RAISE EXCEPTION 'PE10_C6_STALE_CASE_FLOOR_EKB_PRESTATE_INVALID'; END IF;

 -- A controlled SAVEPOINT trial checks that this INSERT is rollback-safe.
 INSERT INTO public.lf_error_knowledge (
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,lote_origen,pr,estado,source_ref,lifecycle_phase,
    root_cause_family,detectability,source_context
 ) VALUES (
    v_code,'PROFILE_EVOLUTION',
    'El gate C6 exigía 11 casos del planificador aunque ya contenía 13',
    'En el PR #3115 el primer run #39896250701 hizo fallar el job real del test declarado con TEST_COUNT_MISMATCH:planner:13!=11. La suite tenía 13 test_* auténticos; el script de C6 todavía esperaba 11 por conteo histórico. Se actualizó el piso declarado a 13 y el total de 55 a 57.',
    'La incorporación de nuevos casos al planificador no actualizó el inventario exacto de pruebas del test canónico C6; el error no era de la regla ni del motor de ejecución.',
    'DRIFT_UMBRAL_CASOS_TEST_DECLARADO_FRENTE_A_SUITE_REAL',
    'Al modificar suites canónicas, reconciliar el número de test_* contra el manifiesto congelado de C6 con readback de fuente y ejecución de CI; actualizar solo el contrato de test cuando los nuevos casos están presentes y pasan realmente. Nunca autodecrementar conteos ni fabricar resultados PASS.',
    'PR #3115 mergeado mediante Train #39896421673. Run #39896340892 SUCCESS, job capture-regression ejecutó el test declarado: 57 casos, recibo SHA256 ab65deba0ca86a2b58faf4ca41edcec437e998511c782bee9607a65e8b07b252, status SOURCE_PROBES_PASS_DB_TRANSACTION_NOT_CLAIMED. PR #3117 compiló luego el runner en Supabase, evento #21504.',
    'MEDIUM',1,'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C6',3115,'ACTIVO',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3115',
    'construction','R2_NO_VE','LOUD_EARLY','PE10_C6_TEST_FLOOR_DRIFT_20261023'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code AND estado='ACTIVO'
      AND root_cause_family='R2_NO_VE' AND frecuencia=1)<>1
 THEN RAISE EXCEPTION 'PE10_C6_CASE_FLOOR_EKB_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
