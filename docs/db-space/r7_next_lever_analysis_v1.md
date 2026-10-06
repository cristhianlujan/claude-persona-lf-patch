# R7 — next DB-space lever after R5

Status: **ANALYSIS ONLY / NO CHANGES**

Observed on 2026-10-06 after R5-D.

## Goal

Current database size: **599,927,955 bytes = 572.14 MiB**.

Accepted R5 physical reclaim estimate: about **95.19 MiB**.

If R5-E + its coordinated VACUUM FULL land near that estimate, the database would be roughly **476.95 MiB**.

Getting to about **400 MiB** therefore requires roughly another **77 MiB** of sustainable reduction.

## Candidate summary

| Candidate | Current physical | Classification | Safe immediate reclaim | Risk |
|---|---:|---|---:|---|
| public.lf_eventos | 48.05 MiB | canonical immutable event/evidence stream | 0 under current rules | very high |
| inventory.objects | 37.30 MiB | mixed: current derived inventory + traceability/history + source-of-truth projections | index/bloat optimization only | medium |
| inventory.search_index | 27.23 MiB | fully derived search projection | up to ~27 MiB if lookup is redesigned to avoid persisted copy | medium |
| private.lf_github_reconciliation_runs_v3 | 20.64 MiB | governed append-only canonical reconciliation evidence | 0 under current rules | very high |
| private.lf_gate_test_runs_v3 | 15.30 MiB | governed append-only canonical gate evidence | 0 under current rules | very high |

## 1. public.lf_eventos — 48.05 MiB

Physical:

- total: 50,380,800 bytes = **48.05 MiB**;
- heap: about 11.1 MiB;
- TOAST/auxiliary: about **33.86 MiB**;
- indexes: about 3.10 MiB;
- rows: 19,461;
- logical row bytes: about 38.96 MiB.

This is not an operational cache.

The table has a `BEFORE DELETE OR UPDATE` trigger:
`trg_00_lf_eventos_immutable -> private.fn_block_lf_eventos_mutation()`.

It also has the event-type, provenance, typed-evidence, closure and validation guards.

Large payload families include:

- `EXTERNAL_CI_VERIFICATION_COMPLETED`: 7,070 rows / ~15.48 MiB logical payload;
- `GATE_TEST_RUN_RECORDED`: 6,999 rows / ~12.26 MiB logical payload.

Those events correspond closely to the detailed reconciliation/gate evidence streams, but that duplication is part of the current governance model. Removing or rewriting historical event payloads would change canonical evidence semantics.

**R7 decision:** do not touch historical `lf_eventos`.

Possible future growth-control design, requiring a new Cristhian-owned contract, would be to make new large events content-address references to an immutable evidence object rather than embedding the full duplicate payload. That would slow future growth but would not reclaim the existing 48 MiB without a separate archival model.

Risk: **VERY HIGH / canonical evidence**.

## 2. inventory.search_index — 27.23 MiB

This relation is the clearest R7 derived candidate.

Current:

- 5,948 rows;
- physical total: **27.23 MiB**;
- logical row bytes: **5.30 MiB**;
- all rows were refreshed together by the inventory refresh path.

`inventory.fn_refresh_search_index_v1()` constructs the relation entirely from:

- `inventory.objects`;
- `inventory.object_tags`;
- `inventory.columns`;
- managed-currentness views/functions.

It upserts every active object and deletes search rows whose object is no longer active.

It is therefore a **derived projection**, not canonical evidence.

Active readers are:

- `inventory.fn_lookup_v2(...)`;
- `inventory.fn_lookup_v3(...)`.

The current finalizer `inventory.fn_finalize_refresh_v1()` calls `fn_refresh_search_index_v1()`, and cron 24 runs the finalizer every six hours.

### Safe R7 options

**R7-A: index cleanup first.**

Existing audited DB-space work already established:

- KEEP `inventory_search_document_gin` (~5.5 MiB): lookup v2/v3 demonstrably uses it;
- DROP candidate `inventory_search_tags_gin`: 2,064,384 bytes;
- DROP candidate `inventory_search_columns_gin`: 1,515,520 bytes.

These two search-index GINs together are ~3.42 MiB.

**R7-B: stop persisting search_index.**

