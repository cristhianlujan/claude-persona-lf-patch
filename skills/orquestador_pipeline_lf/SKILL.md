# SKILL — ORQUESTADOR PIPELINE LF (ACT-0058)

**Código:** ACT-0058
**Nombre canónico:** SKILL_ORQUESTADOR_PIPELINE_LF
**operation_code obligatorio:** `ORQUESTACION_PIPELINE_LF` ← usar EXACTAMENTE este valor en todos los INSERTs
**Estado:** PROD_CONTROLADA_READ_ONLY
**Fuente de verdad:** este archivo + `lf_operation_step_contracts` en Supabase
**Historial:** ver Git history

---

## Rol

Orquestador end-to-end del pipeline de inteligencia LF.
Procesa URLs de `lf_url_queue` una a la vez, en secuencia estricta, con un FOR loop que itera hasta que no queden URLs PENDIENTE.
Coordina: captura web → homologación → análisis de riesgo → escritura KB.

---

## Regla fundamental

**Una URL. Una operación. Una confirmación. Luego la siguiente.**

- Prohibido preparar múltiples INSERTs y ejecutarlos juntos.
- Cada paso requiere confirmación de la DB antes de continuar al siguiente.
- El FOR loop no termina hasta que `lf_url_queue WHERE estado='PENDIENTE'` retorne 0.
- Cualquier error en tablas de log/auditoría NO detiene el loop — solo se registra y se continúa.

---

## Pipeline bajo control

```
ACT-0052 Extracción web
ACT-0054 Extracción noticias   →  ACT-0053 Homologación → ACT-0056 Análisis → ACT-0057 KB Write
ACT-0055 Extracción docs reg
```

---

## Fuentes y keywords objetivo

**Fuentes:** reevalua.com · finanty.com · perudeudas.info · youtube.com · reddit.com/r/PERU · sbs.gob.pe · gestión.pe · elcomercio.pe

**Keywords:** "salir de Infocorp" · "negociar deuda" · "constancia de no adeudo" · "infocorp" · "central de riesgo"

---

## INICIO — antes del FOR loop

**Paso 1 — Registrar ejecución (gate físico)**

```sql
INSERT INTO lf_operation_execution
  (execution_id, operation_code, target_type, target_code, status, manifest)
VALUES
  (gen_random_uuid()::text, 'ORQUESTACION_PIPELINE_LF', 'PIPELINE', 'BATCH', 'IN_PROGRESS', '{}'::jsonb)
RETURNING execution_id, started_at;
```

⚠️ `operation_code` = `ORQUESTACION_PIPELINE_LF` exactamente. Cualquier otro valor → `PIPELINE_REAL_BLOQUEADO`.
Guardar `execution_id`. Sin este registro confirmado → DETENER.

**Paso 2 — Verificar activo vigente**

```sql
SELECT codigo_activo, runtime_estado, estado_operativo
FROM public.v_lf_fuente_operativa
WHERE codigo_activo = 'ACT-0058';
```

Si no retorna fila → DETENER.

**Paso 3 — Contar URLs pendientes**

```sql
SELECT COUNT(*) as total_pendiente FROM lf_url_queue WHERE estado = 'PENDIENTE';
```

```
print("🚀 BATCH INICIADO | execution_id: {execution_id}")
print("📋 URLs pendientes: {total_pendiente}")
```

Si `total_pendiente = 0` → ir directo a CIERRE DE BATCH.

---

## RESULTADO ESPERADO DE ESTA EJECUCIÓN

Al finalizar, `lf_url_queue` NO debe tener ningún registro con `estado='PENDIENTE'`.
Todas deben quedar en `PROCESADO` o `FALLIDO`.

Verificar al terminar:
```sql
SELECT COUNT(*) FROM lf_url_queue WHERE estado = 'PENDIENTE';
-- Resultado esperado: 0
```

## TODO — construir al inicio del loop

