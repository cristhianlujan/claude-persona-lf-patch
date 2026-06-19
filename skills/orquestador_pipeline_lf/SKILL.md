# SKILL — ORQUESTADOR PIPELINE LF (ACT-0058)

**Código:** ACT-0058
**Nombre canónico:** SKILL_ORQUESTADOR_PIPELINE_LF
**Estado:** EN_REVISION / CANDIDATE_READ_ONLY
**Tabla de control:** lf_pipeline_runs
**Impacto automático:** BLOQUEADO
**Versión:** v0.2-candidato

## Rol

Orquestador end-to-end del pipeline de inteligencia competitiva LF.
Coordina la ejecución secuencial de las skills de captura, homologación,
análisis de riesgo y escritura en base de conocimiento.

## Ruta obligatoria

Router → v_lf_fuente_operativa → ACT-0058 (EN_REVISION) → lf_pipeline_runs → Operación → Verificación → Cierre

## Pipeline bajo control

```
ACT-0052 Extracción web      ─┐
ACT-0054 Extracción noticias ─┼→ ACT-0053 Homologación → ACT-0056 Análisis riesgo → ACT-0057 KB Write
ACT-0055 Extracción docs reg ─┘
```

## Fuentes objetivo (scheduler)

- reevalua.com
- finanty.com
- perudeudas.info
- youtube.com (canales finanzas PE)
- reddit.com/r/PERU

## Keywords objetivo

- "salir de Infocorp"
- "negociar deuda"
- "constancia de no adeudo"

## Tabla de control: lf_pipeline_runs

| Campo | Tipo | Descripción |
|---|---|---|
| pipeline_run_id | UUID PK | ID único del run |
| source_url | TEXT | URL fuente procesada |
| keyword_matched | TEXT | Keyword disparador |
| stage_current | TEXT | CAPTURA/HOMOLOGACION/ANALISIS/KB_WRITE/COMPLETED/FAILED/HITL |
| stage_status | TEXT | PENDING/RUNNING/COMPLETED/FAILED/HITL |
| capture_run_id | UUID FK | → lf_capture_runs.run_id |
| homolog_record_id | UUID FK | → lf_homologated_records.homolog_id |
| decision_id | UUID FK | → lf_content_decisions.decision_id |
| kb_id | UUID FK | → lf_knowledge_base.kb_id |
| hitl_triggered | BOOLEAN | HITL activado |
| retry_count | INT | Reintentos (max 3) |

## Contratos (12)

| Orden | Código | Stage |
|---|---|---|
| 10 | CONTRACT_ACT0058_S1A_ROUTER_V1 | Router |
| 20 | CONTRACT_ACT0058_S2A_INIT_RUN_V1 | Init + dedup 24h |
| 30 | CONTRACT_ACT0058_S3A_SCOPE_FILTER_V1 | Scope dominios |
| 40 | CONTRACT_ACT0058_S4A_KEYWORD_MATCH_V1 | Keywords |
| 50 | CONTRACT_ACT0058_S5A_STAGE_CAPTURA_V1 | Captura |
| 60 | CONTRACT_ACT0058_S6A_STAGE_HOMOLOG_V1 | Homologación |
| 70 | CONTRACT_ACT0058_S7A_STAGE_ANALISIS_V1 | Análisis riesgo |
| 80 | CONTRACT_ACT0058_S8A_HITL_TRIGGER_V1 | HITL gate |
| 90 | CONTRACT_ACT0058_S9A_STAGE_KB_WRITE_V1 | KB Write |
| 100 | CONTRACT_ACT0058_S10A_COMPLETED_V1 | Completed |
| 110 | CONTRACT_ACT0058_S11A_FAILED_RETRY_V1 | Retry (max 3) |
| 120 | CONTRACT_ACT0058_S12A_AUDIT_TRAIL_V1 | Audit trail |

## Reglas de gobernanza

