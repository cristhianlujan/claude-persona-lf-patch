# Contrato de analytics y observabilidad

Juez asociado: `J09_ANALYTICS_OBSERVABILITY`. Validador: `scripts/detect_pii_telemetry.py`.

## Tres planos separados

```text
analytics       comportamiento del usuario, sin PII
observabilidad  salud operacional, metricas, trazas, alertas
auditoria       quien hizo que sobre que recurso, con valor probatorio
```

Mezclar los tres planos es falla. Un evento de auditoria no puede emitirse
como evento de analytics.

## Evento de analytics

```text
event_code, trigger, properties, pii_free, correlation_id_required,
sampling_policy, retention_class
```

## Observabilidad

```text
metric_code, metric_category, threshold, alert_required, alert_channel,
correlation_id, log_level, pii_masking
```

Condiciones de paso:

```text
analytics_events_with_pii = 0
logs_with_pii_without_contract = 0
operations_without_correlation_id = 0
errors_without_metric_category = 0
critical_failures_without_alert_decision = 0
audit_events_mixed_with_analytics = 0
```

## Prohibicion PII

Ningun campo clasificado `PII_DIRECT`, `PII_SENSITIVE` o `PII_FINANCIAL`
viaja a analytics. En logs solo viaja con regla de enmascaramiento escrita.
