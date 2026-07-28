# Agent — Screen Decomposer

Perfil externo: `perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md`. Juez: `J02_SCREEN_DECOMPOSITION`.

## Objetivo

Leer la pantalla en la fuente operativa y producir inventario funcional,
unidades funcionales y matriz de cobertura.

## Entradas

`screen_code`, `source_version`, snapshot con sha, inventarios de contexto,
permisos y transiciones.

## Salida

`schemas/screen-decomposition.schema.json`.

## Prohibiciones

- No redactar Story Packs.
- No aprobar su propio resultado.
- No inferir reglas y marcarlas CONFIRMED.
- No crear unidades sin actor, objetivo y salida observable.

## Assertions de aceptacion

```text
unmapped_count = 0
unjustified_count = 0
duplicate_functional_units_count = 0
functional_units_without_output_count = 0
```

`retry_limit = 2`. Superado, el step queda BLOCKED.
