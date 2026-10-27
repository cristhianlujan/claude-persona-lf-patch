# PE10A_SB06 — La readiness respeta las dependencias entre work items

Fecha: 2026-10-27 · Migración: `lf_pe10_readiness_work_item_dependency_gate_v1` · Estado: propuesta en PR, **no aplicada**. v0.2 NO está activo.

## Corrección a la revisión inicial (hallazgo A1)
Lectura de producción (solo lectura, 2026-10-27):
- `fn_engineering_checkpoint_execution_readiness_v1` devuelve `READY` / `reasons: []` para `PE10_C6` y `PE10_C7` mientras `PEVO-PE10A_READY` está en BACKLOG.
- Pero `fn_engineering_unit_bootstrap_v3('…','PE10')` ya devuelve `terminal_action = WAIT_DEPENDENCIES`, y `fn_engineering_checkpoint_close_governed_v1` exige `CONTINUE_CURRENT_CHECKPOINT`.
- Conclusión: el **cierre gobernado ya se rechazaba**. La brecha es de consistencia: la readiness informa lo contrario que el bootstrap (afecta a quien lea solo la readiness, p. ej. `fn_engineering_plan_execution_preflight_v1`). No es un bypass del cierre gobernado. `fn_engineering_checkpoint_transition_v1` llamada directamente no consulta dependencias (no se modifica aquí).

## Cambio
Una sola función reemplazada: `programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1`.
Si el checkpoint está abierto y su work item tiene dependencias sin cumplir (`fn_engineering_effective_dependencies_v1`, misma regla que usa `transition_v1`): `status=NOT_READY`, `execution_ready=false`, razón `WORK_ITEM_DEPENDENCY_UNMET`, gate `DEPENDENCIES_SATISFIED=false` y detalle `dependencies`. Los gates `COMPILE_READY`, `ACTION_EXACT`, `ERROR_CLOSED` no se tocan (los reparadores solo miran esos). En cualquier otro caso la salida es idéntica a la actual.
La migración verifica antes: ejecución del Train, hash `md5(prosrc)` de la función vigente y de la de dependencias (deriva), existencia de `from_context_v1`; y después: marcador en el código, volatilidad, `SECURITY DEFINER` y ACL sin cambios.

## Impacto medido en producción (solo lectura)
Sobre los 275 checkpoints PENDING de todos los planes, solo 59 pertenecen a work items con dependencias sin cumplir, **todos del plan PE10** (9 work items). De esos, hoy únicamente **`PE10_C6` y `PE10_C7`** salen `READY`; los otros 57 ya son `NOT_READY`. Ningún otro plan cambia.

## Pruebas ejecutadas (réplica local PostgreSQL 16; `pe10_sb06_tests/run_tests.sh`)
31 pruebas, 0 fallos: función cambiada; ACL conservada; filas cambiadas == abiertos con dependencia sin cumplir (calculado aparte); resto idéntico (jsonb igual); DONE de PE10 idénticos; C6/C7 READY→NOT_READY con razón y dependencia nombrada; fusión de razones; dependencia DONE / CANCELLED / IN_PROGRESS / FUSED a destino BACKLOG o DONE; checkpoint ya DONE; unidad inexistente; negativos (sin Train, deriva de la función, reaplicar, deriva de dependencias, falta `from_context`); y 2 controles de mutación que la suite detecta.

**Límites:** las copias de `from_payload_v1` (anterior) y `effective_dependencies_v1` son byte a byte las de producción (mismo `md5(prosrc)`), pero `from_context_v1` es un **stub**; no se replican triggers, ACL ni constraints reales, y la réplica es PostgreSQL 16 (producción 17.6). El efecto real sobre C6/C7 se verificará por readback tras el Train.

## Orden del plan (importante)
`PE10A_SB06` pertenece a `PEVO-PE10A_SUPABASE`, que REQUIERE `PE10A_CONTRACTS`, `PE10A_JUDGES` y `PE10A_PIPELINE`. El bootstrap ya impone ese orden: SB06 **no se puede cerrar** (DONE con recibo) hasta que esas tres estén DONE. Este PR es solo la implementación del cambio; el cierre del checkpoint sigue el orden del plan.
