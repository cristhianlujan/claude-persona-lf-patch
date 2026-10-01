# PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1

Puente source-only para conectar un orquestador gobernado con el runtime de perfiles ya existente, sin crear otra operación ni otra queue.

## Problema que resuelve

`ORCHESTRATOR_EXECUTION_GUARD_V1` exige un consumer execution activo antes de emitir el dispatch receipt. El runtime de perfiles actual crea `EJECUCION_PERFIL_LF` dentro del queue worker, demasiado tarde para que un Task Packet gobernado llegue al worker con receipt ya autenticado.

Este bridge fija el orden correcto:

```text
resolver worker PROFILE
        |
        v
lf_profile_execution_begin_v1
        |
        v
fn_lf_orchestrator_dispatch_receipt_v1
        |
        v
fn_lf_capability_bind_from_orchestrator_v1
        |
        v
private.lf_profile_runtime_queue_v1
        |
        v
runtime existente (replay de begin, no segunda ejecución)
```

## Capability lógica

El receipt transversal es capability-scoped. Por ello el bridge usa `PROFILE_EXECUTION_RUNTIME` como identidad lógica de la lane existente `EJECUCION_PERFIL_LF`. Esta identidad no crea un segundo runtime; su eventual registro/cutover es otro lote y sigue bloqueado en este PR.

## Idempotencia

El `request_id` UUID determina exactamente:

- consumer execution: `EXEC-PROFILE-RUNTIME-<request_id>`;
- idempotency key: `profile-runtime-queue:<request_id>`.

Esto coincide con la identidad que usa el worker Hetzner actual. Si el child execution fue creado por el orquestador primero, el worker debe obtener `REPLAY_EXISTING_EXECUTION`, conservar el manifest cross-bound y continuar sobre la misma ejecución.

## Boundary

Este paquete sólo construye y valida el plan. No llama SQL, no inserta queue rows, no registra `PROFILE_EXECUTION_RUNTIME`, no habilita runtime/producción y no modifica PASE/POST-PASE.

La materialización posterior debe verificar además que la fuente del profile sea aceptada por el runtime. Los Story Creator profiles siguen residiendo bajo `skills/creating-integral-user-stories/perfiles/`, mientras el runtime actual exige `profiles/<profile_slug>/`; este PR no oculta ni resuelve ese gap.
