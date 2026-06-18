-- =============================================================================
-- MIGRATION: session_26b_operational_fixes
-- Fecha: 2026-06-18
-- Sesión: 26 (lote 26B)
-- Autor: Claude (operador de gobernanza) / Cristhian Lujan (owner)
-- Referencia evento: 413
-- =============================================================================
-- DESCRIPCIÓN:
--   P2 (Cat C): output_payload declarado en pasos depth/validation y cognitivos
--   P3 (Cat E): purpose paso 10 ORQUESTACION corregido
--   P4 (Cat F): paso 90 ORQUESTACION delegado a ACT-0057
--   P5 (Cat G): paso 100 ORQUESTACION separado en notas S1/S2/S3
--   P7: fn_kb_quality_score creada + aplicada a KB con score NULL o > 1.0
-- =============================================================================

-- -----------------------------------------------------------------------------
-- P3: CATEGORÍA E — purpose desactualizado paso 10 ORQUESTACION
-- -----------------------------------------------------------------------------
UPDATE public.lf_operation_step_contracts
SET
  purpose    = 'Router + verificación fuente operativa. ACT-0058 debe estar APROBADO en v_lf_fuente_operativa antes de operar.',
  updated_at = NOW()
WHERE operation_code = 'ORQUESTACION_PIPELINE_LF'
  AND step_order = 10;

-- -----------------------------------------------------------------------------
-- P4: CATEGORÍA F — SQL hardcodeado paso 90, delegar a ACT-0057
-- -----------------------------------------------------------------------------
UPDATE public.lf_operation_step_contracts
SET
  execution_sql = 'SELECT * FROM public.v_lf_fuente_operativa WHERE codigo_activo = ''ACT-0057'';
-- Delegación: este paso invoca a ACT-0057 (ESCRITURA_BASE_CONOCIMIENTO_LF).
-- Los valores de kb_category, kb_subcategory, content_type y quality_score
-- son determinados por ACT-0057 en tiempo de ejecución, no hardcodeados aquí.',
  notes      = 'Delega escritura a ACT-0057. No hardcodear kb_category, quality_score ni content_type. ACT-0057 recibe decision_id, capture_run_id y source_url como parámetros.',
  updated_at = NOW()
WHERE operation_code = 'ORQUESTACION_PIPELINE_LF'
  AND step_order = 90;

-- -----------------------------------------------------------------------------
-- P5: CATEGORÍA G — multi-statement paso 100, separar en S1/S2/S3
-- -----------------------------------------------------------------------------
UPDATE public.lf_operation_step_contracts
SET
  execution_sql = '-- PASO 100 tiene 3 sentencias — ejecutar en orden separado:
-- S1: UPDATE public.lf_pipeline_runs SET stage_current = ''COMPLETED'', updated_at = NOW() WHERE pipeline_run_id = :pipeline_run_id RETURNING pipeline_run_id, stage_current;
-- S2: UPDATE public.lf_url_queue SET estado = ''PROCESADO'', processed_at = NOW() WHERE url = :source_url RETURNING queue_id, estado;
-- S3: INSERT INTO public.lf_eventos (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, origen) VALUES (''PIPELINE_REAL_COMPLETADO'', ''PIPELINE_RUN'', ''ACT-0058'', :descripcion_cierre, ''INFO'', ''AGENT_GOV'') RETURNING id;',
  notes      = 'MULTI-STATEMENT: ejecutar S1, S2, S3 en llamadas Supabase separadas. Supabase retorna solo la última sentencia si se envían juntas. Orden obligatorio: pipeline_runs → url_queue → lf_eventos.',
  updated_at = NOW()
WHERE operation_code = 'ORQUESTACION_PIPELINE_LF'
  AND step_order = 100;

-- -----------------------------------------------------------------------------
-- P2: CATEGORÍA C — output_payload [] en pasos depth/validation
-- -----------------------------------------------------------------------------
UPDATE public.lf_operation_step_contracts
SET
  output_payload = '{"step_result": "PASS|BLOCKED", "blocking_codes": []}'::jsonb,
  updated_at     = NOW()
WHERE operation_code IN ('CREACION_SKILL_LF', 'CREACION_ADAPTER_LF')
  AND step_id IN (
    'step_depth_validation','pack_internal_depth_validation',
    'examples_depth_validation','evals_depth_validation',
    'judge_depth_validation','schema_depth_validation',
    'output_modes_validation','blocking_overrides_validation',
    'adapter_examples_depth_judge','pre_write_execution_binding_gate'
  )
  AND output_payload = '[]'::jsonb;

-- P2: Pasos cognitivos restantes con []
UPDATE public.lf_operation_step_contracts
SET
  output_payload = '{"step_result": "PASS|BLOCKED", "notes": "GPT_COGNITIVE_STEP"}'::jsonb,
  updated_at     = NOW()
WHERE operation_code IN ('CREACION_SKILL_LF', 'CREACION_ADAPTER_LF', 'ORQUESTACION_PIPELINE_LF')
  AND output_payload = '[]'::jsonb;

-- -----------------------------------------------------------------------------
-- P7: fn_kb_quality_score — función de score automático
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_kb_quality_score(kb_row public.lf_knowledge_base)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  score numeric := 0.0;
BEGIN
  IF kb_row.summary IS NOT NULL AND length(trim(kb_row.summary)) > 50 THEN
    score := score + 0.20;
  END IF;
  IF kb_row.visible_text IS NOT NULL AND length(trim(kb_row.visible_text)) > 100 THEN
    score := score + 0.15;
  END IF;
  IF kb_row.key_insights IS NOT NULL AND jsonb_array_length(kb_row.key_insights) > 0 THEN
    score := score + 0.20;
  END IF;
  IF kb_row.tags IS NOT NULL AND jsonb_array_length(kb_row.tags) > 0 THEN
    score := score + 0.10;
  END IF;
  IF kb_row.grounding_status = 'GROUNDED' THEN
    score := score + 0.15;
  END IF;
  IF kb_row.kb_category IS NOT NULL AND kb_row.kb_subcategory IS NOT NULL THEN
    score := score + 0.10;
  END IF;
  IF kb_row.topic IS NOT NULL AND length(trim(kb_row.topic)) > 0 THEN
    score := score + 0.05;
  END IF;
  IF kb_row.evidence_pack IS NOT NULL AND kb_row.evidence_pack != '{}'::jsonb THEN
    score := score + 0.05;
  END IF;
  RETURN round(score, 2);
END;
$$;

COMMENT ON FUNCTION public.fn_kb_quality_score(public.lf_knowledge_base) IS
  'Calcula quality_score automático (0.0–1.0) basado en completitud del registro KB LF. v1.0 — sesión 26.';

-- Aplicar score a registros con quality_score NULL o fuera de rango
UPDATE public.lf_knowledge_base kb
SET
  quality_score = public.fn_kb_quality_score(kb),
  updated_at    = NOW()
WHERE quality_score IS NULL OR quality_score > 1.0;

-- =============================================================================
-- FIN MIGRATION session_26b_operational_fixes
-- Evento Supabase: id=413
-- =============================================================================
