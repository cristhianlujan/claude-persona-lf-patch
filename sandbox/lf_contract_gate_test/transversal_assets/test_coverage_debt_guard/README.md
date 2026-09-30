# TEST_COVERAGE_DEBT_GUARD

Capability transversal extraída del histórico `S36_ASSURANCE` umbrella.

## Propósito

Proteger la **deuda global aceptada de cobertura estructural de tests** contra crecimiento durante Full Regression / auditoría.

No es un verdict de Assurance, calidad, ejecución de tests, Qualification ni seguridad del changeset.

## Contrato ejecutable

Runner canónico source:

- `test_coverage_debt_guard_v1.py`

Carrier histórico conservado solo por compatibilidad:

- `sandbox/lf_contract_gate_test/s36_wp06_ci_completeness_gate.py`

El carrier delega íntegramente al runner canónico y ya no contiene el query ni emite semántica de Assurance Completeness.

Resultados permitidos:

- `DEBT_STABLE`
- `DEBT_GROWTH_BLOCKED`

`DEBT_STABLE` significa únicamente:

`ACCEPTED_TEST_COVERAGE_DEBT_NOT_GROWING`

No significa:

- Assurance PASS;
- Assurance completeness PASS;
- todas las operaciones cubiertas;
- tests ejecutados o aprobados;
- calidad semántica aprobada;
- Independent Review aprobada;
- Qualification aprobada/current;
- changeset seguro.

Los resultados siempre mantienen `material_assurance_pass=false`, `material_test_pass=false` y `material_qualification_pass=false`.

## Inputs

El guard reutiliza, sin duplicar:

- `public.lf_s36_operation_assurance_coverage_v1()` como provider estructural legacy;
- `lf_strategy_snapshots.id=61 -> test_assurance_coverage_ci.accepted_debt_baseline` como baseline aceptado;
- el universo operacional del provider.

No crea otro coverage engine, test matrix, baseline store ni applicability router.

## Aplicabilidad

Owner objetivo: `FULL_REGRESSION`.

Aplica únicamente a:

- Full Regression explícito;
- auditoría/reconciliación global de deuda de cobertura;
- validación controlada de cutover/migración del baseline.

No aplica a PASE ordinario por el simple hecho de existir un changeset.

## Clases de deuda preservadas

- `NEW_REQUIRED_OPERATION_DEBT`
- `LIVE_BLOCKED`
- `ACCEPTED_DEBT_STATE_CHANGED_WITHOUT_COVERAGE`
- `BINDING_ACTIVITY_WITHOUT_COVERAGE`
- `NEW_RUN_ACTIVITY_WITHOUT_COVERAGE`

Estas clases describen crecimiento/cambio de deuda. Ninguna es un verdict de calidad o Assurance.

## Legacy SQL aggregate

`public.lf_s36_assurance_completeness_v1(boolean)` permanece como artefacto SQL histórico. No es autoridad del nuevo owner y no puede registrarse como nuevo consumer. La implementación ejecutable source del guard ya no lo llama.

El provider estructural `public.lf_s36_operation_assurance_coverage_v1()` sí se reutiliza porque contiene el cálculo estructural que corresponde a `OPERATION_TEST_COVERAGE`.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `TEST-COVERAGE-DEBT-GUARD-SEMANTIC-OVERCLAIM-001`

## Seguridad

Este cambio no crea objetos DB, workflows, routers, registries, writers, coverage engines, baseline stores ni activación runtime/producción. El runner ejecuta una consulta read-only y clasifica únicamente deuda global.
