# GATE MATRIX — ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2

> Estado: CANDIDATO / READ_ONLY · v0.2 · Lote 20B

Cada gate incluye: acción ejecutada · mini-judge · criterio PASS · criterio BLOCK · evidencia requerida · log_key en fallo.

---

## GATE_00 · OPERATION_CODE_VALID

| Campo | Valor |
|---|---|
| **Acción** | `SELECT 1 FROM lf_operation_registry WHERE operation_code = input.operation_code AND status != 'DEPRECATED'` |
| **Mini-judge** | ¿Devuelve al menos 1 fila? |
| **PASS** | operation_code existe y no está deprecado |
| **BLOCK** | operation_code ausente en registry → `BLOCKED_OPERATION_CODE_INVALID` |
| **Evidencia PASS** | `lf_operation_registry.operation_code` = valor verificado |
| **Evidencia BLOCK** | log en raw_payload del run (nada se crea en BD) |
| **Log key en fallo** | `WEB_EXTRACTION_BLOCK` |
| **Final state en fallo** | `BLOCKED_OPERATION_CODE_INVALID` |
| **Crea algo en BD si falla** | ❌ Nada |

---

## GATE_01 · ROLE_PERMISSION

| Campo | Valor |
|---|---|
| **Acción** | Verificar que `actor_role` tiene permiso para el `mode` declarado en el input |
| **Mini-judge** | ¿El par (actor_role, mode) aparece como ✅ en la matriz de permisos? |
| **PASS** | Par válido según matriz `roles_permissions_matrix.md` |
| **BLOCK** | Par inválido (ej. viewer + FULL_EXTRACTION_REGISTER_SANDBOX_ONLY) → `BLOCKED_PERMISSION_DENIED` |
| **Evidencia PASS** | actor_role y mode registrados en raw_payload del run |
| **Evidencia BLOCK** | Evento en `lf_log_operativo` con `WEB_EXTRACTION_BLOCK` |
| **Log key en fallo** | `WEB_EXTRACTION_BLOCK` |
| **Final state en fallo** | `BLOCKED_PERMISSION_DENIED` |
| **Crea algo en BD si falla** | Solo `lf_log_operativo` |

---

## GATE_02 · MODE_CONTRACT

| Campo | Valor |
|---|---|
| **Acción** | Verificar que el input cumple el contrato del mode declarado |
| **Mini-judge** | ¿Todos los campos requeridos por el mode están presentes y válidos? |
| **PASS** | ADMIN_OVERRIDE tiene `admin_override_reason` · ADDENDUM_ONLY tiene URL o `target_record_id` |
| **BLOCK** | Campo requerido ausente o inválido → `BLOCKED_INVALID_INPUT_CONTRACT` |
| **Evidencia PASS** | Campos validados registrados en raw_payload |
| **Evidencia BLOCK** | raw_payload del error con campo faltante identificado |
| **Log key en fallo** | `WEB_EXTRACTION_BLOCK` |
| **Final state en fallo** | `BLOCKED_INVALID_INPUT_CONTRACT` |
| **Crea algo en BD si falla** | ❌ Nada |

---

## GATE_03 · URL_VALIDATION

| Campo | Valor |
|---|---|
| **Acción** | Para cada URL: verificar esquema, ausencia de credenciales, no protocolo local |
| **Mini-judge** | ¿URL comienza con `https://` o `http://`? ¿Sin `user:pass@`? ¿Sin `file://`, `localhost`, `127.`? |
| **PASS** | Todas las URLs del lote válidas |
| **BLOCK** | Al menos una URL inválida → `BLOCKED_URL_INVALID` para esa URL |
| **Evidencia PASS** | Lista de URLs validadas en raw_payload del run |
| **Evidencia BLOCK** | `lf_capture_runs.status = FAILED` con URL inválida en error_message |
| **Log key en fallo** | `WEB_EXTRACTION_BLOCK` |
| **Final state en fallo** | `BLOCKED_URL_INVALID` |
| **Crea algo en BD si falla** | `lf_capture_runs` (run con status=FAILED) |

---

## GATE_04 · SOURCE_CATALOG_CHECK

| Campo | Valor |
|---|---|
| **Acción** | `SELECT source_id, competitor_id FROM sbx_competitive_sources WHERE url_hash = md5(url) AND active = true` |
| **Mini-judge** | ¿Existe la fuente catalogada? → enriquecer registro. ¿No existe? → continuar sin bloquear. |
| **PASS** | Siempre pasa — nunca bloquea |
| **BLOCK** | N/A — este gate nunca bloquea |
| **Evidencia PASS** | `competitor_id` incluido en raw_payload si encontrado; `source_catalogada: false` si no |
| **Nota** | Gate de enriquecimiento, no de control |
| **Log key en fallo** | N/A |
| **Crea algo en BD si falla** | N/A |

