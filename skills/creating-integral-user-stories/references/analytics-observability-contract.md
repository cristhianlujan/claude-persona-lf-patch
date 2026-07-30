# Contrato de analytics y observabilidad

Versión operativa: `v0.5`. Juez asociado: `J09_ANALYTICS_OBSERVABILITY`.
Validador: `scripts/detect_pii_telemetry.py`.

## 1. Propósito

Definir comportamiento medible y salud operacional sin mezclar analytics, observabilidad y auditoría ni filtrar PII.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `story_pack` | Acciones, resultados, errores y campos. |
| `field_contracts` | Clasificación PII y permisos de telemetría. |
| `analytics_taxonomy` | Eventos y propiedades permitidas. |
| `observability_policy` | Logs, métricas, umbrales y alertas. |
| `audit_contract` | Eventos probatorios separados de analytics. |

## 3. Preflight

1. Confirmar entradas, versión, referencias y SHA-256.
2. Confirmar independencia entre worker y J09.
3. Confirmar metadata de juez y ejecutor.
4. Detener con `BLOCKED` ante taxonomía/política ausente, conflicto o metadata faltante.

## 4. Procedimiento obligatorio

1. Identificar eventos de producto y asignar `event_code`.
2. Cruzar propiedades contra clasificación PII.
3. Exigir `pii_free=true` y correlación.
4. Definir contrato de observabilidad con logs, métricas y alertas.
5. Exigir masking cuando un campo PII esté permitido en logs.
6. Mantener eventos de auditoría fuera de analytics.
7. Ejecutar positivo, negativo y metadata ausente contra el validador real.

## 5. Reglas e invariantes

- Analytics mide comportamiento; observabilidad mide salud; auditoría prueba acciones.
- PII directa, sensible y financiera está prohibida en analytics.
- PII en logs exige `masking_rule`.
- Cada evento exige código, `pii_free=true` y `correlation_id_required=true`.
- Error crítico sin decisión de alerta impide PASS.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/analytics`, `/observability` y envelope v0.5.

## 7. Assertions de paso

```text
analytics_section_missing = 0
analytics_events_missing = 0
analytics_events_without_code = 0
observability_contract_missing = 0
analytics_events_with_pii = 0
logs_with_pii_without_contract = 0
operations_without_correlation_id = 0
audit_events_mixed_with_analytics = 0
critical_failures_without_alert_decision = 0
```

## 8. Condiciones de bloqueo

```text
observability_requirements_unavailable = true
analytics_taxonomy_conflict = true
metadata_or_evidence_unavailable = true
retry_limit_exhausted = true
```

## 9. Caso positivo ejecutable

```json
{
  "fields": [{"field_code": "dni", "pii_classification": "PII_DIRECT", "analytics_allowed": false, "logs_allowed": true, "masking_rule": "MASK_LAST_4"}],
  "analytics": [{"event_code": "customer_opened", "properties": ["screen_id"], "pii_free": true, "correlation_id_required": true, "audit_event": false}],
  "observability": {"logs": [{"level": "INFO"}], "metrics": [], "alerts": []},
  "errors": []
}
```

Resultado esperado: `PASS_WITH_EVIDENCE`.

## 10. Caso negativo ejecutable

```json
{
  "fields": [{"field_code": "dni", "pii_classification": "PII_DIRECT", "analytics_allowed": true, "logs_allowed": true, "masking_rule": null}],
  "analytics": [{"event_code": "customer_opened", "properties": ["dni"], "pii_free": false, "correlation_id_required": true, "audit_event": false}],
  "observability": {"logs": [{"fields": ["dni"]}], "metrics": [], "alerts": []},
  "errors": []
}
```

Resultado esperado: `RETURN_TO_WORKER` con `analytics_events_with_pii` y `logs_with_pii_without_contract`.

## 11. Reparación y handoff

Reparar exclusivamente el objeto asociado; no reducir umbral, borrar assertion, degradar clasificación PII ni autoaprobar. Tras `retry_limit = 2`, devolver `BLOCKED`. Entregar comando, ejecutor, conteos, hashes y `evidence_refs`.

## 12. Fuentes de diseño no normativas

- **anthropics/skills:** evals objetivas y reparación iterativa.
- **microsoft/vscode:** workflows y stop conditions.
- **freeCodeCamp/freeCodeCamp:** constraints deterministas.
- **Significant-Gravitas/AutoGPT:** persistencia y límites operativos.

Los contratos LF prevalecen.
