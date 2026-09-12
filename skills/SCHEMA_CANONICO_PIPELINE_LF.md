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
- ❌ `PROD_REGISTER_BLOQUEADO` — siempre bloqueado

---

## ⚠️ GAPS DETECTADOS EN EJECUCIÓN SUPERVISADA 2026-06-17 (Lote 21C)

### GAP #1 — lf_pipeline_runs.stage_current CHECK constraint
- `INIT` **NO EXISTE** como valor de stage_current
- Valores válidos (CHECK constraint): `CAPTURA`, `HOMOLOGACION`, `ANALISIS`, `KB_WRITE`, `COMPLETED`, `FAILED`, `HITL`
- ✅ Corrección: El pipeline_run debe crearse con `stage_current='CAPTURA'` y `stage_status='PENDING'`

### GAP #2 — Manejo de URL duplicada en S2-A (ACT-0052)
- El contrato S2-A no especificaba qué hacer cuando `duplicate_found=TRUE`
- ✅ Corrección: Si duplicado → CANCEL capture_run + marcar pipeline_run stage_status=FAILED + marcar url_queue PROCESADO + evento DUPLICATE_SKIP
- Flujo agente: verificar duplicado ANTES de crear capture_run

### GAP #3 — lf_knowledge_base: texto largo en key_insights causa timeout
- Arrays JSON muy largos en key_insights pueden causar errores intermitentes
- ✅ Corrección: Limitar cada insight a máximo 80 caracteres, máximo 5 elementos

### Secuencia correcta de stage_current en pipeline
```
CAPTURA (PENDING) → CAPTURA (RUNNING) → HOMOLOGACION (RUNNING) → ANALISIS (RUNNING) → KB_WRITE (RUNNING) → COMPLETED (COMPLETED)
```
