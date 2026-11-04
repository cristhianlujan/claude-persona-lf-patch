# PG-04_C7 — Dossier de cobertura para revisión independiente (2026-11-03)

## Objetivo y autoridad

Se completa la **preparación técnica**, sin duplicar el juez de `INDEPENDENT_ASSURANCE` ni registrar autoridad. La operación vigente es `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`; su entrada real requiere un sujeto PG04 con recibo de `EVIDENCE_LEDGER` VERIFIED, productor/revisor independientes y dispatch gobernado.

Lectura directa en Supabase (SELECT únicamente) en este avance: **0** filas `private.lf_evidence_ledger_v1` con `subject_type='PG04_SOLUTION_PARTITION_CANDIDATE'`, `capability_code='EVIDENCE_LEDGER'` y `verification_state='VERIFIED'`. Por tanto NO ejecutar el reviewer ni registrar C7 como DONE.

## Componentes incorporados al PR draft #3528

### 1. Dossier determinista de cobertura

`tools/pg04_c7_coverage_dossier_v1.py` prepara `PG04_C7_DETERMINISTIC_COVERAGE_DOSSIER_V1` a partir de:

- `partition` PG04 candidata exacta con SHA coherente;
- `strategy` PG03 candidata con SHA que coincida con la partición;
- `original_obligations` tipadas utilizadas para crear la partición.

Comprobaciones sin inferencia semántica:
1. Requisitos y aceptaciones del PG03 coinciden exactamente con el origen y con la asignación a soluciones (100 %, cero orfandad y sin múltiples propietarios).
2. Cada átomo original tiene exactamente un propietario y un `source_binding`; se conservan `source_ref`, `scope_id`, riesgo, razón semántica, write-scope y estado `EXISTING`/ `NEW`.
3. Para `EXISTING`, el binding conserva AS-IS y DELTA; para `NEW`, la evaluación acotada de reutilización. Se rechaza mezclar evidencias de estados mutuamente excluyentes.
4. Los `write_scope` y `shared_contract_refs` agregados corresponden a sus átomos, sin pérdida ni incorporación extraña.
5. Se verifican identidad de solución, DAG sin ciclos, proyección de dependencias entre átomos y conservación de `coimplement_with` dentro de la misma solución.
6. El dossier congela el origen con hashes; no convierte referencias `analysis://` ni `synthetic://` en evidencia vigente.

La salida dice `coverage_deterministic_check=PASS_SOURCE_ONLY` solamente para **consistencia estructural sobre datos aportados por el llamador**. Mantiene `semantic_fidelity_judged=false`, `source_currentness_attested=false`, `independent_review_executed=false`, `ledger_subject_receipt_verified=false`, `production_authority=false`.

### 2. Integración con el preflight C7 ya existente

`tools/pg04_independent_review_request_v1.py` acepta ahora el argumento **opcional** `coverage_dossier` (sin romper consumidores anteriores). Cuando se suministra, exige:
- schema/estado de dossier fuente, misma partición SHA y misma estrategia SHA;
- cobertura estructural declarada y flags de autoridad/juicio en falso;
- digest SHA256 exacto del dossier y la misma lista de IDs de soluciones.

El `PG04_C7_PARTITION_REVIEW_REQUEST_CANDIDATE_V1` resultante añade `deterministic_coverage_dossier_sha256`. Es **solo una vinculación de preparación**: el manifiesto de fuentes y el dossier siguen sin autenticación real. La presencia de SHA no equivale a receipt VERIFIED, juicio semántico ni validación de currentness.

### 3. Diferencia entre dos tipos de juez

- **Determinista**: valida pertenencia de átomos, cobertura 100 %, identidades, dependencias, procedencia y consistencia de referencias.
- **Semántico independiente**: tiene que comparar los resultados de negocio de A9/PG03 contra la partición, verificar que las agrupaciones sean coherentes, y determinar si una separación es realmente justificable. Este trabajo pertenece a `INDEPENDENT_ASSURANCE` y no fue ejecutado.

## Bloqueadores y siguiente paso

`PG04_C7_DETERMINISTIC_DOSSIER_SOURCE_READY / NO_VERIFIED_PG04_SUBJECT / NO_SEMANTIC_REVIEW / NO_GO_CHECKPOINT_CLOSE`.

Sigue siendo necesario que la ruta gobernada genere A9 vigente, PG01/PG03 admitidos, un sujeto PG04 congelado y su recibo VERIFIED, y posteriormente el reviewer independiente real. No crear una segunda operación ni una identidad de juez alternativa.

El usuario dejó las pruebas en pausa: **se añadió código y documentación pero no se ejecutaron tests Python de esta nueva pieza**. Tampoco se hicieron escrituras Supabase ni merge ni cambios en Análisis.
