-- PE10 C6: EKB preventive learning from PASE workflow path protection.
-- Register learning only. No CI gate changes, no code/runtime activation.
BEGIN;
DO $preflight$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1')
 OR NOT EXISTS (SELECT 1 FROM public.lf_eventos WHERE id=21479
   AND entidad_codigo='PE10_C6.OUTPUT_READER_ROLLBACK_PROBE.V1'
   AND payload->>'checkpoint_pass'='false')
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7')
     AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'PE10_C6_GOVERNANCE_EKB_PRESTATE_FAILED'; END IF;
END $preflight$;
SAVEPOINT pe10_c6_workflow_ekb_rehearsal;
INSERT INTO public.lf_error_knowledge(
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,lote_origen,pr,estado,source_ref,lifecycle_phase,
 root_cause_family,detectability,source_context
) VALUES(
 'PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1','PROFILE_EVOLUTION',
 'Prueba canónica intentó abrir una ruta CI de pull_request no autorizada',
 'En PR #3084 el nuevo workflow perfil-salida falló en PASE run 39767069642 por no estar allowlisted. Al moverlo al workflow existente, run 39767264454 rechazó modificar .github/workflows/ por FAIL_UNAUTHORIZED_GITHUB_PATH. Se eliminó el workflow nuevo y se restauró íntegramente el existente.',
 'La propuesta de pruebas se cableó fuera del límite de autoridad de cambios de workflows gestionado por la lista permitida y por la protección de rutas del repositorio.',
 'ADICION_O_MODIFICACION_WORKFLOW_PROTEGIDO_SIN_RUTA_DE_ADMISION_CI',
 'Antes de crear/modificar .github/workflows comprobar si el path está gobernado y utilizar lane autorizada de CI. No desactivar ni relajar PASE para hacer pasar un cambio de test. Si requiere workflow nuevo, tramitarlo por el responsable CI y conservar el código de prueba en rama no aplicada.',
 'El PR #3084 eliminó el workflow no autorizado, preservó la fuente del workflow anterior sin diferencias y PASE exact-head SUCCESS; Train #39767493192 mergeado. Test real de canónico PASS en run 39767069689 previo a retirar el nuevo workflow.',
 'MEDIUM',2,'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C6',3084,'ACTIVO',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3084',
 'construction','R2_NO_VE','LOUD_EARLY',
 'PE10_C6_PASE_CI_WORKFLOW_GOVERNANCE_PR3084_20261022'
);
DO $positive$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge
  WHERE codigo='PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1')<>1
 THEN RAISE EXCEPTION 'PE10_C6_EKB_POSITIVE_REHEARSAL_FAILED'; END IF;
END $positive$;
ROLLBACK TO SAVEPOINT pe10_c6_workflow_ekb_rehearsal;
RELEASE SAVEPOINT pe10_c6_workflow_ekb_rehearsal;
DO $rollback$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1')
 THEN RAISE EXCEPTION 'PE10_C6_EKB_REHEARSAL_LEAK'; END IF;
END $rollback$;
INSERT INTO public.lf_error_knowledge(
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,lote_origen,pr,estado,source_ref,lifecycle_phase,
 root_cause_family,detectability,source_context
) VALUES(
 'PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1','PROFILE_EVOLUTION',
 'Prueba canónica intentó abrir una ruta CI de pull_request no autorizada',
 'PR #3084: PASE #39767069642 rechazó nuevo workflow no allowlisted; PASE #39767264454 rechazó modificar workflow protegido. Se restauraron ambos y el PR de dos archivos pasó PASE.',
 'Prueba vinculada a ruta CI no autorizada por política de gobernanza de workflows.',
 'ADICION_O_MODIFICACION_WORKFLOW_PROTEGIDO_SIN_RUTA_DE_ADMISION_CI',
 'No crear o modificar .github/workflows fuera del circuito CI autorizado. Utilizar tests y herramientas del lane existente; no relajar PASE ni simular PASS.',
 'PR #3084 mergeado Train #39767493192; PASE verde después de retirar todos los cambios bajo .github/workflows. La prueba fuente anterior corrió GREEN en #39767069689.',
 'MEDIUM',2,'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C6',3084,'ACTIVO',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3084',
 'construction','R2_NO_VE','LOUD_EARLY',
 'PE10_C6_PASE_CI_WORKFLOW_GOVERNANCE_PR3084_20261022'
);
DO $readback$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE
   codigo='PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1'
   AND categoria='PROFILE_EVOLUTION' AND estado='ACTIVO')<>1
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7')
     AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'PE10_C6_EKB_DURABLE_READBACK_FAILED'; END IF;
END $readback$;
COMMIT;
