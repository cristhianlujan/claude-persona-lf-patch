# ROLES & PERMISSIONS MATRIX — ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2

> Estado: CANDIDATO / READ_ONLY · v0.2 · Lote 20B
> Gate que aplica esta matriz: GATE_01_ROLE_PERMISSION

---

## Matriz principal

| Modo de ejecución | viewer | extractor_operator | register_operator | kb_curator | admin_sandbox |
|---|:---:|:---:|:---:|:---:|:---:|
| `FULL_EXTRACTION_REGISTER_SANDBOX_ONLY` | ❌ | ✅ | ✅ | ❌ | ✅ |
| `DRY_RUN` | ❌ | ✅ | ✅ | ✅ | ✅ |
| `READ_ONLY_RESULT` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `ADDENDUM_ONLY` | ❌ | ❌ | ✅ | ✅ | ✅ |
| `ADMIN_OVERRIDE` (FUTURE_BLOCKED_NO_HOMOLOGATION) | ❌ | ❌ | ❌ | ❌ | ✅ |

**Leyenda:** ✅ = permitido · ❌ = `BLOCKED_PERMISSION_DENIED` en GATE_01

---

## Definición de cada rol

### `viewer`
```yaml
descripcion: Solo puede consultar resultados existentes. No ejecuta extracción.
puede: READ_ONLY_RESULT
no_puede: Cualquier modo que escriba en BD o procese URLs
casos_de_uso:
  - Revisar capturas previas sin modificar nada
  - Auditar registros existentes
restricciones_adicionales:
  - No puede ver raw_payload completo en producción (RLS)
  - Solo puede invocar el adapter en modo lectura
```

### `extractor_operator`
```yaml
descripcion: Operador que ejecuta extracciones nuevas y dry runs.
             No puede modificar registros existentes ni hacer override.
puede: FULL_EXTRACTION_REGISTER_SANDBOX_ONLY, DRY_RUN, READ_ONLY_RESULT
no_puede: ADDENDUM_ONLY, ADMIN_OVERRIDE
casos_de_uso:
  - Captura masiva de nuevas URLs no registradas
  - Pruebas DRY_RUN para validar extracción antes de persistir
restricciones_adicionales:
  - max_urls_per_run ≤ 10 en sandbox
  - No puede modificar registros ya existentes en lf_capture_records
```

### `register_operator`
```yaml
descripcion: Operador con permisos completos excepto override administrativo.
             Puede registrar, actualizar versiones y añadir addenda.
puede: FULL_EXTRACTION_REGISTER_SANDBOX_ONLY, DRY_RUN, READ_ONLY_RESULT, ADDENDUM_ONLY
no_puede: ADMIN_OVERRIDE
casos_de_uso:
  - Captura regular de fuentes catalogadas
  - Actualización de artículos con contenido modificado (REGISTERED_VERSION)
  - Añadir secciones nuevas a artículos ya registrados (ADDENDUM_ONLY)
restricciones_adicionales:
  - Para ADDENDUM_ONLY debe proveer target_record_id o URL del registro existente
```

### `kb_curator`
```yaml
descripcion: Curador de base de conocimiento. Puede añadir addenda
             y hacer dry runs pero no registra nuevos artículos directamente.
puede: DRY_RUN, READ_ONLY_RESULT, ADDENDUM_ONLY
no_puede: FULL_EXTRACTION_REGISTER_SANDBOX_ONLY, ADMIN_OVERRIDE
casos_de_uso:
  - Enriquecer registros existentes con contexto adicional
  - Revisar contenido antes de decidir si hacer extracción completa
  - Auditar registros existentes
restricciones_adicionales:
  - Solo puede añadir addenda a registros ya existentes
  - No puede crear registros nuevos
```

### `admin_sandbox`
```yaml
descripcion: Administrador con acceso completo incluyendo override.
             Requiere admin_override_reason para ADMIN_OVERRIDE.
puede: Todos los modos
restriccion_critica: ADMIN_OVERRIDE requiere campo admin_override_reason no vacío.
                     Si falta → GATE_02 falla → BLOCKED_INVALID_INPUT_CONTRACT.
casos_de_uso:
  - Recuperación de registros fallidos
  - Override documentado de políticas de duplicado
  - Pruebas de extremo a extremo en sandbox
restricciones_adicionales:
  - admin_override_reason debe describir el motivo del override
  - Toda ejecución ADMIN_OVERRIDE queda en lf_log_operativo con log_key WEB_EXTRACTION_ADMIN_OVERRIDE
  - No exime de GATE_00 ni GATE_13 (operation_code y readback siguen obligatorios)
```

---

## Permisos sobre campos de salida

| Campo del output | viewer | extractor_operator | register_operator | kb_curator | admin_sandbox |
|---|:---:|:---:|:---:|:---:|:---:|
| `final_state` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `record_id_bd` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `technical_notes` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gate_fallido` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `raw_payload` completo | ❌ | ✅ | ✅ | ✅ | ✅ |
| `prompt_injection_fragmento` | ❌ | ✅ | ✅ | ✅ | ✅ |
| `admin_override_reason` (ver) | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## Lógica de verificación en GATE_01

```python
# Pseudocódigo del mini-judge de GATE_01

PERMISOS = {
  "viewer":             ["READ_ONLY_RESULT"],
  "extractor_operator": ["FULL_EXTRACTION_REGISTER_SANDBOX_ONLY", "DRY_RUN", "READ_ONLY_RESULT"],
  "register_operator":  ["FULL_EXTRACTION_REGISTER_SANDBOX_ONLY", "DRY_RUN",
                         "READ_ONLY_RESULT", "ADDENDUM_ONLY"],
  "kb_curator":         ["DRY_RUN", "READ_ONLY_RESULT", "ADDENDUM_ONLY"],
  "admin_sandbox":      ["FULL_EXTRACTION_REGISTER_SANDBOX_ONLY", "DRY_RUN", "READ_ONLY_RESULT",
                         "ADDENDUM_ONLY", "ADMIN_OVERRIDE"],
}

def gate_01(actor_role, mode):
    if actor_role not in PERMISOS:
        return BLOCK, "actor_role desconocido"
    if mode not in PERMISOS[actor_role]:
        return BLOCK, f"{actor_role} no puede ejecutar {mode}"
    return PASS
```

---

## Convención de actor_id por rol

| Rol | Formato actor_id | Ejemplos |
|---|---|---|
| viewer | `viewer_<id>` | `viewer_audit_001` |
| extractor_operator | `extractor_<nombre>` | `extractor_claude_v1`, `extractor_jie_01` |
| register_operator | `register_<nombre>` | `register_jie_intake` |
| kb_curator | `curator_<nombre>` | `curator_editorial_01` |
| admin_sandbox | `admin_<nombre>` | `admin_sandbox_gobernanza` |

> El campo `created_by` en `lf_capture_records` siempre es `ADAPTER_JIE_WEB_V0_2_CANDIDATO`
> independientemente del actor_role. El `actor_id` va en `lf_capture_records.actor_id`.

---

> Estado: CANDIDATO / READ_ONLY · No validado · No producción