```
1. Obtener lista completa de URLs pendientes:
   urls_todo ← SELECT queue_id, url, url_tipo, fuente
               FROM lf_url_queue
               WHERE estado = 'PENDIENTE'
               ORDER BY created_at ASC
   total = COUNT(urls_todo)

2. Imprimir TODO list:
   print("📋 TODO LIST — {total} URLs a procesar:")
   PARA CADA url en urls_todo:
     print("[ ] {url}")

3. Procesar CADA url de la lista secuencialmente:
   PARA CADA url en urls_todo:
     → Ejecutar PIPELINE POR URL completo
     → Marcar [✓] al completar
     print("[✓] {i}/{total} completadas — {url}")

4. No terminar hasta que TODO esté 100% completo.
```

**Condiciones de parada:**

| Condición | Acción |
|-----------|--------|
| Todo list procesado al 100% | Salir → CIERRE |
| Error Supabase irrecuperable (conexión caída) | Registrar BATCH_PARCIAL → DETENER |
| Límite de contexto del agente | Registrar BATCH_PARCIAL → DETENER |
| retry_count ≥ 3 en una URL | Marcar FALLIDO → **CONTINUAR con siguiente URL** |
| Error en tabla de log/auditoría | Ignorar → **CONTINUAR con siguiente URL** |

---

## PIPELINE POR URL — operaciones secuenciales

### PASO 0 — Diagnóstico previo

```sql
SELECT pipeline_run_id, stage_current, stage_status, retry_count
FROM lf_pipeline_runs
WHERE source_url = '{url}' AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC LIMIT 1;
```

- `stage_status = COMPLETED` → `print("⏭ SKIP dedup 24h")` → UPDATE lf_url_queue estado='PROCESADO' → siguiente iteración
- `stage_status = FAILED` y `retry_count < 3` → modo RETRY
- Sin resultado → continuar

```sql
SELECT record_id, run_id FROM lf_capture_records
WHERE url = '{url}' AND record_status = 'ACTIVE' LIMIT 1;
```

- Existe → modo REPLAY
- No existe → modo FULL

---

### MODO FULL — 21 operaciones

