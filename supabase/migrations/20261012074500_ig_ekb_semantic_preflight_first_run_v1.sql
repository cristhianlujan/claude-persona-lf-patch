-- EKB: first-run semantic prevention for M9.10, distinct from its contract defect.
-- Append only. Describes a method gap; does not claim a deployed automatic gate.
DO $ekb$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM transversal.error_knowledge
   WHERE codigo='IG-M99-REPETITIVE-SYMPTOM-PATCHING-001'
 ) OR NOT EXISTS (
   SELECT 1 FROM transversal.error_knowledge
   WHERE codigo='IG-M910-SANDBOX-LIVE-RECEIPTS-CONFLATION-001'
 ) THEN
   RAISE EXCEPTION 'EKB_RELATED_CASES_NOT_FOUND';
 END IF;

 INSERT INTO transversal.error_knowledge
   (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,
    evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
 SELECT
   'IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001',
   'ENGINEERING_PROCESS_DEFECT',
   'EKB leida pero antecedentes no contrastados con contrato en primera corrida',
   'Durante la primera ejecucion de M9.10 se consulto EKB y se encontro el antecedente de M9.9 sobre confusion entre pruebas sandbox y admision live. Sin embargo, se inspeccionaron capacidades y recibos faltantes sin contrastar el exit_criterion de M9.10, sus action_specs y gobernanza. Se creo el PR #2280 con el requisito operacional equivocado. La auditoria posterior encontro el problema y preparo PR #2281.',
   'Preflight formal basado en lectura textual de incidentes, sin vinculo semantico obligatorio entre error previo, naturaleza del nuevo checkpoint, exit_criterion, acceptance pass_when, gobernanza y capacidad realmente disponible. Se diagnostico ausencia de evidencia en vez de cuestionar la legitimidad de la evidencia requerida.',
   'ANTES de la primera modificacion o prueba: 1) leer EKB aplicable; 2) comparar causas raiz y sus analogias con la unidad actual; 3) cruzar contrato de salida, criterios de todos los checkpoints afectados, gobernanza y nivel de evidencia (sandbox versus live); 4) verificar que el validador mida la naturaleza correcta y se reutilicen las pruebas acreditadas; 5) detectar contradicciones y reparar contrato y gobernanza juntos ANTES de implementar. Si el preflight no tiene comparacion explicita, no presumir que EKB fue utilizada. Mantener independiente gate operativo sin relajar recibos live.',
   'Caso positivo: una unidad sandbox cuyo pass_when exige recibos live debe marcar CONTRACT_GOVERNANCE_SCOPE_REVIEW_REQUIRED en preflight, antes de producir codigo o repetir pruebas. Negativos: controles live correctamente requeridos mantienen fail-closed; una unidad con contrato coherente continua sin falsas alarmas. Verificar evidencia explicita de comparacion EKB->contrato->gobernanza->validador, ROLLBACK y readback. Regla registrada, automatizacion preventiva todavia NO instalada.',
   'Evidencia: M9.9 EKB IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001 e IG-M99-REPETITIVE-SYMPTOM-PATCHING-001; M9.10 PR #2280 mantuvo per_cohort_receipts_verified=true; auditoria posterior PR #2281 corrige separacion, migracion de M9.10 pendiente de aplicar. Hallazgo de procedimiento no equivale a validacion automatica implementada.',
   'github://cristhianlujan/claude-persona-lf-patch/pull/2281',
   'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.10',
   'ACTIVO','METHODOLOGY_REPAIR',
   ARRAY['Architect','Builder','Judge','Auditor']::text[]
 WHERE NOT EXISTS (
   SELECT 1 FROM transversal.error_knowledge
   WHERE codigo='IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001'
 );
END $ekb$;
