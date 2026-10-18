-- PE10: record execution-evidence QA after RAW freeze; no scores, no methods altered, no false DONE.
-- Routed exclusively through Migration Merge Train and ACTUALIZACION_DB_LF.
DO $pe10_audit$
DECLARE v_count integer;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_work_items WHERE id=1133 AND work_code='PEVO-PE10-METHODS32-P0' AND status='BACKLOG')
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING' AND evidence_ref IS NOT NULL AND assertion_receipt IS NULL AND completed_at IS NULL)<>32
 OR (SELECT count(*) FROM programacion.engineering_work_updates WHERE work_item_id=1133 AND update_type='DELIVERY')<>32
 OR EXISTS (SELECT 1 FROM programacion.engineering_work_updates WHERE work_item_id=1133 AND summary LIKE 'PE10 acceptance-audit %')
 OR EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='PE10-RAW-LITERAL-SQL-AND-ROLE-REUSE-001')
 THEN RAISE EXCEPTION 'PE10_CONTRACT_AUDIT_PRESTATE_DRIFT'; END IF;

 INSERT INTO programacion.engineering_work_updates
  (work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at)
 SELECT 1133, 'NOTE', 'PE10 acceptance-audit ' || c.checkpoint_code,
  CASE WHEN c.checkpoint_code='PE10_M01' THEN
   'ORIGINAL_STRUCTURALLY_REVIEWABLE; 8 literal SELECT queries in immutable RAW; no governed receipt; not a DONE assertion.'
   WHEN c.checkpoint_code='PE10_M02' THEN
   'ORIGINAL_STRUCTURALLY_REVIEWABLE; 3 literal SELECT queries, differential diagnosis and documented non-calibratable BARINEL; no governed receipt.'
   WHEN c.checkpoint_code BETWEEN 'PE10_M03' AND 'PE10_M16' THEN
   'RAW_PARTIAL: method-specific literal SELECT queries absent inside RAW (0); only aggregate query summary; contract incomplete; keep PENDING.'
   ELSE
   'RAW_PARTIAL: 0 literal SELECT queries inside RAW; each of 5 role reports repeats its findings across 16 B methods; unique role investigations unproven; keep PENDING.'
  END,
  CASE WHEN c.checkpoint_code IN('PE10_M01','PE10_M02') THEN
     'Verify source-side attestation, provide active validated governance binding and receipt before any DONE; preserve original bytes.'
   ELSE
     'Complete original method-scoped investigation and freeze literal SQL with observations; for B genuinely distinct role research, then synthesize; no expected answers.'
  END,
  jsonb_build_array(c.evidence_ref,'github://cristhianlujan/claude-persona-lf-patch/docs/profile_updater/experiments/pe10_methods32_p0/raw_contract_audit_v1.json#'||c.checkpoint_code),
  'PE10_CONTRACT_EVIDENCE_AUDIT_V1',clock_timestamp()
 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=1133 ORDER BY c.sequence_no;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>32 THEN RAISE EXCEPTION 'PE10_AUDIT_NOTE_COUNT:%',v_count; END IF;

 INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,severidad,
  lote_origen,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref)
 VALUES
 ('PE10-RAW-LITERAL-SQL-AND-ROLE-REUSE-001','GOVERNANCE',
  'Raw PE10 indexado no demuestra investigacion original completa ni evidencia literal por metodo',
  'En PE10 work item 1133, la auditoria de originales congelados encuentra M01 y M02 con 8 y 3 consultas SQL literales; M03-M32 con cero consultas literales en sus RAW, aunque declaran lectura SQL. En las 16 variantes B, cada uno de cinco roles repite el mismo conjunto de hallazgos: no se acredita investigacion original diferenciada por metodo.',
  'Se confundio generacion mecanica de artefactos y resumen de SELECT con salida de investigacion metodologica verificable; adicionalmente el indexado de hashes se confundio con potencial cierre.',
  'No cerrar checkpoints por archivos o hashes. Exigir SQL literal/resultado/procedencia por metodo, prueba de rol B genuina y sintetizador posterior; preservar M01/M02 sin reejecucion. La transicion DONE exige recibo del proveedor gobernado real.',
  'PE10 work 1133: 32 RAW referenciados, 32 PENDING; M01=8 SQL literales, M02=3, M03-M32=0, 5/5 roles B repiten hallazgos en 16 variantes; ver audit_v1.json y readback. No hay assertion_receipt.',
  'HIGH','PE10-IG-M107-M109-P0','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/docs/profile_updater/experiments/pe10_methods32_p0/raw_contract_audit_v1.json','VALIDATION',ARRAY['Architect','Validator'],
  'R5_EROSION_PROCESO','LOUD_LATE',
  'PE10 method trial 32 independent methodological outputs', 'github://cristhianlujan/claude-persona-lf-patch/docs/profile_updater/experiments/pe10_methods32_p0/raw_contract_audit_v1.json');
 IF (SELECT count(*) FROM programacion.engineering_work_updates
     WHERE work_item_id=1133 AND summary LIKE 'PE10 acceptance-audit %')<>32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND status='PENDING' AND completed_at IS NULL AND assertion_receipt IS NULL)<>32
 OR (SELECT count(*) FROM transversal.error_knowledge WHERE codigo='PE10-RAW-LITERAL-SQL-AND-ROLE-REUSE-001')<>1
 THEN RAISE EXCEPTION 'PE10_AUDIT_POSTSTATE_MISMATCH'; END IF;
END $pe10_audit$;
