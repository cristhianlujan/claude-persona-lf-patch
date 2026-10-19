# Registro de diferencias conocidas Git ↔ ledger (post-baseline)

Alcance: versiones posteriores a `20261005203801`. Main `dd8aca06ff3b346ff95e79d22722634ad3162e9d` contra `supabase_migrations.schema_migrations` (lectura, 2026-10-19).
Este registro **no escribe en la base ni en el ledger**. Lista las diferencias que se mantienen a propósito y su motivo, para que F10-006 ("cero drift no registrado") pueda evaluarse.

## Resumen del inventario

| Estado | # | Acción |
|---|---|---|
| Idénticas (versión, nombre y bytes) | 596 | ninguna |
| Equivalentes (difieren solo en comentarios; hash canónico igual) | 133 | ninguna |
| Registradas abajo (se mantienen) | 22 | ninguna; registradas |
| Pendientes por el carril RECONCILE | 30 | lote 3 (#2622, 29) y `lf_pilot_srcr_g12` (1) |

## A. Aplicadas dos veces en el ledger (12)

El ledger tiene la versión original y una segunda aplicación con nombre `<versión>_<nombre>`. El archivo Git coincide con la versión original. No se toca Git ni el ledger.

| Versión duplicada en ledger | Nombre en ledger | Versión original (en Git) | Mismo contenido | sha256[:16] |
|---|---|---|---|---|
| 20261011000425 | 20261011033000_lf_d2_canonical_binding_readback_v1 | 20261011033000 | sí | 2fa9e47880eddd96 |
| 20261011000445 | 20261011034000_lf_d3_investigation_decision_v1 | 20261011034000 | sí | f6034c24ddd47770 |
| 20261011000451 | 20261011035000_lf_source_investigation_prepare_v1 | 20261011035000 | sí | fa746e2cb3793376 |
| 20261011075708 | 20261011052000_ig_m98_reuse_verified_field_adjudication_v4 | 20261011052000 | sí | 3742dd2e1757b147 |
| 20261011081610 | 20261011081500_ig_source_integrity_rebound_current_cardinality_v1 | 20261011081500 | sí | 38696672846f1bb1 |
| 20261011085515 | 20261011085000_ig_m98_history_currentness_v5 | 20261011085000 | sí | 01713b51e968b5e5 |
| 20261011223638 | 20261011155000_ig_m98_two_phase_field_match_v6 | 20261011155000 | sí | 98e691a7c09d3017 |
| 20261011223646 | 20261011155001_ig_m98_receipt_governance_v6 | 20261011155001 | sí | 2a97e5e5b6db3e23 |
| 20261011223729 | 20261011155002_ig_m98_two_phase_gate_v6 | 20261011155002 | sí | c9083e20ea7f94f7 |
| 20261011233708 | 20261011194000_ig_m98_engineering_assurance_v7 | 20261011194000 | sí | 4f56e1c4dc554b5b |
| 20261011233711 | 20261011194100_ig_m98_engineering_release_governance_v7 | 20261011194100 | sí | d3c1a924281a2d6f |
| 20261011235413 | 20261011211000_ig_m98_ekb_errors_lessons_v1 | 20261011211000 | sí | dc2d38030259fa3c |

## B. Equivalentes por puntero en el ledger (4)

El ledger guarda un puntero `github://…#blob=` y el blob coincide con el archivo Git (documentado en `RECONCILE_BATCH_2.md`, 2026-10-13).

`20261009172500_ig_m713_contract_and_criteria_controls_v1` · `20261009175500_ig_m713_false_pass_fused_m49_validator_v1` · `20261009183000_ig_m713_qualification_asof_readback_v1` · `20261011190000_ig_m713_ekb_errors_findings_v1`

## C. Aplicadas fuera del ledger (2)

Sus efectos existen en la base pero no tienen fila en el ledger (evidencia en `RECONCILE_BATCH_2.md`). No se reaplican ni se escribe el ledger a mano.

`20261006110403_engineering_unit_stop_scope_v1` · `20261006152000_engineering_contract_corrections_privacy_m45`

## D. Archivos históricos sin versión (3)

De junio de 2026, anteriores a la disciplina de ledger; el CLI de Supabase los ignora por no tener versión. Sus objetos existen en la base (lectura 2026-10-19).

| Archivo | Objetos verificados |
|---|---|
| `session_25_contract_fixes.sql` | solo DML de operación (`lf_operation_*`, `lf_eventos`) |
| `session_26b_operational_fixes.sql` | `public.fn_kb_quality_score` |
| `session_26c_pipeline_gaps.sql` | `public.fn_auto_consumer_ready`, `public.fn_restock_url_queue`, trigger `trg_auto_consumer_ready`, evento 416 |

## E. Copia duplicada en Git (1)

`20261012120000_ig_m100_ekb_signed_release_snapshot_learnings.sql` es copia byte a byte de `20261013194245_lf_ig_m100_ekb_signed_release_snapshot_learnings_v1.sql` (que sí coincide con el ledger). El carril RECONCILE no admite borrados (`DELETE_WITHOUT_UNIQUE_IDENTICAL_DESTINATION`). Se mantiene hasta que el carril admita borrar copias exactas. No la aplica el Train (solo aplica lo que trae cada PR); evitar `supabase db push` manual.

## Pendientes (no registrados: se resuelven)

- Lote 3, 29 renombres exactos: #2622 (bloqueado por guard M10.4 en 1 archivo; solución en #2937).
- `20261003003000_lf_pilot_srcr_g12_state_authority_v1.sql` → `20261012064408_20261003003000_lf_pilot_srcr_g12_state_authority_v1.sql`: contenido idéntico; requiere registrar el nombre exacto en el clasificador (decisión de Cristhian).
- Tramo anterior al baseline: no revisado en este corte.
