-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261009210015
-- source_name=t_remed_indexes_v3
-- T-REMED performance: indexes for the lookups the layers and undo perform.
create index if not exists t_remed_change_log_subject_idx on programacion.t_remed_change_log (subject_kind, subject_id, layer, created_at);
create index if not exists t_remed_change_log_target_idx on programacion.t_remed_change_log (target_table, pk_value) where reverted_at is null;
create index if not exists t_remed_links_subject_idx on programacion.t_remed_links (subject_kind, subject_id, status);
