# DB-SPACE PR-IDX-1 — INDEX CLEANUP v1

Base audited: `ed61e9bdac25de5f4bc5a8be3cd7cef21f525b56`.

This PR is prepared only. It must not be applied, merged or deployed without owner approval.

## Why regular DROP INDEX in the migration

`DROP INDEX CONCURRENTLY` cannot run inside a transaction block. This PR keeps every schema change in one versioned migration, and all affected tables are small enough that the eventual apply can be done in a controlled maintenance window with a short metadata lock. The migration uses ordinary `DROP INDEX` and fail-closed preflights instead of moving schema state outside migration history.

## Removal set

| Index | MB now | Reason | Consumers reviewed | Rollback |
|---|---:|---|---|---|
| public.uq_lf_operation_execution_steps_execution_order | 0.61 | exact duplicate of PK (execution_id,step_order) | pg_constraint/conindid + dependent constraints; PK retained | exact CREATE in rollback file |
| public.uq_lf_operation_steps_operation_step | 0.07 | exact duplicate of constraint-backed unique index | constraint/dependency graph | exact CREATE |
| public.uq_lf_operation_steps_operation_order | 0.06 | exact duplicate of PK | constraint/dependency graph | exact CREATE |
| public.uq_lf_operation_judges_operation_judge | 0.07 | exact duplicate of PK | constraint/dependency graph | exact CREATE |
| lf_ops.idx_rp_pantalla | 0.11 | exact duplicate of idx_reglas_pantallas_screen | no constraint dependency | exact CREATE |
| lf_ops.ux_perfiles_permisos_numeric | 0.03 | exact duplicate of constraint-backed key | no dependent constraint | exact CREATE |
| lf_ops.idx_campos_pant_pant | 0.02 | exact duplicate of idx_campos_pantallas_screen | no constraint dependency | exact CREATE |
| lf_ops.ux_user_number | 0.02 | duplicate of constraint-backed user_number key | no dependent constraint | exact CREATE |
| lf_ops.ux_usuarios_perfiles_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_usuarios_permisos_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_company_number | 0.02 | duplicate of constraint-backed company_number key | no dependent constraint | exact CREATE |
| lf_ops.ux_trace_number | 0.02 | duplicate of constraint-backed trace_number key | no dependent constraint | exact CREATE |
| lf_ops.ux_transiciones_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_menu_permisos_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_alert_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_variant_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_pantallas_perfiles_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_pantallas_permisos_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_ops.ux_approval_number | 0.01 | duplicate of constraint-backed approval_number key | no dependent constraint | exact CREATE |
| lf_ops.idx_audit_events_load | 0.01 | exact duplicate of idx_auditoria_load_time | no constraint dependency | exact CREATE |
| lf_ops.ux_audit_number | 0.01 | duplicate of constraint-backed audit_number key | no dependent constraint | exact CREATE |
| lf_ops.ux_file_number | 0.01 | duplicate of constraint-backed file_number key | no dependent constraint | exact CREATE |
| lf_ops.ux_load_number | 0.01 | duplicate of constraint-backed load_number key | no dependent constraint | exact CREATE |
| lf_design.ux_icon_catalog_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| lf_design.ux_visual_decisions_numeric | 0.02 | duplicate of PK | no dependent constraint | exact CREATE |
| public.idx_lf_strategy_snapshots_payload | 6.38 | no demonstrated consumer of GIN-compatible operator on content_payload | 23 DB functions, v_lf_strategy_latest, policies, triggers, repo and all live Edge Functions; the only ?| is on p_patch metadata_merge, not the column | exact CREATE |
| public.idx_lf_strategy_snapshots_metadata | 2.15 | no demonstrated consumer of GIN-compatible operator on metadata | same audit as payload | exact CREATE |
| public.ix_lf_backlog_errores_metadata_gin | 1.02 | no demonstrated metadata GIN consumer | pg_proc/views/policies/triggers, repo and all live Edge Functions | exact CREATE |

Current bytes removed if applied: approximately **10.76 MB**. This is logical index footprint, not an additional REINDEX estimate.

Pairs where **both** duplicate indexes back constraints are intentionally excluded.

## Inventory GIN recommendation — not in migration

| Index | Current behavior | Recommendation |
|---|---|---|
| inventory_objects_metadata_gin (~7.8 MB) | 16 functions reference inventory.objects, but no current function uses metadata containment operators; repo mentions only creation | recommend DROP in a later owner-approved change; no need for jsonb_path_ops without a consumer |
| inventory_search_document_gin (~5.5 MB) | fn_lookup_v2/v3 use search_document @@ plainto_tsquery; EXPLAIN selects Bitmap Index Scan on this exact GIN | KEEP |
| inventory_search_tags_gin (~2.0 MB) | fn_lookup_v2/v3 use scalar = ANY(tags_lc); EXPLAIN is Seq Scan; no tags_lc @> consumer found | recommend DROP in a later owner-approved change |
| inventory_search_columns_gin (~1.5 MB) | lookup uses scalar = ANY(column_names_lc); EXPLAIN is Seq Scan; no column_names_lc @> consumer found | recommend DROP in a later owner-approved change |

`jsonb_path_ops` is not an alternative for the tsvector/array indexes. It would only be relevant for a JSONB containment workload, which is not currently demonstrated for inventory.objects.metadata.

## REINDEX maintenance runbook — not part of migration

Do not run as part of this PR. Run only after explicit owner approval, one index at a time:

```sql
select pg_database_size(current_database()) as before_bytes;

reindex index concurrently public.stg_gov_inventario_documentos__migration_batch_id_id_activo_key;

select
  pg_database_size(current_database()) as after_bytes,
  i.indisvalid,
  i.indisready
from pg_index i
where i.indexrelid='public.stg_gov_inventario_documentos__migration_batch_id_id_activo_key'::regclass;
```

Repeat the same before/reindex/readback sequence for:
- `public.stg_gov_inventario_documentos_migration_batch_id_source_she_key`
- `public.stg_gov_inv_id_activo_idx`
- then the remaining B-tree candidates ordered by estimated savings.

Never batch multiple concurrent rebuilds. Stop immediately if `indisvalid=false`, disk headroom is insufficient, or database size increases unexpectedly and does not settle.
