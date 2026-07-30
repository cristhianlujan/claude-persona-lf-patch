# Contrato integral por campo

Versión operativa: `v0.5`. Juez: `J04_FIELD_CONTRACTS`.
Validador: `scripts/validate_field_coverage.py`.
Evals ejecutables: `E23_FIELD_CONTRACTS_POSITIVE` y `E24_FIELD_CONTRACTS_NEGATIVE`.

## Objetivo

Garantizar cobertura 1:1 entre `screen_fields` y `fields`, con reglas explícitas de visibilidad, edición, validación, privacidad, auditoría y telemetría.

## Entradas obligatorias

- `screen_fields`: inventario completo asociado a la historia.
- `field_inventory`: metadatos fuente por campo.
- `permission_matrix`: perfiles autorizados para ver o editar.
- `privacy_rules`: clasificación y restricciones.
- `token_registry`: componentes y formatos disponibles.
- `source_snapshot`: versión y SHA-256 resolubles.

## Preflight

1. Confirmar que todas las entradas existen y corresponden a la misma fuente.
2. Resolver referencias y permisos aplicables.
3. Detener con `BLOCKED` ante inventario ausente, conflicto de fuente o matriz obligatoria faltante.
4. Prohibido inferir campos, permisos o clasificaciones no documentadas.

## Procedimiento determinista

1. Conciliar `screen_fields` contra contratos.
2. Detectar faltantes, inesperados y códigos duplicados.
3. Validar `visibility_mode` y `editable`.
4. Clasificar PII y restringir analytics, logs y exportación.
5. Para campos editables exigir auditoría y estrategias previo/nuevo.
6. Exigir al menos un `validation_code` por campo.
7. Emitir conteos, detalle de fallas, reparaciones y `evidence_refs`.
8. Ejecutar E23 y E24; E24 debe ser rechazado.

## Contrato de salida

El validador emite el contrato común de juez v0.5:

```text
schema_version, judge_code, judge_version, executor_identity, command,
started_at, completed_at, exit_code, result, compliance_bit, assertions_total,
assertions_passed, failed_assertions, blocking_assertions, repairs,
repair_instructions, evidence_refs, evidence, evidence_sha256, input_sha256,
output_sha256, retry_count
```

Condiciones de paso:

```text
fields_without_contract = 0
unexpected_field_contracts = 0
duplicate_field_codes = 0
fields_without_visibility_rule = 0
fields_without_editability_rule = 0
pii_fields_without_classification = 0
pii_fields_with_analytics_allowed = 0
pii_fields_with_logs_allowed_without_rule = 0
editable_fields_without_audit_strategy = 0
fields_without_validation_mapping = 0
```

## Ejemplo positivo

```json
{
  "field_code": "phone",
  "data_type": "STRING",
  "required": true,
  "editable": true,
  "visibility_mode": "MASKED",
  "pii_classification": "PII_DIRECT",
  "masking_rule": "SHOW_LAST_3",
  "analytics_allowed": false,
  "logs_allowed": false,
  "export_allowed": false,
  "audit_required": true,
  "previous_value_strategy": "MASKED",
  "new_value_strategy": "MASKED",
  "validation_codes": ["VAL-PHONE-FORMAT"],
  "source_ref": "SRC-SENSITIVE#phone"
}
```

Resultado esperado: `PASS_WITH_EVIDENCE`.

## Ejemplo negativo

```json
{
  "field_code": "phone",
  "editable": true,
  "pii_classification": "PII_DIRECT",
  "analytics_allowed": true,
  "audit_required": false,
  "validation_codes": []
}
```

Resultado esperado: `RETURN_TO_WORKER`.

## Reparación y stop conditions

Reparar solo los objetos indicados. Está prohibido borrar assertions, reducir umbrales, inventar fuente o autoaprobar. Tras `retry_limit = 2`, devolver `BLOCKED` con evidencia acumulada.
