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
Cada paso requiere confirmación de la DB antes de continuar.
Si todos los registros tienen el mismo `created_at` → el run es inválido.

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

## Protocolo de ejecución

### INICIO OBLIGATORIO — antes de cualquier URL

**Paso 1 — Registrar ejecución (gate físico)**

```sql
INSERT INTO lf_operation_execution
  (execution_id, operation_code, target_type, target_code, status)
VALUES
  (gen_random_uuid()::text, 'ORQUESTACION_PIPELINE_LF', 'PIPELINE', 'BATCH', 'IN_PROGRESS')
RETURNING execution_id, started_at;
```

Guardar `execution_id`. Sin este registro confirmado, no continuar.

**Paso 2 — Verificar activo vigente**

```sql
SELECT codigo_activo, runtime_estado, estado_operativo
FROM public.v_lf_fuente_operativa
WHERE codigo_activo = 'ACT-0058';
```

Si no retorna fila con estado operativo → BLOQUEAR. No continuar.

**Paso 3 — Obtener URLs pendientes**

```sql
SELECT queue_id, url, url_tipo, fuente, intento_count
FROM lf_url_queue
WHERE estado = 'PENDIENTE'
ORDER BY url_tipo, created_at
LIMIT 50;
```

Si lista vacía → registrar `BATCH_COMPLETADO` y terminar.
Si hay URLs → iterar una por una con el protocolo por URL.

---

### PROTOCOLO POR URL — 20 operaciones secuenciales

Para cada URL de la lista, ejecutar en este orden exacto.
Cada operación debe confirmarse antes de continuar a la siguiente.

**Diagnóstico previo (PASO 0)**

```sql
-- ¿Ya existe pipeline_run completado en 24h?
SELECT pipeline_run_id, stage_current, stage_status, retry_count
FROM lf_pipeline_runs
WHERE source_url = '<URL>'
  AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC LIMIT 1;
```

- `stage_status = COMPLETED` → saltar URL (deduplicación).
- `stage_status = FAILED` y `retry_count < 3` → modo RETRY.
- Sin resultado → continuar.

```sql
-- ¿Existe capture_record activo?
SELECT record_id, run_id FROM lf_capture_records
WHERE url = '<URL>' AND record_status = 'ACTIVE' LIMIT 1;
```

- Existe → modo REPLAY (saltar captura web).
- No existe → modo FULL (captura web real).

**Operaciones (modo FULL)**

```
1.  SELECT now()                                        → T1
2.  INSERT lf_pipeline_runs                             → confirmar pipeline_run_id
3.  SELECT now()                                        → T2
4.  Captura web real de la URL (HEAD/GET, timeout 8s)
      · Si HTTP 200/301/302 → continuar
      · Si 403/timeout → UPDATE lf_url_queue estado='FALLIDO', continuar con siguiente URL
5.  INSERT lf_capture_runs                              → confirmar run_id
6.  SELECT now()                                        → T3
7.  INSERT lf_capture_records                           → confirmar record_id
8.  UPDATE lf_pipeline_runs SET stage_current='HOMOLOGACION'
9.  SELECT now()                                        → T4
10. INSERT lf_homologated_records                       → confirmar homolog_id
11. UPDATE lf_pipeline_runs SET stage_current='ANALISIS'
12. SELECT now()                                        → T5
13. INSERT lf_content_decisions                         → confirmar decision_id
14. UPDATE lf_pipeline_runs SET stage_current='KB_WRITE'
    · Si hitl_required=TRUE → SET stage_current='HITL', stage_status='HITL'. Detener esta URL.
    · Si decision='BLOCK'   → SET stage_current='FAILED'. Detener esta URL.
15. SELECT now()                                        → T6
16. INSERT lf_knowledge_base                            → confirmar kb_id
17. UPDATE lf_pipeline_runs SET stage_current='COMPLETED', stage_status='COMPLETED'
18. SELECT now()                                        → T7
19. UPDATE lf_url_queue SET estado='PROCESADO' WHERE queue_id='<id>'
20. INSERT lf_eventos (evento individual por URL)
```

**Modo REPLAY** — capture_record ya existe:
- Saltar pasos 4-7. Usar `run_id` y `record_id` existentes.
- Verificar idempotencia antes de ANALISIS y KB_WRITE (SELECT primero, reutilizar si existe).
- Continuar desde paso 8.

**Modo RETRY** — pipeline_run fallido con retry_count < 3:
- Leer `stage_current` del run fallido. Reiniciar desde ese stage.
- `UPDATE lf_pipeline_runs SET retry_count = retry_count + 1, stage_status='PENDING'`.
- Si retry_count llega a 3 → marcar FALLIDO definitivo.

**Validación T1-T7 obligatoria:**
Si T1 = T2 = T3 = T4 = T5 = T6 = T7 para cualquier URL → run inválido.
No registrar como COMPLETED. Registrar evento `BATCH_INVALIDO`.

---

### CIERRE DE BATCH

**Evento resumen:**

```sql
INSERT INTO lf_eventos
  (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen)
VALUES (
  'BATCH_COMPLETADO',
  'PIPELINE_RUN', 'ACT-0058',
  'Batch completado: N procesadas, M fallidas',
  'INFO',
  '{"urls_procesadas": N, "urls_fallidas": M, "kb_creados": J}'::jsonb,
  'ACT-0058_AUTOMATION'
);
```

Usar `BATCH_PARCIAL` si no se procesaron todas por límite de contexto.

**Redescubrimiento de URLs (obligatorio tras BATCH_COMPLETADO):**

Buscar nuevas URLs en fuentes objetivo. Mínimo 5 URLs nuevas por ejecución.

```sql
-- Verificar deduplicación antes de insertar
SELECT COUNT(*) FROM lf_url_queue WHERE url = '<URL_CANDIDATA>';
SELECT COUNT(*) FROM lf_knowledge_base WHERE source_url = '<URL_CANDIDATA>';
-- Solo insertar si ambas retornan 0

INSERT INTO lf_url_queue (url, fuente, keyword_target, estado, url_tipo, created_by)
VALUES ('<url>', '<dominio>', '<keyword>', 'PENDIENTE', '<tipo>', 'ACT-0058_AUTOMATION');
```

```sql
INSERT INTO lf_eventos
  (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen)
VALUES (
  'QUEUE_RECARGADA', 'PIPELINE_RUN', 'ACT-0058',
  'Redescubrimiento: N URLs nuevas añadidas',
  'INFO',
  '{"urls_nuevas": N, "fuentes_exploradas": ["reevalua.com","finanty.com","perudeudas.info"]}'::jsonb,
  'ACT-0058_AUTOMATION'
);
```

Si no se encuentran 5 URLs → registrar con severidad `WARN`.

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
| `INIT is invalid for stage_current` | Enum incorrecto | Usar `CAPTURA` como stage inicial |
| `severidad WARNING invalid` | Enum incorrecto | Usar `WARN` |