- impacto_automatico = BLOQUEADO
- No merge a main sin CI verde
- DRY_RUN requerido antes de gate APROBADO
- HITL obligatorio si lf_content_decisions.hitl_required = TRUE
- Deduplicación por source_url en ventana 24h
- retry_count máximo: 3

---

## Modos de ejecución

El agente que ejecuta este skill DEBE detectar automáticamente el modo correcto antes de iniciar cualquier escritura. No asumir el modo — verificar siempre contra Supabase.

### PASO 0 — Diagnóstico obligatorio pre-ejecución

Antes de cualquier acción, correr estas 3 queries en orden:

**Query 1 — ¿Ya existe un pipeline_run para esta URL en las últimas 24h?**
```sql
SELECT pipeline_run_id, stage_current, stage_status, retry_count, kb_id
FROM lf_pipeline_runs
WHERE source_url = '<URL_OBJETIVO>'
  AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC
LIMIT 1;
```
→ Si existe con stage_status='COMPLETED': **NO procesar. Deduplicación activa.**
→ Si existe con stage_status='FAILED' y retry_count < 3: **Modo RETRY.**
→ Si no existe: continuar a Query 2.

**Query 2 — ¿Existe capture_record activo para esta URL?**
```sql
SELECT record_id, run_id, capture_confidence, risk_level, record_status,
       title_or_hook, raw_text, topic, funnel_stage, content_type
FROM lf_capture_records
WHERE url = '<URL_OBJETIVO>'
  AND record_status = 'ACTIVE'
LIMIT 1;
```
→ Si existe: **Modo REPLAY** (saltar captura web, usar record existente).
→ Si no existe: continuar a Query 3.

**Query 3 — ¿Hay acceso externo disponible?**
```
Intentar HEAD/GET a la URL objetivo con timeout 8s.
HTTP 200/301/302 → acceso disponible.
HTTP 403/timeout/connection error → acceso bloqueado.
```
→ Si acceso disponible: **Modo FULL.**
→ Si acceso bloqueado: UPDATE lf_url_queue SET estado='PENDIENTE' WHERE url='<URL>'. Detener. No forzar captura.

---

### Modo FULL — Captura + pipeline completo

**Condición:** Egress disponible + sin capture_record previo.

```
1. INSERT lf_pipeline_runs (stage_current='CAPTURA', stage_status='PENDING')
2. Captura web real → extraer raw_text, title, topic, risk_level
3. INSERT lf_capture_runs + lf_capture_records (record_status='ACTIVE')
4. UPDATE lf_pipeline_runs SET capture_run_id=<id>, stage_current='HOMOLOGACION', stage_status='PENDING'
5. Continuar → HOMOLOGACION → ANALISIS → KB_WRITE → COMPLETED
```

**Valores enum críticos — lf_capture_records:**
- `capture_confidence`: ALTA / MEDIA / BAJA (no numérico)
- `risk_level`: BAJO / MEDIO / ALTO / CRITICO
- `record_status`: ACTIVE / SKIPPED / DUPLICATE / BLOCKED / DISCARDED / TEST
- `url` (no source_url — la columna se llama `url`)

---

### Modo REPLAY — Reutilizar captura existente

**Condición:** capture_record ACTIVE ya existe para la URL (sin egress o captura previa).

```
1. INSERT lf_pipeline_runs (stage_current='CAPTURA', stage_status='PENDING')
2. UPDATE lf_pipeline_runs SET capture_run_id=<run_id_del_record_existente>,
          stage_current='HOMOLOGACION', stage_status='PENDING'
   → NO insertar nuevo lf_capture_record
3. Continuar → HOMOLOGACION → ANALISIS → KB_WRITE → COMPLETED
```

**Idempotencia en ANALISIS:** Si al llegar a ANALISIS ya existe `lf_content_decisions` con ese `capture_record_id`, leer el decision_id existente y reutilizarlo. No insertar uno nuevo (viola UNIQUE constraint `lf_content_decisions_capture_record_uk`).

