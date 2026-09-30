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

1. binding exacto `ACTIVE`;
2. Router determina que el claim aplica;
3. source/currentness exactos;
4. canonical owners intactos;
5. review nuevo usa `INDEPENDENT_REVIEW`/`INDEPENDENT_HOLDOUT`;
6. no existe otro evaluator activo;
7. regresión fail-closed demuestra `UNPROVEN` ante evidencia parcial/unsupported;
8. activation/cutover se hace en un lote posterior explícito, no por nombre de metodología.

## EKB

- `ASSURANCE-EVALUATOR-LEGACY-S36-REINTRODUCTION-RISK-001`
- `ASSURANCE-METHOD-CANDIDATE-NOT-PASE-CONTROL-001`
- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
