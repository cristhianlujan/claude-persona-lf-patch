-- EKB operational, source first. IG M9.9 verified root cause and cross-unit anti-loop rule.
-- No schema migrations, checkpoint transitions, lifecycle reclassification, or production effects.
-- Idempotent by codigo; existing runtime/receipt findings remain ACTIVO for live admission.
INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,evidencia,lote_origen,pr,lifecycle_phase,consumer_role,
  root_cause_family,detectability,source_context,source_ref)
VALUES
 ('IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001',
  'CONTRACT_GOVERNANCE_SCOPE',
  'M9.9 bloqueada por mezclar calificacion sandbox con certificacion operativa',
  'El mismo contrato de ingenieria exigia recibos firmados de un canary live y revision independiente para cerrar un ensayo reversible sandbox, mientras runtime_activation=false y production_activation=false. Multiples pruebas correctas no podian satisfacer un criterio de otro nivel.',
  'ERROR PRINCIPAL: criterio de salida de checkpoint y gobernanza de activacion operativa se conflaron. Se trato como falla de ejecutor, de verificador, de recibos y de infraestructura cuando la prueba sandbox ya demostraba el comportamiento requerido. El control de release estaba ubicado en una unidad de construccion sin habilitacion operacional.',
  'Reparar sintomas repetidamente (oraculo, adaptador, lector, firma, ensayo) sin verificar si la condicion terminal corresponde a la naturaleza y nivel de la unidad; progreso fijo en 55% pese a PR sucesivos.',
  'PREFLIGHT TRANSVERSAL ANTES DE DOS REINTENTOS: clasificar objetivo/alcance (CONSTRUCCION_SANDBOX, INTEGRACION, CALIFICACION_OP, ACTIVACION_PROD), efectos permitidos y dueño del control; contrastar criterio de salida vs evidencia producible; identificar requisitos ajenos a la fase. Si hay desalineacion, corregir atomicamente CONTRATO DE UNIDAD + GOBERNANZA DE ADMISION + CHECKPOINT/VALIDADOR, con control positivo y negativo, sin ampliar permisos. Los recibos live no deben ser dependencia de DONE sandbox; siempre quedan exigidos para habilitacion real. No cambiar un solo campo y dejar reglas contradictorias.',
  'PR #2276 y migracion exacta 20261012070000: CP4/CP5 sandbox aceptan 6 casos (CLEAN + FALSE_PASS, DIVERGENCE, TIMEOUT, EXECUTION_ERROR, MISSING_RECEIPT), rollback transaccional, baseline INPUT_GOVERNANCE 1.0.0 intacta y cero residuos. Gate operativo independiente sigue BLOCKED. PR #2278 y 20261012071000: M9.9 DONE 100%, 5/5 con asercion CP4 y readback CP5; Git=ledger=DB. Timeout usa dato historico y NO demuestra canary operativo live. Negativo: 0 recibos IG_CANARY_OBSERVATION no autoriza production/runtime.',
  'CRITICAL','VERIFICADO',
  '2026-10-12. Diagnostico principal confirmado: el ultimo cambio de alcance + gobernanza, no los numerosos ensayos del ejecutor, permitio resolver M9.9. PR2276 squash 06be0bec8417e5aa4e18e43d397f8dbb8d83aab1, blob 70641b5fe90a91506f5ae8a698d9569f166e8528. PR2278 squash 57424e5c9bdcfff4c0b4cd51fa7a38c87f68bb4b, blob e842f5c7e66ef87ba08ef6bdce8be5c05c69d1a5. Estado terminal STOP_TERMINAL_DONE 100% 5/5; admission operativa separada bloqueada.',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.9',
  'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2276',
  'CONTRACT_DESIGN',ARRAY['Architect','Builder','Judge','Auditor']::text[],
  'R4_NO_CUESTIONA','PROCESS_DEPENDENT',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.9/CP4_CP5',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261012070000_ig_m99_two_level_canary_contract_governance_v2.sql'),
 ('IG-M99-REPETITIVE-SYMPTOM-PATCHING-001',
  'ENGINEERING_PROCESS_DEFECT',
  'Multiples reparaciones locales sin reexaminar el criterio de salida',
  'PR #2261, #2266, #2267, #2269, #2270, #2271, #2272, #2274 y #2275 aislaron defectos reales y verificaron capacidades, pero no movieron el 55% oficial: se repitio el ciclo de crear pruebas, leer recibos y endurecer condiciones sin auditar la legitimidad del criterio terminal.',
  'Fallo del metodo de diagnostico: optimizacion local ante falla recurrente; ausencia de escalamiento inmediato desde el sintoma hacia contrato+gobernanza+validador+alcance. Se anunciaron soluciones parciales como resolucion integral, confundiendo PR fusionado o test PASS con CHECKPOINT DONE.',
  'Dos o mas intentos tecnicos equivalentes sin mejora del checkpoint, circularidad entre emisor, recibo y aprobador, o dependencia de prueba no producible en el alcance.',
  'REGLA ANTI-BUCLE: tras 2 fallas/iteraciones sin avance verificable detener parcheo del mismo sintoma, leer EKB, comparar contrato de unidad, gobernanza de fase y naturaleza del validador, proponer al menos: ajuste de medicion, separacion de release gate, reutilizacion o NOT_APPLICABLE justificado. Seleccionar causa raiz y aplicar reparacion conjunta. Medir avance solo con bootstrap/ledger; test local PASS no es DONE. No inventar recibos ni rebajar protecciones de produccion.',
  'Regresion: si 2 iteraciones no incrementan progreso y el requisito exige capacidades fuera del nivel, el preflight debe emitir CONTRACT_GOVERNANCE_SCOPE_REVIEW_REQUIRED. Demostrar matriz antes/despues, ROLLBACK sin residuos, fuente Git=ledger=DB, y conservar release gate fail-closed. Regla registrada como aprendizaje; no declarar automatizacion transversal instalada.',
  'HIGH','ACTIVO',
  'Historia de diagnostico M9.9 PR #2261/#2266/#2267/#2269/#2270/#2271/#2272/#2274/#2275; ultimo cambio #2276 + #2278 alcanzo 100%. Esta regla es preventiva y requiere validacion automatica generica futura; no afirmar que existe un nuevo motor/gate.',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.9',
  'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2278',
  'METHODOLOGY_REPAIR',ARRAY['Architect','Builder','Judge','Auditor']::text[],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.9/REPETITIVE_RETRY',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261012071000_ig_m99_sandbox_closeout_v2.sql')
