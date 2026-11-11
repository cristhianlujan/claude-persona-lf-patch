# PG-06_C1 — Reutilización de vigencia de PG-01 (2026-11-03)

## Contrato canónico

La definición de `PG-06_C1` exige: “Reutiliza la decisión de vigencia de PG-01; solo vuelve a evaluarla con un motivo tipado (SOURCE_DRIFT, STALE); nunca re-enlaza a mitad de ejecución (mid_execution_rebind_forbidden)”.

Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

La política material existente es `CURRENTNESS_AUTHORITY`. Su vocabulario de decisión es `CURRENT`, `CURRENT_REBOUND`, `STALE_AFFECTED` y `UNKNOWN_FAIL_CLOSED`. Un cambio general de SHA de main, por sí solo, **no invalida automáticamente** las evidencias materiales. La autoridad ya tiene su mecanismo y no se reimplementa en PG-06.

## Implementación

`tools/pg06_c1_currentness_reuse_candidate_v1.py`

`prepare_pg06_c1(pg05_exit, pg01_currentness_binding, change_signal=None, execution_started=False)`

Consume:
- `PG05_TO_PG06_EXIT_CANDIDATE_V1` íntegro, congelado, no admitido;
- la **referencia explícita** de decisión PG-01, su digest y cuatro fingerprints/identificadores materiales (`context_sha256`, `snapshot_schema_digest_sha256`, `authority_fingerprint_sha256`, `source_snapshot_sha256`), más `decision` y `decision_source_capability=CURRENTNESS_AUTHORITY`;
- opcionalmente, `change_signal` con razón tipada `SOURCE_DRIFT` o `STALE`, `evidence_ref`, `affected_scope_ids` y `observed_source_snapshot_sha256`.

### Sin señal de cambio

`mode=REUSE_PG01_DECISION_REFERENCE`. Si el valor declarado fue `CURRENT` o `CURRENT_REBOUND`, genera un candidato no admitido que conserva la misma referencia: **no recalcula vigencia** y exige readback auténtico del recibo PG-01. Si el valor fue `STALE_AFFECTED` o `UNKNOWN_FAIL_CLOSED`, devuelve `BLOCKED`, no una nueva aprobación.

### Con señal tipada

`mode=REQUEST_GOVERNED_RECHECK` y `status=BLOCKED`. Se exige un conjunto de scopes afectados; no se hace invalidación general ni se reevalúa toda la estrategia. Para `SOURCE_DRIFT`, una señal que conserva exactamente el mismo digest de snapshot es rechazada como contradicción estructural. La referencia de evidencia y el hash observado **no autentican la existencia del cambio**; un actor autorizado debe leerlos de su fuente real.

### Rebind y ejecución

`execution_started=True` bloquea la operación `PG06_C1_MID_EXECUTION_REBIND_FORBIDDEN`. La implementación no vuelve a vincular, no modifica el recibo PG-01 y no llama a `CURRENTNESS_AUTHORITY`. En todos los casos devuelve `pg01_decision_readback_verified=false`, `source_snapshot_currentness_verified=false`, `recheck_executed=false`, `pg06_ready=false`, `execution_allowed=false`, `production_authority=false` y `handoff_allowed=false`.

La procedencia de los valores PG-01 es **caller supplied, unverified**. El formato del digest no constituye una prueba de autenticidad. No se crea un segundo motor de vigencia ni un permiso nuevo.

## Bloqueos reales

1. Entrada PG-05 gobernada y admitida; el envelope del laboratorio sigue `CANDIDATE_NOT_ADMITTED`.
2. Decisión PG-01 realmente existente y CURRENT, con recibo/readback de procedencia y fingerprints exactos.
3. Si hay SOURCE_DRIFT o STALE, recheck por la capacidad existente solo para scopes afectados.
4. Validación de ausencia de rebind durante ejecución real antes de permitir PG-06.

**Dictamen:** `PG06_C1_SOURCE_REUSE_AND_RECHECK_REQUEST_PREPARED / PG01_DECISION_NOT_READ_BACK / PG06_NOT_ADMITTED`.

No se ejecutaron pruebas Python, de acuerdo con el aplazamiento del Owner. No se ejecutaron acciones de escritura, no hubo cambios en Análisis, Supabase o main y no se abrió ninguna rama de producto.
