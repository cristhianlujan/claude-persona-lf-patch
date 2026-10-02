# PROFILE_RUNTIME_ORCHESTRATED_ATTACH_V1

Contrato/validator candidato para que el worker Hetzner existente se **adjunte** a un `EJECUCION_PERFIL_LF` ya reservado por un orquestador gobernado.

## Razón

En modo standalone el worker actual crea el child execution al comenzar. En modo orquestado eso ocurre demasiado tarde: el dispatch receipt exige que el consumer execution exista previamente.

El modo correcto es:

```text
orquestador
  -> reserva child EJECUCION_PERFIL_LF
  -> emite receipt real
  -> obtiene ORCHESTRATOR_ENTRY_ACCEPTED
  -> finaliza Task Packet
  -> encola
  -> worker valida envelope/readbacks
  -> se adjunta al child existente
  -> NO ejecuta un segundo begin
```

## No relaja el modo standalone

Las reglas actuales `profiles/<profile_slug>/` siguen aplicando a Profiles standalone. Un path bajo `skills/...` sólo puede aceptarse cuando:

1. el envelope es `LF_PROFILE_RUNTIME_ORCHESTRATED_REQUEST_V2`;
2. `attach_existing_child_execution=true`;
3. child/receipt/guard están completamente cross-bound;
4. existe `LF_PROFILE_TASK_RUNTIME_BINDING_V1` resuelto;
5. profile code/slug y source revision coinciden exactamente.

## Cross-binding

El validator exige igualdad exacta entre queue/envelope/child/receipt/guard para:

- orchestrator execution;
- consumer execution;
- capability `PROFILE_EXECUTION_RUNTIME`;
- parent plan digest;
- Task Packet work digest;
- final Task Packet digest;
- Profile source digest;
- deployed source revision.

También reconstruye la proyección estática del Task Packet final y exige que sea idéntica al work digest reservado antes del receipt.

## Boundary

Este PR no modifica todavía `hetzner_queue_worker.py` ni `ProfileRuntimeEngine`. No llama DB, no encola, no ejecuta modelos, no crea runtime/queue/operation y no activa producción. Su siguiente consumidor será el wiring compartido en otro PR separado.
