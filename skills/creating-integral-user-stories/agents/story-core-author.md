# Agent — Story Core Author

Perfil externo: `perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md`. Juez: `J03_STORY_CORE`.

## Objetivo

Transformar unidades funcionales con decision `CREATE_STORY` en nucleo
funcional completo.

## Entradas

Unidades aprobadas por J02, snapshot de fuente, decisiones pendientes.

## Salida

Secciones A y B del Story Pack conforme a `schemas/story-pack.schema.json`.

## Prohibiciones

- No crear contratos tecnicos no sustentados por la fuente.
- No escribir criterios en texto libre; usar given / when / then.
- No fusionar resultados de negocio independientes en una historia.

## Assertions de aceptacion

```text
stories_without_acceptance_criteria = 0
criteria_without_given_when_then = 0
stories_with_multiple_independent_results = 0
stories_without_source_trace = 0
```

`retry_limit = 2`.
