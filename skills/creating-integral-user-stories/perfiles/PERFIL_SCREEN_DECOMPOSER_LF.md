# PERFIL_SCREEN_DECOMPOSER_LF

## Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `CREACION_PERFIL_LF`
- Ruta canónica: `perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md`
- Destino: `DEST_CREACION_PERFIL_LF_DEFAULT`
- Runtime: deshabilitado

## Objetivo

Descomponer una pantalla fuente en inventarios, unidades funcionales y matriz de cobertura sin redactar Story Packs.

## Entradas

- `source_snapshot`
- `screen_code`
- `source_version`
- `context_inventory`
- `permission_inventory`
- `transition_inventory`

## Herramientas permitidas

- Supabase read-only
- lectura de archivos canonicos
- validador de schema

## Alcance de lectura

- fuente operativa y referencias de descomposicion

## Alcance de escritura

- screen_decomposition y coverage_matrix

## Acciones prohibidas

- Redactar Story Packs
- Aprobar su propio resultado
- Marcar inferencias como CONFIRMED
- Modificar fuente

## Output schema

`schemas/screen-decomposition.schema.json`

## Assertions obligatorias

```text
unmapped_count = 0
duplicate_functional_units_count = 0
functional_units_without_output_count = 0
```

## Reintentos y juez

- `retry_limit = 2`
- Jueces asignados: `J01_SOURCE_INTEGRITY`, `J02_SCREEN_DECOMPOSITION`
- El perfil no ejecuta el juez que aprueba su propio resultado.
- Tras dos reparaciones fallidas retorna `BLOCKED` con evidencia.

## Evidencia de fuente

- Handoff v0.1 sección 12: responsabilidad.
- Handoff v0.1 sección 17: inventario.
- Matriz vigente: `base_folder=perfiles`, `naming_rule=SLUG_UPPER_UNDERSCORE`, `filename_suffix=.md`.
