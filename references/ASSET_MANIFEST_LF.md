# ASSET_MANIFEST_LF — claude-persona

Estado: CANDIDATO_READ_ONLY  
Fecha: 2026-05-20  
Ámbito: assets visuales y referencias Markdown del repositorio `takechanman1228/claude-persona`

## Objetivo

Evitar que la documentación o instalación declare assets que no existen, no renderizan o no tienen control mínimo de ruta. Este manifiesto es un control candidato para prevenir fallas visuales como la referencia rota a `assets/workflow.svg`.

## Inventario mínimo obligatorio

| Asset | Ruta esperada | Referenciado por | Estado esperado | Control |
|---|---|---|---|---|
| Logo principal | `assets/claude-persona-logo.png` | `README.md` | Debe existir y renderizar | PNG signature + link check |
| Diagrama workflow | `assets/workflow.svg` | `docs/ARCHITECTURE.md` | Debe existir y renderizar | XML parse + link check |

## Reglas candidatas LF

1. Ningún Markdown puede referenciar `assets/*` si el archivo no existe.
2. Todo asset referenciado en documentación debe existir en el repositorio antes de aprobar release visual/documental.
3. Los assets SVG deben pasar parseo XML básico.
4. Los assets PNG deben iniciar con la firma binaria PNG.
5. Los instaladores pueden copiar `assets/`, pero eso no reemplaza un control de existencia/ruta/render.
6. Si una ruta visual falla, el estado mínimo debe ser `BLOQUEADO_VISUAL_P0` o equivalente proporcional.

## Gate de cierre

Un cambio visual/documental solo puede pasar a candidato de producción si:

- `python3 -m unittest tests/test_markdown_asset_links.py` pasa sin errores.
- `README.md` y `docs/ARCHITECTURE.md` no tienen rutas rotas.
- El asset nuevo o modificado está inventariado en este manifiesto.
- La validación es posterior al cambio, no solo previa.

## Pendientes no cubiertos por este manifiesto

- Validación visual humana de calidad del logo.
- Validación pixel-perfect del SVG en todos los renderizadores.
- Control de peso/tamaño máximo de assets.
