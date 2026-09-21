# PROFILE_RESEARCH_BASELINE_FREEZE

Inventory status: `CANDIDATE_PENDING_QUALIFICATION`.

## Propósito

Capability transversal de `EJECUCION_PERFIL_LF` que materializa una identidad externa e inmutable del baseline de solución **antes** de entrar a investigación/challenger. Evita que un perfil pueda investigar primero y reconstruir retrospectivamente su propio BEFORE.

Cadena: `context_admission -> research_baseline_freeze -> execute_profile`.

## Aplicabilidad

La decide el servidor desde `public.lf_activos.metadata.research_baseline_mode`; el caller no puede activarla ni desactivarla. Modos: `NOT_REQUIRED` y `PRE_RESEARCH_ALWAYS`. El default es `NOT_REQUIRED`, por lo que perfiles existentes no pagan una fase/model call adicional.

## Contrato de freeze

Cuando aplica, el perfil debe declarar `research_baseline_contract=PROFILE_OUTPUT_VALIDATOR_BOUND_V1`. El baseline usa `capture_stage=PRE_RESEARCH_CHALLENGER`, queda ligado al digest del input y a la revisión exacta de fuente, y referencia sólo evidencia interna disponible antes de research. Se rechazan refs `http://`, `https://`, `external://` y `web://` dentro del baseline congelado.

El step limpio queda en `public.lf_operation_execution_steps`; el recorder canónico impide reemplazarlo con evidencia distinta. Se persisten el snapshot exacto, el digest canónico declarado y un `server_snapshot_fingerprint` independiente. El runtime **no reimplementa** la canonicalización del perfil: `execute_profile` debe transportar `research_baseline_ref` + `research_baseline_digest`, el server compara el snapshot/digest final contra lo persistido y el output validator del perfil verifica que el digest canónico corresponda al snapshot.

## No duplicación

No crea otro agente, judge, tabla ni autoridad. Reutiliza `EJECUCION_PERFIL_LF`, `lf_operation_execution_steps`, `lf_record_operation_step_core_v1` y el semantic judge existente. La fase de baseline usa el mismo runtime/model seleccionado para la ejecución del perfil; sólo cambia el orden y la evidencia persistida.

## Performance/context

Perfiles `NOT_REQUIRED` cierran el step como N/A de forma server-side y no generan baseline por modelo. En perfiles opt-in se transporta sólo snapshot compacto + digest + ref; la investigación completa sigue JIT por referencia.

## Readback

Verificar: step `research_baseline_freeze` limpio, `baseline_receipt_ref` exacto, digest persistido, igualdad con `profile_output.research_assurance.baseline_solution_snapshot/baseline_digest`, y ausencia de evidencia externa dentro del baseline.

## Rollback

Primero retirar el opt-in del perfil por reconciliación gobernada; luego revertir el step/runtime. No reescribir ejecuciones históricas.

## Fuente

- Contract: `sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json`
- Contract SHA-256: `df9a62eedf7168fad10f71af9f7026a1300396b506fd498a6563a21e7140702b`
- Operation: `public.lf_operation_registry/EJECUCION_PERFIL_LF`
- Durable evidence: `public.lf_operation_execution_steps`
