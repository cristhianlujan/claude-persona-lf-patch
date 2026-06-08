# RUNBOOK — ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2

> Estado: CANDIDATO / READ_ONLY · Solo sandbox · No producción
> Leer antes de ejecutar: README.md → permissions/roles_matrix.md → este archivo

---

## Pre-condiciones obligatorias

Antes de ejecutar, verificar que todo esto es verdad:

```
[ ] Estás en ambiente sandbox — NO en producción
[ ] Tu actor_role permite el mode que vas a usar
    → Ver permissions/roles_matrix.md
[ ] operation_code = CAPTURE_INTAKE_MULTI_SOURCE_FIXTURE_V0_1
    → Existe en lf_operation_registry (verificado Lote 20B)
[ ] Las URLs que vas a procesar son https:// o http://
[ ] Tienes acceso de lectura a: lf_log_config, lf_operation_registry, sbx_competitive_sources
[ ] Tienes acceso de escritura a: lf_capture_runs, lf_capture_records, lf_log_operativo
[ ] Los 6 log_keys WEB_EXTRACTION_* están activos en lf_log_config
    → Verificar: SELECT log_key, enabled FROM lf_log_config WHERE log_key LIKE 'WEB_EXTRACTION_%'
```

Si alguna pre-condición falla → detener. No ejecutar.

---

## Construir el input

Referencia completa: `contracts/input_contract.yaml`

**Input mínimo válido:**
```yaml
mode: FULL_EXTRACTION_REGISTER_SANDBOX_ONLY      # o DRY_RUN para probar sin escribir
actor_id: "tu_id_aqui"              # string no vacío
actor_role: extractor_operator      # según tu rol real
urls:
  - "https://url-a-procesar.com/articulo"
operation_code: CAPTURE_INTAKE_MULTI_SOURCE_FIXTURE_V0_1
```

**Regla de oro:** En duda, usar `mode: DRY_RUN` primero.
DRY_RUN no escribe nada en BD. Sirve para verificar que el input es válido.

---

## Ejecución — seguir los gates en orden

No saltar gates. No asumir que un gate pasó sin verificarlo.

### GATE_00 — Verificar operation_code
```sql
SELECT operation_code, status FROM lf_operation_registry
WHERE operation_code = 'CAPTURE_INTAKE_MULTI_SOURCE_FIXTURE_V0_1';
-- Debe devolver 1 fila. Si no → detener. No continuar.
```
**Si falla:** `final_state = BLOCKED_OPERATION_CODE_INVALID`. No crear nada en BD.

### GATE_01 — Verificar permisos
Usar `permissions/roles_matrix.md`.

Ejemplo:
- `extractor_operator + FULL_EXTRACTION_REGISTER_SANDBOX_ONLY` → PASS
- `viewer + FULL_EXTRACTION_REGISTER_SANDBOX_ONLY` → BLOCK

**Si falla:** `BLOCKED_PERMISSION_DENIED`.

### GATE_02 — Validar contrato de input
Validar contra `commands/capture_web_article/input_contract.yaml`.

Check mínimo:
```yaml
mode: presente y válido
actor_id: string no vacío
actor_role: rol válido
urls: array con 1–10 URLs
```

**Si mode=ADMIN_OVERRIDE:** requiere `admin_override_reason`. Si falta → BLOCK.

### GATE_03 — Validar URL
Cada URL debe:
- empezar con `http://` o `https://`;
- no usar `file://`, `localhost`, `127.0.0.1`;
- no contener credenciales `user:pass@`.

### GATE_04 — Buscar fuente catalogada
Consultar `sbx_competitive_sources` si la URL pertenece a fuente conocida.
Si no está, puede continuar como fuente no catalogada si el modo lo permite, pero debe registrarse en notas técnicas.

### GATE_05 — Intento fetch
Registrar:
- URL solicitada;
- URL final;
- HTTP status;
- redirección detectada;
- error si aplica.

### GATE_06 — Normalizar URL final
Calcular:
```text
url_hash = md5(url_final)
content_hash = md5(raw_text) si existe
```

### GATE_07 — Anti-duplicado
Consultar `lf_capture_records` por `url_hash`.

Casos:
- no existe → `PASS_NEW`;
- existe y mismo content_hash → `BLOCKED_DUPLICATE_POLICY`;
- existe y distinto content_hash → `REGISTERED_VERSION` si `allow_new_version=true`;
- modo `ADDENDUM_ONLY` → agregar addendum si hay target válido.

### GATE_08 — Extracción campo a campo
Extraer solo evidencia literal:
- title_or_hook;
- autor_declarado;
- fecha_publicacion_declarada;
- meta_description;
- lead_literal;
- claims_json;
- ctas_json;
- senales_confianza_json;
- antipatrones_json;
- producto_mencionado_json;
- prompt_injection_detectado.

Reglas críticas:
- Si no visible → `NOT_FOUND`.
- Nunca inferir autor, fecha, fuente o claim.
- `claims_json[].verificado_fuente_primaria` siempre `false`.

### GATE_09 — Evidencia mínima
Bloquear si:
- `raw_text` < 100 caracteres;
- `title_or_hook` vacío;
- no hay URL final;
- falta evidencia mínima.

### GATE_10 — Validar log_key
Todo log debe usar un `WEB_EXTRACTION_*` registrado en `lf_log_config`.

### GATE_11 — Decisión de persistencia
Decidir si se escribe:
- READ_ONLY_RESULT → no escribe;
- DRY_RUN → no escribe;
- FULL_EXTRACTION_REGISTER_SANDBOX_ONLY → escribe;
- ADDENDUM_ONLY → escribe addendum;
- ADMIN_OVERRIDE → solo si permitido por contrato y razón documentada.

### GATE_12 — Escritura en BD
Escribir en:
- `lf_capture_runs`;
- `lf_capture_records`;
- `lf_log_operativo`.

### GATE_13 — Readback obligatorio
Después de escribir, hacer SELECT para confirmar:
- record_id existe;
- db_write_confirmed=true;
- created_by correcto;
- run_id asociado.

No declarar éxito sin este gate.

### GATE_14 — Log final
Registrar evento final en `lf_log_operativo`.

### GATE_15 — Estado final
Asignar `final_state` según resultado.

---

## Estados finales esperados

Ver `domain/states.md` y `commands/capture_web_article/output_contract.yaml`.

Regla:
```text
flow_terminated = true siempre
```

---

## Checklist de cierre

```
[ ] Todos los gates fueron ejecutados en orden
[ ] Si hubo escritura, GATE_13 confirmó readback
[ ] final_state pertenece a output_contract.yaml
[ ] flow_terminated=true
[ ] No se generó homologación
[ ] No se generó insight
[ ] No se generó alert
[ ] No se invocó n8n
```

---

## Qué hacer si algo falla

| Falla | Acción |
|---|---|
| operation_code inválido | Detener, `BLOCKED_OPERATION_CODE_INVALID` |
| permiso inválido | Detener, `BLOCKED_PERMISSION_DENIED` |
| URL inválida | Detener esa URL, `BLOCKED_URL_INVALID` |
| fetch falla | Registrar, `BLOCKED_FETCH_FAILED` |
| duplicado exacto | No insertar, `BLOCKED_DUPLICATE_POLICY` |
| raw_text insuficiente | Bloquear, `BLOCKED_MIN_EVIDENCE_NOT_MET` |
| escritura falla | `BLOCKED_DB_WRITE_FAILED` |
| readback falla | `BLOCKED_DB_READBACK_FAILED` |

---

## Cierre

Este runbook no autoriza producción, main, PR, merge, homologación ni runtime automático.
