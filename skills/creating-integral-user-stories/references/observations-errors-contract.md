# Contrato de observaciones y errores

Juez asociado: `J05_OBSERVATIONS_ERRORS`.

## Observacion

Hallazgo sobre el dato o el proceso que el usuario puede entender y accionar.

```text
observation_code, category, severity, affected_field, affected_record,
blocking, continuation_allowed, suggested_action, downloadable_detail,
audit_required
```

Toda observacion requiere accion sugerida. Una observacion bloqueante exige
decision explicita de continuacion.

## Error

Falla de ejecucion.

```text
error_code, category, severity, blocking, retryable, automatic_retry,
user_title_code, user_message_code, suggested_action, action_token,
trace_code_required, correlation_id_required, audit_required, alert_required,
technical_detail_visibility
```

## Reglas duras

- Toda condicion bloqueante necesita `error_code`.
- Todo error reintentable necesita politica de reintento.
- Todo error necesita estrategia de correlacion.
- `technical_detail_visibility` nunca expone stack trace al usuario final.
- Codigos de error duplicados: falla.

## Separacion

El mensaje al usuario se referencia por token (`user_message_code`), nunca se
escribe literal en la historia. El detalle tecnico viaja por observabilidad,
no por la interfaz.