```
OP-1.  SELECT now() → T1 | print("  ⏱ T1: {T1}")

OP-2.  INSERT lf_pipeline_runs:
         execution_id = {execution_id}   ← obligatorio, ya obtenido en INICIO
         source_url   = '{url}'
         stage_current = 'CAPTURA'
         stage_status  = 'PENDING'
         created_by    = 'ORQUESTACION_PIPELINE_LF'
       → SELECT RETURNING pipeline_run_id → confirmar
       print("  ✅ pipeline_run: {pipeline_run_id}")

OP-3.  SELECT now() → T2 | print("  ⏱ T2: {T2}")

OP-4.  Captura web real — seleccionar motor según agente ejecutor

       ## REGLAS DE MOTOR DE BÚSQUEDA POR AGENTE

       SI el agente es GPT (ChatGPT / OpenAI):
         → Usar: web.run → open(url)
         → Este es el ÚNICO método confirmado funcional para fetch externo en GPT.
         → NO usar: container.exec, urllib, python fetch, container.download
         → Ejemplo: web.run open "https://reevalua.com/blog"
         → Extraer: título, texto principal, descripción meta

       SI el agente es Claude (Anthropic):
         → Usar: web_fetch(url) o web_search(query)
         → Ejemplo: web_fetch "https://reevalua.com/blog"
         → Extraer: título, texto principal, descripción meta

       SI el agente es desconocido:
         → Intentar web.run → open primero
         → Si falla, intentar web_fetch
         → Si ambos fallan → registrar WEB_FETCH_UNAVAILABLE y continuar con siguiente URL

       ## RESULTADO ESPERADO de OP-4
       · Éxito → raw_text extraído, title extraído → continuar a OP-5
       · 403/timeout/error de red → UPDATE lf_url_queue SET estado='FALLIDO'
                                    print("  ❌ Acceso bloqueado: {motivo}")
                                    → continuar con siguiente URL (no detener pipeline)
       · Herramienta no disponible → registrar WEB_FETCH_UNAVAILABLE en lf_eventos
                                     → continuar con siguiente URL (no detener pipeline)

OP-5.  INSERT lf_capture_runs:
         operation_code = 'ORQUESTACION_PIPELINE_LF'
         capture_scope  = 'WEB_ARTICLE'
         run_type       = 'SCHEDULED'
         status         = 'COMPLETED'
         completed_at   = NOW()          ← OBLIGATORIO si status=COMPLETED
         records_detected = 1
         records_inserted = 1
         raw_payload    = jsonb con raw_text, title, url
         created_by     = 'ORQUESTACION_PIPELINE_LF'
       → SELECT RETURNING run_id → confirmar
       print("  ✅ capture_run: {run_id}")

OP-6.  SELECT now() → T3 | print("  ⏱ T3: {T3}")

OP-7.  INSERT lf_capture_records:
         url            = '{url}'        ← columna se llama 'url' no 'source_url'
         run_id         = {run_id}
         record_status  = 'ACTIVE'
         capture_confidence = 'ALTA' | 'MEDIA' | 'BAJA'
         risk_level     = 'BAJO' | 'MEDIO' | 'ALTO' | 'CRITICO'
       → SELECT RETURNING record_id → confirmar
       print("  ✅ capture_record: {record_id}")

OP-8.  UPDATE lf_pipeline_runs SET stage_current='HOMOLOGACION', stage_status='PENDING',
              capture_run_id={run_id}, updated_at=NOW()
       WHERE pipeline_run_id={pipeline_run_id}
       print("  → stage: HOMOLOGACION")

OP-9.  SELECT now() → T4 | print("  ⏱ T4: {T4}")

OP-10. INSERT lf_homologated_records:
         capture_record_id = {record_id}
         run_id            = {run_id}
         operation_code    = 'ORQUESTACION_PIPELINE_LF'
         execution_mode    = 'FULL'
         homolog_status    = 'APROBADO'  ← OBLIGATORIO este valor exacto
         consumer_gate_passed = TRUE
         homolog_package   = '{}'::jsonb
       → SELECT RETURNING homolog_id → confirmar
       print("  ✅ homolog: {homolog_id}")

OP-11. UPDATE lf_pipeline_runs SET stage_current='ANALISIS', stage_status='PENDING',
              homolog_record_id={homolog_id}, updated_at=NOW()
       print("  → stage: ANALISIS")

OP-12. SELECT now() → T5 | print("  ⏱ T5: {T5}")

OP-13. -- Verificar idempotencia primero
       SELECT decision_id FROM lf_content_decisions WHERE capture_record_id='{record_id}';
       -- Si no existe, insertar:
       INSERT lf_content_decisions:
         capture_record_id = {record_id}
         run_id            = {run_id}
         operation_code    = 'ORQUESTACION_PIPELINE_LF'
         execution_mode    = 'FULL'
         decision          = 'ALLOW_PROD_GATE' | 'BLOCK' | 'HITL_REQUIRED'
         risk_level        = 'BAJO' | 'MEDIO' | 'ALTO' | 'CRITICO'
         hitl_required     = FALSE | TRUE
         consumer_gate_passed = TRUE
         created_by        = 'ORQUESTACION_PIPELINE_LF'
       → SELECT RETURNING decision_id → confirmar
       print("  ✅ decision: {decision_id} | risk: {risk_level} | hitl: {hitl_required}")

OP-14. CHECK hitl_required / decision:
       · hitl_required=TRUE → UPDATE stage_current='HITL', stage_status='HITL', hitl_triggered=TRUE
                              print("  🛑 HITL — pausado")
                              UPDATE lf_url_queue estado='PROCESADO'
                              → siguiente iteración del FOR
       · decision='BLOCK'   → UPDATE stage_current='FAILED', stage_status='FAILED'
                              print("  🚫 BLOQUEADO")
                              UPDATE lf_url_queue estado='PROCESADO'
                              → siguiente iteración del FOR
       · decision='ALLOW_PROD_GATE' → continuar

OP-15. UPDATE lf_pipeline_runs SET stage_current='KB_WRITE', stage_status='PENDING',
              decision_id={decision_id}, updated_at=NOW()
       print("  → stage: KB_WRITE")

OP-16. SELECT now() → T6 | print("  ⏱ T6: {T6}")

OP-16B. CHECKPOINT S5-B — KB QUALITY GATE (OBLIGATORIO ANTES DEL INSERT)
        Construir y mostrar en pantalla antes de insertar:

        visible_text  → extracto literal de la fuente (no resumen interno)
        summary       → interpretacion interna LF — DEBE SER DIFERENTE a visible_text
        key_insights  → JSON array, MINIMO 3 strings accionables
                        PROHIBIDO: ["keyword1 / keyword2 / keyword3"]
                        CORRECTO:  ["Insight accionable 1", "Insight 2", "Insight 3"]
        kb_enriched   → JSON object completo con estas claves obligatorias:
                        identidad, confianza, conversion, uso_semantico,
                        propuesta_comercial, riesgo_cumplimiento
                        PROHIBIDO: {}
                        Si un dato no esta en la fuente: "no_encontrado_en_fuente"

        Si CUALQUIER campo falla el control:
        → NO insertar en lf_knowledge_base
        → UPDATE lf_pipeline_runs SET stage_current='FAILED'
        → INSERT lf_eventos tipo='KB_QUALITY_GATE_FAILED'
        → continuar con siguiente URL

OP-17. -- Verificar idempotencia primero
       SELECT kb_id FROM lf_knowledge_base WHERE decision_id='{decision_id}';
       -- Si no existe, insertar (solo si OP-16B paso todos los controles):
       INSERT lf_knowledge_base:
         decision_id      = {decision_id}
         run_id           = {run_id}
         operation_code   = 'ORQUESTACION_PIPELINE_LF'
         execution_mode   = 'FULL'
         source_url       = '{url}'
         decision_upstream = 'ALLOW_PROD_GATE'
         kb_dimension     = 'EDUCATIVO' | 'ALERTA' | 'REGULATORIO' | 'SEÑAL_MERCADO' | 'PSICOLOGIA_USUARIO' | 'COMPORTAMIENTO_DIGITAL'
         kb_polarity      = 'POSITIVO' | 'NEGATIVO' | 'NEUTRAL'  ← NEUTRAL no NEUTRO
         kb_category      = 'REHABILITACION_CREDITICIA' | 'EDUCACION_FINANCIERA' | 'COMPETENCIA' | 'REGULACION' | 'OTRO'
         kb_subcategory   = 'SALIR_INFOCORP' | 'NEGOCIAR_DEUDA' | 'CONSTANCIA_PAGO' | 'HISTORIAL_CREDITICIO' | 'CENTRAL_RIESGO' | 'OTRO'
         content_type     = 'LANDING' | 'ARTICULO_EDUCATIVO' | 'FAQ' | 'BLOG_INDEX' | 'PRODUCTO' | 'OTRO'
         visible_text     = '{visible_text}'   ← literal de la fuente
         summary          = '{summary}'        ← interpretacion LF, distinto a visible_text
         key_insights     = '[...]'::jsonb     ← array minimo 3 strings accionables
         kb_enriched      = '{...}'::jsonb     ← OBLIGATORIO completo, PROHIBIDO {}
         consumer_ready   = FALSE              ← trigger lo actualiza si califica
         quality_score    = 0.0 a 1.0
         created_by       = 'ORQUESTACION_PIPELINE_LF'
       → SELECT RETURNING kb_id → confirmar
       print("  ✅ kb: {kb_id} | score: {quality_score}")

OP-18. UPDATE lf_pipeline_runs SET stage_current='COMPLETED', stage_status='COMPLETED',
              kb_id={kb_id}, updated_at=NOW()
       print("  → stage: COMPLETED")

OP-19. SELECT now() → T7 | print("  ⏱ T7: {T7}")
       Si T1=T2=T3=T4=T5=T6=T7 → BATCH_INVALIDO (no registrar como éxito)

OP-20. UPDATE lf_url_queue SET estado='PROCESADO', updated_at=NOW()
       WHERE queue_id='{queue_id}'

OP-21. INSERT lf_eventos:
         evento_tipo = 'PIPELINE_COMPLETADO'
         entidad_tipo = 'PIPELINE_RUN'
         entidad_codigo = 'ACT-0058'
         severidad = 'INFO'
         payload = jsonb con pipeline_run_id, kb_id, T1-T7, quality_score
         origen = 'ORQUESTACION_PIPELINE_LF'
```

