-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · M8.1 / PAULO-013
-- Persist minimal per-run phase timings without changing runtime execution paths.
-- PHASE_MODEL:
--   curator_duration_ms   = created_at -> curator_completed_at
--   validator_duration_ms = curator_completed_at -> validator_completed_at
-- The columns are stored generated values so historical and future runs share one deterministic model.

alter table programacion.input_readiness_runs
  add column curator_duration_ms bigint generated always as (
    case
      when curator_completed_at is null then null
      else round(extract(epoch from (curator_completed_at - created_at)) * 1000)::bigint
    end
  ) stored,
  add column validator_duration_ms bigint generated always as (
    case
      when validator_completed_at is null or curator_completed_at is null then null
      else round(extract(epoch from (validator_completed_at - curator_completed_at)) * 1000)::bigint
    end
  ) stored;

alter table programacion.input_readiness_runs
  add constraint input_readiness_runs_curator_duration_nonnegative_chk
    check (curator_duration_ms is null or curator_duration_ms >= 0),
  add constraint input_readiness_runs_validator_duration_nonnegative_chk
    check (validator_duration_ms is null or validator_duration_ms >= 0);

comment on column programacion.input_readiness_runs.curator_duration_ms is
  'M8.1 persisted Curator phase duration in milliseconds: created_at -> curator_completed_at.';

comment on column programacion.input_readiness_runs.validator_duration_ms is
  'M8.1 persisted Validator phase duration in milliseconds: curator_completed_at -> validator_completed_at.';