---

## GATE_05 · FETCH_ATTEMPT

| Campo | Valor |
|---|---|
| **Acción** | Solicitar contenido HTTP de la URL. Registrar: `http_status`, `url_final`, tiempo de respuesta |
| **Mini-judge** | ¿http_status es 2xx? ¿Contenido disponible? |
| **PASS** | http_status 2xx y contenido no vacío |
| **BLOCK_404** | http_status 404 → `BLOCKED_404_RECORDED` |
| **BLOCK_TIMEOUT** | Sin respuesta o error de red → `BLOCKED_FETCH_FAILED` |
| **Evidencia PASS** | http_status, url_final, tiempo_respuesta en raw_payload |
| **Evidencia BLOCK** | `lf_capture_runs.status = FAILED`, http_status en error_message |
| **Log key en fallo** | `WEB_EXTRACTION_BLOCK` (404) · `WEB_EXTRACTION_ERROR` (timeout) |
| **Final state en fallo** | `BLOCKED_404_RECORDED` o `BLOCKED_FETCH_FAILED` |
| **Crea algo en BD si falla** | `lf_capture_runs` (run con status=FAILED) |

---

## GATE_06 · ACCESS_RESULT_CAPTURE

| Campo | Valor |
|---|---|
| **Acción** | Registrar: `url_solicitada` = URL original del input · `url` = `url_final` (post-redirect) · `redireccion_detectada` = (`url_solicitada` != `url_final`) |
| **Mini-judge** | ¿Los tres campos se registraron correctamente? |
| **PASS** | Siempre pasa si GATE_05 pasó |
| **BLOCK** | N/A — fallo aquí se trata como `BLOCKED_PARTIAL_EXECUTION` |
| **Evidencia PASS** | `url_solicitada`, `url`, `redireccion_detectada` en raw_payload del run |
| **Log key en fallo** | `WEB_EXTRACTION_ERROR` |
| **Crea algo en BD si falla** | `lf_capture_runs` (run parcial) |

---

## GATE_07 · DUPLICATE_CHECK

| Campo | Valor |
|---|---|
| **Acción** | `url_hash = md5(url_final)` · `SELECT record_id, content_hash FROM lf_capture_records WHERE url_hash = url_hash` |
| **Mini-judge** | ¿Existe registro previo? ¿Con mismo o diferente content_hash? |
| **PASS_NEW** | No existe → proceder como `REGISTERED_NEW` |
| **PASS_VERSION** | Existe con diferente content_hash y `allow_new_version=true` → `REGISTERED_VERSION` |
| **PASS_ADDENDUM** | Existe y mode=ADDENDUM_ONLY → `ADDENDUM_REGISTERED` |
| **BLOCK** | Existe con mismo content_hash → `BLOCKED_DUPLICATE_POLICY` |
| **Fixtures reales a verificar** | `e5ef8029e79db297c9660fa9e44a6e1a` (Reevalúa) · `84a5bc12d53b9f0dee9d156fa0d8e958` (RTC) |
| **Evidencia PASS** | url_hash calculado y resultado de SELECT en raw_payload |
| **Evidencia BLOCK** | `lf_capture_runs` con run registrado, sin nueva fila en `lf_capture_records` |
| **Log key en fallo** | `WEB_EXTRACTION_BLOCK` |
| **Final state en fallo** | `BLOCKED_DUPLICATE_POLICY` |
| **Crea algo en BD si falla** | `lf_capture_runs` (run registrado como duplicado detectado) |

---

## GATE_08 · EXTRACTION

| Campo | Valor |
|---|---|
| **Acción** | Extraer campos del contenido HTML/texto. Ver lista completa en `schemas/` |
| **Mini-judge** | ¿Cada campo tiene valor literal visible en el contenido, o NOT_FOUND? ¿Ninguno inventado? |
| **PASS** | Todos los campos son literales verificables o NOT_FOUND explícito |
| **BLOCK** | Si algún campo contiene valor inferido sin evidencia textual → fallo de judge J01 |
| **Regla madre** | Campo no visible en texto → NOT_FOUND. Nunca inferir, completar ni inventar. |
| **Detección truncado** | Si `raw_text` termina abruptamente: `truncado_en` = posición, `campos_truncados_json` = lista |
| **Detección injection** | Si contenido contiene instrucción tipo "Ignora…": `prompt_injection_detectado=true`, fragmento en `prompt_injection_fragmento`, instrucción ignorada |
| **Evidencia PASS** | Todos los campos en `lf_capture_records` con valor literal o `NOT_FOUND` explícito |
| **Log key en fallo** | `WEB_EXTRACTION_ERROR` |
| **Final state en fallo** | `BLOCKED_PARTIAL_EXECUTION` |

