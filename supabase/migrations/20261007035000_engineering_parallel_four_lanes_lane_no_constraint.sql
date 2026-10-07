-- Complete the authorized 4-lane storage contract.
-- Historical rows remain valid; current lane numbers may be 1..4.
alter table programacion.engineering_parallel_pilot_lane_runs
  drop constraint if exists engineering_parallel_pilot_lane_runs_lane_no_check;

alter table programacion.engineering_parallel_pilot_lane_runs
  add constraint engineering_parallel_pilot_lane_runs_lane_no_check
  check (lane_no between 1 and 4);

update public.lf_error_knowledge
set evidencia=concat_ws(E'\n',nullif(evidencia,''),
  '[FOUR_LANE_LANE_NO_CONSTRAINT_FIX_20261007] lane_no storage CHECK aligned from 1..2 to 1..4.'),
  ultima_vez=now(),
  updated_at=now()
where codigo='ENGINEERING-PARALLEL-EXECUTOR-V1-001';
