# PROFILE_RESEARCH_BASELINE_FREEZE

Inventory status: `CANDIDATE_PENDING_QUALIFICATION`.

## Propósito

Capability transversal de `EJECUCION_PERFIL_LF` que materializa una identidad externa e inmutable del baseline de solución **antes** de entrar a investigación/challenger. Evita que un perfil pueda investigar primero y reconstruir retrospectivamente su propio BEFORE.

Cadena: `context_admission -> research_baseline_freeze -> execute_profile`.

## Aplicabilidad

La decide el servidor desde `public.lf_activos.metadata.research_baseline_mode`; el caller no puede activarla ni desactivarla. Modos: `NOT_REQUIRED` y `PRE_RESEARCH_ALWAYS`. El default es `NOT_REQUIRED`, por lo que perfiles existentes no pagan una fase/model call adicional.

## Contrato de freeze

Cuando aplica, el perfil declara en su asset un contrato PROFILE_RESEARCH_BASELINE_BINDING_V1 con capture_stage, output_snapshot_path, output_digest_path y profile_validator_binding=PROFILE_OUTPUT_VALIDATOR_BOUND_V1. El runtime no conoce el vocabulario interno del perfil.

El productor entrega un envelope genérico con snapshot opaco, baseline_digest, capture_stage, input_digest, profile_source_digest y evidence_refs. El servidor valida identidad/orden temporal, bloquea evidencia externa antes del freeze y persiste un server_snapshot_fingerprint independiente. Ese fingerprint no sustituye el digest canónico del perfil.

El step limpio queda en public.lf_operation_execution_steps; el recorder canónico impide reemplazarlo con evidencia distinta. En execute_profile, el server usa las rutas declarativas del asset para extraer snapshot/digest del output y compararlos con lo congelado. La corrección del digest canónico sigue siendo responsabilidad del output validator enlazado del perfil.

## No duplicación

No crea otro agente, judge, tabla ni autoridad. Reutiliza `EJECUCION_PERFIL_LF`, `lf_operation_execution_steps`, `lf_record_operation_step_core_v1` y el semantic judge existente. La fase de baseline usa el mismo runtime/model seleccionado para la ejecución del perfil; sólo cambia el orden y la evidencia persistida.

## Performance/context

Perfiles `NOT_REQUIRED` cierran el step como N/A de forma server-side y no generan baseline por modelo. En perfiles opt-in se transporta sólo snapshot compacto + digest + ref; la investigación completa sigue JIT por referencia.

## Readback

Verificar: step `research_baseline_freeze` limpio, `baseline_receipt_ref` exacto, digest persistido, igualdad entre el output resuelto por output_snapshot_path/output_digest_path y el baseline persistido, y ausencia de evidencia externa dentro del baseline.

## Aplicación gobernada

La migración sólo reconoce como actor una ejecución de actualización runtime con production_apply_authorized=true. Los intentos source-only o bloqueados no pueden aplicar el cambio live.

## Rollback

Primero retirar el opt-in del perfil por reconciliación gobernada; luego revertir el step/runtime. No reescribir ejecuciones históricas.

## Fuente

- Contract: `sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json`
- Contract SHA-256: 30ff1918b724847551cd32719b89936aac34ee1f2d1d951adaf191796c912160
- Operation: `public.lf_operation_registry/EJECUCION_PERFIL_LF`
- Durable evidence: `public.lf_operation_execution_steps`
