# Main Contract — Data Placement Router

## Input
- `project_code`: proyecto lógico autorizado.
- `data_type`: tipo canónico de información.
- `record`: datos a persistir o relacionar.

## Obligatorio
1. Resolver destino solo desde `adapters/project-data-map.yaml`.
2. Verificar existencia real de esquema, tabla y columnas antes de escribir.
3. Buscar equivalente antes de insertar.
4. Validar valores de catálogo/estado contra la fuente real.
5. Si no existe destino explícito, devolver `BLOCKED_NO_DESTINATION`.

## Prohibido
- Crear tablas/esquemas/catálogos automáticamente.
- Usar `public` como fallback.
- Inventar tabla, columna, estado o código.
- Guardar en una tabla aproximada por conveniencia.

## Output
`project_code`, `schema`, `data_type`, `table`, `action`, `reason`.
