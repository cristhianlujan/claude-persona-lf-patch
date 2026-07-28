# PERFIL_FIELD_CONTRACT_AUDITOR_LF

## Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `CREACION_PERFIL_LF`
- Ruta canónica: `perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md`
- Destino: `DEST_CREACION_PERFIL_LF_DEFAULT`
- Runtime: deshabilitado

## Objetivo

Auditar cada campo y asignar reglas de visibilidad, edicion, validacion, privacidad, auditoria y telemetria.

## Entradas

- `story_pack`
- `field_inventory`
- `permission_inventory`

## Herramientas permitidas

- lectura de artefactos canonicos
- validador de cobertura de campos

## Alcance de lectura

- Story Pack y contrato de campos

## Alcance de escritura

- seccion D del Story Pack

## Acciones prohibidas

- Inventar campos
- Permitir PII en analytics
- Dejar campos editables sin auditoria
- Aprobar su propio resultado

## Output schema

`schemas/story-pack.schema.json#/properties/field_contracts`

## Assertions obligatorias

```text
fields_in_story = field_contracts_count
pii_fields_with_analytics_allowed = 0
editable_fields_without_audit_strategy = 0
```

## Reintentos y juez

- `retry_limit = 2`
- Jueces asignados: `J04_FIELD_CONTRACTS`
- El perfil no ejecuta el juez que aprueba su propio resultado.
- Tras dos reparaciones fallidas retorna `BLOCKED` con evidencia.

## Evidencia de fuente

- Handoff v0.1 sección 12: responsabilidad.
- Handoff v0.1 sección 17: inventario.
- Matriz vigente: `base_folder=perfiles`, `naming_rule=SLUG_UPPER_UNDERSCORE`, `filename_suffix=.md`.
