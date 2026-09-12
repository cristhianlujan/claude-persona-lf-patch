# LF Shell Resolution Contract

## Objetivo

Resolver la estructura LF antes de permitir que un perfil tome o implemente una decisión de pantalla.

## Resolución canónica

1. Resolver `screen_code` en `lf_ops.pantallas`.
2. Leer `module_code` de la pantalla.
3. Resolver `module_code` en `lf_ops.modulos` y obtener `app_shell_code`.
4. Resolver `app_shell_code` en `lf_ops.app_shells`.
5. Leer versión, estado, Design System y bindings de componentes/tokens del Shell.
6. Resolver variantes y elementos específicos de pantalla cuando existan.
7. Resolver los tokens referenciados contra `lf_design.*_tokens`.
8. Conservar `source_decision_id/source_decision_number` disponibles como trazabilidad.

## Estado y precedencia

- `VIGENTE`: puede actuar como autoridad canónica para una salida candidata.
- `CANDIDATO`: solo permite `BOUND_CANDIDATE_ONLY`; nunca promoción implícita.
- estado desconocido/incompatible: devolver conflicto o blocker; no asumir vigencia.

Si una pantalla no tiene relación suficiente para resolver su módulo/Shell, no inventar el vínculo.

## Clasificación de targets

Cada target relevante debe clasificarse antes de ejecutar el delta:

- `SHELL_LOCKED`: navegación global, topbar/sidebar, breadcrumb, page shell o componente/token declarado por el Shell como estructura global.
- `SCREEN_SLOT`: región de contenido que el Shell deja para la pantalla y cuyo contenido puede ser definido por el perfil competente.
- `SCREEN_COMPONENT`: componente propio de la pantalla, ligado a `pantalla_elementos`, `pantalla_variantes`, contrato UI upstream o Component Tree verificable.

Un target no resuelto no se trata automáticamente como editable.

## Regla de cambio de Shell

Si el pedido requiere cambiar `SHELL_LOCKED`:

`observación/perfil -> identificar target protegido -> preservar Shell -> RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED -> proceso separado de cambio de Shell`

El adapter no ejecuta ese cambio ni lo disfraza como delta de pantalla.

## Precisión

Usar la misma jerarquía de UI Architect:

1. `CANONICAL_TOKEN` si el valor/token existe en la fuente canónica.
2. `UPSTREAM_VALUE` si existe una decisión exacta upstream sin token DS.
3. `EXPLORATORY_PROPOSAL` si no existe autoridad canónica y el valor es exploratorio/low-risk.
4. `RELATIVE_GUIDANCE` si una unidad exacta crearía falsa precisión.
5. devolver al orchestrator si el faltante cambia semántica, negocio, seguridad, CTA, ruta o constraint protegido.

## Consistencia

Con idéntico contexto, Router y activación directa deben resolver el mismo Shell, mismos locks y mismo delta normalizado. Metadatos de routing no autorizan diferencias materiales.

## Readback mínimo

Antes de cerrar:

- confirmar `screen_code` resuelto;
- confirmar `module_code`;
- confirmar `app_shell_code`, versión y estado;
- confirmar referencias de tokens realmente usadas;
- confirmar que ningún target `SHELL_LOCKED` quedó dentro de `profile_delta` ejecutable;
- confirmar handoff downstream y sus límites.