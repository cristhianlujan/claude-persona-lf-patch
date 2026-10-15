-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH2-20261013-001
-- source_version=20261007032243
-- source_name=engineering_parallel_executor_four_lanes_constraint_fix
alter table programacion.engineering_parallel_pilot_runs
  drop constraint if exists engineering_parallel_pilot_runs_max_lanes_check;

alter table programacion.engineering_parallel_pilot_runs
  add constraint engineering_parallel_pilot_runs_max_lanes_check
  check (max_lanes in (2,4));

update public.lf_error_knowledge
set evidencia=concat_ws(E'\n',nullif(evidencia,''),
    '[FOUR_LANE_STORAGE_CONSTRAINT_FIX_20261007] Storage CHECK aligned with the authorized 4-lane scheduler contract while preserving historical 2-lane runs. PR #1855 merge ca992311546529ef5648bee9bf408caf109d121b.'),
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-PARALLEL-EXECUTOR-V1-001';
