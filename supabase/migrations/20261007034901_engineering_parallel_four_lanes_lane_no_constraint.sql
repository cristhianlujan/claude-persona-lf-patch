-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH2-20261013-001
-- source_version=20261007034901
-- source_name=engineering_parallel_four_lanes_lane_no_constraint
alter table programacion.engineering_parallel_pilot_lane_runs
  drop constraint if exists engineering_parallel_pilot_lane_runs_lane_no_check;

alter table programacion.engineering_parallel_pilot_lane_runs
  add constraint engineering_parallel_pilot_lane_runs_lane_no_check
  check (lane_no between 1 and 4);

update public.lf_error_knowledge
set evidencia=concat_ws(E'\n',nullif(evidencia,''),
  '[FOUR_LANE_LANE_NO_CONSTRAINT_FIX_20261007] lane_no storage CHECK aligned from 1..2 to 1..4. PR #1857 merge 7b00104f63f7f642b1f2a9901ddcc14ea53848ed.'),
  ultima_vez=now(),
  updated_at=now()
where codigo='ENGINEERING-PARALLEL-EXECUTOR-V1-001';
