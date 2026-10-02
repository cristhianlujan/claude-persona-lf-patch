# ASSURANCE_EVALUATOR_BOUNDARY_V1

## Estado

`ASSURANCE_EVALUATOR` queda definido como **CANDIDATE_DORMANT_NO_ACTIVE_BINDING**.

Readback live 2026-09-28:

- `lf_assurance_claim_catalog`: 36 total / 0 ACTIVE / 36 CANDIDATO;
- `lf_assurance_obligation_catalog`: 48 total / 0 ACTIVE / 48 CANDIDATO;
- `lf_assurance_defeater_catalog`: 34 total / 0 ACTIVE / 34 CANDIDATO;
- `lf_assurance_subject_bindings`: 4 total / 0 ACTIVE / 4 CANDIDATO;
- `lf_assurance_evaluations`: store append-only existente;
- no existe un evaluator live; sólo existe `lf_assurance_reject_mutation_v1` para proteger inmutabilidad.

Por lo tanto **no se activa un evaluator en el PASE normal**. Mientras no exista un binding exacto `ACTIVE`, Assurance evaluator es `NOT_APPLICABLE`.

## Punto de entrada transversal obligatorio

`ASSURANCE_EVALUATOR` no implementa un guard propio. Reutiliza el contrato compartido ya usado por las capabilities transversales:

```text
CALLER
  |
  v
ORCHESTRATOR DISPATCH
  |
  v
ORCHESTRATOR_EXECUTION_GUARD_V1
  |
  +-- dispatch receipt ausente/inválido -> BLOCK
  +-- orchestrator no operacional -> BLOCK
  +-- capability/consumer/plan_digest mismatch -> BLOCK
  |
  v
public.fn_lf_capability_bind_from_orchestrator_v1
  |
  v
ASSURANCE_EVALUATOR currentness
  |
  +-- sin current pointer -> BLOCK_NO_CURRENT_CAPABILITY
  |
  v
ASSURANCE_ACTIVATION_GATE_V1
```

Reglas:

- owner administrativo de la capability: `SUPER_ADMIN`;
- nuevas entradas directas por `public.fn_lf_capability_bind_current_v1` deben bloquearse;
- la capability no hardcodea un operation code de orquestador;
- `ORCHESTRATOR_EXECUTION_GUARD_V1` resuelve dinámicamente una operación `operation_family='ORCHESTRATION'` en lifecycle operacional;
- el dispatch receipt queda cross-bound a `orchestrator_execution_id`, `consumer_execution_id`, `capability_code` y `plan_digest`;
- este guard responde solamente **de dónde viene la ejecución**; no sustituye Router ni `ASSURANCE_ACTIVATION_GATE_V1`;
- `ASSURANCE_ACTIVATION_GATE_V1` sigue respondiendo **si Assurance aplica y existe exactamente un binding ACTIVE exacto**;
- registrar la capability sin current pointer no activa el evaluator: el guarded caller debe fallar cerrado con `BLOCK_NO_CURRENT_CAPABILITY` hasta la promoción funcional separada.

Source projection del primer cutover:

- `sandbox/lf_contract_gate_test/assurance_evaluator_boundary/ASSURANCE_EVALUATOR_registry_entry_guard_v1.sql`.

Ese lote registra `ASSURANCE_EVALUATOR` en `public.lf_capability_registry` con `owner_scope=SUPER_ADMIN`, `entry_guard_required=true` y `entry_guard_code=ORCHESTRATOR_EXECUTION_GUARD_V1`, pero deliberadamente no crea versión ni `lf_capability_current`.

## Contrato canónico de invocación

La forma de llamar `ASSURANCE_EVALUATOR` no se infiere por nombre ni por workflow. El contrato machine-readable es `assurance_evaluator_call_contract_v1.json`.

Secuencia obligatoria:

