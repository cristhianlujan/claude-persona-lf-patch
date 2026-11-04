# D11 — Autoridad de operaciones LF para PIP-1 (Paulo)

**Fuente:** Supabase RO, `public.lf_operation_registry`, consulta del 31/10/2026. **Estado:** investigativo, sin autorización para ejecución PIP-1.

| Código | Versión | Estado | Ciclo de vida | Tipo |
|---|---|---|---|---|
| `ORQUESTACION_PIPELINE_LF` | `v0.1` | `APROBADO_PRODUCCION_CONTROLADA` | `OP_OPERATIONAL` | `SCHEDULER_DRIVEN` |
| `CIERRE_CHECKPOINT_INGENIERIA_LF` | `v1.0-candidate` | `CANDIDATO_READ_ONLY` | `OP_CANDIDATE` | `CONTROLLED_ADMINISTRATIVE_TRANSITION` |

## Dictamen

1. La operación de **orquestación general** está registrada como operacional, pero **no existe prueba de que admita el RunContract PIP-1** ni de que los 159 registros anteriores le pertenezcan.
2. La operación de **cierre de checkpoints** continúa `OP_CANDIDATE`: **NO puede asumirse como servicio de cierre autorizado**.
3. El módulo `pip1_operation_preflight.py` del PR #3402 es un **ensayo de forma sintética**, no un contrato aprobado. Sus fixtures usan un código de operación de cierre que no debe promoverse a runtime.
4. `pip1_core` mantiene `operational=True` cerrado y carece de registro de un run PIP-1 persistido/acreditado.
5. La decisión sobre el código de operación, writer y recibo pertenece a la gobernanza y al dueño del Carril D; no inferirla desde el chat.

## Próximo test obligatorio

Antes de integración: casos negativos de cruce de `run_id`, `execution_id`, HEAD, digest de inventario, proveedor y reutilización de recibo; revisión independiente. Las pruebas de forma pueden ejecutarse hoy, **sin conceder autoridad**.

## Prohibiciones

Sin SQL de escritura, sin `DONE`, sin migraciones, sin promoción de `CIERRE_CHECKPOINT_INGENIERIA_LF`, sin operación de router ni merge automático.
