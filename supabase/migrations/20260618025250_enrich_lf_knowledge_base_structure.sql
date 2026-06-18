-- Migration: enrich_lf_knowledge_base_structure
-- Version: 20260618025250
-- Fecha: 2026-06-18 | Sesion: 24C
-- Aplicada via: apply_migration (Supabase MCP)
-- Evento Supabase: id=388
--
-- Objetivo: Enriquecer lf_knowledge_base con estructura estandar de 6 bloques,
--           constraints de categoria en MAYUSCULAS y campo content_type.
--
-- NOTA: Esta migration ya fue aplicada en Supabase produccion.
--       Este archivo es el registro documental en GitHub.

-- 1. CHECK constraints kb_category y kb_subcategory en MAYUSCULAS
ALTER TABLE public.lf_knowledge_base
  ADD CONSTRAINT lf_kb_category_check
    CHECK (kb_category IS NULL OR kb_category = ANY (ARRAY[
      'REHABILITACION_CREDITICIA','EDUCACION_FINANCIERA','COMPETENCIA',
      'PRODUCTO_LF','REGULACION','OTRO'])),
  ADD CONSTRAINT lf_kb_subcategory_check
    CHECK (kb_subcategory IS NULL OR kb_subcategory = ANY (ARRAY[
      'SALIR_INFOCORP','HISTORIAL_CREDITICIO','NEGOCIAR_DEUDA',
      'CONSTANCIA_PAGO','PRESTAMOS_REPORTADO','CENTRAL_RIESGO',
      'REINSERCION_FINANCIERA','OTRO']));

-- 2. Campo estructurado enriquecido
--    Estructura: {identidad, propuesta_comercial, conversion,
--                 confianza, riesgo_cumplimiento, uso_semantico}
ALTER TABLE public.lf_knowledge_base
  ADD COLUMN kb_enriched jsonb NOT NULL DEFAULT '{}'::jsonb;

-- 3. content_type con CHECK
ALTER TABLE public.lf_knowledge_base
  ADD COLUMN content_type text,
  ADD CONSTRAINT lf_kb_content_type_check
    CHECK (content_type IS NULL OR content_type = ANY (ARRAY[
      'LANDING','ARTICULO_EDUCATIVO','FAQ','BLOG_INDEX','PRODUCTO','OTRO']));

-- Pre-migration: 5 registros normalizados a MAYUSCULAS antes de aplicar constraints.
