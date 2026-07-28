# Contrato de auditoria y trazabilidad

Juez asociado: `J07_AUDIT_TRACEABILITY`. Validador: `scripts/validate_traceability.py`.

## Evento de auditoria

```text
audit_event_code, action_code, actor_id, actor_profile, company_id,
resource_type, resource_id, previous_state, new_state, permission_used,
policy_version, correlation_id, idempotency_key, result, occurred_at
```

## Auditoria por campo

```text
field_code, change_type, previous_value_strategy, new_value_strategy,
changed_by, changed_at, change_reason
```

## Cadena de trazabilidad

```text
fuente -> regla -> criterio de aceptacion -> prueba -> evidencia
```

Condiciones de paso:

```text
rules_without_source_reference = 0
criteria_without_test_reference = 0
tests_without_story_reference = 0
traceability_breaks = 0
```

## Reglas duras

- Toda mutacion genera evento de auditoria.
- Toda descarga sensible genera evento de auditoria.
- Evento sin actor o sin empresa: falla.
- Campo sensible editable sin estrategia de valor previo: falla.
- Auditoria no se sustituye por analytics ni por logs.
