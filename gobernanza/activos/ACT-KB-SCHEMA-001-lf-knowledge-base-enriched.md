# ACT-KB-SCHEMA-001 — lf_knowledge_base Schema Enriquecido
Estado: APROBADO
Fecha: 2026-06-18 | Sesion: 24C
Evento Supabase: id=388
Migration: enrich_lf_knowledge_base_structure (version 20260618025250)

## Cambios aplicados en Supabase

### Nuevas columnas
- kb_enriched jsonb NOT NULL DEFAULT {}  — estructura de 6 bloques
- content_type text CHECK (LANDING | ARTICULO_EDUCATIVO | FAQ | BLOG_INDEX | PRODUCTO | OTRO)

### Nuevos CHECK constraints
- lf_kb_category_check: REHABILITACION_CREDITICIA | EDUCACION_FINANCIERA | COMPETENCIA | PRODUCTO_LF | REGULACION | OTRO
- lf_kb_subcategory_check: SALIR_INFOCORP | HISTORIAL_CREDITICIO | NEGOCIAR_DEUDA | CONSTANCIA_PAGO | PRESTAMOS_REPORTADO | CENTRAL_RIESGO | REINSERCION_FINANCIERA | OTRO

## Estructura kb_enriched (6 bloques)



## Pre-migration
5 registros normalizados a MAYUSCULAS antes de aplicar constraints.
Tipos de contenido diferenciados: ARTICULO_EDUCATIVO vs LANDING.