---

## GATE_09 · MINIMUM_EVIDENCE

| Campo | Valor |
|---|---|
| **Acción** | Verificar evidencia mínima: `title_or_hook` presente · `raw_text` ≥ 100 caracteres · `url` (url_final) presente · `url_hash` calculado |
| **Mini-judge** | ¿Los cuatro campos cumplen el umbral mínimo? |
| **PASS** | Todos los 4 campos pasan el umbral |
| **BLOCK** | Cualquier campo bajo umbral → `BLOCKED_MIN_EVIDENCE_NOT_MET` |
| **Evidencia PASS** | Longitudes y presencia registradas en raw_payload |
| **Evidencia BLOCK** | `lf_capture_runs.status=FAILED`, campo faltante en `error_message` |
| **Log key en fallo** | `WEB_EXTRACTION_BLOCK` |
| **Final state en fallo** | `BLOCKED_MIN_EVIDENCE_NOT_MET` |
| **Crea algo en BD si falla** | `lf_capture_runs` con status=FAILED |

---

## GATE_10 · LOG_KEY_VALIDATION

| Campo | Valor |
|---|---|
| **Acción** | `SELECT enabled FROM lf_log_config WHERE log_key = 'WEB_EXTRACTION_COMPLETE' AND enabled = true` |
| **Mini-judge** | ¿Log key habilitado? |
| **PASS** | Devuelve `enabled=true` |
| **ADVERTENCIA** | No habilitado → registrar advertencia en `raw_payload` del run, continuar |
| **Nunca bloquea** | Este gate emite advertencia, no bloqueo |
| **Evidencia PASS** | `log_key_validated: true` en raw_payload |
| **Evidencia ADVERTENCIA** | `log_key_validated: false, log_key_warning: "WEB_EXTRACTION_COMPLETE disabled"` en raw_payload |

---

## GATE_11 · PERSISTENCE_DECISION

| Campo | Valor |
|---|---|
| **Acción** | Determinar acción de persistencia según `mode` y resultado de GATE_07 |
| **Tabla de decisión** | |

| mode | GATE_07 resultado | Decisión |
|---|---|---|
| FULL_EXTRACTION_REGISTER_SANDBOX_ONLY | nuevo | REGISTERED_NEW → GATE_12 escribe |
| FULL_EXTRACTION_REGISTER_SANDBOX_ONLY | versión nueva | REGISTERED_VERSION → GATE_12 escribe |
| DRY_RUN | cualquiera | DRY_RUN_PREVIEW_READY → NO escribe |
| READ_ONLY_RESULT | cualquiera | READ_ONLY_RESULT → NO escribe |
| ADDENDUM_ONLY | existente | ADDENDUM_REGISTERED → GATE_12 escribe |
| ADMIN_OVERRIDE | cualquiera | ADMIN_OVERRIDE_RECORDED (FUTURE_BLOCKED) → GATE_12 escribe en lf_log_operativo |

| **Evidencia PASS** | Decisión registrada en raw_payload del run |

---

## GATE_12 · DB_WRITE_OR_TRACEABLE_BLOCK

| Campo | Valor |
|---|---|
| **Acción** | Si GATE_11 decidió escribir: (1) INSERT `lf_capture_runs` · (2) INSERT `lf_capture_records` con todos los campos incluyendo columnas web · (3) Verificar que INSERT retornó `record_id` |
| **Mini-judge** | ¿Ambos INSERTs retornaron IDs? |
| **PASS** | `run_id` y `record_id` recibidos |
| **BLOCK** | Error de BD en cualquier INSERT → `BLOCKED_DB_WRITE_FAILED` |
| **Evidencia PASS** | `run_id` y `record_id` en output_contract_v2 |
| **Evidencia BLOCK** | `flow_terminated=true`, `extraction_successful=false`, error en `lf_log_operativo` |
| **Log key en fallo** | `WEB_EXTRACTION_ERROR` |
| **Final state en fallo** | `BLOCKED_DB_WRITE_FAILED` |
| **Crea algo en BD si falla** | ❌ Intento fallido, nada confirmado |

---

## GATE_13 · READBACK

