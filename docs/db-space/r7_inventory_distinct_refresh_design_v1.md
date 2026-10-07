# R7 — inventory refresh no-op UPDATE suppression

Status: **DRAFT / IMPLEMENTATION CANDIDATE / NO APPLY**

## Ownership

No CODEOWNERS file is present for these paths.

Repository history for the two migrations that introduced/wired the refresh layer is authored by `paulozterra`:

- `20260930224100_lf_global_technical_inventory_refresh_v1.sql`
- `20260930224200_lf_global_technical_inventory_wiring_v1.sql`

So the observable repository owner of this code is **Paulo / paulozterra**. Cristhian still owns the repo/governance boundary and should review any contract-visible timestamp semantic change.

## Current cron topology

All five inventory jobs are active and run every six hours:

| Job | Schedule | Function | Relevant effect |
|---|---|---|---|
| 20 lf-global-inventory-catalog-v2 | `17 */6 * * *` | `inventory.fn_refresh_catalog_v2()` | upserts PG catalog objects; also calls search-index refresh |
| 21 lf-global-inventory-details-v2 | `22 */6 * * *` | `inventory.fn_refresh_db_details_v2()` | upserts DB_INDEX / DB_TRIGGER / RLS_POLICY objects and detail tables |
| 22 lf-global-inventory-exact-deps-v1 | `27 */6 * * *` | `inventory.fn_refresh_dependencies_exact_v1()` | dependency refresh |
| 23 lf-global-inventory-static-incremental-v1 | `32 */6 * * *` | `inventory.fn_refresh_static_incremental_v1()` | already change-aware by definition hash |
| 24 lf-global-inventory-finalize-v1 | `37 */6 * * *` | `inventory.fn_finalize_refresh_v1()` | tags/registries + calls search-index refresh again |

Important consequence: `fn_refresh_search_index_v1()` is currently invoked **twice per six-hour cycle**:

1. inside job 20 / `fn_refresh_catalog_v2()`;
2. inside job 24 / `fn_finalize_refresh_v1()`.

## Evidence of unconditional row churn

Live PostgreSQL statistics:

- `inventory.objects`: ~555k UPDATEs for ~6,000 live rows;
- `inventory.search_index`: ~645k UPDATEs for ~5,948 live rows.

The current functions contain `ON CONFLICT ... DO UPDATE` without a `WHERE ... IS DISTINCT FROM ...` guard.

They also assign timestamps unconditionally:

- objects: `last_seen_at=now(), updated_at=now()`;
- search index: `refreshed_at=now()`.

Therefore an otherwise identical row is physically rewritten.

### Catalog projection readback

Against current live data, reproducing the current catalog projection and ignoring timestamp-only differences:

| Projection | Current candidates | New inserts | Real semantic updates | No-op conflicts today |
|---|---:|---:|---:|---:|
| relations | 604 | 0 | 0 | **604** |
| functions | 780 | 23 | 35 | **722** |

Thus 1,326 of 1,384 existing relation/function conflicts in that snapshot were semantically unchanged.

### DB-details object population

The details job currently maintains at least:

- DB_INDEX: 1,176 active objects;
- DB_TRIGGER: 350;
- RLS_POLICY: 370.

Its object upserts also set `last_seen_at` and `updated_at` on every conflict.

### Search-index projection readback

Current projection versus the stored search index:

- projected active rows: 5,948;
- inserts: 0;
- semantic changes at observation time: 3,573;
- already semantically identical rows: **2,375**.

The high semantic-change count is expected because objects/tags/currentness had advanced after the previous search-index refresh. Once the first refresh catches up, the second refresh 20 minutes later has a large no-op opportunity.

## Existing change-aware path

`inventory.fn_refresh_static_incremental_v1()` is already designed correctly for this concern.

It first counts functions whose stored `static_analysis_sha256` differs from `definition_sha256`, returns `NO_CHANGES` when zero, and updates only changed definitions.

That pattern should be preserved.

## Proposed change

Candidate scope for a later implementation migration:

1. `inventory.fn_refresh_catalog_v2()`
2. `inventory.fn_refresh_db_details_v2()`
3. `inventory.fn_refresh_search_index_v1()`

Every `ON CONFLICT ... DO UPDATE` that currently rewrites an unchanged row gains a tuple comparison such as:

```sql
on conflict (object_ref) do update
set
  ...,
  last_seen_at = now(),
  updated_at = now()
where
  (
    inventory.objects.object_type,
    inventory.objects.schema_name,
    inventory.objects.object_name,
    inventory.objects.domain,
    inventory.objects.source_system,
    inventory.objects.source_of_truth,
    inventory.objects.status,
    inventory.objects.definition_sha256,
    inventory.objects.metadata,
    inventory.objects.active
  )
  is distinct from
  (
    excluded.object_type,
    excluded.schema_name,
    excluded.object_name,
    excluded.domain,
    excluded.source_system,
    excluded.source_of_truth,
    excluded.status,
    excluded.definition_sha256,
    excluded.metadata,
    excluded.active
  );
```