---

### MODO REPLAY — capture_record existe

- Saltar OP-4 a OP-7. Usar `run_id` y `record_id` existentes.
- Continuar desde OP-8.
- Verificar idempotencia en OP-13 y OP-17 antes de insertar.

### MODO RETRY — pipeline_run fallido, retry_count < 3

```sql
UPDATE lf_pipeline_runs
SET retry_count = retry_count + 1, stage_status = 'PENDING', updated_at = NOW()
WHERE pipeline_run_id = '{pipeline_run_id}';
```

- Reiniciar desde el `stage_current` donde falló.
- Si retry_count llega a 3 → marcar FAILED definitivo → siguiente iteración.

---

## CIERRE DE BATCH

```
print("═════════════════════════════════════════")
print("🏁 BATCH COMPLETADO")
print("   Procesadas : {procesadas}")
print("   Fallidas   : {fallidas}")
print("   KB creados : {kb_creados}")
print("═════════════════════════════════════════")
```

```sql
INSERT INTO lf_eventos
  (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen)
VALUES (
  'BATCH_COMPLETADO',
  'PIPELINE_RUN', 'ACT-0058',
  'Batch: {procesadas} procesadas, {fallidas} fallidas',
  'INFO',
  '{"urls_procesadas": N, "urls_fallidas": M, "kb_creados": J, "execution_id": "..."}'::jsonb,
  'ACT-0058_AUTOMATION'
);
```