ON CONFLICT(codigo) DO NOTHING;

-- Existing findings still matter to any future operational canary, but are
-- NOT prerequisites of a sandbox-only M9.9 engineering DONE.
UPDATE transversal.error_knowledge
SET evidencia=CASE WHEN position('M99_ROOT_CAUSE_CONSOLIDATED_EKB_20261012' in coalesce(evidencia,''))>0
  THEN evidencia ELSE concat_ws(E'\n', evidencia,
  'M99_ROOT_CAUSE_CONSOLIDATED_EKB_20261012: Exclusion del alcance M9.9 sandbox confirmada por PR2276/2278. Los recibos de canary real y revision independiente siguen siendo validaciones de activacion operativa (separada y bloqueada). La causa principal de estancamiento fue IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001, no la imposibilidad de revertir en sandbox. Regla anti-bucle: IG-M99-REPETITIVE-SYMPTOM-PATCHING-001.') END,
 updated_at=clock_timestamp()
WHERE codigo IN ('IG-M99-RUNTIME-EXECUTOR-RECEIPT-DISCONNECTED-001',
                 'IG-M99-ROLLBACK-FIVE-TRIGGERS-VALIDATION-GAP-001',
                 'IG-M99-CONTRACT-REPAIR-DISPATCH-UNSUPPORTED-001');

DO $check$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001'
 AND estado='VERIFICADO'
 AND position('PREFLIGHT TRANSVERSAL' in prevencion)>0)
 OR NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M99-REPETITIVE-SYMPTOM-PATCHING-001'
 AND estado='ACTIVO'
 AND position('REGLA ANTI-BUCLE' in prevencion)>0)
 THEN RAISE EXCEPTION 'EKB_M99_LEARNING_READBACK_FAILED'; END IF;
END $check$;

SELECT codigo,estado,root_cause_family,detectability
FROM transversal.error_knowledge
WHERE codigo IN ('IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001',
                 'IG-M99-REPETITIVE-SYMPTOM-PATCHING-001')
ORDER BY codigo;
