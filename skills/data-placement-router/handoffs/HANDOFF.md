# Handoff — Data Placement Router

## Uso
Invocar antes de cualquier escritura gobernada en Supabase cuando el destino dependa del proyecto y tipo de información.

## Entrada mínima
- `project_code`
- `data_type`
- registro a guardar/relacionar

## Readback obligatorio
1. Leer `adapters/project-data-map.yaml`.
2. Verificar esquema/tabla/columnas reales.
3. Buscar duplicidad.
4. Validar catálogos/estados.

## Cierre
- Si existe destino: devolver ruta y acción.
- Si no existe: `BLOCKED_NO_DESTINATION`.
- Nunca crear tabla, esquema o catálogo como fallback.
