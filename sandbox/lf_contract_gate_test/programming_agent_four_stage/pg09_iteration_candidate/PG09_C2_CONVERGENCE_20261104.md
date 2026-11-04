# PG-09_C2 — Detector de convergencia de iteraciones (candidato, 2026-11-04)

## Contrato oficial
El checkpoint `PG-09_C2` exige: **“Convergencia: una iteración repetida sin evidencia nueva ni reducción de findings se detiene y se reclasifica”**. Criterio de salida: **“Detector probado”**. Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

Este cambio es **código fuente candidato**. Todavía no está conectado al Worker ni tiene pruebas de calificación.

## Implementación
`tools/pg09_c2_convergence_guard_candidate_v1.py` expone:

`prepare_pg09_c2(pg07_c5, pg09_c1, iteration_observations)`

Reutiliza:
- `PG07_C5_ITERATION_GUARD_CANDIDATE_V1`: identidad de propuestas de iteración, relaciones `previous_iteration_ref` y clasificación de cambios de objetivo/aceptación/scope, sin duplicar ese detector.
- `PG09_C1_ITERATION_COST_GOVERNOR_CANDIDATE_V1`: límites de presupuesto e intentos declarados, sin volver a calcular precios o tokens.

Compara por solución, para cada iteración, los conjuntos `before_finding_refs` / `after_finding_refs` y `before_evidence_refs` / `after_evidence_refs`, con referencia a herramienta y recibo de comparación. Exige que los valores “before” de una iteración posterior coincidan exactamente con los “after” reportados en la previa.

Se clasifican:
- `FIRST_ITERATION_BASELINE_REPORTED`: primera comparación (no se presenta como iteración repetida).
- `REPORTED_PROGRESS_UNVERIFIED`: iteración repetida que declara evidencia nueva o menos hallazgos.
- `STOP_AND_RECLASSIFY`: intento repetido sin evidencia nueva **ni** reducción del número de hallazgos.
- `BLOCK_ROUTE_PG10`: propuesta que altera objetivo, criterios de aceptación o alcance según PG-07_C5.
- `REQUIRES_DECISION`: presupuesto o intentos declarados agotados, o costo no disponible.

Las comparaciones usan referencias suministradas por el invocador. La igualdad de identificadores **no prueba equivalencia semántica de hallazgos**, ni que un documento constituya evidencia nueva válida. Por eso no se certifica convergencia real ni se autoriza reintentar solo porque aparezca una referencia novedosa.

## Límites
El detector rechaza fuentes con esquema/hash inválido, autoridad prematura, soluciones o iteraciones ausentes, cadenas no contiguas, duplicados, referencias sin contenido y cambios de identidad entre PG-07_C5 y el historial observado.

La salida conserva `comparison_receipts_authenticated=false`, `worker_iterations_observed=false`, `finding_equivalence_verified=false`, `new_evidence_verified=false`, `repeat_execution_allowed=false`, `retry_authorized=false`, `pg09_c2_pass=false`, `pg09_c2_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

## Qué falta para terminar
1. Conectar el detector al historial real de intentos del ejecutor autorizado.
2. Validar referencias de hallazgos y pruebas con un verificador independiente, incluidas mejoras aparentes que solo cambian IDs.
3. Probar adversarialmente los bucles sin progreso; comprobar que se detienen y reclasifican.
4. Acreditar la política de presupuesto de C1 y el vínculo con PG-10 para cambios materiales.
5. Calificación exact-HEAD del checkpoint y recibos reales.

**Estado:** `PG09_C2_SOURCE_PREPARED / ITERATIONS_NOT_OBSERVED / OFFICIAL_PENDING`.

Siguiente punto exacto: **PG-09_C3**, prohibición de desactivar reglas, introducir supresiones sin waiver o borrar pruebas para forzar un PASS. No se cambia Supabase, Análisis, main ni el producto. Las pruebas oficiales permanecen pausadas y el PR #3528 queda draft.
