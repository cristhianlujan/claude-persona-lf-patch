-- LF engineering plan follow-up, approved 2026-10-14.
-- Tracking only: two distinct work items under Paulo's existing workstream.
-- Only historical use or explicit user request with real consumer admits development.
-- Never repair unrequested dormant operations just because a catalog gap exists.
-- No modification of Migration/Operation functionality, PASE or POST-PASE.
-- Existing Operation implementation is primarily Cristhian's work; Paulo owns the extension only.
-- SOURCE_FIRST: Git branch -> PR -> LF Migration Merge Train -> ledger -> readback.
BEGIN;
DO $paulo_tracking$
DECLARE
  v_stream_id bigint;
  v_migration_id bigint;
  v_operation_id bigint;
BEGIN
  SELECT id INTO v_stream_id
    FROM programacion.engineering_workstreams
   WHERE stream_code = 'PAULO-LF-ENGINEERING-2026'
     AND owner_ref = 'PAULO'
     AND status = 'ACTIVE';
  IF v_stream_id IS NULL THEN
    RAISE EXCEPTION 'PAULO_WORKSTREAM_NOT_CURRENT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM programacion.engineering_work_items
     WHERE work_code IN ('PAULO-MIGRATION-001','PAULO-OPERATION-001')
  ) THEN
    RAISE EXCEPTION 'PAULO_TRACKING_UNIT_ALREADY_EXISTS';
  END IF;

  INSERT INTO programacion.engineering_work_items
    (work_code,workstream_id,title,objective,expected_result,work_type,
     priority,status,assignee_type,assignee_ref,target_repo,target_domain,
     target_component,source_ref,acceptance_criteria,created_by_execution_id)
  VALUES
    ('PAULO-MIGRATION-001',v_stream_id,
     'Migration: ampliar LF Migration Merge Train por casos de cambio',
     'Cubrir Migration solo para uso historico o pedido expreso: nuevas migraciones retiro source-only y recovery. Evitar variantes no solicitadas y motores paralelos.',
     'Train existente admite y rechaza correctamente cada naturaleza aplicable con tests y recibos Git=ledger=DB; no modifica PASE/POST-PASE.',
     'DATABASE','P1','BACKLOG','MIXED','PAULO',
     'cristhianlujan/claude-persona-lf-patch','LF_MIGRATION',
     'LF_MIGRATION_MERGE_TRAIN',
     'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2644',
     jsonb_build_array('Unidades IG M excluidas','Distinguir DROP SQL vs REMOVE de fuente','Sin replay de migraciones ya aplicadas','Todos los checkpoints con evidencia y readback','Autoría histórica preservada'),
     'PAULO_SCOPE_TRACKING_20261014')
  RETURNING id INTO v_migration_id;

  INSERT INTO programacion.engineering_work_items
    (work_code,workstream_id,title,objective,expected_result,work_type,
     priority,status,assignee_type,assignee_ref,target_repo,target_domain,
     target_component,source_ref,acceptance_criteria,created_by_execution_id)
  VALUES
    ('PAULO-OPERATION-001',v_stream_id,
     'Operation: ampliar cobertura gobernada de operaciones LF',
     'Extender lf_operation_* solo si existe uso historico documentado o solicitud expresa con consumidor real. No perfeccionar operaciones nunca usadas/no pedidas; preservar autoria de Cristhian.',
     'Inventario focalizado en casos usados o pedidos; contratos, jueces y readback solo donde apliquen; integracion con Migration unicamente ante un caso compartido real.',
     'BACKEND','P1','BACKLOG','MIXED','PAULO',
     'cristhianlujan/claude-persona-lf-patch','LF_OPERATION',
     'LF_OPERATION_FRAMEWORK',
     'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2646',
     jsonb_build_array('Trabajo base previo principalmente de Cristhian','Ampliación asignada a Paulo','Reutilizar lf_operation_* y Router','Verificar efecto, judge y cierre','No sumar unidades IG M ni PASE/POST-PASE','Evidencia y readback en vista canónica'),
     'PAULO_SCOPE_TRACKING_20261014')
  RETURNING id INTO v_operation_id;

  INSERT INTO programacion.engineering_work_checkpoints
 (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
 SELECT v_migration_id, cp.checkpoint_code, cp.title, cp.sequence_no, 1, true, 'PENDING', 'PAULO_SCOPE_TRACKING_20261014'
 FROM (VALUES
  ('MIG-CP1', 'Diagnosticar Train para casos reales o pedidos; descartar variantes de cambios de fuente sin uso ni demanda', 1),
  ('MIG-CP2', 'Contratar solo casos de nuevas migraciones retiro source-only y recovery sustentados en demanda', 2),
  ('MIG-CP3', 'Extender Train existente con cambios aislados y gobierno vigente, sin motor paralelo', 3),
  ('MIG-CP4', 'Probar positivos/negativos y ROLLBACK aplicable; no replay ni alteración histórica indebida', 4),
  ('MIG-CP5', 'Verificar ejecución Train, source, ledger, DB, parity y readback exactos', 5),
  ('MIG-CP6', 'Registrar resultados, EKB y cierre solo con evidencia real por caso', 6)
 ) AS cp(checkpoint_code,title,sequence_no);

  INSERT INTO programacion.engineering_work_checkpoints
 (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
 SELECT v_operation_id, cp.checkpoint_code, cp.title, cp.sequence_no, 1, true, 'PENDING', 'PAULO_SCOPE_TRACKING_20261014'
 FROM (VALUES
  ('OP-CP1', 'Seleccionar solo operaciones con uso previo documentado o pedido expreso y consumidor; descartar inventario sin demanda', 1),
  ('OP-CP2', 'REUSE/EXTEND solo en operaciones con uso probado o pedido expreso; no reparar huecos de operaciones ociosas', 2),
  ('OP-CP3', 'Verificar steps contratos mini-jueces Router y effect guard solo para casos admitidos con demanda', 3),
  ('OP-CP4', 'Probar solo rutas realmente usadas o solicitadas; evitar pruebas hipoteticas por familia', 4),
  ('OP-CP5', 'Probar integracion con Migration si existe un caso compartido real; si no NOT_APPLICABLE', 5),
  ('OP-CP6', 'Recibos, readback, EKB y cierre basado en evidencia, conservando autoría histórica', 6)
 ) AS cp(checkpoint_code,title,sequence_no);

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id = v_migration_id) <> 6
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id = v_operation_id) <> 6 THEN
      RAISE EXCEPTION 'PAULO_TRACKING_CHECKPOINTS_INCOMPLETE';
  END IF;
END;
$paulo_tracking$;
COMMIT;
