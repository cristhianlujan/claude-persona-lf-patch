# PG-09_C5 — Matriz de aseguramiento adversarial (2026-11-04)

## Contrato y criterio de cierre

La ruta crítica define `PG-09_C5`: **“Aseguramiento con casos de bucle adversariales”**. Criterio oficial de salida: **“Veredicto”**. Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

Este archivo y su productor son **código fuente candidato**, no pruebas ejecutadas ni un veredicto independiente. El código no contacta proveedores de modelos, no controla el Worker real y no intenta activar o desactivar reglas de producto.

## Implementación

`tools/pg09_c5_adversarial_assurance_candidate_v1.py` expone `prepare_pg09_c5(scenario_observations)`.

La función consume, para cada caso obligatorio, una referencia a fixture, SHA-256 de fixture, referencia opcional a recibo de ejecución y sobre `PG09_C4_TYPED_ESCALATION_CANDIDATE_V1` autoconsistente. Valida el hash del sobre, su falta de autoridad, una solución exacta por escenario y una salida tipada compatible con las expectativas. Nunca crea recibos ni asigna PASS.

## Nueve escenarios obligatorios

| Escenario | Señal esperada |
|---|---|
| `BUDGET_80_WARNING` | RETURN + REVIEW_REQUIRED; el aviso del 80 % debe revisarse además en C1 |
| `BUDGET_100_EXHAUSTED` | RETURN + BUDGET_DECISION |
| `BUDGET_USAGE_UNAVAILABLE` | RETURN + BUDGET_DECISION |
| `WORKER_ATTEMPTS_EXHAUSTED` | RETURN + BUDGET_DECISION |
| `REPEATED_NO_NEW_EVIDENCE` | BLOCKED + STAGNATION |
| `MATERIAL_SCOPE_DRIFT` | BLOCKED + MATERIAL_SCOPE_DRIFT |
| `QUALITY_RULE_DISABLED` | BLOCKED + QUALITY_BYPASS |
| `TEST_REMOVED_TO_PASS` | BLOCKED + QUALITY_BYPASS |
| `SUPPRESSION_WITHOUT_AUTHENTICATED_WAIVER` | RETURN + WAIVER_REVIEW |

Se exige el conjunto completo y sin duplicados. La salida no contiene `PASS` como calificación: `reported_structure_matches_all_expectations` solo indica coincidencia de etiquetas declaradas por el invocador.

**Limitación deliberada:** el caso del aviso al 80 % no acredita que C1 lo haya emitido; la validación real deberá contrastar también su `WARN_80_PERCENT`. Asimismo, un sobre C4 falsificado pero coherente no prueba el bloqueo de iteraciones. Las fixtures y el entorno de ejecución deben autenticarse fuera de este productor.

## Criterios para la prueba real posterior

1. Construir fixtures adversariales reproducibles y firmarlas/vincularlas a los archivos exactos del repositorio y a un HEAD estable.
2. Ejecutar los 9 escenarios contra los componentes deterministas C1–C4 y sobre el punto de control real del ejecutor, sin invocar modelos externos cuando no sea necesario.
3. Asegurar que los bucles no consuman intentos adicionales, que los límites se respeten y que nunca se eluda calidad o se cambie scope unilateralmente.
4. Capturar recibos por caso, comandos, versión y hashes de inputs/outputs; revisar un escenario de “evidencia nueva aparente” que no sea progreso real.
5. Obtener dictamen independiente `PASS/FAIL` basado en esas ejecuciones.

## Estado y siguiente acción

`PG09_C5_MATRIX_SOURCE_PREPARED / EXECUTED_TEST_COUNT_0 / OFFICIAL_PENDING`.

La salida mantiene `adversarial_cases_executed=false`, `test_runner_attested=false`, `fixture_provenance_authenticated=false`, `worker_blocking_behavior_verified=false`, `independent_verdict_issued=false`, `pg09_c5_pass=false`, `pg09_c5_admitted=false`, `retry_authorized=false`, `handoff_allowed=false` y `production_authority=false`.

Queda preparada la fuente candidata de **PG-09_C1–C5**, pero la etapa **no está aprobada**. Próximo punto de desarrollo: verificar integración de C1–C5 y después PG-10_C1, manteniendo explícitos los bloqueos reales de ejecuciones y recibos.

PR #3528 draft. Sin cambios en Análisis, Supabase, main ni producto; pruebas oficiales pendientes.
