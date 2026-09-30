# OPERATION_TEST_COVERAGE

Capability transversal LF candidata: `OPERATION_TEST_COVERAGE`.

## Estado

- Estado de esta definición: `CANDIDATE_TYPED_PROJECTION`
- Autoridad live actual: provider legacy read-only `public.lf_s36_operation_assurance_coverage_v1()`
- Proyección tipada source: `operation_test_coverage_projection_v1.py`
- Cutover live: **NO realizado por esta capability**
- Motor paralelo: **prohibido**

## Propósito

Responder una sola pregunta:

> Para una operación gobernada, ¿existe la estructura de cobertura de tests requerida en la matriz canónica LF?

La cobertura estructural comprende únicamente la relación operación → binding requerido → suite existente → casos existentes. Los runs observados son un diagnóstico separado y jamás producen un verdict dentro de este owner.

## Salida tipada

La proyección canónica separa explícitamente:

- `structural_coverage_state`;
- `execution_observation_state`;
- `quality_verdict_state`;
- `assurance_verdict_state`;
- `qualification_verdict_state`;
- `material_pass_claimed`.

La traducción legacy es estricta:

- `COVERED` → `STRUCTURALLY_COVERED`;
- `BLOCK` → `STRUCTURAL_BLOCKED`;
- `NOT_COVERED` → `NOT_COVERED`;
- `EVIDENCE_UNMAPPED` → `EVIDENCE_UNMAPPED`;
- `DISCOVERED` → `DISCOVERED`.

Los tres campos de verdict siempre son `NOT_EVALUATED` y `material_pass_claimed=false`.

Una operación con binding + suite + casos y `observed_run_count=0` puede ser `STRUCTURALLY_COVERED` y, simultáneamente, `NO_EXECUTION_OBSERVED`. Incluso si `observed_run_count>0`, este owner solamente devuelve `EXECUTION_OBSERVED`; no infiere PASS, calidad, Assurance ni Qualification.

## Responsabilidad propia

Esta capability puede:

1. enumerar operaciones aplicables que le entregue el plan/consumer;
2. leer `lf_test_requirement_bindings`;
3. leer `lf_test_suites`;
4. leer `lf_test_suite_cases`;
5. leer `lf_test_runs` solo para diagnóstico de evidencia no mapeada/conteo observado;
6. proyectar cobertura estructural y observación de ejecución en dimensiones separadas.

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

El provider existente que contiene el cálculo estructural útil es:

- `public.lf_s36_operation_assurance_coverage_v1()`
- source: `supabase/migrations/20260914205435_s36_assurance_completeness_engine_v1.sql`

`public.lf_s36_assurance_completeness_v1(boolean)` puede permanecer físicamente como lineage histórico, pero **no puede tener nuevos consumers** y no es autoridad de esta capability. El owner umbrella `ASSURANCE_COMPLETENESS` se retira mediante `20260930073000_lf_assurance_completeness_legacy_owner_retirement_v1.sql`.

Para cerrar `OPERATION-TEST-COVERAGE-COVERED-OVERCLAIM-001` no es necesario borrar la función histórica; sí es obligatorio demostrar en live readback que:

- el contexto activo ya no inyecta `ASSURANCE_COMPLETENESS`;
- el activo umbrella ya no es `ACTIVE_SHARED_ENFORCEMENT`;
- nuevos consumers de la función legacy están prohibidos;
- la salida nueva sigue separando estructura, ejecución y verdict.

## Relación con otros owners

- `CHANGESET_GOVERNANCE` / Router: decide applicability y entrega scope.
- `OPERATION_TEST_COVERAGE`: informa únicamente cobertura estructural del scope.
- Test execution / validators: ejecutan pruebas y producen resultados.
- `INDEPENDENT_REVIEW`: produce juicio independiente cuando la política lo exige.
- `QUALIFICATION_FRAMEWORK`: owner canónico de materialización/currentness de qualification.
- `TEST_COVERAGE_DEBT_GUARD` / Full Regression: controla deuda global y monotonicidad; no pertenece al pase normal.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `OPERATION-TEST-COVERAGE-COVERED-OVERCLAIM-001`
- `ASSURANCE-COMPLETENESS-LEGACY-OWNER-RESIDUE-001`

## Regla de no duplicación

La proyección tipada no crea función SQL, tabla, matriz, runner DB ni segundo applicability engine. Consume la fila del provider legacy y elimina la ambigüedad semántica antes de exponerla a nuevos consumers. El cutover del umbrella legacy se hace desde la autoridad de policy/context e inventario, no creando otro Assurance engine.
