# Contrato por campo

Juez asociado: `J04_FIELD_CONTRACTS`. Validador: `scripts/validate_field_coverage.py`.

Todo campo presente en la pantalla debe tener contrato. La condicion de paso es
`fields_in_story = field_contracts_count`.

## Claves obligatorias

```text
field_code            context_code           entity_code
source_type           data_type              required
editable              editable_by            viewable_by
visibility_mode       pii_classification     masking_rule
analytics_allowed     logs_allowed           export_allowed
audit_required        retention_class        validation_codes
observation_codes     error_codes            message_codes
component_token       format_token           previous_value_strategy
new_value_strategy    hash_required          change_reason_required
```

## Reglas duras

- Campo editable sin estrategia de auditoria: falla.
- Campo PII sin `pii_classification`: falla.
- Campo PII con `analytics_allowed = true`: falla.
- Campo PII con `logs_allowed = true` sin `masking_rule`: falla.
- Campo sin mapeo a validaciones: falla.

## Clasificacion de privacidad

```text
NONE            dato no personal
PII_INDIRECT    identifica en combinacion
PII_DIRECT      identifica por si mismo
PII_SENSITIVE   categoria especial
PII_FINANCIAL   deuda, ingreso, score, medio de pago
```

En contexto LF los campos de comportamiento crediticio se tratan como
`PII_FINANCIAL` salvo contrato explicito en contrario registrado en la fuente.

## Estrategia de valor previo

`previous_value_strategy` y `new_value_strategy` admiten `FULL`, `MASKED`,
`HASH`, `OMITTED`. Para campos sensibles no se permite `FULL` sin regla escrita.