A larger redesign can change lookup v3 to build its search projection from objects/tags/columns directly (or from a thinner current cache) and retire the duplicated persisted row set.

Maximum current physical gain: about **27.23 MiB**.

Trade-off: lookup latency may rise materially because the current `search_document` GIN gives Bitmap Index Scan behavior. This needs query latency/EXPLAIN qualification before any schema change.

Risk: **MEDIUM** because it is derived, but it is an active read-path optimization.

## 3. inventory.objects — 37.30 MiB

This table is **not safely disposable as a whole**.

Current:

- 6,000 rows;
- physical total: **37.30 MiB**;
- logical row bytes: only **5.47 MiB**.

Source mix includes:

- 3,080 active `SUPABASE_PG_CATALOG` source-of-truth rows;
- 2,314 active `GOOGLE_DRIVE_REPO_INVENTORY` rows marked `source_of_truth=false`;
- LF_ACTIVOS / PROGRAMACION_CONTRATOS / LF_OPERATION_REGISTRY projections;
- external-currentness/readback state;
- retired PG objects retained as `NO_LONGER_IN_PG_CATALOG`.

Writers include:

- cron 20 -> `inventory.fn_refresh_catalog_v2()`;
- cron 21 -> DB detail refresh;
- cron 23 -> static incremental refresh;
- external baseline begin/stage/finalize functions;
- external currentness observation functions.

Readers include dependency, impact, lookup refresh and external-currentness read models.

The PG-catalog subset can be regenerated from live catalogs, and the Google Drive/repo subset is explicitly non-authoritative. However, `objects` also carries stable object ids, first/last seen timestamps, retirement/currentness state and links used by tags/dependencies. A wholesale truncate/rebuild would lose traceability and can break dependent object ids.

### Strong physical-bloat signal

Postgres stats show approximately:

- objects: **555,974 UPDATEs** for 6,000 live rows;
- search_index: **645,414 UPDATEs** for 5,948 live rows.

Autovacuum currently reports zero dead tuples, but ordinary VACUUM does not shrink the relation files.

The objects heap is ~23 MiB while current logical row bytes are only ~5.47 MiB. That does **not** prove an exact reclaim number, but it strongly supports measuring a rewrite before considering semantic deletion.

Also already audited as unused:

- `inventory_objects_metadata_gin`: **8,208,384 bytes** (~7.83 MiB).

Together with the two unused search array GINs, the already-qualified inventory index candidates total **11,788,288 bytes = 11.24 MiB**.

**R7 decision:** first take the known ~11.24 MiB index win, then physically simulate/rewrite `inventory.objects` to measure free-space reclaim. Do not delete inventory objects to save space without a new traceability model.

Risk: **LOW-MEDIUM** for previously audited unused indexes; **MEDIUM-HIGH** for changing object retention/reconstruction semantics.

## 4. private.lf_github_reconciliation_runs_v3 — 20.64 MiB

Current:

- 7,064 rows;
- **20.64 MiB** physical;
- newest row: 2026-09-29;
- all rows are older than 7 days;
- 4,930 rows are older than 30 days.

This table is governed append-only:

`trg_00_guard_lf_github_reconciliation_runs_v3 -> fn_guard_governed_relation_v3('APPEND_ONLY')`.

The schema defaults `authoritative=true`, and current control functions read it for:

- LF artifact evidence validity;
- dependency readiness;
- artifact promotion;
- reconciliation nonce/current gate validation;
- architecture probes.

There is also at least one live FK consumer:
`private.lf_github_reconciliation_quarantine_v7.reconciliation_run_id`.

**cron 28 does not retain/delete this table.**

`private.fn_operational_retention_v1(true)` currently covers only:

- `cron.job_run_details` older than 30 days except latest per job;
- `private.lf_architecture_monitor_runs_v4`;
- old PG_NOTIFY outbox rows;
- succeeded `private.lf_profile_runtime_queue_v1` rows meeting its guard.

Job 7 is a different P0 evidence policy and only targets
`private.lf_p0_review_evidence_objects_v1`.

Therefore there is currently **no authorized retention policy** for reconciliation v3.

Risk: **VERY HIGH / canonical control evidence**.

