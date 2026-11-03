# PG-04 → PG-05: paquete de salida candidato consolidado (2026-11-03)

## Contexto del contrato

Fuente actual de los checkpoints: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.
- PG-04 produce soluciones por resultado de negocio, cubre requisitos y aceptaciones al 100 %, conserva su procedencia y enlaza DoD y revisión independiente.
- PG-05_C1 exige `repo_full_name` y `base_head_sha` **desde un `target_binding`**, nunca inferidos.
- PG-05_C2 requiere `write_scope` por solución; lo compartido entre soluciones es **READ_ONLY** por defecto.
- PG-05_C3 exige locks y detección de choques materiales antes de writers paralelos.
- PG-05_C4 bloquea cambios fuera de scope por solución afectada.
- PG-05_C5 exige aseguramiento independiente.

No se activa ninguna de esas acciones con este componente: su función es congelar la **estructura candidata de entrega**, no iniciar PG-05.

## Nueva pieza

`tools/pg04_pg05_exit_candidate_v1.py` expone:

`assemble_pg04_exit_candidate(partition, dod, coverage_dossier, review_request, target_binding=None)`

No crea un segundo motor PG-04. Consume únicamente los componentes candidatos ya existentes:
- PG04_C2: partición semántica, `PG04_SEMANTIC_PARTITION_CANDIDATE_V1`;
- PG04_C5: plan de `Definition of Done` por SOLUTION, `PG04_SOLUTION_DOD_CANDIDATE_V1`;
- PG04_C7: dossier estructural, `PG04_C7_DETERMINISTIC_COVERAGE_DOSSIER_V1`;
- PG04_C7: preflight de `INDEPENDENT_ASSURANCE`, `PG04_C7_PARTITION_REVIEW_REQUEST_CANDIDATE_V1`.

El consolidador comprueba los cuatro hashes canónicos; que DoD, dossier y review-request correspondan a la misma partición; que las soluciones sean exactamente las mismas en los cuatro sobres; y que las obligaciones por solución concuerden con el dossier. Rechaza checks DoD que aparenten `PASS` o tengan recibos de ejecución: solo se aceptan `NOT_EXECUTED` y `receipt_id=null`.

Cada `solution` entregada conserva:
- `solution_id`, `business_outcome`, `atom_ids`;
- `requirement_ids`, `acceptance_ids`, `depends_on`;
- `write_scope_candidates` y `source_bindings`;
- `shared_contract_refs` con `shared_contract_access_default=READ_ONLY`;
- `implementation_state`;
- `dod` con criterios de cierre pendientes;
- `pg05_write_scope_authorized=false`, `pg05_parallel_writer_lock_acquired=false`, `execution_allowed=false`.

## Vinculación del destino

`target_binding=None` es válido para una vista de preparación pero devuelve `repo_full_name=null`, `base_head_sha=null`, `target_binding_ref=null`, `source_attested=false`, y `first_pg05_blocker=PG05_TARGET_BINDING_MISSING`.

Se puede proporcionar explícitamente un `target_binding` con `repo_full_name`, `base_head_sha` de 40 caracteres hexadecimales y `target_binding_ref`; el consolidador comprueba la forma y lo copia sin deducir valores de ramas o proyectos. **NO** verifica que la referencia sea actual, legítima o de autoridad reconocida. Aunque se proporcione, `source_attested=false`, `pg05_branch_creation_allowed=false` y `first_pg05_blocker=PG04_INDEPENDENT_REVIEW_NOT_EXECUTED`.

No se generó ningún `target_binding` falso ni se creó rama `lf/prog-...`.

## Salida y límites

`schema_version=PG04_TO_PG05_EXIT_CANDIDATE_V1` con SHA propio, siempre:
- `status=CANDIDATE_NOT_ADMITTED`;
- `pg04_admitted=false`, `pg05_admission_allowed=false`;
- `independent_review_executed=false`, `ledger_subject_receipt_verified=false`;
- `pg05_branch_creation_allowed=false`, `pg05_write_allowed=false`, `handoff_allowed=false`;
- `target_binding_inferred=false`, `target_branch_created=false`.

**No es un `PROGRAMMING_SOLUTION_PARTITION_SET_V1` admitido** y no suplanta ni modifica el contrato canónico del PR #1912 (todavía fuente candidata). Un consumidor PG-05 debe rechazar este envelope como autoridad ejecutable y exigir readback/receipts gobernados reales.

## Bloqueadores

1. Paquete A9 auténtico y estrategia PG03 admitida; no volver a intervenir en la implementación de Análisis.
2. Sujeto PG04 congelado con recibo `EVIDENCE_LEDGER VERIFIED` y review real `INDEPENDENT_ASSURANCE` C7.
3. `target_binding` legítimo del paquete, autorizado y atestiguado, y PG-05_C1.
4. Calificación de código exact-HEAD de estos componentes, diferida por decisión del Owner.

**No se ejecutaron nuevas pruebas** de este cambio. Sin escritura en Supabase, sin merge, sin cambios en Análisis ni en `main`.
