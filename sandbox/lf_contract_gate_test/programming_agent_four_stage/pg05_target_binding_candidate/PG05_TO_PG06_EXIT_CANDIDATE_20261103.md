# PG-05 → PG-06: contrato de salida candidato (2026-11-03)

## Alcance

Consolida las fuentes C1–C5 de PG-05 sin afirmar que PG-05 está cerrada, sin crear una rama del target y sin iniciar PG-06. Se reutilizan los sobres fuente del PR #3528.

## Componente agregado

`tools/pg05_pg06_exit_candidate_v1.py` expone:

`assemble_pg05_pg06_candidate(pg04_exit, pg05_c1, pg05_c2, pg05_c3, pg05_c4, pg05_c5)`

Produce `PG05_TO_PG06_EXIT_CANDIDATE_V1`. Comprueba:
- SHA256 exacto de los cinco sobres de entrada con `candidate_sha256` y el `request_sha256` del preflight C5.
- Cadena de hashes PG04 → PG05_C1 → C2 → C3 → C4, y correspondencia con el sujeto C5.
- Conjunto idéntico de `solution_id` en todos los sobres, clasificación de hallazgos de C4 y locks de C3 no adquiridos.
- Preservación de recursos de escritura candidatos, dependencias, referencias compartidas de solo lectura y hallazgos aislados por solución.
- Ausencia de afirmaciones de autoridad de producción, revisión independiente ejecutada o admisión upstream.

El paquete incluye `target_binding` y nombre de rama **exactamente según C1**, incluso si son nulos. No rellena valores ficticios ni consulta el target. Distingue `affected_solutions` de `unaffected_solutions_not_promoted`: ninguna solución obtiene autoridad por no registrar desvíos.

## Condiciones que recibirá PG-06

Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`:

- **PG-06_C1**: reutilizar decisión de vigencia PG-01; solo revalidar con motivo tipado `SOURCE_DRIFT` o `STALE`; no hacer rebind durante ejecución.
- **PG-06_C2**: validar toolchain/entorno conforme al catálogo vigente (referencia de diseño V1 a Maven/JDK, pnpm/Node y docker compose con PostgreSQL 17 + Floci); no fingir disponibilidad.
- **PG-06_C3**: leer obligaciones de reversibilidad del paquete (frentes A7 `MIGRATION_CUTOVER` y `ROLLBACK_RECOVERY`), elaborar plan técnico; no inventar que A7 ya probó el rollback.
- **PG-06_C4**: registrar build + lint sin cambios del target y violaciones previas; requiere ejecución real.
- **PG-06_C5**: aseguramiento independiente.

Estas son condiciones que PG-06 tendrá que satisfacer; el consolidador no ejecuta ninguna.

## Límites de autoridad

Invariantes: `CANDIDATE_NOT_ADMITTED`, `pg05_admitted=false`, `pg06_admitted=false`, `pg01_currentness_decision_verified=false`, `target_binding_verified=false`, `toolchain_verified=false`, `rollback_plan_verified=false`, `baseline_build_lint_executed=false`, `pg05_independent_review_executed=false`, `locks_acquired=false`, `branch_created=false`, `write_allowed=false`, `production_authority=false` y `handoff_allowed=false`.

La presencia de un hash o de una referencia solo inmoviliza la declaración del llamador, no demuestra que el repositorio o las pruebas existan y estén CURRENT.

No se ejecutaron nuevos tests Python por instrucción del Owner; no se afirma PASS exact-HEAD ni admisión de un checkpoint oficial. No hubo escrituras en Supabase, cambios en Análisis, creación de ramas del target ni merge a main.

**Estado:** `PG05_TO_PG06_CANDIDATE_EXIT_SOURCE_READY / PG05_ASSURANCE_PENDING / PG06_ENTRY_NOT_ADMITTED`.
