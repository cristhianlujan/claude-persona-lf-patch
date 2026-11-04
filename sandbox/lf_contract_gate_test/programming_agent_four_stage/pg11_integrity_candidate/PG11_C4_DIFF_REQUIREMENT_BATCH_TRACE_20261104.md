# PG-11_C4 — Trazabilidad diff ↔ requisito ↔ lote (2026-11-04)

## Criterio oficial
**PG-11_C4:** «Trazabilidad diff ↔ requisito ↔ lote». Criterio de salida PG-11: «Diff final no contiene cambios huérfanos, deuda inventada ni scope creep». Consultado por lectura SQL; estado oficial **PENDING**.

## Fuente candidata preparada
`tools/pg11_c4_diff_requirement_batch_trace_candidate_v1.py`: `prepare_pg11_c4(pg11_c1, pg11_c2, pg11_c3, declared_diff, authorized_scope, trace_observations)`.

Se valida integridad de los sobres C1–C3 y enlace por SHA C1→C2→C3, sin atribuirles autenticidad. Se compara la lista de cambios declarados con el alcance autorizado bajo los digests previamente registrados por C1. Cada ruta del diff debe tener cobertura exacta y un enlace declarado a requisito, lote, alcance y evidencia. Se rechazan cambios huérfanos, duplicaciones, referencias incompletas, enlaces divergentes del alcance, coberturas incompletas, drift de tipo de cambio y supresiones declaradas por C3 que no estén en el diff o tengan un requisito distinto. Ninguna declaración autoriza la supresión.

## Límites
La concordancia entre listas declaradas **no equivale a trazabilidad real**. No se consultaron los requisitos, lotes o diff de producción ni se autenticaron sus versiones. No se activó revisión ni ejecución de programación.

Se devuelve siempre `trace_complete_verified=false`, `real_diff_verified=false`, `pg11_c4_pass=false`, `pg11_c4_admitted=false`, `handoff_allowed=false`, `production_authority=false`.

**Estado:** `PG11_C4_SOURCE_PREPARED / NOT_TESTED / REAL_TRACE_NOT_QUALIFIED / OFFICIAL_PENDING`.

## Deuda técnica diferida
- Obtener del Git real base/HEAD y changeset completo; exigir alcance exacto por requisito y lote gobernados.
- Validar versiones de requisitos, pertenencia y estado real de lotes, trazabilidad de bloques de cambios (no solo archivos), y supresiones parciales.
- Ejecución reproducible de negativos de archivos huérfanos, cambios sin lote, falsificación de enlaces y pérdida de cobertura; recibos y calificador independiente.

**Siguiente:** PG-11_C5, revisor distinto del constructor. PR #3528 draft; sin escribir Análisis, Supabase, main ni producto.
