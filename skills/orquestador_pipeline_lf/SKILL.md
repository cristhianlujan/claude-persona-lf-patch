# SKILL — ORQUESTADOR PIPELINE LF (ACT-0058)

**Código:** ACT-0058
**Nombre canónico:** SKILL_ORQUESTADOR_PIPELINE_LF
**Estado:** PRODUCCION_CONTROLADA_READ_ONLY
**Fuente de verdad:** este archivo + `lf_operation_step_contracts` en Supabase
**Historial:** ver Git history

---

## Rol

Orquestador end-to-end del pipeline de inteligencia LF.
Procesa URLs de `lf_url_queue` una a la vez, en secuencia estricta.
Coordina: captura web → homologación → análisis de riesgo → escritura KB.

---

## Regla fundamental

**Una URL. Una operación. Una confirmación. Luego la siguiente.**

Está prohibido preparar múltiples INSERTs y ejecutarlos juntos.
Cada paso requiere confirmación de la DB antes de continuar al siguiente.
Si todos los registros de un batch tienen el mismo `created_at` → el run es inválido.

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

## Protocolo de ejecución — FOR loop obligatorio

### INICIO — antes del loop

**Paso 1 — Registrar ejecución (gate físico)**

```sql
INSERT INTO lf_operation_execution
  (execution_id, operation_code, target_type, target_code, status, manifest)
VALUES
  (gen_random_uuid()::text, 'ORQUESTACION_PIPELINE_LF', 'PIPELINE', 'BATCH', 'IN_PROGRESS', '{}'::jsonb)
RETURNING execution_id, started_at;
```

Guardar `execution_id`. Sin este registro confirmado → DETENER. No continuar.

**Paso 2 — Verificar activo vigente**

```sql
SELECT codigo_activo, runtime_estado, estado_operativo
FROM public.v_lf_fuente_operativa
WHERE codigo_activo = 'ACT-0058';
```

Si no retorna fila con estado operativo → DETENER.

**Paso 3 — Contar URLs pendientes**

```sql
SELECT COUNT(*) as total_pendiente FROM lf_url_queue WHERE estado = 'PENDIENTE';
```

```
print("🚀 BATCH INICIADO | execution_id: {execution_id}")
print("📋 URLs pendientes: {total_pendiente}")
```

Si `total_pendiente = 0` → registrar BATCH_COMPLETADO y terminar.

---

### FOR loop — una URL a la vez

```
i = 0

REPETIR:

  i = i + 1

  url_actual ← SELECT queue_id, url, url_tipo, fuente
               FROM lf_url_queue
               WHERE estado = 'PENDIENTE'
               ORDER BY url_tipo, created_at
               LIMIT 1

  SI url_actual está vacío → salir del loop → ir a CIERRE

  print("─────────────────────────────────────────")
  print("[{i}/{total_pendiente}] 📌 {url_actual.url}")

  → Ejecutar PIPELINE COMPLETO para url_actual (ver sección siguiente)

  → Al finalizar url_actual:
      print("[{i}/{total_pendiente}] ✅ COMPLETADA | score: {quality_score} | kb_id: {kb_id}")
      — o —
      print("[{i}/{total_pendiente}] ❌ FALLIDA | motivo: {error_detail}")

  → VOLVER AL INICIO DEL LOOP

FIN LOOP
```

**Condiciones de salida del loop:**

| Condición | Acción |
|-----------|--------|
| No hay más URLs PENDIENTE | Salir → CIERRE |
| Error Supabase irrecuperable | Registrar BATCH_PARCIAL → DETENER |
| Límite de contexto del agente | Registrar BATCH_PARCIAL con URLs restantes → DETENER |
| retry_count ≥ 3 en una URL | Marcar FALLIDO → CONTINUAR con siguiente iteración |

---

### PIPELINE COMPLETO por URL — 20 operaciones secuenciales

**Diagnóstico previo (PASO 0)**

```sql
-- ¿Ya existe run completado en 24h?
SELECT pipeline_run_id, stage_current, stage_status, retry_count
FROM lf_pipeline_runs
WHERE source_url = '{url}' AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC LIMIT 1;
```

- `stage_status = COMPLETED` → `print("⏭ SKIP — deduplicación 24h")` → UPDATE PROCESADO → siguiente iteración
- `stage_status = FAILED` y `retry_count < 3` → modo RETRY
- Sin resultado → continuar

