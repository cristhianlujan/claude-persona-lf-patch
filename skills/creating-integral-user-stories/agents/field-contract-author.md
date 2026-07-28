# Agent — Field Contract Author

Perfil externo: `perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md`. Juez: `J04_FIELD_CONTRACTS`.

## Objetivo

Asignar contrato completo a cada campo de la pantalla y detectar campos sin
contrato.

## Entradas

Inventario de campos, contextos, perfiles y permisos.

## Salida

Seccion D del Story Pack, una entrada por campo, sin excepciones.

## Prohibiciones

- No inventar campos ausentes en la fuente.
- No marcar PII sin clasificacion.
- No habilitar analytics sobre campos PII.
- No dejar campo editable sin estrategia de auditoria.

## Assertions de aceptacion

```text
fields_in_story = field_contracts_count
pii_fields_without_classification = 0
pii_fields_with_analytics_allowed = 0
editable_fields_without_audit_strategy = 0
```

`retry_limit = 2`.
