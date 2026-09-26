# OPERATION_TEST_COVERAGE

Capability transversal LF candidata: `OPERATION_TEST_COVERAGE`.

## Estado

- Estado de esta definición: `CANDIDATE_BOUNDARY_ONLY`
- Autoridad live actual: `ASSURANCE_COMPLETENESS` / `public.lf_s36_operation_assurance_coverage_v1()`
- Cutover live: **NO realizado por este cambio**
- Motor paralelo: **prohibido**

## Propósito

Responder una sola pregunta:

> Para una operación gobernada, ¿existe la estructura de cobertura de tests requerida en la matriz canónica LF?

La cobertura estructural comprende únicamente la relación operación → binding requerido → suite existente → casos existentes. Puede exponer conteos de runs observados como diagnóstico, pero **no convierte esos runs en verdict, PASS ni assurance**.

## Semántica

La salida legacy `coverage_state='COVERED'` se interpreta durante la transición exclusivamente como `STRUCTURALLY_COVERED`.

`STRUCTURALLY_COVERED` **NO significa**:

- test ejecutado;
- test PASS;
- evidencia current;
- qualification aprobada;
- independent review aprobado;
- cierre del pase;
- assurance completo.

Una operación con binding + suite + casos y `observed_run_count=0` puede estar estructuralmente cubierta y, al mismo tiempo, no tener ninguna prueba ejecutada.

## Responsabilidad propia

Esta capability puede:

1. enumerar operaciones aplicables que le entregue el plan/consumer;
2. leer `lf_test_requirement_bindings`;
3. leer `lf_test_suites`;
4. leer `lf_test_suite_cases`;
5. leer `lf_test_runs` solo para diagnóstico de evidencia no mapeada/conteo observado;
6. devolver cobertura estructural y gaps.

## Fuera de responsabilidad

Esta capability no debe:

- determinar applicability del changeset;
- ejecutar tests;
- emitir verdict de calidad;
- ejecutar independent review;
- materializar qualification;
- cambiar lifecycle de qualification/test/suite;
- ejecutar Card prepromotion E2E;
- probar lifecycle de activos;
- ejecutar adversarial/security assurance;
- administrar deuda global histórica;
- ejecutar Full Regression;
- escribir runtime, producción o negocio;
- crear otra matriz/store/registry de tests.

## Superficie legacy reutilizada

Hasta un cutover separado y gobernado, la implementación existente que contiene el cálculo útil es:

- `public.lf_s36_operation_assurance_coverage_v1()`
- source: `supabase/migrations/20260914205435_s36_assurance_completeness_engine_v1.sql`

`public.lf_s36_assurance_completeness_v1(boolean)` es un agregador global legacy y no define el contrato del pase normal.

## Relación con otros owners

- `CHANGESET_GOVERNANCE` / Router: decide applicability y entrega scope.
- `OPERATION_TEST_COVERAGE`: informa cobertura estructural del scope.
- Test execution / validators: ejecutan pruebas y producen resultados.
- `INDEPENDENT_REVIEW`: produce juicio independiente cuando la política lo exige.
- `QUALIFICATION_FINALIZATION`: materializa el resultado de qualification.
- `TEST_COVERAGE_DEBT_GUARD` / Full Regression: controla deuda global y monotonicidad; no pertenece al pase normal.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `OPERATION-TEST-COVERAGE-COVERED-OVERCLAIM-001`

## Regla de no duplicación

Este cambio define ownership y semántica. No crea función SQL nueva, tabla nueva, matriz nueva, runner de DB nuevo ni segundo applicability engine. El eventual rename/cutover debe reutilizar la implementación útil existente y conservar alias de compatibilidad solo durante una migración explícita.