**Idempotencia en KB_WRITE:** Si ya existe `lf_knowledge_base` con ese `decision_id`, leer el kb_id existente y vincularlo al pipeline_run. No insertar uno nuevo (viola UNIQUE constraint `lf_knowledge_base_decision_id_uk`).

---

### Modo AUDIT — Verificación sin escritura

**Condición:** KB ya existe para la URL (`lf_knowledge_base.source_url` match + `consumer_ready=TRUE`).

```
1. NO crear pipeline_run nuevo.
2. Verificar cadena FK: pipeline_run → capture_run → homolog → decision → kb
3. Reportar integridad: qué eslabones están completos, cuáles faltan.
4. Registrar en lf_eventos (evento_tipo='AUDIT_INTEGRIDAD', severidad='INFO').
```

---

### Modo RETRY — Reintentar run fallido

**Condición:** pipeline_run existe con stage_status='FAILED' y retry_count < 3.

```
1. Leer error_detail del pipeline_run fallido.
2. Si error_detail LIKE 'HITL_RESUELTO%': NO reintentar.
   UPDATE lf_pipeline_runs SET stage_current='HITL', stage_status='FAILED' WHERE pipeline_run_id=<id>.
3. Si error es técnico (timeout, parse error): reintentar desde stage_current donde falló.
4. UPDATE lf_pipeline_runs SET retry_count = retry_count + 1, stage_status='PENDING'.
5. Si retry_count llega a 3: UPDATE stage_status='FAILED'. Registrar en lf_eventos (severidad='WARN').
```

---

### Pasos comunes (FULL, REPLAY, RETRY)

**HOMOLOGACION — step 60**
```sql
INSERT INTO lf_homologated_records
  (capture_record_id, run_id, operation_code, execution_mode,
   topic_homologado, funnel_stage_homologado, source_type_homologado,
   content_category, homolog_status, consumer_gate_passed,
   consumer_gate_reason, homolog_package, created_by)
VALUES (...);

UPDATE lf_pipeline_runs
SET homolog_record_id=<homolog_id>, stage_current='ANALISIS', stage_status='PENDING'
WHERE pipeline_run_id=<id>;
```

**ANALISIS — step 70**
```sql
-- Verificar primero si ya existe decision para este capture_record
SELECT decision_id FROM lf_content_decisions WHERE capture_record_id='<id>';
-- Si no existe, insertar:
INSERT INTO lf_content_decisions
  (run_id, operation_code, execution_mode, source_url, topic,
   risk_family, risk_level, decision, decision_reason,
   grounding_status, hitl_required, consumer_gate_passed,
   created_by, capture_record_id)
VALUES (...);

UPDATE lf_pipeline_runs
SET decision_id=<decision_id>, stage_current='KB_WRITE', stage_status='PENDING'
WHERE pipeline_run_id=<id>;
```

**Valores enum críticos — lf_content_decisions:**
- `risk_level`: BAJO / MEDIO / ALTO / CRITICO
- `decision`: ALLOW_PROD_GATE / BLOCK / HITL_REQUIRED

**HITL CHECK — step 80**
- Si `hitl_required = TRUE`: UPDATE lf_pipeline_runs SET stage_current='HITL', stage_status='HITL', hitl_triggered=TRUE. **Detener. No continuar a KB_WRITE.**
- Si `hitl_required = FALSE` y decision='ALLOW_PROD_GATE': continuar directo a KB_WRITE.
- Si decision='BLOCK': UPDATE stage_current='FAILED', stage_status='FAILED', error_detail='DECISION_BLOCK'. Registrar evento.

