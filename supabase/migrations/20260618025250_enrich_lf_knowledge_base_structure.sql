-- Migration: enrich_lf_knowledge_base_structure
-- Fecha: 2026-06-18 | Sesion: 24C
-- Objetivo: Enriquecer lf_knowledge_base con estructura estandar de 6 bloques,
--           constraints de categoria en MAYUSCULAS y campo content_type.

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

-- 2. Campo estructurado enriquecido (6 bloques: identidad, propuesta_comercial,
--    conversion, confianza, riesgo_cumplimiento, uso_semantico)
ALTER TABLE public.lf_knowledge_base
  ADD COLUMN kb_enriched jsonb NOT NULL DEFAULT '{}'::jsonb;

-- 3. content_type con CHECK
ALTER TABLE public.lf_knowledge_base
  ADD COLUMN content_type text,
  ADD CONSTRAINT lf_kb_content_type_check
    CHECK (content_type IS NULL OR content_type = ANY (ARRAY[
      'LANDING','ARTICULO_EDUCATIVO','FAQ','BLOG_INDEX','PRODUCTO','OTRO']));

-- Nota: pre-migration se normalizaron 5 registros existentes a valores MAYUSCULAS
-- Evento Supabase: id=388 | SCHEMA_ENRICHMENT
