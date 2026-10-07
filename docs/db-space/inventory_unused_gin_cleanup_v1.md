# Inventory unused GIN cleanup

Status: **DRAFT / DO NOT APPLY**

## Exact physical footprint and runtime counters

Read-only live observation:

| Index | Bytes | MiB | pg_stat_user_indexes.idx_scan |
|---|---:|---:|---:|
| inventory_objects_metadata_gin | 8,208,384 | 7.83 | 0 |
| inventory_search_tags_gin | 2,064,384 | 1.97 | 0 |
| inventory_search_columns_gin | 1,515,520 | 1.45 | 0 |

Total current physical footprint: **11,788,288 bytes = 11.24 MiB**.

The migration fail-closes if any of the three indexes has a non-zero `idx_scan` at apply time or if its exact index definition has changed.

## Readers reviewed

All live DB functions whose definitions reference either `inventory.objects` or `inventory.search_index` were scanned.

### objects.metadata

No live function uses a GIN-compatible predicate against `inventory.objects.metadata`:

- no `metadata @> ...`;
- no `metadata ? ...`;
- no `metadata @@ ...`;
- no `metadata @? ...`.

The metadata GIN therefore has no demonstrated DB-function consumer.

### search_index.tags_lc

Potential readers:

`inventory.fn_lookup_v2(...)` and `inventory.fn_lookup_v3(...)`.

Their predicate is scalar-array membership:

```sql
lower(btrim(p_term)) = any(e.tags_lc)
```

This is not an array-containment predicate such as `tags_lc @> ARRAY[...]` or overlap `&&`, so it does not use the audited GIN operator path.

### search_index.column_names_lc

The same lookup functions use:

```sql
lower(btrim(p_term)) = any(e.column_names_lc)
```

Again, no `@>` / `&&` consumer exists in the live DB function corpus.

## Index explicitly retained

`inventory_search_document_gin` is **not** part of this PR.

Lookup v2/v3 use:

```sql
e.search_document @@ plainto_tsquery('simple', lower(btrim(p_term)))
```

which is the intended full-text GIN access pattern. Even though its current `idx_scan` counter is also 0 in the present stats window, its query/operator contract is real and it remains.

## Rollback

Exact rollback definitions:

```sql
CREATE INDEX inventory_objects_metadata_gin
  ON inventory.objects USING gin (metadata);

CREATE INDEX inventory_search_tags_gin
  ON inventory.search_index USING gin (tags_lc);

CREATE INDEX inventory_search_columns_gin
  ON inventory.search_index USING gin (column_names_lc);
```

No REINDEX and no table data change are included.
