# PG-06_C3 — Plan técnico de reversibilidad ligado a A7 (2026-11-03)

## Mandato

El checkpoint PG-06_C3 requiere recibir las **obligaciones reales** de reversibilidad desde el paquete de Análisis (A7) y preparar un plan técnico de migración reversible, expand/contract o rollback, según corresponda; PG-06 no debe añadir obligaciones inexistentes ni modificar A7.

La fuente `analysis_material_front_coverage_contract_v1.json` establece que los frentes son `EVIDENCE_DERIVED_OPEN_CATALOG`, con `MIGRATION_CUTOVER` y `ROLLBACK_RECOVERY` entre los tipos de ejemplo. Los estados son `REQUIRED`, `REUSE_AS_IS` y `NOT_APPLICABLE`, con cierre `CLOSED` o `BLOCKED`. **La ausencia de un frente nunca equivale a NOT_APPLICABLE**. A9 debe preservar el artefacto A7 completo.

## Implementación candidata

`tools/pg06_c3_reversibility_plan_candidate_v1.py` implementa:

`prepare_pg06_c3(pg05_exit, pg06_c1, pg06_c2, a7_material_front_coverage, solution_reversibility_plans)`

- Valida los hashes y vínculos de los sobres PG-05 → PG-06, PG-06_C1 y PG-06_C2. Todos deben permanecer sin autoridad de ejecución.
- Exige un `MATERIAL_FRONT_COVERAGE_V1` declarado completo, con identificador y digest, material fronts tipados, fuentes y referencias de vigencia. Estos datos son **caller supplied**, no autenticados.
- Selecciona solamente los frentes A7 de tipo `MIGRATION_CUTOVER` y `ROLLBACK_RECOVERY`, y exige un registro de plan por cada frente aplicable a cada solución y ámbito. Si no se registra ningún frente de esos tipos, falla estructuralmente para que un responsable verifique si la cobertura A7 efectivamente justifica su ausencia.
- Para `REQUIRED`, exige `technical_steps_ref`, `rollback_steps_ref`, `verification_ref` y `cutover_or_recovery_strategy_ref`; no acepta inventar una ejecución o validar el contenido de esas referencias.
- Para `REUSE_AS_IS` o `NOT_APPLICABLE`, conserva la disposición explícita `REUSE_EXISTING` o `JUSTIFIED_NOT_APPLICABLE`, respectivamente, y no genera instrucciones técnicas ficticias.
- Detecta y conserva `closure=BLOCKED` o blockers A7; esas soluciones quedan en estado diagnóstico `BLOCKED_A7_FRONT` y no contaminan automáticamente otras soluciones.
- Valida la cobertura completa de front IDs y scope refs declarados; no permite omitir silenciosamente una obligación A7 del conjunto recibido.

El resultado `PG06_C3_REVERSIBILITY_PLAN_CANDIDATE_V1` conserva `a7_artifact_currentness_verified=false`, `a7_fronts_semantically_verified=false`, `rollback_plan_verified=false`, `migration_or_rollback_executed=false`, `pg06_admitted=false`, `write_allowed=false`, `production_authority=false` y `handoff_allowed=false`.

## Precisión de autoridad

El contrato A7 describe qué debe quedar cubierto; **no demuestra por sí mismo que una migración sea reversible**. El verificador autorizado tendrá que comprobar los pasos técnicos, expand/contract cuando corresponda, seguridad de datos, restauración y el procedimiento real. Los planes fuente solo contienen referencias, no evidencia de éxito.

En esta revisión no se obtuvo un paquete A7 auténtico y admitido para una solución real; no se ejecutó la función con evidencias reales. Tampoco se probó el código Python por la pausa indicada por el Owner.

**Estado:** `PG06_C3_REVERSIBILITY_SOURCE_PREPARED / A7_CURRENT_READBACK_MISSING / ROLLBACK_NOT_EXECUTED / OFFICIAL_PENDING`.

Próximo checkpoint: **PG-06_C4**, build + lint de línea base del target sin cambios y registro de violaciones previas; la implementación candidata no podrá declarar que ejecutó esas herramientas.