For `search_index`, the guard includes all material projection columns:

- ref/name/type/schema;
- tags and columns;
- source/status;
- `search_document`;
- currentness/currentness source;
- observed timestamp/main SHA;
- source traceability.

`refreshed_at` is **not** part of the distinctness predicate.

## Timestamp semantic consequence

Suppressing no-op UPDATEs means:

- `objects.last_seen_at` no longer means “the most recent six-hour refresh touched this exact row”;
- `search_index.refreshed_at` no longer advances when the projection is identical.

Read-only dependency review:

- `fn_retire_missing_pg_objects_v1()` does **not** use `last_seen_at`; it computes the live PG object set directly.
- No read-side DB function outside the refresh/external-sync writer family currently depends on `objects.last_seen_at`.
- `refreshed_at` is referenced by the search/external-baseline refresh family and a profile-runtime reconcile path, so its semantic change needs explicit owner review.

If “last poll time” must remain observable, do **not** preserve it with per-row timestamp writes, because that recreates the bloat. Prefer one source-level heartbeat/snapshot row per refresh execution.

## Proposed qualification before apply

A future implementation PR should:

1. pin MD5 preflight for all three modified functions;
2. contain static complete `CREATE OR REPLACE FUNCTION` definitions;
3. in `BEGIN -> candidate functions -> probes -> ROLLBACK`:
   - execute one catalog refresh and one finalizer cycle;
   - assert row contents equal baseline expected projection;
   - execute the same refresh a second time with no source changes;
   - assert second-cycle UPDATE counts are zero for semantically unchanged rows;
   - verify newly added/changed PG objects still update;
   - verify retirement still works from direct catalog membership;
   - verify lookup v2/v3 results are unchanged.
4. report table sizes and `n_tup_upd` deltas from the qualification session.

## Additional optimization opportunity

Once no-op suppression is qualified, review whether the job-20 call to `fn_refresh_search_index_v1()` is still needed given job 24 performs the canonical final refresh 20 minutes later.

That is a separate scheduling/latency decision and is **not** bundled into this proposal.

No live function is modified by this Draft.


## Implementación Draft

Se agregó `supabase/migrations/20261006232000_inventory_distinct_refresh_v1.sql`
como candidato **no aplicado**.

- Los tres writers quedan fijados por MD5 antes de reemplazarse.
- Los upserts de `inventory.objects` actualizan `last_seen_at/updated_at`
  solo cuando cambia la proyección material.
- El upsert de `inventory.search_index` actualiza `refreshed_at` solo cuando
  cambia una columna material; `refreshed_at` no participa en la comparación.
- La frescura del polling se conserva en la tabla pequeña
  `inventory.refresh_heartbeats_v1`, con una fila por ruta de refresh.
- Se elimina la llamada temprana a `fn_refresh_search_index_v1()` de
  `fn_refresh_catalog_v2()`; permanece la llamada canónica del finalizer
  (job 24), posterior a catálogo, detalles, dependencias, estático, registros y tags.
- No se modifica ningún schedule de cron en este Draft.

Owner observable del código: **Paulo / paulozterra**. No hay CODEOWNERS para
estas rutas. Cristhian mantiene el boundary de governance/revisión para cualquier
cambio visible de semántica temporal.


### Semántica de currentness verificada en DB

`inventory.v_managed_currentness_v1` **no usa `objects.last_seen_at`**.
La frescura de `SUPABASE_PG_CATALOG`, `LF_ACTIVOS`,
`PROGRAMACION_CONTRATOS` y `LF_OPERATION_REGISTRY` se deriva del último
snapshot `INVENTORY_STAGED_REFRESH_V1 / DATABASE_AND_REGISTRIES`.

Por eso detener los UPDATEs de `last_seen_at` en filas sin cambio no degrada
`currentness`. El snapshot del finalizer conserva la semántica canónica;
`refresh_heartbeats_v1` queda como señal operacional pequeña de ejecución.

También se cubrió `fn_refresh_registries_v1()`: sus tres upserts sobre
`inventory.objects` ahora tienen guardas semánticas. En `search_index`,
`observed_at` solo fuerza UPDATE para `repo://` y `edge://`; para fuentes
gestionadas el `observed_at` efectivo se obtiene en lectura desde
`v_managed_currentness_v1`, evitando churn por el timestamp de cada snapshot.
