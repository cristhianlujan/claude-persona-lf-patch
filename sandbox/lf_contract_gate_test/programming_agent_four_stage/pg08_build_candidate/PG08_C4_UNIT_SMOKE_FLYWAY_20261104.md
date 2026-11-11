# PG-08_C4 — Unitarias focales, smoke y migraciones Flyway locales (2026-11-04)

## Definición oficial

La migración `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql` define:

- `PG-08_C4`: **“Unitarias focales + smoke; migraciones Flyway contra el PostgreSQL local (apply/rollback/reapply, *PRV-SQL-001*)”**.
- Criterio de salida: **PASS**.

Este paquete es **candidato de fuente**; no ejecuta test suites, base de datos, migraciones ni modelo de IA.

## Dependencias reutilizadas

- `PG08_C1_BUILD_COMPILATION_CANDIDATE_V1`: repo, base SHA, HEAD candidato, digest del diff y modalidad de ejecución.
- `PG08_C3_TYPECHECK_CANDIDATE_V1`: misma identidad y digest ligado al manifiesto de C1. El propio C3 ya enlaza C2 con C1.
- Proveedor de generación declarado: `GPT_NATIVE`, `CLAUDE_NATIVE` o `WORKER_API`. La procedencia se preserva sin elevarla a autoridad.

No reimplementamos PG-06, PG-07, la ejecución por carriles, un orquestador de pruebas o la política de permisos.

## Implementación

`tools/pg08_c4_test_flyway_candidate_v1.py` expone:

`prepare_pg08_c4(pg08_c1, pg08_c3, test_observations)`

El paquete exige una observación por solución, con `solution_id`, repo/HEAD/diff/executor exactos y las observaciones de checks.

Para cada solución exige **UNIT_FOCAL** y **SMOKE**. También exige una declaración explícita de aplicabilidad de Flyway:

- `REQUIRED`: obliga a **FLYWAY_APPLY**, **FLYWAY_ROLLBACK** y **FLYWAY_REAPPLY**, en ese orden, todos vinculados a una sola referencia declarada de aislamiento de PostgreSQL local. No permite declarar PASS posterior tras fallo/bloqueo anterior.
- `NOT_APPLICABLE`: no exige el ciclo Flyway, pero **la no aplicabilidad sigue sin verificar** hasta inspección del repo y del perfil de CI. La declaración no basta para eximir a PG-08_C4 del criterio oficial.

Cada check declara tipo, comando, herramienta, versión, SHA-256 de configuración/stdout/stderr, estado `PASS|FAIL|BLOCKED`, código de salida, recibo y diagnósticos. Se rechazan duplicados, combinaciones contradictorias, omisiones y desviaciones de identidad.

El contrato añade `runtime_target_ref` por check; para Flyway debe coincidir con `local_pg_isolation_ref`. Es solo un vínculo aportado por el invocador, no una prueba de que el destino no es remoto.

## Garantías que todavía **no** tenemos

1. Readback exacto del HEAD candidato, diff y permisos de escritura.
2. Selección y ejecución real de pruebas unitarias/smoke según la matriz de tarea y tecnología del target.
3. Confirmación de si Flyway es aplicable al repo y la tarea.
4. Aislamiento efectivo de PostgreSQL local, base limpia y reversibilidad `PRV-SQL-001`.
5. Ejecución real y recibos autenticados del ciclo Flyway.
6. Juez/verificador independiente que admita resultados exact-HEAD.

Un conjunto de resultados declarados como `PASS` solo produce `REPORTED_TEST_PASS_UNVERIFIED`.

El sobre conserva siempre:
`tests_executed_by_this_component=false`,
`flyway_executed_by_this_component=false`,
`local_postgresql_verified=false`,
`migration_applicability_verified=false`,
`diff_readback_verified=false`,
`receipts_authenticated=false`,
`pg08_c4_pass=false`,
`pg08_c4_admitted=false`,
`handoff_allowed=false`,
`production_authority=false`.

## Estado y siguiente checkpoint

**`PG08_C4_SOURCE_PREPARED / TESTS_NOT_EXECUTED / FLYWAY_NOT_EXECUTED / OFFICIAL_PENDING`**.

Siguiente: `PG-08_C5` — contratos OpenAPI, Spectral/oasdiff y catálogo de BD migrada. No se toca Supabase, el repositorio de producto, Análisis ni `main`; no se ejecutan las pruebas oficiales, que permanecen pausadas por instrucción del Owner. Todo queda en PR draft #3528.
