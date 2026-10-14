-- LF engineering plan follow-up, approved 2026-10-14.
-- Tracking only: 2 domain items and 3 independent, measurable Migration deliverables.
-- Delivery progress is the completion of NEW, REMOVE, RECOVERY, not general CP count.
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
     'Migration medido por 3 entregables: NEW, REMOVE y RECOVERY. Cada entrega cerrada con resultado util y readback; CP internos solo para seguimiento de detalle.',
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

  -- Each Migration deliverable is an independently observable backlog row.
  -- NEW is already supported for one added SQL file: validate existing function,
  -- and extend only if a documented real case demonstrates a gap.
  -- REMOVE handles DROP of a DB object via NEW versioned migration and
  -- source-only retirement of an obsolete unapplied Git source as DIFFERENT paths.
  -- RECOVERY handles a concrete main/ledger/DB discrepancy without false apply.
  INSERT INTO programacion.engineering_work_items
    (work_code,workstream_id,parent_work_item_id,title,objective,expected_result,
     work_type,priority,status,assignee_type,assignee_ref,target_repo,target_domain,
     target_component,source_ref,acceptance_criteria,created_by_execution_id)
  SELECT d.code,v_stream_id,v_migration_id,d.title,d.objective,d.expected_result,
         'DATABASE','P1','BACKLOG','MIXED','PAULO',
         'cristhianlujan/claude-persona-lf-patch','LF_MIGRATION',
         'LF_MIGRATION_MERGE_TRAIN',
         'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2644',
         d.acceptance_criteria,'PAULO_SCOPE_TRACKING_20261014'
    FROM (VALUES
      ('PAULO-MIGRATION-NEW',
       'NEW — migracion nueva versionada',
       'Comprobar que LF Train procesa una migracion SQL nueva added con version y scope exactos; no reimplementar un soporte que ya funciona.',
       'Caso real NEW verificado: archivo versionado, pruebas, apply/ledger y readback de Git/DB; mejora de codigo solo si el caso muestra una brecha.',
       jsonb_build_array('Existe uso/pedido concreto','NEW no se reconstruye si ya funciona','Prueba positiva y negativa por caso real','Readback git ledger DB')),
      ('PAULO-MIGRATION-REMOVE',
       'REMOVE — retiro controlado de objeto o fuente',
       'Atender retiro solicitado separando DROP de objeto SQL mediante nueva migracion versus REMOVE source-only de fuente historica obsoleta/no aplicada.',
       'REMOVE solicitado queda cubierto con ruta correcta por naturaleza, bloqueo de historicos inseguros, pruebas y evidencia; sin hard delete de ledger.',
       jsonb_build_array('Pedido explicito de REMOVE','DROP SQL y retiro source-only tienen contratos distintos','No tocar SQL historico ya aplicado','Positivo/negativo y rollback cuando aplica','Readback exacto')),
      ('PAULO-MIGRATION-RECOVERY',
       'RECOVERY — recuperar migracion o paridad inconsistente',
       'Atender incidentes reales de fuente fusionada no aplicada y desviacion Git/ledger/DB, sin replay ni fingir apply.',
       'Un caso real RECOVERY termina con resultado y conciliacion exacta, o rechazo seguro demostrado con motivo y evidencia.',
       jsonb_build_array('Incidente historico identificado','Version blob y fuente exactos','No replay ni ledger artificial','Prueba y readback real'))
    ) AS d(code,title,objective,expected_result,acceptance_criteria);

  -- Internal checkpoints are the drill-down; delivery rows are the primary metric.
  INSERT INTO programacion.engineering_work_checkpoints
    (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
  SELECT child.id, cp.checkpoint_code, cp.title, cp.sequence_no, 1, true, 'PENDING',
         'PAULO_SCOPE_TRACKING_20261014'
    FROM (VALUES
      ('PAULO-MIGRATION-NEW','NEW-C1','Caso NEW real y baseline exacta',1),
      ('PAULO-MIGRATION-NEW','NEW-C2','Validar alcance/contrato existente, ampliar solo si hace falta',2),
      ('PAULO-MIGRATION-NEW','NEW-C3','Prueba positiva y negativa bajo ruta admitida',3),
      ('PAULO-MIGRATION-NEW','NEW-C4','Entrega verificada con Git ledger DB y evidencia',4),
      ('PAULO-MIGRATION-REMOVE','REMOVE-C1','Caso REMOVE clasificado: DROP SQL o retiro de fuente',1),
      ('PAULO-MIGRATION-REMOVE','REMOVE-C2','Ruta de retiro segura por naturaleza y gobierno',2),
      ('PAULO-MIGRATION-REMOVE','REMOVE-C3','Positivo negativo y rollback donde aplica',3),
      ('PAULO-MIGRATION-REMOVE','REMOVE-C4','Entrega REMOVE demostrada con recibo y readback',4),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C1','Incidente concreto y fuente/ledger version exactos',1),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C2','Ruta admitida y guard anti-replay',2),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C3','Prueba acotada con negativos',3),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C4','Entrega RECOVERY con readback de paridad',4)
    ) AS cp(work_code,checkpoint_code,title,sequence_no)
    JOIN programacion.engineering_work_items child ON child.work_code=cp.work_code
   WHERE child.parent_work_item_id=v_migration_id
     AND child.workstream_id=v_stream_id;

  INSERT INTO programacion.engineering_work_checkpoints
 (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
 SELECT v_migration_id, cp.checkpoint_code, cp.title, cp.sequence_no, 1, true, 'PENDING', 'PAULO_SCOPE_TRACKING_20261014'
 FROM (VALUES
   ('MIG-DEL-NEW','Entregable NEW: cerrado solo si PAULO-MIGRATION-NEW esta DONE con evidencia',1),
   ('MIG-DEL-REMOVE','Entregable REMOVE: cerrado solo si PAULO-MIGRATION-REMOVE esta DONE con evidencia',2),
   ('MIG-DEL-RECOVERY','Entregable RECOVERY: cerrado solo si PAULO-MIGRATION-RECOVERY esta DONE con evidencia',3)
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
      WHERE work_item_id = v_migration_id) <> 3
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id = v_operation_id) <> 6 THEN
      RAISE EXCEPTION 'PAULO_TRACKING_CHECKPOINTS_INCOMPLETE';
  END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_items
       WHERE parent_work_item_id = v_migration_id
         AND workstream_id = v_stream_id
         AND work_code IN ('PAULO-MIGRATION-NEW','PAULO-MIGRATION-REMOVE','PAULO-MIGRATION-RECOVERY')) <> 3
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
           JOIN programacion.engineering_work_items w ON w.id=c.work_item_id
          WHERE w.parent_work_item_id=v_migration_id) <> 12 THEN
    RAISE EXCEPTION 'PAULO_MIGRATION_DELIVERABLES_INCOMPLETE';
  END IF;
END;
$paulo_tracking$;
COMMIT;