```text
Router / Changeset Governance
  -> public.fn_lf_orchestrator_dispatch_receipt_v1(...)
  -> ORCHESTRATOR_EXECUTION_GUARD_V1
  -> public.fn_lf_capability_bind_from_orchestrator_v1(
       execution_id,
       'ASSURANCE_EVALUATOR',
       expected_manifest_sha256,
       plan_digest,
       dispatch_receipt_id,
       actor_execution_id
     )
  -> ASSURANCE_ACTIVATION_GATE_V1
  -> assurance_evaluator_runner_v1.py
```

Para una **entrada nueva** está prohibido usar `public.fn_lf_capability_bind_current_v1(...)` como atajo. El resultado esperado es `BLOCK_ORCHESTRATOR_ENTRY_GUARD_REQUIRED`. Mientras no exista `lf_capability_current` para `ASSURANCE_EVALUATOR`, incluso una llamada válida del Orquestador debe terminar en `BLOCK_NO_CURRENT_CAPABILITY`; eso es el estado fail-closed esperado y no un error de wiring.

El inventario canónico debe proyectar además el activo `ASSURANCE_EVALUATOR`, su gobierno por `ACT-0001`, su dependencia de `CURRENTNESS_AUTHORITY` y su relación de linaje con `ASSURANCE_COMPLETENESS` retirado.

## Responsabilidad única

Cuando exista un binding activo y Router determine aplicabilidad, el evaluator transversal responde solamente:

> ¿La evidencia de la revisión exacta demuestra el claim material aplicable y cierra sus defeaters obligatorios?

Cadena semántica única:

`binding exacto -> claim -> obligations -> evidencia de revisión exacta -> defeaters -> resultado derivado`

Resultados permitidos:

- `PASS`
- `FAIL`
- `OPEN`
- `UNPROVEN`
- `FALSE_PASS_RISK`
- `NOT_APPLICABLE`

Una regla/closure shape no soportada mecánicamente produce `UNPROVEN`; nunca se interpreta por aproximación para fabricar PASS.

## Autoridades que reutiliza

No crea stores, matrices, routers ni jueces paralelos. Reutiliza:

- `public.lf_assurance_claim_catalog`;
- `public.lf_assurance_obligation_catalog`;
- `public.lf_assurance_defeater_catalog`;
- `public.lf_assurance_subject_bindings`;
- `public.lf_assurance_evaluations`;
- LF Test Matrix (`lf_test_suites`, `lf_test_suite_cases`, `lf_test_runs`, assertions/artifacts);
- `INDEPENDENT_REVIEW` / `INDEPENDENT_HOLDOUT` como tipos canónicos de review nuevo.

`S36_ASSURANCE` puede existir únicamente como evidencia histórica persistida y explícitamente compatible. Nunca vuelve a ser un valor de escritura nuevo ni un owner.

## Aplicabilidad y cierre

- **Router / Changeset Governance** decide si Assurance aplica.
- Assurance evaluator **no descubre aplicabilidad** y no lanza controles.
- **Closure** decide si el PASE puede finalizar y consume receipts requeridos.
- Assurance evaluator no sustituye Closure ni cuenta controles verdes como PASS global.

Normal PASE sin binding activo:

`Router -> Assurance N/A -> no evaluator execution`

PASE con claim material y binding activo:

`Router -> exact binding -> evaluator mínimo -> typed result/receipt -> Closure`

## Gate mecánico de activación

`ASSURANCE_ACTIVATION_GATE_V1` formaliza la entrada al evaluator sin convertirse en un segundo Router.

Autoridades:

- aplicabilidad: `CHANGESET_GOVERNANCE_LF_V1`;
- bindings: `public.lf_assurance_subject_bindings`;
- consumidor eventual: `ASSURANCE_EVALUATOR`.

Regla determinista:

`Router applicable=true + subject_type exacto + subject_code exacto + subject_revision + exactamente 1 binding ACTIVE exacto -> READY_FOR_ASSURANCE_EVALUATOR`.

Cualquier otra situación queda tipada:

- Router declara N/A -> `NOT_APPLICABLE_NO_EXECUTION`;
- 0 binding `ACTIVE` exactos -> `NOT_APPLICABLE_NO_EXECUTION`;
- binding `CANDIDATO` -> nunca ejecuta;
- binding `ACTIVE` con `subject_code='*'` -> `BLOCKED_NON_EXACT_ACTIVE_BINDING`;
- más de un binding `ACTIVE` exacto -> `BLOCKED_AMBIGUOUS_ACTIVE_BINDING`;
- autoridad, subject o revision inválidos -> `BLOCKED`.

