-- ENGINEERING_PARALLEL_EXECUTOR_V1: align storage constraint with 4-lane contract.
-- Scope: preserve historical 2-lane runs; allow current 4-lane runs only.
-- max_turns_per_lane and selector semantics are unchanged.

alter table programacion.engineering_parallel_pilot_runs
  drop constraint if exists engineering_parallel_pilot_runs_max_lanes_check;

alter table programacion.engineering_parallel_pilot_runs
  add constraint engineering_parallel_pilot_runs_max_lanes_check
  check (max_lanes in (2,4));

update public.lf_error_knowledge
set evidencia=concat_ws(E'\n',nullif(evidencia,''),
    '[FOUR_LANE_STORAGE_CONSTRAINT_FIX_20261007] Storage CHECK aligned with the authorized 4-lane scheduler contract while preserving historical 2-lane runs.'),
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-PARALLEL-EXECUTOR-V1-001';
