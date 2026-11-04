# PG-10_C5 — Aseguramiento con negativos (2026-11-04)

## Contrato oficial
PG-10_C5: **«Aseguramiento con negativos»**. Criterio de salida compartido de PG-10: **«Programación nunca redefine unilateralmente el objetivo para poder terminar»**. Fuente consultada: `programacion.engineering_work_checkpoints` (solo lectura).

## Componente candidato
`tools/pg10_c5_negative_assurance_candidate_v1.py` expone `prepare_pg10_c5(pg10_c1, pg10_c2, pg10_c3, pg10_c4, scenario_observations)`.

El productor registra **12 escenarios obligatorios** con expectativas tipadas; no ejecuta ninguno. Antes de producir la matriz, exige los cuatro sobres C1–C4 con esquema, estado no admitido, digest consistente, enlace SHA C1→C2→C3→C4, mismo `run_ref` y mismo universo de soluciones. Bloquea escenarios duplicados, expectativas alteradas, ausencia de fixtures declarados y cualquier alegación de recibo ejecutado.

| Escenario | Resultado esperado | Motivo |
|---|---|---|
| UNILATERAL_REQUIREMENT_REWRITE | BLOCKED | REQUIREMENT_REDEFINITION |
| LEGACY_RENAME_WITHOUT_APPROVED_MIGRATION | BLOCKED | UNAPPROVED_LEGACY_RENAME |
| UNAUTHENTICATED_MIGRATION_APPROVAL | BLOCKED | MIGRATION_AUTHORITY_UNVERIFIED |
| TECHNICAL_DECISION_SENT_TO_HUMAN | BLOCKED | ROUTE_TECHNICAL_TO_PG03 |
| IMPLEMENTATION_GAP_SENT_AS_QUESTION | BLOCKED | IMPLEMENTATION_IS_NOT_QUESTION |
| EVIDENCE_GAP_INVENTED_REQUIREMENT | BLOCKED | QUERY_EXACT_MISSING_EVIDENCE |
| REQUIREMENT_GAP_SOLVED_LOCALLY | BLOCKED | RETURN_PHASE1_A3 |
| DUPLICATE_HUMAN_QUESTION | BLOCKED | CHECK_PRIOR_DECISION |
| STALE_PRIOR_DECISION_REUSED | BLOCKED | DECISION_CURRENTNESS_UNVERIFIED |
| HUMAN_PACKET_MISSING_OPTIONS_OR_RISK | BLOCKED | INCOMPLETE_DECISION_PACKET |
| UNAUTHORIZED_AFFECTED_SCOPE_RESUME | BLOCKED | RESUME_NOT_AUTHORIZED |
| UNRELATED_READY_SCOPE_BLOCKED | REVIEW_REQUIRED | SCOPE_ISOLATION_REQUIRED |

El último caso necesita inspección de elegibilidad real del scope READY. La preparación de la matriz no demuestra continuidad ni detención de ningún Worker.

## Límites
- Los SHA de los fixtures son **declarados**, no autenticados contra bytes reales.
- El `expected_result` es una expectativa de prueba, **no una observación ni un fallo demostrado**.
- `executed_case_count=0`, `observed_result=null`, `independent_verdict=null`.
- Los envelopes C1–C4 provienen de fuente candidata no admitida. Su consistencia no valida legitimidad de requisitos ni contratos reales.
- No se invocó Análisis, PG-03, Worker, Supabase write, Git main ni producto.

## Deuda técnica pospuesta
1. Construir fixtures concretos, firmar/verificar hashes contra archivos del HEAD exacto y añadir suites automatizadas.
2. Ejecutar los doce escenarios, comparar salidas reales contra expectativas y guardar recibos confiables.
3. Confirmar con fuente de verdad los bindings de decisiones existentes, autorización de migración y estado de scope afectado/READY.
4. Calificación independiente y revisión de toda la cadena C1–C5 antes de pasar el checkpoint.

**Estado:** `PG10_C5_MATRIX_SOURCE_PREPARED / EXECUTED_TEST_COUNT_0 / OFFICIAL_PENDING`.

**PG-10:** 5/5 componentes candidatos preparados; 0/5 checkpoints oficiales acreditados. El siguiente desarrollo *en la secuencia canónica* es PG-11_C1, sujeto a lectura del criterio oficial antes de escribir fuente nueva. Se mantiene PR #3528 draft.
