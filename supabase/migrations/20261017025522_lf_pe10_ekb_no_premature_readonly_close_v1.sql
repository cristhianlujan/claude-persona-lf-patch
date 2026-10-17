-- LF Profile Updater / PE10: registrar error operativo de cierre prematuro.
-- Ruta de escritura: ACT-0001 (MIGRATION + UPDATE) -> ACTUALIZACION_DB_LF -> PR -> CI -> PASE -> LF Merge Train.
-- No cambia el estado de PE10_C5/C6/C7, autorizaciones, contratos, runtime ni version v0.1.
BEGIN;
DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'
  ) THEN
    RAISE EXCEPTION 'PE10_EKB_DUPLICATE_RECONCILE_EXISTING';
  END IF;
END $preflight$;

SAVEPOINT pe10_ekb_positive_probe;
INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context)
VALUES
('CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL',
 'PROFILE_EVOLUTION',
 'Un fallo read-only no demuestra bloqueo global: recuperar Router tipado y LF Merge Train',
 'Durante recuperacion LF PE10 se comprobo que la consulta libre al Router sobre escritura de EKB producia BLOCK_OPERATION_NOT_REGISTERED / BLOCK_EXECUTOR_CAPABILITY_UNATTESTED o una ruta ajena a DB. El mismo Router, con hints tipados p_action_hint=UPDATE y p_asset_type_hint=MIGRATION, devolvio READY_TO_EXECUTE con operation_code ACTUALIZACION_DB_LF. El conector Supabase read-only no es el ejecutor de la migracion.',
 'Error de criterio: inferir imposibilidad global a partir de la interfaz RO o de una resolucion lexica del Router sin probar la firma tipada, la ruta canónica existente y los precedentes del Train. La identidad de la operacion y el destino no estaban resueltos antes del diagnostico.',
 'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL: un transporte no disponible se trata erradamente como prohibicion absoluta; una clasificacion libre de ACT-0001 oculta la ruta tipada funcional.',
 'Antes de declarar un bloqueo, leer EKB y firma del Router, probar hints tipados del sujeto y accion real, inspeccionar operation_code/politicas, DB_WRITE_TRANSPORT y precedentes exactos del Train. Para DB usar exclusivamente PR+CI+PASE+ready-to-merge+LF Merge Train y verificar readback. No convertir respuestas de Router no admitidas en permiso ni inventar receipts; investigar si la ruta tipada falla y clasificar CONTINUABLE mientras exista un camino autorizado.',
 'Readback 2026-10-17: Router free-text para EKB/MIGRATION dio BLOCKED o ruta CREACION_SKILL_LF; SELECT public.lf_router_resolve_v1(request,NULL,UPDATE,MIGRATION,ROUTER) devolvio READY_TO_EXECUTE / ACTUALIZACION_DB_LF / downstream_execution_allowed=true. ACTUALIZACION_DB_LF v0.1 SANDBOX_ACTIVE, PR #2860 integrado por Train con ejecucion EXEC-DB-TRAIN-PR2860-20261017022000-R38993917528 COMPLETED. PE10_C5/C6/C7 continúan PENDING. Prueba de escritura via SAVEPOINT / rollback y readback durable.',
 'MEDIUM',1,'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5',
 'ACTIVO','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2860',
 'construction','R2_NO_VE','PROCESS_DEPENDENT','LF_PE10_PROFILE_UPDATER_RECOVERY_20261017');

DO $test_positive$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge
     WHERE codigo='CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'
       AND estado='ACTIVO'
       AND root_cause_family='R2_NO_VE'
       AND detectability='PROCESS_DEPENDENT') <> 1
 THEN RAISE EXCEPTION 'PE10_EKB_INSERT_PROBE_FAILED'; END IF;
END $test_positive$;
ROLLBACK TO SAVEPOINT pe10_ekb_positive_probe;
DO $test_rollback$
BEGIN
 IF EXISTS (
   SELECT 1 FROM public.lf_error_knowledge
   WHERE codigo='CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'
 ) THEN RAISE EXCEPTION 'PE10_EKB_ROLLBACK_LEAK'; END IF;
END $test_rollback$;
RELEASE SAVEPOINT pe10_ekb_positive_probe;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context)
VALUES
('CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL',
 'PROFILE_EVOLUTION',
 'Un fallo read-only no demuestra bloqueo global: recuperar Router tipado y LF Merge Train',
 'Durante recuperacion LF PE10 se comprobo que la consulta libre al Router sobre escritura de EKB producia BLOCK_OPERATION_NOT_REGISTERED / BLOCK_EXECUTOR_CAPABILITY_UNATTESTED o una ruta ajena a DB. El mismo Router, con hints tipados p_action_hint=UPDATE y p_asset_type_hint=MIGRATION, devolvio READY_TO_EXECUTE con operation_code ACTUALIZACION_DB_LF. El conector Supabase read-only no es el ejecutor de la migracion.',
 'Error de criterio: inferir imposibilidad global a partir de la interfaz RO o de una resolucion lexica del Router sin probar la firma tipada, la ruta canónica existente y los precedentes del Train. La identidad de la operacion y el destino no estaban resueltos antes del diagnostico.',
 'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL: un transporte no disponible se trata erradamente como prohibicion absoluta; una clasificacion libre de ACT-0001 oculta la ruta tipada funcional.',
 'Antes de declarar un bloqueo, leer EKB y firma del Router, probar hints tipados del sujeto y accion real, inspeccionar operation_code/politicas, DB_WRITE_TRANSPORT y precedentes exactos del Train. Para DB usar exclusivamente PR+CI+PASE+ready-to-merge+LF Merge Train y verificar readback. No convertir respuestas de Router no admitidas en permiso ni inventar receipts; investigar si la ruta tipada falla y clasificar CONTINUABLE mientras exista un camino autorizado.',
 'Readback 2026-10-17: Router free-text para EKB/MIGRATION dio BLOCKED o ruta CREACION_SKILL_LF; SELECT public.lf_router_resolve_v1(request,NULL,UPDATE,MIGRATION,ROUTER) devolvio READY_TO_EXECUTE / ACTUALIZACION_DB_LF / downstream_execution_allowed=true. ACTUALIZACION_DB_LF v0.1 SANDBOX_ACTIVE, PR #2860 integrado por Train con ejecucion EXEC-DB-TRAIN-PR2860-20261017022000-R38993917528 COMPLETED. PE10_C5/C6/C7 continúan PENDING. Prueba de escritura via SAVEPOINT / rollback y readback durable.',
 'MEDIUM',1,'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5',
 'ACTIVO','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2860',
 'construction','R2_NO_VE','PROCESS_DEPENDENT','LF_PE10_PROFILE_UPDATER_RECOVERY_20261017');
DO $test_durable$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge
     WHERE codigo='CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'
       AND estado='ACTIVO'
       AND categoria='PROFILE_EVOLUTION'
       AND root_cause_family='R2_NO_VE') <> 1
 THEN RAISE EXCEPTION 'PE10_EKB_FINAL_READBACK_FAILED'; END IF;
END $test_durable$;
COMMIT;
