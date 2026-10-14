-- LF engineering plan follow-up, approved 2026-10-14.
-- Tracking only: 2 domain parents, 2 conditional Migration deliveries,
-- and 1 evidenced Operation delivery with separate readiness of access.
-- Baseline verified: NEW via PR #2355/#2400 and ledger;
-- REMOVE source-only via RECONCILE PR #2412; ledger -> source via PR #2420;
-- only unmet, explicitly needed variants are valid new Paulo deliverables.
-- Do not credit historical NEW capability as Paulo's new delivered work.
-- Delivery progress is 2 pending outputs: REMOVE and RECOVERY; technical CP in detail.
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
     'NEW existente (PR 2355/2400+ledger), REMOVE source-only realizado (PR 2412), RECOVERY source desde ledger realizado (PR 2420, 17 fuentes). Solo admitir y medir ampliaciones de Paulo para brechas restantes con consumidor real.',
     'DATABASE','P1','BACKLOG','MIXED','PAULO',
     'cristhianlujan/claude-persona-lf-patch','LF_MIGRATION',
     'LF_MIGRATION_MERGE_TRAIN',
     'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2644',
     jsonb_build_array('Unidades IG M excluidas','NEW existente PR 2355/2400 ledger','REMOVE source-only existente PR 2412','RECOVERY fuente ledger existente PR 2420','Solo gap residual demostrado puede entrar a Paulo','No adjudicar trabajo previo a Paulo','Train strict para removed, RECONCILE es separado','No replay, evidencias y readback'),
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
     'Operation measured by one current concrete delivered capability: governed operational DB execution; the code-only PR 2367 already exists but Router admission and safe closeout are not installed. MCP HTTPS access is later and conditional.',
     'BACKEND','P1','BACKLOG','MIXED','PAULO',
     'cristhianlujan/claude-persona-lf-patch','LF_OPERATION',
     'LF_OPERATION_FRAMEWORK',
     'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2646',
     jsonb_build_array('Trabajo base previo principalmente de Cristhian','Ampliación asignada a Paulo','Reutilizar lf_operation_* y Router','Verificar efecto, judge y cierre','No sumar unidades IG M ni PASE/POST-PASE','Evidencia y readback en vista canónica'),
     'PAULO_SCOPE_TRACKING_20261014')
  RETURNING id INTO v_operation_id;

  -- Only unsatisfied Migration deliverables become new Paulo backlog rows.
  -- NEW is already supported by the Train and actual merged+applied migrations.
  -- REMOVE source-only is already possible via RECONCILE (#2412); DO NOT rebuild it.
  -- An exact Train route for removed files is NOT shown and must be justified by use.
  -- RECOVERY ledger->Git has run (#2420); premerged orphan case remains distinct.
  -- Neither residual item authorizes generalized new development without need.
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
      ('PAULO-MIGRATION-REMOVE',
       'REMOVE — solo brecha no cubierta por RECONCILE',
       'Retiro source-only ya demostrado por PR 2412 via RECONCILE y DROP SQL por nueva migracion: no reconstruir. Atender solo caso residual no cubierto con uso o pedido concreto, p.ej. integracion Train si es imprescindible.',
       'Demostrar gap restante con caso concreto y entregar correccion minima; si lo existente resuelve el caso, cerrar sin nueva implementacion y referenciar PR 2412.',
       jsonb_build_array('REMOVE ya existe via PR 2412 RECONCILE','Train strict removed no equivale a ausencia de retiro','Solo admitir gap de uso real','No tocar SQL aplicado ni ledger','Readback de la ruta existente o delta minimo')),
      ('PAULO-MIGRATION-RECOVERY',
       'RECOVERY — solo casos no cubiertos por reconciliacion existente',
       'Ya existe reconstruccion source-only desde ledger PR 2420 (17/17); admitir solo incidente nuevo o abierto no resuelto por esa ruta ni por version nueva gobernada.',
       'Identificar caso excepcional aun sin ruta; si ya hay solucion material, conservar evidencia y no crear otro executor ni aplicar SQL innecesario.',
       jsonb_build_array('RECOVERY ledger->Git existente PR 2420 17/17','Caso premerged especial debe ser actual y no resuelto','Version blob fuente exactos','No replay ni ledger artificial','Sin nuevas rutas sin demanda'))
    ) AS d(code,title,objective,expected_result,acceptance_criteria);

  -- Internal checkpoints are the drill-down; delivery rows are the primary metric.
  INSERT INTO programacion.engineering_work_checkpoints
    (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
  SELECT child.id, cp.checkpoint_code, cp.title, cp.sequence_no, 1, true, 'PENDING',
         'PAULO_SCOPE_TRACKING_20261014'
    FROM (VALUES
      ('PAULO-MIGRATION-REMOVE','REMOVE-C1','Readback PR 2412 y caso REMOVE aun sin ruta real',1),
      ('PAULO-MIGRATION-REMOVE','REMOVE-C2','Confirmar que RECONCILE y Train existentes no cubren ese caso',2),
      ('PAULO-MIGRATION-REMOVE','REMOVE-C3','Delta minimo solo ante brecha aprobada y su prueba',3),
      ('PAULO-MIGRATION-REMOVE','REMOVE-C4','Readback del resultado o cierre sin cambio si ya resuelto',4),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C1','Readback PR 2420 y caso aun no cubierto si existe',1),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C2','Evaluar rutas actuales y cerrar si ya cubren el caso',2),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C3','Delta minimo y negativos solo si hay necesidad real',3),
      ('PAULO-MIGRATION-RECOVERY','RECOVERY-C4','Readback o cierre sin cambio si no hay brecha',4)
    ) AS cp(work_code,checkpoint_code,title,sequence_no)
    JOIN programacion.engineering_work_items child ON child.work_code=cp.work_code
   WHERE child.parent_work_item_id=v_migration_id
     AND child.workstream_id=v_stream_id;

  INSERT INTO programacion.engineering_work_checkpoints
 (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
 SELECT v_migration_id, cp.checkpoint_code, cp.title, cp.sequence_no, 1, true, 'PENDING', 'PAULO_SCOPE_TRACKING_20261014'
 FROM (VALUES
   ('MIG-DEL-REMOVE','REMOVE solo si PAULO-MIGRATION-REMOVE esta DONE con evidencia',1),
   ('MIG-DEL-RECOVERY','RECOVERY solo si PAULO-MIGRATION-RECOVERY esta DONE con evidencia',2)
 ) AS cp(checkpoint_code,title,sequence_no);

  -- Operation: only a concrete existing-demand gap (#2371, code-only PR #2367).
  -- No implementation or activation of arbitrary non-requested catalog operations.
  INSERT INTO programacion.engineering_work_items
    (work_code,workstream_id,parent_work_item_id,title,objective,expected_result,
     work_type,priority,status,assignee_type,assignee_ref,target_repo,target_domain,
     target_component,source_ref,acceptance_criteria,created_by_execution_id)
  VALUES
    ('PAULO-OPERATION-DB-EXECUTE',v_stream_id,v_operation_id,
     'OPERATIONAL_DB - ejecucion transaccional gobernada',
     'Reutilizar el executor candidato PR 2367, completar solo su ruta real solicitada en issue 2371, sin DML SQL arbitrario, sin duplicar Migration ni las operaciones existentes.',
     'Un caso operacional real autorizado ejecuta y cierra con Router, permisos minimos, effect guard, lease/fence, evidencia y readback positivo/negativo. El despliegue MCP HTTPS es posterior condicional, no forma parte de este DONE.',
     'BACKEND','P1','BACKLOG','MIXED','PAULO',
     'cristhianlujan/claude-persona-lf-patch','LF_OPERATION',
     'EJECUCION_OPERATIVA_LF',
     'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2371',
     jsonb_build_array('Demanda concreta issue 2371; reusar PR 2367',
       'Router OPERATIONAL_DB admitido y bound sin afectar DB UPDATE',
       'DML restringido por handler, identidad y rol minimo, nunca SQL arbitrario',
       'Cierre atomico canonical fail-closed; no DONE sin judge y efecto',
       'E2E sandbox, pruebas positivas y negativas, ROLLBACK y readback',
       'Sin despliegue ni activacion MCP automatica'),
     'PAULO_SCOPE_TRACKING_20261014');

  INSERT INTO programacion.engineering_work_checkpoints
    (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
  SELECT child.id, cp.checkpoint_code, cp.title, cp.sequence_no,
         1, true, 'PENDING', 'PAULO_SCOPE_TRACKING_20261014'
    FROM (VALUES
      ('OPDB-C1','Reutilizar PR 2367, calificar necesidad real y Router OPERATIONAL_DB',1),
      ('OPDB-C2','Contratos, step judges, DML minimo y cierre atomico autorizados',2),
      ('OPDB-C3','Ensayo transaccional ROLLBACK, positivos/negativos y E2E acotado',3),
      ('OPDB-C4','Resultado de operacion real, receipt, readback y EKB; sin despliegue automatico',4)
    ) AS cp(checkpoint_code,title,sequence_no)
    JOIN programacion.engineering_work_items child
      ON child.work_code='PAULO-OPERATION-DB-EXECUTE'
     AND child.parent_work_item_id=v_operation_id
     AND child.workstream_id=v_stream_id;

  -- Parent progress is a delivery decision, NOT a count of technical CP.
  INSERT INTO programacion.engineering_work_checkpoints
 (work_item_id, checkpoint_code, title, sequence_no, weight, required, status, created_by_execution_id)
 SELECT v_operation_id, cp.checkpoint_code, cp.title, cp.sequence_no,
        1, true, 'PENDING', 'PAULO_SCOPE_TRACKING_20261014'
 FROM (VALUES
   ('OP-DEL-EXECUTE','Entregable: OPERATIONAL_DB solo DONE tras evidencia del hijo y readback',1)
 ) AS cp(checkpoint_code,title,sequence_no);

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id = v_migration_id) <> 2
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id = v_operation_id) <> 1 THEN
      RAISE EXCEPTION 'PAULO_TRACKING_CHECKPOINTS_INCOMPLETE';
  END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_items
       WHERE parent_work_item_id = v_migration_id
         AND workstream_id = v_stream_id
         AND work_code IN ('PAULO-MIGRATION-REMOVE','PAULO-MIGRATION-RECOVERY')) <> 2
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
           JOIN programacion.engineering_work_items w ON w.id=c.work_item_id
          WHERE w.parent_work_item_id=v_migration_id) <> 8 THEN
    RAISE EXCEPTION 'PAULO_MIGRATION_DELIVERABLES_INCOMPLETE';
  END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_items
       WHERE parent_work_item_id = v_operation_id
         AND workstream_id = v_stream_id
         AND work_code='PAULO-OPERATION-DB-EXECUTE') <> 1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
           JOIN programacion.engineering_work_items w ON w.id=c.work_item_id
          WHERE w.parent_work_item_id=v_operation_id) <> 4 THEN
    RAISE EXCEPTION 'PAULO_OPERATION_DELIVERABLE_INCOMPLETE';
  END IF;
END;
$paulo_tracking$;
COMMIT;