**KB_WRITE — step 90**
```sql
-- Verificar primero si ya existe KB para este decision_id
SELECT kb_id FROM lf_knowledge_base WHERE decision_id='<id>';
-- Si no existe, insertar:
INSERT INTO lf_knowledge_base
  (decision_id, run_id, operation_code, execution_mode,
   kb_category, kb_subcategory, topic, risk_family, funnel_stage,
   source_url, visible_text, summary, key_insights, tags,
   grounding_status, decision_upstream, quality_score,
   consumer_ready, reviewed_by, reviewed_at,
   kb_dimension, kb_polarity, content_type, kb_enriched, created_by)
VALUES (...);

UPDATE lf_pipeline_runs
SET kb_id=<kb_id>, stage_current='COMPLETED', stage_status='COMPLETED'
WHERE pipeline_run_id=<id>;
```

**Valores enum críticos — lf_knowledge_base:**
- `kb_dimension`: EDUCATIVO / ALERTA / REGULATORIO / SEÑAL_MERCADO / PSICOLOGIA_USUARIO / COMPORTAMIENTO_DIGITAL
- `kb_polarity`: POSITIVO / NEGATIVO / NEUTRO

**AUDIT TRAIL — step 120 (siempre, todos los modos)**
```sql
INSERT INTO lf_eventos
  (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen)
VALUES (
  'PIPELINE_COMPLETADO',  -- o PIPELINE_FALLIDO / PIPELINE_HITL / PIPELINE_DEDUP / AUDIT_INTEGRIDAD
  'PIPELINE_RUN',
  '<pipeline_run_id>',
  '<descripcion breve>',
  'INFO',                 -- INFO / WARN / CRITICAL (no WARNING)
  '{"modo":"FULL|REPLAY|RETRY|AUDIT","url":"...","stage_final":"...","kb_id":"..."}'::jsonb,
  '<nombre_agente>'
);
```

**Columnas correctas de lf_eventos** (verificadas contra schema real):
- `evento_tipo` (no `tipo_evento`)
- `entidad_tipo`, `entidad_codigo`, `descripcion`, `severidad`, `payload`, `origen`
- `severidad` acepta: INFO / WARN / CRITICAL (no WARNING)

**lf_url_queue — valores enum estado** (verificados):
- PENDIENTE / PROCESADO / FALLIDO / DESCARTADO / SKIP
- (no PROCESADA — es PROCESADO)

---

## Errores frecuentes — no repetir

| Error | Causa | Solución |
|---|---|---|
| `column tipo_evento does not exist` | Nombre incorrecto | Usar `evento_tipo` |
| `violates check constraint lf_url_queue_estado_check` | Enum incorrecto | Usar `PROCESADO` (no `PROCESADA`) |
| `duplicate key lf_content_decisions_capture_record_uk` | Decision ya existe | SELECT primero, reutilizar decision_id |
| `duplicate key lf_knowledge_base_decision_id_uk` | KB ya existe | SELECT primero, reutilizar kb_id |
| `column source_url does not exist in lf_capture_records` | Nombre incorrecto | Usar `url` (no `source_url`) |
| `INIT is invalid for stage_current` | Enum incorrecto | Usar `CAPTURA` como stage inicial |
| `column url_id does not exist in lf_url_queue` | Nombre incorrecto | PK se llama `queue_id` |
| `severidad WARNING invalid` | Enum incorrecto | Usar `WARN` (no `WARNING`) |

---

## Insumo base

Reporte de Inteligencia Competitiva LF (Google Doc ID: 1aeyx7-PqLc1VZI7Fe8Rd5aONnlacjVZQuvHoalSt7R8)
Leído y asimilado en sesión 2026-06-17.

## Evento Supabase

id=319 — CONSTRUCCION_ACTIVO / ACT-0058 / Fases 1-4 completadas
v0.2 — Modos de ejecución añadidos — sesión 2026-06-18
---

## Modo batch — loop sobre lf_url_queue

El agente DEBE procesar todas las URLs PENDIENTE en lf_url_queue en una sola sesión, no solo una.
El loop es obligatorio. Procesar una URL y detenerse es incorrecto.

