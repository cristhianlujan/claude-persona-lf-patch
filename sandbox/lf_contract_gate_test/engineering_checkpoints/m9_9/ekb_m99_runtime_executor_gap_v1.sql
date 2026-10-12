-- EKB operational incident register: M9.9 false-PASS execution boundary.
-- Append-only/idempotent incident evidence; not a schema or authority migration.
-- Source-first and readback mandatory; never close M9.9 from this record.
WITH new_issue AS (
 INSERT INTO transversal.error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,
  prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,
  lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,
  root_cause_family,detectability,source_context,source_ref)
 VALUES (
  gen_random_uuid(),
  'IG-M99-RUNTIME-EXECUTOR-RECEIPT-DISCONNECTED-001',
  'ENGINEERING_RUNTIME_GOVERNANCE',
  'M9.9 canary carece de conexion ejecutor a recibos de rollback autenticos',
  'La regla de cinco condiciones decide ROLLBACK_REQUIRED; el consumidor de recibos es read-only y el promotor puede revertir transacciones, pero ningun ejecutor vivo aplica automaticamente esa decision y emite prueba atestada del mismo canary.',
  'Falta una arista fisica gobernada entre la decision basada en observacion independiente, la accion reversible, el emisor EVIDENCE_VERIFIER_V1 y el verificador terminal. Las pruebas historicas emplearon flags adversariales y rollback de subtransaccion, sin prueba de receptor vivo.',
  'Decision y capacidad aisladas se confunden con ejecucion integrada; no hay recibos IG_CANARY_OBSERVATION persistidos.',
  'En el adaptador IG especifico enlazar identidad/candidato/cohorte/baseline y observar productor vs oraculo independiente; usar el promotor gobernado en SAVEPOINT o transaccion reversible, hacer abort condicionado, emitir observacion+oraculo+accion por issuer autorizado tras readback real y verificar causalidad. Mantener el motor transversal sin ramas IG y separar cinco disparadores.',
  'Control positivo CLEAN y negativo FALSE_PASS sobre estado real, restauracion exacta del puntero/manifest/versiones y residuos cero; recibos de canary autenticados y asociados a misma ejecucion antes de cerrar checkpoint. Prueba ROLLBACK no equivale a certificacion live.',
  'HIGH',1,clock_timestamp(),clock_timestamp(),
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.9',
  'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2271',
  'ACTIVO',
  'M99_EKB_EXECUTOR_AUDIT_20261012: PR2271 prueba puntero gobernado con aborto condicionado y restauracion exacta. Nueva prueba false_pass_db_observed_canary_v1.sql: CLEAN PASS/PASS CONTINUE; FALSE_PASS PASS/FAIL ROLLBACK_REQUIRED; ambos 0 residuos y ROLLBACK. Cero recibos IG_CANARY_OBSERVATION, runtime live no probado; migracion M9.9 20261012013000 no aplicada.',
  'CHECKPOINT_RUNTIME',
  ARRAY['Builder','Judge','Auditor']::text[],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.9/ROLLBACK_TRIGGER_NEGATIVE',
  'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m9_9/cases/false_pass_db_observed_canary_v1.sql'
 )
 ON CONFLICT(codigo) DO UPDATE SET
 evidencia=CASE WHEN position('M99_EKB_EXECUTOR_AUDIT_20261012' in coalesce(transversal.error_knowledge.evidencia,''))>0
 THEN transversal.error_knowledge.evidencia
 ELSE concat_ws(E'\n',transversal.error_knowledge.evidencia,excluded.evidencia) END,
 ultima_vez=clock_timestamp(),updated_at=clock_timestamp()
 RETURNING codigo,estado
), update_prior AS (
 UPDATE transversal.error_knowledge
 SET evidencia=CASE WHEN position('M99_EKB_REAL_DB_OBSERVATION_20261012' in coalesce(evidencia,''))>0 THEN evidencia
 ELSE concat_ws(E'\n',evidencia,
 'M99_EKB_REAL_DB_OBSERVATION_20261012: los scripts false_pass_real_pointer_rollback_v1.sql y false_pass_db_observed_canary_v1.sql demuestran promocion y retorno fisicos en sandbox, pero no el receipt firmado del canary vivo. Exigir fuente y emisor real; no cerrar checkpoint.') END,
 updated_at=clock_timestamp()
 WHERE codigo='IG-M99-ROLLBACK-FIVE-TRIGGERS-VALIDATION-GAP-001'
 RETURNING codigo,estado
)
SELECT 'NEW_INCIDENT' AS record_kind,codigo,estado FROM new_issue
UNION ALL SELECT 'EXISTING_FINDING_UPDATE',codigo,estado FROM update_prior;
