# ADAPTER: lf_knowledge_base

**Skill owner:** SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF (ACT-0057)
**Tabla destino:** public.lf_knowledge_base
**Estado:** CANDIDATO_READ_ONLY
**Operacion:** WRITE (solo con ALLOW_PROD_GATE y execution_mode autorizado)

## Mapeo de campos

| Campo skill output | Columna BD | Notas |
|---|---|---|
| decision_id | decision_id | FK a lf_content_decisions |
| run_id | run_id | UUID del run actual |
| operation_code | operation_code | ESCRITURA_BASE_CONOCIMIENTO_LF |
| execution_mode | execution_mode | DRY_RUN no escribe a tabla real |
| kb_category | kb_category | Categoria KB clasificada |
| kb_subcategory | kb_subcategory | Nullable |
| topic | topic | Del upstream ACT-0056 |
| source_url | source_url | Nullable |
| visible_text | visible_text | Nullable |
| summary | summary | Generado en S5-A |
| key_insights | key_insights | JSONB array |
| tags | tags | JSONB array |
| competitor | competitor | Nullable |
| decision_upstream | decision_upstream | Siempre ALLOW_PROD_GATE |
| quality_score | quality_score | 0-10 |
| consumer_ready | consumer_ready | Default false hasta gate |
| evidence_pack | evidence_pack | JSONB completo |
| evidence_event_id | evidence_event_id | ID evento lf_eventos |

## Restricciones

- NO escribir sin decision_upstream = ALLOW_PROD_GATE verificado
- NO escribir sin run_id valido
- DRY_RUN: simular write sin INSERT real
