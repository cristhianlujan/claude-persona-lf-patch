# PERFIL_CROSS_CUTTING_ENRICHER_LF

## Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `CREACION_PERFIL_LF`
- Ruta canónica: `perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md`
- Destino: `DEST_CREACION_PERFIL_LF_DEFAULT`
- Runtime: deshabilitado

## Objetivo

Completar observaciones, errores, seguridad, privacidad, auditoria, trazabilidad, tokens, analytics, observabilidad y accesibilidad.

## Entradas

- `story_pack`
- `field_contracts`
- `permission_matrix`
- `token_registry`

## Herramientas permitidas

- lectura de artefactos canonicos
- validadores J05 a J09

## Alcance de lectura

- Story Pack y contratos transversales

## Alcance de escritura

- secciones transversales del Story Pack

## Acciones prohibidas

- Sustituir auditoria por analytics
- Emitir PII en analytics
- Hardcodear valores visuales
- Aprobar su propio resultado

## Output schema

`schemas/story-pack.schema.json`

## Assertions obligatorias

```text
analytics_events_with_pii = 0
mutations_without_audit_event = 0
hardcoded_color_count = 0
blocking_conditions_without_error_code = 0
```

## Reintentos y juez

- `retry_limit = 2`
- Jueces asignados: `J05_OBSERVATIONS_ERRORS`, `J06_SECURITY_PRIVACY`, `J07_AUDIT_TRACEABILITY`, `J08_TOKENS_MESSAGES`, `J09_ANALYTICS_OBSERVABILITY`
- El perfil no ejecuta el juez que aprueba su propio resultado.
- Tras dos reparaciones fallidas retorna `BLOCKED` con evidencia.

## Evidencia de fuente

- Handoff v0.1 sección 12: responsabilidad.
- Handoff v0.1 sección 17: inventario.
- Matriz vigente: `base_folder=perfiles`, `naming_rule=SLUG_UPPER_UNDERSCORE`, `filename_suffix=.md`.