Usar `BATCH_PARCIAL` si se detuvo por límite de contexto.

---

## REDESCUBRIMIENTO DE URLs (tras BATCH_COMPLETADO)

Buscar mínimo 5 URLs nuevas. Deduplicar antes de insertar:

```sql
SELECT COUNT(*) FROM lf_url_queue WHERE url = '{url_candidata}';
SELECT COUNT(*) FROM lf_knowledge_base WHERE source_url = '{url_candidata}';
-- Solo insertar si ambas = 0
```

```sql
INSERT INTO lf_url_queue (url, fuente, keyword_target, estado, url_tipo, created_by)
VALUES ('{url}', '{dominio}', '{keyword}', 'PENDIENTE', '{tipo}', 'ACT-0058_AUTOMATION');
```

`url_tipo` valores válidos: `EDUCATIVO / COMERCIAL / REGULATORIO / COMPETENCIA / INDICE / OTRO`

Si no se encuentran 5 URLs → registrar evento con severidad `WARN`.

---

## Enums críticos — verificados contra DB

| Tabla | Campo | Valores válidos |
|-------|-------|----------------|
| `lf_capture_runs` | `status` | STARTED / COMPLETED / FAILED / CANCELLED / BLOCKED |
| `lf_capture_runs` | `run_type` | MANUAL / SCHEDULED / BACKFILL / TEST / DRY_RUN |
| `lf_capture_runs` | `completed_at` | **Obligatorio si status=COMPLETED** |
| `lf_capture_records` | `capture_confidence` | ALTA / MEDIA / BAJA |
| `lf_capture_records` | `risk_level` | BAJO / MEDIO / ALTO / CRITICO |
| `lf_capture_records` | `record_status` | ACTIVE / SKIPPED / DUPLICATE / BLOCKED / DISCARDED / TEST |
| `lf_capture_records` | columna URL | `url` (no `source_url`) |
| `lf_homologated_records` | `homolog_status` | **APROBADO** (para que el pipeline avance) |
| `lf_homologated_records` | `execution_mode` | FULL / REPLAY / RETRY / DRY_RUN |
| `lf_content_decisions` | `risk_level` | BAJO / MEDIO / ALTO / CRITICO |
| `lf_content_decisions` | `decision` | ALLOW_PROD_GATE / BLOCK / HITL_REQUIRED |
| `lf_knowledge_base` | `kb_dimension` | EDUCATIVO / ALERTA / REGULATORIO / SEÑAL_MERCADO / PSICOLOGIA_USUARIO / COMPORTAMIENTO_DIGITAL |
| `lf_knowledge_base` | `kb_polarity` | POSITIVO / NEGATIVO / **NEUTRAL** (no NEUTRO) |
| `lf_knowledge_base` | `kb_category` | REHABILITACION_CREDITICIA / EDUCACION_FINANCIERA / COMPETENCIA / PRODUCTO_LF / REGULACION / OTRO |
| `lf_knowledge_base` | `kb_subcategory` | SALIR_INFOCORP / HISTORIAL_CREDITICIO / NEGOCIAR_DEUDA / CONSTANCIA_PAGO / PRESTAMOS_REPORTADO / CENTRAL_RIESGO / REINSERCION_FINANCIERA / OTRO |
| `lf_knowledge_base` | `content_type` | LANDING / ARTICULO_EDUCATIVO / FAQ / BLOG_INDEX / PRODUCTO / OTRO |
| `lf_knowledge_base` | `kb_enriched` | **Obligatorio** — usar `'{}'::jsonb` si no hay datos |
| `lf_knowledge_base` | `decision_upstream` | **Obligatorio** — usar `'ALLOW_PROD_GATE'` |
| `lf_pipeline_runs` | `stage_current` | CAPTURA / HOMOLOGACION / ANALISIS / KB_WRITE / COMPLETED / FAILED / HITL |
| `lf_pipeline_runs` | `stage_status` | PENDING / RUNNING / COMPLETED / FAILED / HITL |
| `lf_url_queue` | `estado` | PENDIENTE / PROCESADO / FALLIDO / DESCARTADO / SKIP |
| `lf_url_queue` | `url_tipo` | EDUCATIVO / COMERCIAL / REGULATORIO / COMPETENCIA / INDICE / OTRO |
| `lf_eventos` | `severidad` | INFO / WARN / CRITICAL |
| `lf_eventos` | columna tipo | `evento_tipo` (no `tipo_evento`) |

