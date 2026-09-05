# LF BACKOFFICE EMPRESA — INSTRUCCIONES OPERATIVAS

## Alcance

Este proyecto trabaja exclusivamente el Backoffice Empresa de Libertad Financiera. El shell funcional es `B2B_APP_SHELL`.

## Regla de contexto

Antes de proponer, diseñar, documentar, generar una imagen, crear una historia o guardar información:

`Backoffice → módulo → pantalla → funcionalidad`

Resolver contexto desde:
- `lf_ops.app_shells`
- `lf_ops.modulos`
- `lf_ops.pantallas`

## Persistencia funcional

Usar las estructuras existentes. No crear tablas, esquemas, catálogos ni JSON genéricos cuando exista una estructura especializada.

- reglas → `lf_ops.reglas`
- regla/pantalla → `lf_ops.reglas_pantallas`
- campos → `lf_ops.campos`
- campo/pantalla → `lf_ops.campos_pantallas`
- validaciones → `lf_ops.campos_validaciones`
- estados → `lf_ops.estados_catalogo`
- transiciones → `lf_ops.estados_transiciones`
- perfiles → `lf_ops.perfiles`
- permisos → `lf_ops.permisos`
- relaciones de acceso → `lf_ops.perfiles_permisos`, `lf_ops.pantallas_perfiles`, `lf_ops.pantallas_permisos`
- seguridad/sesión/timeout/rate limit/OTP/aprobación → tablas `lf_ops.politicas_*` y `lf_ops.otp_politicas`
- errores de producto/sistema → `lf_ops.errores_catalogo`
- ocurrencias → `lf_ops.errores_ocurrencias`
- evidencia visual de pantalla → `lf_ops.pantalla_artefactos`

## Sistema visual obligatorio

Toda pantalla nueva o iteración visual de LF Backoffice debe consultar primero el design system `LF_DS_V1` en `lf_design`.

Fuentes visuales autorizadas:
- sistema raíz → `lf_design.design_systems`
- colores → `lf_design.color_tokens`
- tipografía → `lf_design.typography_tokens`
- espaciados → `lf_design.spacing_tokens`
- responsive/breakpoints → `lf_design.responsive_tokens`
- componentes y estados → `lf_design.component_tokens`
- temas/rutas → `lf_design.theme_bindings`
- iconos → `lf_design.icon_catalog`
- logos/activos de marca → `lf_design.brand_assets`
- decisiones visuales → `lf_design.visual_decisions`

Reglas visuales:
1. Reutilizar tokens existentes; no inventar colores, fuentes, tamaños, espacios, componentes o iconos.
2. Preferir tokens con estado `VIGENTE`.
3. `CANDIDATO`, `CANDIDATO_VISUAL` o `PENDIENTE_DECISION_FINAL` no se convierten en definitivos por inferencia.
4. No reutilizar tokens `DEPRECADO`.
5. Si falta un token necesario, registrar el faltante como pendiente; no crear uno automáticamente.
6. Todas las pantallas Backoffice deben mantener coherencia visual entre sí usando el mismo `LF_DS_V1`.

## Conocimiento transversal LF

Solo usar `public` cuando el mapping sea explícito:
- errores aprendidos → `public.lf_error_knowledge`
- prevención → `public.lf_prevention_rules`
- buenas prácticas → `public.lf_best_practices`
- decisiones → `public.lf_decision_log`

`public` nunca es fallback.

## Regla de no mezcla

- LF Backoffice funcional → `lf_ops.*`
- LF Backoffice visual → `lf_design.*`
- Overall → `overall_design.*`
- Saly → `saly.*`

Nunca usar una tabla de otro proyecto porque tenga un concepto parecido.

## Antes de guardar

`identificar proyecto → clasificar dato → resolver mapping → buscar existente → validar tabla/columnas/estado → reutilizar/relacionar/actualizar o insertar`

Si no existe destino autorizado: `BLOCKED_NO_DESTINATION`.
