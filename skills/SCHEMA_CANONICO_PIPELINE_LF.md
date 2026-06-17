# SCHEMA CANÓNICO VERIFICADO — Pipeline LF
**Fuente:** Supabase `mhwmirqcgxxukpctffuv` — verificado 2026-06-17 en ejecución real

## lf_capture_runs
- PK: `run_id` (UUID)
- NOT NULL sin default: `operation_code`, `capture_scope`, `run_type`
- `run_type` válidos: `MANUAL`, `SCHEDULED`, `BACKFILL`, `TEST`, `DRY_RUN`
- `status` válidos: `STARTED`, `COMPLETED`, `FAILED`, `CANCELLED`, `BLOCKED`
- ⚠️ NO existe columna `records_inserted` ni `records_captured`
- UPDATE de cierre: solo `status='COMPLETED'` y `completed_at=NOW()`

## lf_capture_records
- PK: `record_id` (UUID) ← NO es `capture_record_id`
- FK: `run_id` → `lf_capture_runs`
- `record_status` válidos: `ACTIVE`, `SKIPPED`, `DUPLICATE`, `BLOCKED`, `DISCARDED`, `TEST`
- ⚠️ `CAPTURED` NO EXISTE como valor de record_status
- `risk_level` válidos: `BAJO`, `MEDIO`, `ALTO`, `CRITICO`
- `capture_confidence` válidos: `ALTA`, `MEDIA`, `BAJA`
- ⚠️ NO existe columna `summary` — usar `visual_summary` y `raw_text`

## lf_homologated_records
- PK: `homolog_id` (UUID)
- FK: `capture_record_id` → `lf_capture_records.record_id` ← nombre de FK diferente al PK
- `homolog_status`: `APROBADO` / `RECHAZADO`
- `execution_mode` acepta: `TEST`, `DRY_RUN`, `READ_ONLY`, `SCHEDULED`, `REAL`

## lf_content_decisions
- PK: `decision_id` (UUID)
- FK: `capture_record_id` → `lf_capture_records.record_id` ← NO es `homolog_id` ni `record_id`
- `decision` válidos: `ALLOW_PROD_GATE`, `REJECT`, `HITL_REQUIRED`, `DEFER`, `BLOCK`
- `consumer_gate_passed=TRUE` solo cuando `decision=ALLOW_PROD_GATE`

## lf_knowledge_base
- PK: `kb_id` (UUID)
- FK: `decision_id` → `lf_content_decisions`
- ✅ SÍ tiene columna `summary` (a diferencia de `lf_capture_records`)
- `consumer_ready=FALSE` SIEMPRE — solo owner puede cambiar

## lf_url_queue
- PK: `queue_id` (UUID)
- `estado` válidos: `PENDIENTE`, `PROCESADO`, `FALLIDO`
- `pipeline_run_id` FK → `lf_pipeline_runs` (NO a `lf_capture_runs`)
- ⚠️ UPDATE sin `pipeline_run_id` para evitar FK violation si no existe run en `lf_pipeline_runs`

## lf_pipeline_runs
- PK: `pipeline_run_id` (UUID)
- Es el target de FK desde `lf_url_queue.pipeline_run_id`

## lf_eventos
- Campos obligatorios: `evento_tipo`, `entidad_tipo`, `entidad_codigo`, `descripcion`, `severidad`, `origen`

## Dominios permitidos en pipeline
- reevalua.com
- finanty.com
- perudeudas.info ← ⚠️ NO perudeudas.com (dominio inexistente)
- youtube.com
- reddit.com/r/PERU

## Modos de ejecución permitidos (pipeline real)
- `TEST`, `DRY_RUN`, `READ_ONLY`, `SCHEDULED`, `REAL`
- ❌ `PRODUCTION_REGISTER` — siempre bloqueado
