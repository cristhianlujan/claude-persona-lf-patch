# Contrato de observaciones y errores

Versión operativa: `v0.3`. Juez asociado: `J05_OBSERVATIONS_ERRORS`.

## 1. Propósito

Separar hallazgos accionables de fallas de ejecución y asegurar que cada condición relevante tenga código, mensaje, correlación, reintento y evidencia.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `validations` | Reglas que pueden producir observaciones o errores. |
| `main_and_alternative_flows` | Puntos funcionales donde ocurre cada condición. |
| `message_catalog` | Mensajes reutilizables autorizados. |
| `observability_contract` | Correlación, logging, métricas y alertas. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Clasificar cada condición como observación, error o decisión pendiente.
2. Asignar código único, categoría, severidad y alcance.
3. Definir blocking y continuation_allowed.
4. Vincular campo o recurso afectado.
5. Definir acción sugerida y mensaje por token.
6. Para errores, definir retryable, automatic_retry, trace_code y correlation_id.
7. Definir auditoría y alerta cuando la severidad o impacto lo exijan.
8. Verificar que el detalle técnico no se expone al usuario.
9. Derivar pruebas positivas y negativas.
10. Entregar evidencia y catálogo usado a J05.

## 5. Reglas e invariantes

- Observación es un hallazgo de dominio que el usuario puede entender y accionar.
- Error es una falla de ejecución; nunca se comunica mediante stack trace.
- Toda condición bloqueante requiere error_code o una decisión bloqueante explícita.
- Error reintentable exige retry_policy con límite y backoff.
- Los códigos son únicos dentro del paquete.
- Mensajes se referencian por message_code y action_token.
- Correlación es obligatoria para errores operativos y críticos.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/observations y /errors`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
blocking_conditions_without_error_code = 0
observations_without_user_action = 0
retryable_errors_without_retry_policy = 0
errors_without_correlation_strategy = 0
technical_errors_exposed_to_user = 0
duplicate_error_codes = 0
```

## 8. Condiciones de bloqueo

```text
error_catalog_required_but_unavailable = true
severity_policy_conflict = true
```

## 9. Ejemplo mínimo completo

```json
{
  "error_code": "ERR-CUSTOMER-QUERY-TIMEOUT",
  "category": "DEPENDENCY",
  "severity": "HIGH",
  "blocking": true,
  "retryable": true,
  "retry_policy": {"max_attempts": 2, "backoff": "EXPONENTIAL"},
  "user_message_code": "MSG-QUERY-TEMPORARILY-UNAVAILABLE",
  "correlation_id_required": true,
  "technical_detail_visibility": "INTERNAL_ONLY"
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
