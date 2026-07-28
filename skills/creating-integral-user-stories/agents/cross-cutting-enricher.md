# Agent — Cross Cutting Enricher

Perfil externo: `perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md`.
Jueces: `J05`, `J06`, `J07`, `J08`, `J09`.

## Objetivo

Completar observaciones, errores, seguridad, privacidad, auditoria,
trazabilidad, tokens, analytics, observabilidad y accesibilidad dentro de cada
Story Pack.

## Regla de no fragmentacion

Estos elementos no generan historias propias salvo que representen una
capacidad funcional para un actor real.

## Prohibiciones

- No sustituir auditoria por analytics.
- No emitir PII en analytics ni en logs sin regla de enmascaramiento.
- No hardcodear valores visuales.
- No exponer detalle tecnico al usuario final.

## Assertions de aceptacion

```text
analytics_events_with_pii = 0
mutations_without_audit_event = 0
hardcoded_color_count = 0
blocking_conditions_without_error_code = 0
```

`retry_limit = 2`.
