# PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1

Puente source-only para conectar un orquestador gobernado con el runtime de perfiles existente sin crear otra operación, queue ni runtime.

## Problema resuelto

El `Task Packet` final exige `dispatch_receipt_ref` y `ORCHESTRATOR_ENTRY_ACCEPTED`, pero `fn_lf_orchestrator_dispatch_receipt_v1` sólo puede emitir un receipt cuando el consumer execution ya existe y está `IN_PROGRESS`. Por tanto, reservar el child usando el Task Packet final forma una circularidad de autoridad.

El bridge separa **trabajo estático** de **autoridad dinámica de ejecución**.

## Protocolo de dos fases

```text
Task Packet seed
(sin receipt/guard)
        |
        v
task_packet_work_digest
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
readback ORCHESTRATOR_ENTRY_ACCEPTED
        |
        v
Task Packet final
(receipt + guard reales)
        |
        v
verificar proyección estática == work digest
        |
        v
queue/runtime de perfiles existente
```

## Fase 1 — seed estático

El seed puede contener sólo la identidad lógica del worker resuelto:

- `resolution_mode`;
- `worker_ref`;
- `worker_kind`;
- `binding_authority_ref`;
- `binding_revision`;
- `binding_digest`.

Antes del dispatch están prohibidos:

- `orchestrator_execution_id` dentro del binding;
- `dispatch_receipt_ref`;
- `entry_guard_code`;
- `entry_guard_decision`.

De ese seed se deriva `task_packet_work_digest`. El child `EJECUCION_PERFIL_LF` queda cross-bound a ese digest, al orquestador, al `plan_digest`, a `PROFILE_EXECUTION_RUNTIME`, a la revisión fuente y al digest del Profile.

## Fase 2 — autoridad dinámica

Sólo después del readback real del receipt y del entry guard se agregan al Task Packet:

- `orchestrator_execution_id`;
- `dispatch_receipt_ref` con `receipt_id` y SHA-256;
- `entry_guard_code=ORCHESTRATOR_EXECUTION_GUARD_V1`;
- `entry_guard_decision=ORCHESTRATOR_ENTRY_ACCEPTED`.

El bridge vuelve a quitar esos cuatro campos y exige que el digest resultante sea exactamente el `task_packet_work_digest` original. Cualquier drift bloquea.

## Reutilización

Se reutilizan sin reemplazo:

- `EJECUCION_PERFIL_LF`;
- `public.lf_profile_execution_begin_v1`;
- `public.fn_lf_orchestrator_dispatch_receipt_v1`;
- `public.fn_lf_capability_bind_from_orchestrator_v1`;
- `private.lf_profile_runtime_queue_v1`;
- `ACT-0001`;
- `CURRENTNESS_AUTHORITY`.

## Boundary

Este paquete construye/valida el protocolo y no llama SQL, no encola trabajo, no registra `PROFILE_EXECUTION_RUNTIME`, no activa runtime/producción y no modifica PASE/POST-PASE.

El worker compartido aún debe incorporar, en otro PR, un modo explícito `attach_existing_child_execution=true` para no intentar un segundo `begin`. La compatibilidad de Profiles embebidos bajo `skills/.../perfiles/` también se resuelve en soluciones separadas.
