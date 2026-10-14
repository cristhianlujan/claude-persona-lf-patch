-- LF engineering plan follow-up, approved 2026-10-14.
-- Tracking only: two distinct work items under Paulo's existing workstream.
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
     'Cubrir brechas verificadas de clasificación de fuente, retiro source-only y recuperación; conservar nueva migración SQL para cambios de objetos y no crear un segundo motor.',
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
     'Extender el framework existente lf_operation_* por necesidades reales no cubiertas, sin reemplazar Migration ni atribuir a Paulo el trabajo previo de Cristhian.',
     'Inventario de cobertura por naturaleza, contratos/steps/judges/materialización, casos positivos/negativos, cierre y readback; integración con Migration como consumidor, no transporte paralelo.',
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
  ('MIG-CP1', 'Inventariar Train y clasificar CREATE/ALTER/REPLACE/RENAME/DROP de objetos, y added/modified/removed/renamed de fuentes', 1),
  ('MIG-CP2', 'Definir contrato por naturaleza: nuevas migraciones, retiro source-only, recuperación exacta y control de riesgos', 2),
  ('MIG-CP3', 'Extender Train existente con cambios aislados y gobierno vigente, sin motor paralelo', 3),
  ('MIG-CP4', 'Probar positivos/negativos y ROLLBACK aplicable; no replay ni alteración histórica indebida', 4),
  ('MIG-CP5', 'Verificar ejecución Train, source, ledger, DB, parity y readback exactos', 5),
  ('MIG-CP6', 'Registrar resultados, EKB y cierre solo con evidencia real por caso', 6)
 ) AS cp(checkpoint_code,title,sequence_no);

  INSERT INTO programacion.engineering_work_checkpoints
 (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
 SELECT v_operation_id, cp.checkpoint_code, cp.title, cp.sequence_no, 1, true, 'PENDING', 'PAULO_SCOPE_TRACKING_20261014'
 FROM (VALUES
  ('OP-CP1', 'Inventario de operaciones y necesidades reales por familia/naturaleza; separar cobertura declarada de probada', 1),
  ('OP-CP2', 'Actualizar contratos/gobierno con REUSE/EXTEND para CREATE/UPDATE/EXECUTE/RETIRE y necesidades evidenciadas', 2),
  ('OP-CP3', 'Asegurar cobertura de steps, contratos, mini-jueces, bindings, Router y effect guard', 3),
  ('OP-CP4', 'Validar positivos, negativos, idempotencia, dependencias, lifecycle y cierre fail-closed', 4),
  ('OP-CP5', 'Probar integración con Migration por Router/ACTUALIZACION_DB_LF sin duplicar transporte', 5),
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
