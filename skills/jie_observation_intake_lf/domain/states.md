# ESTADOS DEL SISTEMA — JIE Observation Intake LF

> Estado: CANDIDATO_READ_ONLY · Lote 20B

---

## Estados de un registro de captura (lf_capture_records)

| Estado | extraction_successful | db_write_confirmed | Descripción |
|---|:---:|:---:|---|
| `REGISTERED_NEW` | true | true | URL nueva persistida correctamente |
| `REGISTERED_VERSION` | true | true | URL existente con contenido actualizado |
| `ADDENDUM_REGISTERED` | true | true | Addendum añadido a registro existente |
| `DRY_RUN_PREVIEW_READY` | false* | false | Simulación sin escritura (por diseño) |
| `READ_ONLY_RESULT` | false* | false | Solo lectura sin escritura (por diseño) |
| `BLOCKED_404_RECORDED` | false | false | URL no encontrada |
| `BLOCKED_DUPLICATE_POLICY` | false | false | Hash ya existe en BD |
| `BLOCKED_PERMISSION_DENIED` | false | false | Rol sin permiso para el modo |
| `BLOCKED_INVALID_INPUT_CONTRACT` | false | false | Input malformado |
| `BLOCKED_URL_INVALID` | false | false | URL con formato inválido |
| `BLOCKED_FETCH_FAILED` | false | false | Error de red o timeout |
| `BLOCKED_MIN_EVIDENCE_NOT_MET` | false | false | raw_text < 100 chars o title vacío |
| `BLOCKED_DB_WRITE_FAILED` | false | false | Error al escribir en BD |
| `BLOCKED_DB_READBACK_FAILED` | false | false | Escritura no confirmada |
| `BLOCKED_OPERATION_CODE_INVALID` | false | false | operation_code no en registry |
| `BLOCKED_PARTIAL_EXECUTION` | false | false | Fallo interno sin gate específico |
| `EXTRACCION_PARCIAL` | true | true | Escrito con raw_text truncado |

*false por diseño, no error

---

## Estados del skill (nivel gobernanza)

| Estado | Descripción |
|---|---|
| `CANDIDATO_READ_ONLY` | Estado actual. Solo sandbox. No producción. |
| `EN_REVISION` | Pendiente de revisión formal (requiere evals + judge) |
| `PRUEBA_SANDBOX` | Evals ejecutados, judge en curso |
| `APROBADO` | Aprobación explícita del operador de gobernanza |
| `PRODUCCION_CONTROLADA` | Merge a main autorizado (futuro) |
| `DEPRECATED` | Reemplazado por versión superior |

**Estado actual de este paquete:** `CANDIDATO_READ_ONLY`

---

## Estados bloqueados (nunca alcanzables sin aprobación)

```
FUTURE_BLOCKED_NO_HOMOLOGATION   → Homologación no disponible en esta versión
FUTURE_BLOCKED_NO_INSIGHT        → Insights automáticos no disponibles
FUTURE_BLOCKED_NO_ALERT          → Alertas automáticas no disponibles
FUTURE_BLOCKED_NO_N8N            → Conexión n8n no disponible
FUTURE_BLOCKED_ADMIN_OVERRIDE    → ADMIN_OVERRIDE bloqueado por defecto
```

---

## Convención de estado en lf_capture_runs

| Valor | Significado |
|---|---|
| `RUNNING` | Corrida en progreso |
| `COMPLETED` | Todos los URLs procesados (con o sin errores por URL) |
| `FAILED` | Error crítico que impidió completar la corrida |
| `DRY_RUN_COMPLETED` | Corrida DRY_RUN sin escritura en BD |
