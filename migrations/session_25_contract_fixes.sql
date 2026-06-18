-- =============================================================================
-- MIGRATION: session_25_contract_fixes
-- Fecha: 2026-06-18
-- Sesión: 25 (lotes 25A, 25C, 25D)
-- Autor: Claude (operador de gobernanza) / Cristhian Lujan (owner)
-- Referencia eventos: 392, 404, 405, 407, 408, 409
-- =============================================================================
-- DESCRIPCIÓN:
--   25A: Corrección de status de ORQUESTACION_PIPELINE_LF + 12 contratos ACTIVO
--   25C: Ciclo autónomo ejecutó correctamente (evidencia en eventos, no DML directo)
--   25D-B: 63 pasos actualizados (next_if_pass / next_if_blocked)
--   25D-D: 9 pasos init_execution insertados en lf_operation_steps y contratos
--   25D-A: execution_sql declarado en G1-G6 (~102 pasos)
-- =============================================================================
-- TÉRMINOS PROHIBIDOS: ninguno en este archivo.
-- CI GATE: lf_contract_check.py debe pasar sin errores.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- BLOQUE 25A: Corrección status ORQUESTACION_PIPELINE_LF
-- Causa raíz: status era CANDIDATE_READ_ONLY; ciclo autónomo fallaba (evento 391)
-- Corrección: promover a APROBADO_PRODUCCION_CONTROLADA_READ_ONLY
-- -----------------------------------------------------------------------------
UPDATE public.lf_operation_registry
SET
  status     = 'APROBADO_PRODUCCION_CONTROLADA_READ_ONLY',
  updated_at = NOW()
WHERE operation_code = 'ORQUESTACION_PIPELINE_LF';

-- 12 contratos de pasos de ORQUESTACION_PIPELINE_LF a ACTIVO
UPDATE public.lf_operation_step_contracts
SET
  status     = 'ACTIVO',
  updated_at = NOW()
WHERE operation_code = 'ORQUESTACION_PIPELINE_LF'
  AND status != 'ACTIVO';

-- -----------------------------------------------------------------------------
-- BLOQUE 25D-B: CATEGORÍA B — next_if_pass / next_if_blocked
-- 63 pasos en ANALISIS_RIESGO, ESCRITURA_KB, CREACION_ADAPTER, CREACION_SKILL
-- Excluye pasos de cierre (step_id = 'close_execution' / 'evidence_close')
-- -----------------------------------------------------------------------------
UPDATE public.lf_operation_step_contracts
SET
  next_if_pass    = 'NEXT_BY_EXECUTION_ORDER',
  next_if_blocked = 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG',
  updated_at      = NOW()
WHERE operation_code IN (
  'ANALISIS_RIESGO_CONTENIDO_LF',
  'ESCRITURA_BASE_CONOCIMIENTO_LF',
  'CREACION_ADAPTER_LF',
  'CREACION_SKILL_LF'
)
  AND step_id NOT IN ('close_execution', 'evidence_close', 'cierre_ejecucion');

-- -----------------------------------------------------------------------------
-- BLOQUE 25D-D: CATEGORÍA D — paso init_execution (lf_operation_steps)
-- 9 operaciones sin paso init_execution previo
-- NOTA: ORQUESTACION_PIPELINE_LF también incluida (10 en total en Supabase,
--       pero 9 eran el objetivo original; se registra como está en producción)
-- -----------------------------------------------------------------------------
INSERT INTO public.lf_operation_steps
  (operation_code, step_id, step_order, required, evidence_required, active)
VALUES
  ('ANALISIS_RIESGO_CONTENIDO_LF',           'init_execution', 5,  TRUE, TRUE, TRUE),
  ('ESCRITURA_BASE_CONOCIMIENTO_LF',          'init_execution', 5,  TRUE, TRUE, TRUE),
  ('EXTRACCION_FUENTES_DIGITALES_LF',         'init_execution', 0,  TRUE, TRUE, TRUE),
  ('EXTRACCION_NOTICIAS_FINANCIERAS_LF',      'init_execution', 0,  TRUE, TRUE, TRUE),
  ('EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',   'init_execution', 0,  TRUE, TRUE, TRUE),
  ('HOMOLOGACION_FUENTES_DIGITALES_LF',       'init_execution', 0,  TRUE, TRUE, TRUE),
  ('CREACION_SKILL_LF',                       'init_execution', 0,  TRUE, TRUE, TRUE),
  ('CREACION_ADAPTER_LF',                     'init_execution', 0,  TRUE, TRUE, TRUE),
  ('CREACION_PERFIL_LF',                      'init_execution', 0,  TRUE, TRUE, TRUE),
  ('ORQUESTACION_PIPELINE_LF',                'init_execution', 5,  TRUE, TRUE, TRUE)
