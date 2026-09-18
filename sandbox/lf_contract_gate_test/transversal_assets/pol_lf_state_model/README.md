# POL-LF-STATE-MODEL / STATE_MODEL_POLICY

Inventory status: `ACTIVE_TRANSVERSAL_POLICY`.

Este README cubre `POL-LF-STATE-MODEL` y el alias/capability `STATE_MODEL_POLICY`.

## Propósito

Define el modelo canónico de estados de lifecycle. Separa lifecycle de visibilidad, runtime mode e impact policy para evitar inferir estado desde campos de compatibilidad.

## Cuándo consumirlo

En cualquier decisión que lea o cambie estado de operaciones, strategies u otros assets gobernados por Router.

## Cómo consumirlo

Resolver la policy activa, usar `lf_ops.estados_catalogo` como catálogo canónico y `lf_ops.estados_transiciones` para transiciones. Los campos legacy sólo sirven como compatibilidad/proyección.

## Superficies canónicas

- Policy: `public.lf_policy_versions.policy_code=POL-LF-STATE-MODEL`
- Catálogo: `lf_ops.estados_catalogo`
- Transiciones: `lf_ops.estados_transiciones`
- Alias legacy: `public.cat_estado_normalizacion_lf`

## Fail-closed / límites

Un estado desconocido bloquea la acción. `SANDBOX`, `READ_ONLY`, visibilidad o impact policy no son estados de lifecycle.

## Validación y readback

Verificar version/SHA activos y que el estado/transición exista en catálogos canónicos. Los aliases de inventario deben resolver a este mismo README.

## No duplicación

No crear otro state machine ni otra policy bajo `STATE_MODEL_POLICY`; ese código es alias de inventario.

## Currentness

Releer policy, catálogo y transición vigentes antes de decidir o persistir un cambio de estado.