```sql
-- ¿Existe capture_record activo?
SELECT record_id, run_id FROM lf_capture_records
WHERE url = '{url}' AND record_status = 'ACTIVE' LIMIT 1;
```

- Existe → modo REPLAY · `print("  ♻️ Modo REPLAY — reutilizando captura existente")`
- No existe → modo FULL · `print("  🌐 Modo FULL — captura web real")`

**Secuencia de operaciones (modo FULL)**

```
1.  SELECT now()                              → T1
    print("  ⏱ T1: {T1}")

2.  INSERT lf_pipeline_runs (execution_id=<id>, source_url, stage_current='CAPTURA')
    → CONFIRMAR pipeline_run_id con SELECT
    print("  ✅ pipeline_run creado: {pipeline_run_id}")

3.  SELECT now()                              → T2
    print("  ⏱ T2: {T2}")

4.  Captura web real (HEAD/GET, timeout 8s)
    · HTTP 200/301/302 → continuar
    · 403/timeout → UPDATE lf_url_queue estado='FALLIDO'
                    print("  ❌ Acceso bloqueado — marcando FALLIDO")
                    → siguiente iteración del FOR

5.  INSERT lf_capture_runs
    → CONFIRMAR run_id
    print("  ✅ capture_run: {run_id}")

6.  SELECT now()                              → T3
    print("  ⏱ T3: {T3}")

7.  INSERT lf_capture_records (url='{url}', record_status='ACTIVE', ...)
    → CONFIRMAR record_id
    print("  ✅ capture_record: {record_id} | confidence: {capture_confidence}")

8.  UPDATE lf_pipeline_runs SET stage_current='HOMOLOGACION'
    print("  → stage: HOMOLOGACION")

9.  SELECT now()                              → T4
    print("  ⏱ T4: {T4}")

10. INSERT lf_homologated_records
    → CONFIRMAR homolog_id
    print("  ✅ homolog: {homolog_id}")

11. UPDATE lf_pipeline_runs SET stage_current='ANALISIS'
    print("  → stage: ANALISIS")

12. SELECT now()                              → T5
    print("  ⏱ T5: {T5}")

13. INSERT lf_content_decisions (verificar UNIQUE antes)
    → CONFIRMAR decision_id
    print("  ✅ decision: {decision_id} | risk: {risk_level} | hitl: {hitl_required}")

14. CHECK hitl_required:
    · TRUE  → UPDATE stage_current='HITL', stage_status='HITL'
              print("  🛑 HITL requerido — pipeline pausado")
              → siguiente iteración del FOR
    · decision='BLOCK' → UPDATE stage_current='FAILED'
              print("  🚫 Contenido BLOQUEADO por análisis de riesgo")
              → siguiente iteración del FOR
    · FALSE → continuar

15. UPDATE lf_pipeline_runs SET stage_current='KB_WRITE'
    print("  → stage: KB_WRITE")

16. SELECT now()                              → T6
    print("  ⏱ T6: {T6}")

17. INSERT lf_knowledge_base (verificar UNIQUE antes)
    → CONFIRMAR kb_id
    print("  ✅ kb: {kb_id} | quality_score: {quality_score} | consumer_ready: {consumer_ready}")

18. UPDATE lf_pipeline_runs SET stage_current='COMPLETED', stage_status='COMPLETED', kb_id=<kb_id>
    print("  → stage: COMPLETED")

19. SELECT now()                              → T7
    print("  ⏱ T7: {T7}")

    VALIDAR TIMESTAMPS:
    Si T1=T2=T3=T4=T5=T6=T7 → print("  🔴 BATCH_INVALIDO — timestamps idénticos")
                                No registrar como COMPLETED. Registrar evento BATCH_INVALIDO.

20. UPDATE lf_url_queue SET estado='PROCESADO' WHERE queue_id='{queue_id}'

21. INSERT lf_eventos (PIPELINE_COMPLETADO, severidad=INFO, payload con T1-T7)
```

**Modo REPLAY** — capture_record activo ya existe:
- Saltar operaciones 4-7. Usar `run_id` y `record_id` existentes.
- Verificar idempotencia en ANALISIS y KB_WRITE (SELECT antes de INSERT).
- Continuar desde operación 8.