| Campo | Valor |
|---|---|
| **Acción** | `SELECT record_id FROM lf_capture_records WHERE record_id = <id_insertado>` |
| **Mini-judge** | ¿El SELECT devuelve el mismo `record_id`? |
| **PASS** | `record_id` confirmado → `db_write_confirmed = true` |
| **BLOCK** | Sin resultado → `BLOCKED_DB_READBACK_FAILED` |
| **Evidencia PASS** | `db_write_confirmed: true` en output_contract_v2 |
| **Evidencia BLOCK** | `db_write_confirmed: false`, `extraction_successful: false` |
| **Log key en fallo** | `WEB_EXTRACTION_ERROR` |
| **Final state en fallo** | `BLOCKED_DB_READBACK_FAILED` |

---

## GATE_14 · LOG_WRITE

| Campo | Valor |
|---|---|
| **Acción** | INSERT en `lf_log_operativo`: log_key correcto según resultado · entidad_codigo = record_id o run_id · payload con resumen |
| **Mini-judge** | ¿INSERT retornó `log_event_id`? |
| **PASS** | `log_event_id` devuelto |
| **ADVERTENCIA** | Error de logging → no bloquea la extracción; registrar en raw_payload del run |
| **Evidencia PASS** | `log_event_id` en `trazabilidad_run.lf_log_event_ids` |
| **Log key usado** | `WEB_EXTRACTION_COMPLETE` (éxito) · `WEB_EXTRACTION_BLOCK` (bloqueo) · `WEB_EXTRACTION_ERROR` (error) |

---

## GATE_15 · FINAL_STATE

| Campo | Valor |
|---|---|
| **Acción** | Asignar: `flow_terminated=true` · `extraction_successful` según evidencia de GATE_13 · `fecha_proxima_revision` según regla de contenido |
| **Regla fecha_proxima_revision** | |

| Condición | Días | Ejemplo |
|---|---|---|
| `ctas_json` contiene precios o tasas | 30d | "TEA 45%" |
| `claims_json` menciona SBS, BCRP, SMV | 90d | "según SBS" |
| Contenido educativo sin claims regulatorios | 180d | guía genérica |

| **Mini-judge** | ¿`flow_terminated=true`? ¿`extraction_successful` correcto? ¿`fecha_proxima_revision` calculada? |
| **PASS** | Los tres campos asignados correctamente |
| **BLOCK** | N/A — fallo aquí se registra como `BLOCKED_PARTIAL_EXECUTION` |
| **Evidencia PASS** | Los tres campos en `lf_capture_records` y `output_contract_v2` |

---

## RESUMEN VISUAL — Flujo de gates

```
INPUT
  │
  ▼
GATE_00 ─── FAIL ──► BLOCKED_OPERATION_CODE_INVALID (nada en BD)
  │ PASS
  ▼
GATE_01 ─── FAIL ──► BLOCKED_PERMISSION_DENIED (solo log)
  │ PASS
  ▼
GATE_02 ─── FAIL ──► BLOCKED_INVALID_INPUT_CONTRACT (nada en BD)
  │ PASS
  ▼
GATE_03 ─── FAIL ──► BLOCKED_URL_INVALID (run=FAILED)
  │ PASS
  ▼
GATE_04 ─── (nunca falla, solo enriquece)
  │
  ▼
GATE_05 ─── FAIL ──► BLOCKED_404_RECORDED / BLOCKED_FETCH_FAILED (run=FAILED)
  │ PASS
  ▼
GATE_06 ─── (registra redirección, siempre pasa)
  │
  ▼
GATE_07 ─── DUPLICATE ──► BLOCKED_DUPLICATE_POLICY (run registrado)
  │ PASS/VERSION/ADDENDUM
  ▼
GATE_08 ─── FAIL ──► BLOCKED_PARTIAL_EXECUTION
  │ PASS
  ▼
GATE_09 ─── FAIL ──► BLOCKED_MIN_EVIDENCE_NOT_MET (run=FAILED)
  │ PASS
  ▼
GATE_10 ─── (advierte si log_key disabled, nunca bloquea)
  │
  ▼
GATE_11 ─── (decisión de persistencia según mode)
  │
  ▼
GATE_12 ─── FAIL ──► BLOCKED_DB_WRITE_FAILED
  │ PASS
  ▼
GATE_13 ─── FAIL ──► BLOCKED_DB_READBACK_FAILED
  │ PASS
  ▼
GATE_14 ─── (log_write, nunca bloquea extracción)
  │
  ▼
GATE_15 ──► REGISTERED_NEW / REGISTERED_VERSION / ADDENDUM_REGISTERED
            flow_terminated=true · extraction_successful=true
```

---

> Estado: CANDIDATO / READ_ONLY · No validado · No producción
