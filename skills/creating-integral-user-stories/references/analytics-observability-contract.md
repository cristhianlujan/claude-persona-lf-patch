# Contrato de analytics y observabilidad

Versión operativa: `v0.3`. Juez asociado: `J09_ANALYTICS_OBSERVABILITY`.

## 1. Propósito

Definir comportamiento medible y salud operacional sin mezclar analytics, observabilidad y auditoría ni filtrar PII.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `story_pack` | Acciones, resultados, errores y campos. |
| `field_contracts` | Clasificación PII y permisos de telemetría. |
| `analytics_taxonomy` | Eventos y propiedades permitidas. |
| `observability_policy` | Métricas, logs, trazas, umbrales y alertas. |
| `audit_contract` | Eventos probatorios que deben permanecer separados. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Identificar eventos de comportamiento realmente útiles para producto.
2. Asignar event_code y trigger exacto.
3. Enumerar propiedades y cruzarlas contra clasificación PII.
4. Definir correlation_id, sampling y retención.
5. Identificar operaciones, dependencias y errores que requieren métricas.
6. Definir metric_code, categoría, dimensión segura y umbral.
7. Definir logs con nivel, masking y correlation_id.
8. Decidir alert_required y canal por falla crítica.
9. Comprobar que ningún audit_event se reutiliza como analytics.
10. Derivar pruebas de ausencia de PII y presencia de correlación.

## 5. Reglas e invariantes

- Analytics mide comportamiento; observabilidad mide salud; auditoría prueba quién hizo qué.
- PII_DIRECT, PII_SENSITIVE y PII_FINANCIAL están prohibidos en analytics.
- PII en logs exige masking_rule y necesidad operacional documentada.
- Toda operación crítica requiere correlation_id.
- Toda falla crítica tiene decisión de alerta.
- Las métricas no usan dimensiones de alta cardinalidad sensibles.
- Ausencia de evento también es una decisión explícita cuando no aporta valor.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/analytics y /observability`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
analytics_events_with_pii = 0
logs_with_pii_without_contract = 0
operations_without_correlation_id = 0
errors_without_metric_category = 0
critical_failures_without_alert_decision = 0
audit_events_mixed_with_analytics = 0
```

## 8. Condiciones de bloqueo

```text
observability_requirements_unavailable = true
analytics_taxonomy_conflict = true
```

## 9. Ejemplo mínimo completo

```json
{
  "event_code": "customer_query_completed",
  "trigger": "query returns a terminal outcome",
  "properties": ["result_category", "duration_bucket"],
  "pii_free": true,
  "correlation_id_required": true,
  "sampling_policy": "100_PERCENT",
  "retention_class": "PRODUCT_STANDARD"
}
```

## 10. Reparación

Cuando una assertion falle, reparar exclusivamente el objeto asociado; no reducir el umbral, borrar la assertion ni modificar la fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con la evidencia acumulada.

## 11. Handoff

Entregar al juez: versión de fuente, SHA-256, objetos procesados, conteos, assertions, fallas, decisiones pendientes, reparaciones aplicadas y evidence_refs resolubles.

## 12. Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.
- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.

Estas fuentes aportan patrones de ejecutabilidad, validación y pruebas. Los contratos LF y la fuente operativa prevalecen ante cualquier diferencia.
