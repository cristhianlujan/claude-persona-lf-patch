# Mini Judge — Data Placement Router

Return `BLOCKED` if:
- `project_code` no tiene mapping.
- `data_type` no tiene destino autorizado.
- esquema/tabla/columna no existe en readback.
- valor de catálogo/estado no existe.
- se intenta crear tabla, esquema o fallback a `public`.

Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` if:
- no se buscó duplicidad antes del INSERT.
- falta `reason` o trazabilidad del destino.

Return `PASS_TO_WRITE` solo cuando destino, estructura y valores fueron verificados y la acción es REUSE, RELATE, UPDATE o INSERT.
