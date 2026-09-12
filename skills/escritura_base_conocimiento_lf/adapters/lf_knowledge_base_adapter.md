# ADAPTER: lf_knowledge_base

**Skill owner:** SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF (ACT-0057)
**Tabla destino:** public.lf_knowledge_base
**Estado:** CANDIDATO_READ_ONLY
**Operacion:** WRITE (con ALLOW_PROD_GATE o ALERT_CAPTURE y execution_mode autorizado)
**Version:** v0.2 — soporte KB multidimensional + kb_enriched obligatorio

## Mapeo de campos

| Campo skill output | Columna BD | Tipo | Notas |
|---|---|---|---|
| decision_id | decision_id | UUID | FK a lf_content_decisions |
| run_id | run_id | UUID | UUID del run actual |
| operation_code | operation_code | TEXT | ESCRITURA_BASE_CONOCIMIENTO_LF |
| execution_mode | execution_mode | TEXT | DRY_RUN no escribe a tabla real |
| kb_category | kb_category | TEXT | Categoria KB clasificada |
| kb_subcategory | kb_subcategory | TEXT | Nullable |
| kb_polarity | kb_polarity | TEXT | POSITIVO/NEGATIVO/NEUTRAL — NOT NULL desde v0.2 |
| kb_dimension | kb_dimension | TEXT | EDUCATIVO/ALERTA/REGULATORIO/SEÑAL_MERCADO — NOT NULL desde v0.2 |
| topic | topic | TEXT | Del upstream ACT-0056 |
| source_url | source_url | TEXT | Nullable |
| visible_text | visible_text | TEXT | Nullable |
| summary | summary | TEXT | Generado en S5-A |
| key_insights | key_insights | JSONB | Array de strings |
| tags | tags | JSONB | Array de strings |
| competitor | competitor | TEXT | Nullable |
| decision_upstream | decision_upstream | TEXT | ALLOW_PROD_GATE o ALERT_CAPTURE |
| quality_score | quality_score | NUMERIC | 0-10 |
| consumer_ready | consumer_ready | BOOLEAN | Default false hasta gate |
| kb_enriched | kb_enriched | JSONB | Estructura completa generada en S5-B — OBLIGATORIO |
| alert_actor | — | — | Solo para ALERT_CAPTURE — va dentro de evidence_pack |
| alert_evidence_url | — | — | Solo para ALERT_CAPTURE — va dentro de evidence_pack |
| evidence_pack | evidence_pack | JSONB | JSONB completo |
| evidence_event_id | evidence_event_id | BIGINT | ID evento lf_eventos |

## Restricciones

- NO escribir sin decision_upstream verificado (ALLOW_PROD_GATE o ALERT_CAPTURE)
- NO escribir sin run_id valido
- NO escribir si kb_enriched = {} o null — bloquear en S5-B
- NO escribir ALERT_CAPTURE sin alert_actor en evidence_pack
- DRY_RUN: simular write sin INSERT real

## Regla de calidad kb_enriched

El campo kb_enriched debe tener las 6 secciones completas antes del INSERT:
identidad, confianza, conversion, uso_semantico, propuesta_comercial, riesgo_cumplimiento.
Si cualquier seccion falta o esta vacia, S5-B debe rellenarla con el raw_text disponible.
Un kb_enriched = {} es failure_reason = kb_enriched_no_generado en lf_pipeline_runs.