### PASO B0 — Obtener lista completa de URLs pendientes

Al inicio de cada sesión, antes de procesar cualquier URL, ejecutar:

```sql
SELECT queue_id, url, url_tipo, fuente, intento_count
FROM lf_url_queue
WHERE estado = 'PENDIENTE'
ORDER BY url_tipo, created_at
LIMIT 50;
```

→ Si la lista está vacía: registrar evento BATCH_COMPLETADO y terminar.
→ Si hay URLs: iterar sobre cada una ejecutando el pipeline completo (PASO 0 → AUDIT TRAIL).

### PASO B1 — Loop de ejecución



No detenerse entre URLs salvo:
- Error irrecuperable de conexión a Supabase
- retry_count >= 3 en la URL actual (marcar FALLIDO y continuar con la siguiente)
- Límite de contexto del agente alcanzado (registrar evento BATCH_PARCIAL con URLs restantes)

### PASO B2 — Manejo de errores por URL

Si una URL falla, NO abortar el batch completo:

```sql
UPDATE lf_url_queue
SET estado = 'FALLIDO',
    intento_count = intento_count + 1,
    error_detail = '<descripcion del error>'
WHERE queue_id = '<queue_id>';
```

Luego continuar con la siguiente URL de la lista.

### PASO B3 — Evento resumen al finalizar el batch

Al terminar todas las URLs (o al alcanzar límite de contexto):

```sql
INSERT INTO lf_eventos
  (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen)
VALUES (
  'BATCH_COMPLETADO',   -- o BATCH_PARCIAL si no se procesaron todas
  'PIPELINE_RUN',
  'ACT-0058',
  'Batch completado: N URLs procesadas, M fallidas, K pendientes',
  'INFO',
  '{urls_procesadas: N, urls_fallidas: M, urls_pendientes_restantes: K, kb_creados: J}'::jsonb,
  '<nombre_agente>'
);
```

### Criterio de parada

| Condición | Acción |
|---|---|
| lf_url_queue sin PENDIENTE | Registrar BATCH_COMPLETADO. Terminar. |
| Error Supabase irrecuperable | Registrar BATCH_PARCIAL. Terminar. |
| Límite de contexto del agente | Registrar BATCH_PARCIAL con URLs restantes en payload. Terminar. |
| retry_count >= 3 en una URL | Marcar esa URL como FALLIDO. Continuar con la siguiente. |


---

## Regla de trazabilidad por step — OBLIGATORIA

Cada step del pipeline debe ejecutarse como una operación Supabase SEPARADA y secuencial.
Está PROHIBIDO preparar múltiples INSERTs y ejecutarlos en batch o en una sola transacción.

### Por qué es obligatorio

Si todos los registros tienen el mismo `created_at` hasta el microsegundo, significa que el agente ejecutó en batch y NO siguió el pipeline real. El judge puede detectar esto automáticamente.

### Protocolo por step

Antes de cada step, ejecutar:
```sql
SELECT now() AS timestamp_step;
```
Guardar ese valor. El timestamp del INSERT siguiente debe ser >= a ese valor.

Al finalizar el batch, el payload del evento BATCH_COMPLETADO DEBE incluir:
```json
{
  "timestamps_por_url": {
    "https://ejemplo.com": {
      "T1_pipeline_run_created": "2026-06-19T22:01:05.123Z",
      "T2_capture_run_created": "2026-06-19T22:01:07.456Z",
      "T3_capture_record_created": "2026-06-19T22:01:09.789Z",
      "T4_homolog_created": "2026-06-19T22:01:12.012Z",
      "T5_decision_created": "2026-06-19T22:01:14.345Z",
      "T6_kb_created": "2026-06-19T22:01:16.678Z",
      "T7_completed_at": "2026-06-19T22:01:18.901Z"
    }
  }
}
```

Si T1 = T2 = T3 ... = T7 para cualquier URL → BATCH_INVALIDO. No registrar como completado.

