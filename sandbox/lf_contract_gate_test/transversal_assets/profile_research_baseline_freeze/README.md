# PROFILE_RESEARCH_BASELINE_FREEZE

Inventory status: `CANDIDATE_PENDING_QUALIFICATION`.

## Propósito

Capability transversal de `EJECUCION_PERFIL_LF` que materializa una identidad externa e inmutable del baseline de solución **antes** de entrar a investigación/challenger. Evita que un perfil pueda investigar primero y reconstruir retrospectivamente su propio BEFORE.

Cadena: `context_admission -> research_baseline_freeze -> execute_profile`.

## Aplicabilidad

La decide el servidor desde `public.lf_activos.metadata.research_baseline_mode`; el caller no puede activarla ni desactivarla. Modos: `NOT_REQUIRED` y `PRE_RESEARCH_ALWAYS`. El default es `NOT_REQUIRED`, por lo que perfiles existentes no pagan una fase/model call adicional.

## Contrato de freeze

Cuando aplica, el perfil declara en su asset un contrato PROFILE_RESEARCH_BASELINE_BINDING_V1 con capture_stage, snapshot_schema, output_snapshot_path, output_digest_path y profile_validator_binding=PROFILE_OUTPUT_VALIDATOR_BOUND_V1. El runtime no conoce el vocabulario interno del perfil; el schema del snapshot también pertenece al asset del perfil.

El asset puede declarar snapshot_binding_paths para campos internos del snapshot que no deben ser inventados por el modelo. Las fuentes permitidas son input_digest, profile_source_digest, evidence_refs y capture_stage; cada una apunta a una ruta JSON arbitraria del snapshot. El runtime elimina esas hojas del schema de generación, las inyecta determinísticamente antes de validar/hash y el servidor vuelve a comprobarlas antes de persistir.

El productor entrega un envelope genérico con snapshot opaco, baseline_digest, capture_stage, input_digest, profile_source_digest y evidence_refs. El servidor valida identidad/orden temporal, bloquea evidencia externa antes del freeze y verifica el baseline_digest con la primitiva transversal private.fn_payload_sha256_v7 antes de persistir. También conserva un server_snapshot_fingerprint independiente basado en jsonb::text para readback; ese fingerprint no sustituye el digest canónico.

El step limpio queda en public.lf_operation_execution_steps; el recorder canónico impide reemplazarlo con evidencia distinta. En execute_profile, el server usa las rutas declarativas del asset para extraer snapshot/digest del output y compararlos con lo congelado. La corrección del digest canónico sigue siendo responsabilidad del output validator enlazado del perfil.

## No duplicación

No crea otro agente, judge, tabla ni autoridad. Reutiliza `EJECUCION_PERFIL_LF`, `lf_operation_execution_steps`, `lf_record_operation_step_core_v1` y el semantic judge existente. La fase de baseline usa el mismo runtime/model seleccionado para la ejecución del perfil; sólo cambia el orden y la evidencia persistida.

## Cableado runtime

El consumidor operativo es el worker Hetzner existente. Cada queue request materializa/reanuda la misma EJECUCION_PERFIL_LF antes del primer model call, registra context_admission, ejecuta el handshake research_baseline_freeze y sólo después despacha el endpoint principal. Si requiere baseline, usa /v1/profile/research-baseline con el mismo runtime/model persistente. El worker registra execute_profile y output_validate en la misma ejecución; semantic_judge no se auto-certifica.

Los steps previos al modelo tienen resolver determinista explícito. Sólo execute_profile delega al modelo seleccionado; output_validate vuelve al validator enlazado y semantic_judge conserva su autoridad separada.

## Dispatch determinista

La primera llamada al step siempre es server-side con baseline_envelope=null. Si el asset indica NOT_REQUIRED, la función materializa N/A y termina sin llamada de modelo. Si indica PRE_RESEARCH_ALWAYS, devuelve BASELINE_REQUIRED sin cerrar el step; sólo entonces se invoca el mismo runtime/model seleccionado para producir el envelope compacto y se reintenta el mismo step.

## Performance/context

Perfiles `NOT_REQUIRED` cierran el step como N/A de forma server-side y no generan baseline por modelo. En perfiles opt-in se transporta sólo snapshot compacto + digest + ref; la investigación completa sigue JIT por referencia.

## Readback

Verificar: step `research_baseline_freeze` limpio, `baseline_receipt_ref` exacto, digest persistido, igualdad entre el output resuelto por output_snapshot_path/output_digest_path y el baseline persistido, y ausencia de evidencia externa dentro del baseline.

## Compatibilidad de ejecuciones en vuelo

La política queda snapshotteada al crear cada ejecución. Durante la migración, ejecuciones antiguas IN_PROGRESS que ya pasaron context_admission y no conocían este control se materializan como NOT_REQUIRED mediante la misma función canónica; no se inventa un baseline requerido retroactivo. Si una ejecución preexistente ya declara PRE_RESEARCH_ALWAYS, la migración falla y exige resolverla antes del corte. Ejecuciones COMPLETED no se reescriben.

## Aplicación gobernada

La migración sólo reconoce como actor una ejecución de actualización runtime con production_apply_authorized=true. Los intentos source-only o bloqueados no pueden aplicar el cambio live.

## Rollback

Primero retirar el opt-in del perfil por reconciliación gobernada; luego revertir el step/runtime. No reescribir ejecuciones históricas.

## Fuente

- Contract: `sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json`
- Contract SHA-256: 4d2de745272a3d5b746deab20de182dc560798d031388aa7d7086de411537f35
- Operation: `public.lf_operation_registry/EJECUCION_PERFIL_LF`
- Durable evidence: `public.lf_operation_execution_steps`