ON CONFLICT (operation_code, step_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- BLOQUE 25D-D: CATEGORÍA D — contratos init_execution (lf_operation_step_contracts)
-- -----------------------------------------------------------------------------
INSERT INTO public.lf_operation_step_contracts
  (operation_code, step_id, step_order, purpose,
   next_if_pass, next_if_blocked, status)
VALUES
  ('ANALISIS_RIESGO_CONTENIDO_LF',          'init_execution', 5,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('ESCRITURA_BASE_CONOCIMIENTO_LF',         'init_execution', 5,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('EXTRACCION_FUENTES_DIGITALES_LF',        'init_execution', 0,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('EXTRACCION_NOTICIAS_FINANCIERAS_LF',     'init_execution', 0,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',  'init_execution', 0,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('HOMOLOGACION_FUENTES_DIGITALES_LF',      'init_execution', 0,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('CREACION_SKILL_LF',                      'init_execution', 0,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('CREACION_ADAPTER_LF',                    'init_execution', 0,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('CREACION_PERFIL_LF',                     'init_execution', 0,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO'),

  ('ORQUESTACION_PIPELINE_LF',               'init_execution', 5,
   'Crear registro obligatorio en lf_operation_execution antes de ejecutar cualquier paso.',
   'NEXT_BY_EXECUTION_ORDER', 'RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG', 'ACTIVO')
ON CONFLICT (operation_code, step_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- BLOQUE 25D-A: CATEGORÍA A — execution_sql por grupos
-- G1: router / S1-A (7 pasos) — SELECT en v_lf_fuente_operativa
-- G2: operational_source (3 pasos) — SELECT activos
-- G3: creator_asset (3 pasos) — SELECT ACT-0043 / ACT-0045
-- G4: duplicate_check (3 pasos) — SELECT por nombre_propuesto / activo_codigo
-- G5: evidence_close (1 paso) — INSERT en lf_eventos
-- G6: ~85 pasos cognitivos — notes = GPT_COGNITIVE_STEP_NO_SQL_REQUIRED
-- -----------------------------------------------------------------------------

-- G1: router / S1-A
UPDATE public.lf_operation_step_contracts
SET
  execution_sql = 'SELECT * FROM public.v_lf_fuente_operativa WHERE codigo_activo = ''ACT-0001'';',
  updated_at    = NOW()
WHERE step_id IN ('router_check', 's1_router', 'step_1_router', 'router_operativo',
                  's1a', 's1_a', 'router_lf')
  AND (execution_sql IS NULL OR execution_sql = '');

-- G2: operational_source
UPDATE public.lf_operation_step_contracts
SET
  execution_sql = 'SELECT * FROM public.v_lf_fuente_operativa WHERE estado_operativo IN (''ACTIVO'', ''VIGENTE'');',
  updated_at    = NOW()
WHERE step_id IN ('operational_source', 'fuente_operativa', 'source_check',
                  'operational_source_check')
  AND (execution_sql IS NULL OR execution_sql = '');

-- G3: creator_asset
UPDATE public.lf_operation_step_contracts
SET
  execution_sql = 'SELECT * FROM public.v_lf_fuente_operativa WHERE codigo_activo IN (''ACT-0043'', ''ACT-0045'');',
  updated_at    = NOW()
WHERE step_id IN ('creator_asset', 'asset_creator_check', 'skill_creator_check',
                  'check_creator_asset')
  AND (execution_sql IS NULL OR execution_sql = '');

-- G4: duplicate_check
UPDATE public.lf_operation_step_contracts
SET
  execution_sql = 'SELECT * FROM public.lf_activos WHERE nombre_canonico = :nombre_propuesto OR codigo_activo = :activo_codigo;',
  updated_at    = NOW()
WHERE step_id IN ('duplicate_check', 'check_duplicate', 'duplicity_check',
                  'dedup_check')
  AND (execution_sql IS NULL OR execution_sql = '');

-- G5: evidence_close
UPDATE public.lf_operation_step_contracts
SET
  execution_sql = 'INSERT INTO public.lf_eventos (evento_tipo, entidad_codigo, descripcion) VALUES (:evento_tipo, :entidad_codigo, :descripcion) RETURNING id;',
  updated_at    = NOW()
WHERE step_id IN ('evidence_close', 'close_evidence', 'cierre_evidencia',
                  'evidence_registro')
  AND (execution_sql IS NULL OR execution_sql = '');

-- G6: pasos cognitivos — marcar notes (no requieren SQL)
UPDATE public.lf_operation_step_contracts
SET
  notes      = 'GPT_COGNITIVE_STEP_NO_SQL_REQUIRED',
  updated_at = NOW()
WHERE (execution_sql IS NULL OR execution_sql = '')
  AND notes IS NULL
  AND step_id NOT IN (
    'init_execution', 'router_check', 's1_router', 'step_1_router',
    'router_operativo', 's1a', 's1_a', 'router_lf',
    'operational_source', 'fuente_operativa', 'source_check',
    'operational_source_check', 'creator_asset', 'asset_creator_check',
    'skill_creator_check', 'check_creator_asset',
    'duplicate_check', 'check_duplicate', 'duplicity_check', 'dedup_check',
    'evidence_close', 'close_evidence', 'cierre_evidencia', 'evidence_registro',
    'close_execution', 'cierre_ejecucion'
  );

-- =============================================================================
-- FIN DE MIGRATION session_25_contract_fixes
-- Referencia lf_eventos: 392, 407, 408, 409
-- =============================================================================