**Modo RETRY** — pipeline_run fallido con retry_count < 3:
- Leer `stage_current` del run fallido. Reiniciar desde ese stage.
- `UPDATE lf_pipeline_runs SET retry_count = retry_count + 1, stage_status='PENDING'`
- Si retry_count llega a 3 → FALLIDO definitivo → siguiente iteración.

---

### CIERRE DE BATCH

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
  'BATCH_COMPLETADO',   -- o BATCH_PARCIAL si no se procesaron todas
  'PIPELINE_RUN', 'ACT-0058',
  'Batch completado: {procesadas} procesadas, {fallidas} fallidas',
  'INFO',
  '{"urls_procesadas": N, "urls_fallidas": M, "kb_creados": J, "execution_id": "..."}'::jsonb,
  'ACT-0058_AUTOMATION'
);
```

---

### REDESCUBRIMIENTO DE URLs (tras BATCH_COMPLETADO)

Obligatorio. Buscar mínimo 5 URLs nuevas en fuentes objetivo.

```
print("🔍 Iniciando redescubrimiento de URLs...")
```

Deduplicación obligatoria antes de insertar:
```sql
SELECT COUNT(*) FROM lf_url_queue WHERE url = '{url_candidata}';
SELECT COUNT(*) FROM lf_knowledge_base WHERE source_url = '{url_candidata}';
-- Solo insertar si ambas retornan 0
```

```sql
INSERT INTO lf_url_queue (url, fuente, keyword_target, estado, url_tipo, created_by)
VALUES ('{url}', '{dominio}', '{keyword}', 'PENDIENTE', '{tipo}', 'ACT-0058_AUTOMATION');
```

```
print("🔍 Redescubrimiento: {n_nuevas} URLs nuevas añadidas")
```

```sql
INSERT INTO lf_eventos (...) VALUES ('QUEUE_RECARGADA', ...);
```

Si no se encuentran 5 URLs → severidad `WARN`.

---

## Enums críticos

| Tabla | Campo | Valores válidos |
|-------|-------|----------------|
| `lf_capture_records` | `capture_confidence` | ALTA / MEDIA / BAJA |
| `lf_capture_records` | `risk_level` | BAJO / MEDIO / ALTO / CRITICO |
| `lf_capture_records` | `record_status` | ACTIVE / SKIPPED / DUPLICATE / BLOCKED / DISCARDED / TEST |
| `lf_capture_records` | columna URL | `url` (no `source_url`) |
| `lf_content_decisions` | `risk_level` | BAJO / MEDIO / ALTO / CRITICO |
| `lf_content_decisions` | `decision` | ALLOW_PROD_GATE / BLOCK / HITL_REQUIRED |
| `lf_knowledge_base` | `kb_dimension` | EDUCATIVO / ALERTA / REGULATORIO / SEÑAL_MERCADO / PSICOLOGIA_USUARIO / COMPORTAMIENTO_DIGITAL |
| `lf_knowledge_base` | `kb_polarity` | POSITIVO / NEGATIVO / NEUTRO |
| `lf_pipeline_runs` | `stage_current` | CAPTURA / HOMOLOGACION / ANALISIS / KB_WRITE / COMPLETED / FAILED / HITL |
| `lf_url_queue` | `estado` | PENDIENTE / PROCESADO / FALLIDO / DESCARTADO / SKIP |
| `lf_eventos` | `severidad` | INFO / WARN / CRITICAL |
| `lf_eventos` | columna tipo | `evento_tipo` (no `tipo_evento`) |

---

## Errores frecuentes

| Error | Causa | Solución |
|-------|-------|---------|
| `column tipo_evento does not exist` | Nombre incorrecto | Usar `evento_tipo` |
| `violates check constraint lf_url_queue_estado_check` | Enum incorrecto | Usar `PROCESADO` (no `PROCESADA`) |
| `duplicate key lf_content_decisions_capture_record_uk` | Decision ya existe | SELECT primero, reutilizar `decision_id` |
| `duplicate key lf_knowledge_base_decision_id_uk` | KB ya existe | SELECT primero, reutilizar `kb_id` |
| `column source_url does not exist in lf_capture_records` | Nombre incorrecto | Usar `url` |
| `null value in column execution_id` | FK faltante | INSERT en `lf_operation_execution` primero |
| `INIT is invalid for stage_current` | Enum incorrecto | Usar `CAPTURA` como stage inicial |
| `severidad WARNING invalid` | Enum incorrecto | Usar `WARN` |