---

## Errores no bloqueantes — ignorar y continuar el loop

| Error | Acción |
|-------|--------|
| Cualquier error en `lf_operation_execution_steps` | Ignorar — es log granular opcional. Continuar. |
| `lf_operation_execution` — error al hacer UPDATE final | Ignorar — trazabilidad ya está en `lf_eventos`. Continuar. |

---

## Errores frecuentes — causa y solución

| Error | Causa | Solución |
|-------|-------|---------|
| `PIPELINE_REAL_BLOQUEADO` | GPT usó nombre canónico como operation_code | Usar `ORQUESTACION_PIPELINE_LF` exactamente |
| `violates check constraint lf_capture_runs_completed_status_check` | `completed_at` nulo con status=COMPLETED | Agregar `completed_at = NOW()` |
| `violates check constraint lf_url_queue_estado_check` | Enum incorrecto | Usar `PROCESADO` (no `PROCESADA`) |
| `violates check constraint lf_kb_polarity_check` | Enum incorrecto | Usar `NEUTRAL` (no `NEUTRO`) |
| `violates check constraint lf_kb_category_check` | Enum fuera de lista | Ver tabla de enums arriba |
| `null value in column kb_enriched` | Campo obligatorio omitido | Usar `'{}'::jsonb` |
| `null value in column decision_upstream` | Campo obligatorio omitido | Usar `'ALLOW_PROD_GATE'` |
| `duplicate key lf_content_decisions_capture_record_uk` | Decision ya existe | SELECT primero, reutilizar `decision_id` |
| `duplicate key lf_knowledge_base_decision_id_uk` | KB ya existe | SELECT primero, reutilizar `kb_id` |
| `column source_url does not exist in lf_capture_records` | Nombre incorrecto | Usar `url` |
| `null value in column execution_id` | FK faltante | INSERT en `lf_operation_execution` primero |
| `stage_current INIT invalid` | Enum incorrecto | Usar `CAPTURA` como stage inicial |
| `severidad WARNING invalid` | Enum incorrecto | Usar `WARN` |
| `homolog_status PENDING — step no avanza` | Default de DB — GPT no lo sobreescribió | Insertar `homolog_status='APROBADO'` explícitamente |