El gate no consulta Supabase, no ejecuta el evaluator, no modifica Router, no activa runtime/producción y no crea bindings. Recibe como input un readback del binding authority y devuelve únicamente una decisión determinista.

Readback live 2026-09-30: `lf_assurance_subject_bindings` = **4 total / 0 ACTIVE / 4 CANDIDATO**. Por tanto el estado real sigue siendo `NOT_APPLICABLE_NO_EXECUTION` para cualquier PASE normal.

## Qué se conserva de PR #879

Se conserva únicamente la semántica útil:

- exact-revision evidence;
- claim -> obligation -> evidence -> defeater;
- false-PASS detection;
- unsupported evidence/rules -> `UNPROVEN`;
- negative/adversarial evidence para cerrar defeaters;
- reutilización de `lf_assurance_evaluations` y LF Test Matrix.

El paquete #879 **no se integra** porque mezcla el evaluator con workflows, deployment-close, cambios de Migration Parity y semántica legacy `S36_ASSURANCE` ya retirada.

## No responsabilidades

`ASSURANCE_EVALUATOR` no posee:

- applicability/routing;
- Contract Check;
- Migration Parity;
- Pack Validation;
- Runtime;
- DB Regression;
- Operation Test Coverage;
- Test Coverage Debt Guard;
- Independent Review;
- Qualification;
- Card/lifecycle/security domain controls;
- workflow/deployment;
- migration transport/parity;
- production/runtime activation;
- final PASE Closure.

## Condiciones antes de una futura activación

1. entrada válida por `ORCHESTRATOR_EXECUTION_GUARD_V1`;
2. binding exacto `ACTIVE`;
3. Router determina que el claim aplica;
4. source/currentness exactos;
5. canonical owners intactos;
6. review nuevo usa `INDEPENDENT_REVIEW`/`INDEPENDENT_HOLDOUT`;
7. no existe otro evaluator activo;
8. regresión fail-closed demuestra `UNPROVEN` ante evidencia parcial/unsupported;
9. activation/cutover se hace en un lote posterior explícito, no por nombre de metodología.

## EKB

- `ASSURANCE-EVALUATOR-LEGACY-S36-REINTRODUCTION-RISK-001`
- `ASSURANCE-METHOD-CANDIDATE-NOT-PASE-CONTROL-001`
- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `ASSURANCE-ORCHESTRATOR-ENTRYPOINT-GAP-001`

## Provider-bound Independent Review readback

`ASSURANCE_EVALUATOR` no debe tratar un `judge_result_id` tipado como prueba material. El adaptador gobernado candidato es `public.fn_lf_assurance_independent_review_provider_readback_v1(...)`, documentado por `assurance_independent_review_provider_readback_contract_v1.json`.

La secuencia material esperada es:

```text
INDEPENDENT_REVIEW
  -> public.lf_test_judge_results
  -> LF_SUPABASE_READBACK_V1
  -> EVIDENCE_LEDGER + EVIDENCE_ANTIREPLAY
  -> fn_lf_assurance_independent_review_provider_readback_v1(...)
  -> VERIFIED_PROVIDER_BOUND
  -> ASSURANCE_EVALUATOR semantic core
```

El adaptador es **read-only respecto de evidencia/judges**: recomputa el digest de la fila del judge dentro de Supabase y exige un receipt `VERIFIED` del Evidence Ledger cross-bound a la misma ejecución Assurance, obligación, judge, reviewer, revisión y source head. No puede crear el receipt, ejecutar Independent Review, decidir Assurance, promover `CURRENT` ni activar bindings. Mientras `EVIDENCE_LEDGER` y `EVIDENCE_ANTIREPLAY` no estén `CURRENT`, el resultado esperado es `BLOCK_ASSURANCE_REVIEW_PROVIDER_DEPENDENCY_NOT_CURRENT`.
