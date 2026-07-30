# Contrato de observaciones y errores

Versión operativa: `v0.5`. Juez: `J05_OBSERVATIONS_ERRORS`.
Validador: `scripts/validate_field_coverage.py`.
Evals ejecutables: `E23_FIELD_CONTRACTS_POSITIVE` y `E24_FIELD_CONTRACTS_NEGATIVE`.

## Objetivo

Separar observaciones accionables de errores técnicos y asegurar código, mensaje, correlación, reintento y protección del detalle técnico.

## Entradas obligatorias

- `validations`: reglas que originan condiciones.
- `main_flow` y `alternative_flows`: puntos funcionales afectados.
- `message_catalog`: mensajes autorizados.
- `observability_contract`: logs, trazas, métricas y alertas.
- `source_snapshot`: versión y SHA-256 resolubles.

## Preflight

1. Confirmar entradas y compatibilidad de versiones.
2. Resolver referencias del catálogo y observabilidad.
3. Detener con `BLOCKED` si el catálogo requerido no existe o hay conflicto de severidad.
4. No exponer stack traces ni detalles internos al usuario.

## Procedimiento determinista

1. Clasificar cada condición como observación, error o decisión pendiente.
2. Para observaciones exigir acción clara del usuario.
3. Para errores bloqueantes exigir `error_code`.
4. Para errores reintentables exigir `retry_policy.max_attempts` y `backoff`.
5. Exigir correlación mediante `correlation_id_required` o `trace_code`.
6. Exigir `user_message_code`.
7. Mantener `technical_detail_visibility = INTERNAL_ONLY`.
8. Detectar códigos duplicados.
9. Emitir reparaciones y evidencia resoluble.
10. Ejecutar E23 y E24; E24 debe ser rechazado por J05.

## Contrato de salida

```text
schema_version, judge_code, judge_version, executor_identity, command,
started_at, completed_at, exit_code, result, compliance_bit, assertions_total,
assertions_passed, failed_assertions, blocking_assertions, repairs,
repair_instructions, evidence_refs, evidence, evidence_sha256, input_sha256,
output_sha256, retry_count
```

Condiciones de paso:

```text
blocking_conditions_without_error_code = 0
observations_without_user_action = 0
retryable_errors_without_retry_policy = 0
errors_without_correlation_strategy = 0
technical_errors_exposed_to_user = 0
duplicate_error_codes = 0
errors_without_message_code = 0
```

## Ejemplo positivo

```json
{
  "error_code": "ERR-PROFILE-UPDATE-TIMEOUT",
  "blocking": true,
  "retryable": true,
  "retry_policy": {"max_attempts": 2, "backoff": "EXPONENTIAL"},
  "user_message_code": "MSG-PROFILE-TEMPORARILY-UNAVAILABLE",
  "correlation_id_required": true,
  "technical_detail_visibility": "INTERNAL_ONLY"
}
```

Resultado esperado: `PASS_WITH_EVIDENCE`.

## Ejemplo negativo

```json
{
  "blocking": true,
  "retryable": true,
  "technical_detail_visibility": "USER_VISIBLE"
}
```

Resultado esperado: `RETURN_TO_WORKER`.

## Reparación y stop conditions

Agregar únicamente la información respaldada por política o fuente. No borrar assertions, reducir umbrales, inventar códigos ni autoaprobar. Tras `retry_limit = 2` reintentos fallidos, devolver `BLOCKED`.