Potential gain if a future contract allowed full external archival: at most **20.64 MiB** current physical. Do not count this as available under current rules.

## 5. private.lf_gate_test_runs_v3 — 15.30 MiB

Current:

- 6,989 rows;
- **15.30 MiB** physical;
- newest row: 2026-09-29;
- all rows are older than 7 days;
- 4,877 rows older than 30 days.

It is also governed append-only and protected by V7 writer/nonce guards.

Current readers include:

- `private.fn_gate_nonce_v6_valid`;
- `private.fn_gate_nonce_v7_valid`;
- V7 reconciliation/gate guard paths.

cron 28 does **not** cover it, and neither does the P0 retention job.

Risk: **VERY HIGH / canonical gate evidence**.

Potential gain under a future approved archive/receipt model: at most **15.30 MiB** current physical. Not available under the current no-delete-canonical-evidence rule.

## 6. Growth rate — what is actually measurable

Exact seven-day physical MiB/day is **not yet available**.

`private.lf_db_size_snapshots_v1` currently has only one historical snapshot:

- 2026-10-06 15:16 UTC:
  567,569,555 bytes = 541.28 MiB.

Current readback during this analysis:

- 599,927,955 bytes = 572.14 MiB.

That is +30.86 MiB since the first snapshot, but it spans only part of one highly active migration day and must **not** be extrapolated as a daily growth rate.

Cron 29 now captures one DB snapshot daily, so a defensible seven-day physical trend becomes available after seven daily samples.

There is no existing per-table physical-size history.

### Logical growth proxies

For the seven calendar days 2026-09-30 through 2026-10-06:

**public.lf_eventos**

- new logical row bytes: ~1.42 MiB total;
- average: ~**0.20 MiB/day logical**;
- 738 new rows.

This excludes the 2026-09-29 spike of 3,381 rows / ~7.59 MiB logical.

**inventory.objects**

- all seven-day first-seen logical bytes: ~5.47 MiB, dominated by the initial 2026-09-30 inventory bootstrap;
- after that bootstrap (Oct 1-6): only ~0.11 MiB first-seen logical data, ~0.018 MiB/day.

However this severely understates physical churn because the refresh jobs repeatedly UPDATE the same rows hundreds of thousands of times.

**reconciliation v3 / gate-test v3**

- no new rows in the last seven days;
- logical growth proxy: **0 MiB/day** over that interval.

**inventory.search_index**

- no historical row-creation timestamp suitable for daily growth;
- current refresh timestamp is shared across all rows;
- physical daily growth cannot be recovered retrospectively from current state.

## 7. Can derived-only work get us to ~400 MiB?

Starting after the accepted R5-E estimate: ~**476.95 MiB**.

Known/credible derived-space actions:

1. audited unused inventory indexes: **~11.24 MiB**;
2. full retirement/redesign of persisted `inventory.search_index`: **up to 27.23 MiB**.

If both achieved their full current footprints:

~476.95 - 11.24 - 27.23 = **438.48 MiB**.

So the known derived-only levers do **not** yet reach 400 MiB.

The two private v3 evidence tables together occupy **35.95 MiB**. Removing them after an approved archive/retention contract would mathematically bring that estimate close to **402.5 MiB**, and a measured inventory.objects rewrite could plausibly close the remaining gap.

But those two tables are canonical governed evidence today. They are **not** an authorized R7 lever.

## Recommended R7 order

1. Finish R5-E and obtain actual post-VACUUM size.
2. Apply the already-audited three unused inventory GIN removals (~11.24 MiB) in a separate owner-approved change.
3. Physically simulate `inventory.objects` and `inventory.search_index` after rewrite to quantify churn/bloat reclaim.
4. Benchmark an inventory lookup design with no persisted `search_index`. If acceptable, this is the largest safe semantic-free/derived-model lever (~27 MiB current).
5. Let cron 29 accumulate seven daily DB snapshots before setting a growth budget.
6. Do **not** touch `lf_eventos`, reconciliation v3 or gate-test v3 without a separate evidence-retention/archive contract approved by Cristhian.

Under today's governance rules, a durable ~400 MiB target is **not yet demonstrated without a new evidence-retention model**. The next safe goal after R5 is approximately the low-440s, with further improvement dependent on measured inventory bloat reclaim.
