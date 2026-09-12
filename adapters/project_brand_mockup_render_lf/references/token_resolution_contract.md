# Token Resolution Contract

## Objetivo

Resolver colores y tokens del proyecto antes de construir mockups o PDF con pantallas.

## Orden de resolucion

1. Leer binding por ruta/pantalla.
2. Leer design_system_code.
3. Leer tokens de color del proyecto.
4. Deduplicar tokens por nombre.
5. Mapear tokens a uso visual.
6. Bloquear si no hay tokens y el entregable exige marca.

## Overall source

Para Overall usar:

- overall_design.v_route_theme_resolver
- overall_design.v_route_theme_tokens
- overall_design.color_tokens
- overall_design.route_theme_bindings

## Output esperado

| Rol | Token |
|---|---|
| primary | brand.blue.600 |
| header | brand.blue.700 |
| active | brand.indigo.500 |
| secondary | brand.violet.500 |
| success | semantic.success.600 |
| warning | semantic.warning.500 |
| error | semantic.error.600 |
| surface | surface.50 / surface.0 |

## Bloqueos

- token ausente sin fallback;
- color inventado;
- usar paleta LF generica cuando hay paleta del proyecto;
- no registrar tokens usados en readback.