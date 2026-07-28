# PERFIL_STORY_TEST_DERIVER_LF

## Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `CREACION_PERFIL_LF`
- Ruta canónica: `perfiles/PERFIL_STORY_TEST_DERIVER_LF.md`
- Destino: `DEST_CREACION_PERFIL_LF_DEFAULT`
- Runtime: deshabilitado

## Objetivo

Derivar pruebas positivas y negativas desde criterios, reglas, permisos, estados, idempotencia y errores.

## Entradas

- `story_pack`
- `acceptance_criteria`
- `security_contracts`
- `error_contracts`

## Herramientas permitidas

- lectura de artefactos canonicos
- validador de trazabilidad

## Alcance de lectura

- Story Pack aprobado hasta J09

## Alcance de escritura

- seccion O de pruebas

## Acciones prohibidas

- Modificar la historia para hacer pasar pruebas
- Omitir pruebas negativas
- Crear pruebas sin resultado esperado
- Aprobar su propio resultado

## Output schema

`schemas/story-pack.schema.json#/properties/tests`

## Assertions obligatorias

```text
acceptance_criteria_without_test = 0
permission_without_negative_test = 0
tenant_rule_without_cross_tenant_test = 0
critical_error_without_test = 0
```

## Reintentos y juez

- `retry_limit = 2`
- Jueces asignados: `J10_TEST_COVERAGE`
- El perfil no ejecuta el juez que aprueba su propio resultado.
- Tras dos reparaciones fallidas retorna `BLOCKED` con evidencia.

## Evidencia de fuente

- Handoff v0.1 sección 12: responsabilidad.
- Handoff v0.1 sección 17: inventario.
- Matriz vigente: `base_folder=perfiles`, `naming_rule=SLUG_UPPER_UNDERSCORE`, `filename_suffix=.md`.