### Orden de operaciones por URL (NO modificar)

```
1.  SELECT now()                          → T1
2.  INSERT lf_pipeline_runs               → confirmar con SELECT pipeline_run_id
3.  SELECT now()                          → T2
4.  [captura web real de la URL]
5.  INSERT lf_capture_runs                → confirmar con SELECT run_id
6.  SELECT now()                          → T3
7.  INSERT lf_capture_records             → confirmar con SELECT record_id
8.  UPDATE lf_pipeline_runs stage=HOMOLOGACION
9.  SELECT now()                          → T4
10. INSERT lf_homologated_records         → confirmar con SELECT homolog_id
11. UPDATE lf_pipeline_runs stage=ANALISIS
12. SELECT now()                          → T5
13. INSERT lf_content_decisions           → confirmar con SELECT decision_id
14. UPDATE lf_pipeline_runs stage=KB_WRITE
15. SELECT now()                          → T6
16. INSERT lf_knowledge_base              → confirmar con SELECT kb_id
17. UPDATE lf_pipeline_runs stage=COMPLETED
18. SELECT now()                          → T7
19. UPDATE lf_url_queue estado=PROCESADO
20. INSERT lf_eventos (evento individual por URL)
```

Cada confirmación con SELECT es obligatoria antes de continuar al paso siguiente.

---

## PASO B4 — Redescubrimiento de URLs (después de BATCH_COMPLETADO)

Este paso es OBLIGATORIO al finalizar cada batch. Sin él, la queue queda vacía y el pipeline no tiene nada que procesar en la siguiente ejecución.

### Objetivo

Buscar nuevas URLs candidatas en las fuentes objetivo y cargarlas en lf_url_queue para la próxima ejecución.

### Fuentes a explorar

| Fuente | Método | Keywords |
|---|---|---|
| reevalua.com/blog | Listar artículos del blog | salir infocorp, score crediticio, deuda |
| finanty.com/blog | Listar artículos del blog | infocorp, constancia, negociar |
| perudeudas.info | Listar categorías y posts | infocorp, deuda castigada |
| sbs.gob.pe | Buscar páginas de usuario | reporte deudas, centrales riesgo |
| gestión.pe / elcomercio.pe | Buscar noticias recientes | infocorp, ley 32327, deuda peru |

### Deduplicación obligatoria

Antes de insertar, verificar que la URL no exista ya:
```sql
SELECT COUNT(*) FROM lf_url_queue WHERE url = '<URL_CANDIDATA>';
SELECT COUNT(*) FROM lf_knowledge_base WHERE source_url = '<URL_CANDIDATA>';
```
Solo insertar si ambos retornan 0.

### INSERT de nuevas candidatas

```sql
INSERT INTO lf_url_queue (url, fuente, keyword_target, estado, url_tipo, created_by)
VALUES ('<url>', '<dominio>', '<keyword>', 'PENDIENTE', '<EDUCATIVO|REGULATORIO|COMPETENCIA|INDICE>', 'ACT-0058_AUTOMATION');
```

### Evento de cierre con recarga

```sql
INSERT INTO lf_eventos
  (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen)
VALUES (
  'QUEUE_RECARGADA',
  'PIPELINE_RUN',
  'ACT-0058',
  'Redescubrimiento completado: N URLs nuevas añadidas a lf_url_queue',
  'INFO',
  '{"urls_nuevas_encontradas": N, "urls_ya_existentes_descartadas": M, "fuentes_exploradas": ["reevalua.com","finanty.com","perudeudas.info"]}'::jsonb,
  'ACT-0058_AUTOMATION'
);
```

### Criterio mínimo

El agente debe añadir al menos 5 URLs nuevas por ejecución. Si no encuentra 5, registrar evento con severidad WARN y continuar.

---

## Versión

v0.4 — Trazabilidad por step + PASO B4 redescubrimiento — sesión 2026-06-18
