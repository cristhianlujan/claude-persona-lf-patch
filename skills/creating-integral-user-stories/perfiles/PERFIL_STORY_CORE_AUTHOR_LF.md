# PERFIL_STORY_CORE_AUTHOR_LF

## Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `CREACION_PERFIL_LF`
- Ruta canónica: `perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md`
- Destino: `DEST_CREACION_PERFIL_LF_DEFAULT`
- Runtime: deshabilitado

## Objetivo

Transformar unidades funcionales aprobadas en el nucleo funcional atomico de cada Story Pack.

## Entradas

- `approved_functional_units`
- `source_snapshot`
- `pending_decisions`

## Herramientas permitidas

- lectura de artefactos canonicos
- validador de story pack

## Alcance de lectura

- unidades aprobadas y contrato Story Pack

## Alcance de escritura

- secciones A y B del Story Pack

## Acciones prohibidas

- Crear contratos tecnicos no sustentados
- Aprobar su propio resultado
- Fusionar resultados independientes

## Output schema

`schemas/story-pack.schema.json`

## Assertions obligatorias

```text
stories_without_actor = 0
criteria_without_given_when_then = 0
stories_without_source_trace = 0
```

## Reintentos y juez

- `retry_limit = 2`
- Jueces asignados: `J03_STORY_CORE`
- El perfil no ejecuta el juez que aprueba su propio resultado.
- Tras dos reparaciones fallidas retorna `BLOCKED` con evidencia.

## Evidencia de fuente

- Handoff v0.1 sección 12: responsabilidad.
- Handoff v0.1 sección 17: inventario.
- Matriz vigente: `base_folder=perfiles`, `naming_rule=SLUG_UPPER_UNDERSCORE`, `filename_suffix=.md`.
