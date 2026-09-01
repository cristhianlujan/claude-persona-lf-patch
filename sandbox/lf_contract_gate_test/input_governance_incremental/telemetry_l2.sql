-- INPUT_GOVERNANCE_AGENT incremental improvement L2
-- Read-only telemetry harness. No canonical DDL, no state mutation.
-- EKB: EKB-INPUT-GOV-INCREMENTAL-20260901-02
-- Baseline run 183 is historical evidence only; it is not current and is never treated as a live receipt.

-- 1) Historical end-to-end latency from the latest 30 completed v19 runs.
-- NOTE: current historical rows co-timestamp curator_completed_at and validator_completed_at,
-- so this query intentionally does NOT claim separate validator latency.
with recent_completed as (
  select
    r.id,
    p.codigo as screen_code,
    extract(epoch from (r.curator_completed_at-r.created_at))*1000 as curator_to_recorded_completion_ms,
    extract(epoch from (r.validator_completed_at-r.created_at))*1000 as total_recorded_ms
  from programacion.input_readiness_runs r
  join lf_ops.pantallas p on p.id=r.pantalla_id
  where r.version_id=19
    and r.status='COMPLETED'
    and r.curator_completed_at is not null
    and r.validator_completed_at is not null
  order by r.id desc
  limit 30
)
select
  count(*) as runs,
  round(percentile_cont(0.5) within group(order by total_recorded_ms)::numeric,1) as total_p50_ms,
  round(percentile_cont(0.95) within group(order by total_recorded_ms)::numeric,1) as total_p95_ms,
  round(max(total_recorded_ms)::numeric,1) as total_max_ms
from recent_completed;

-- 2) Context-size economics: full 47-family payload versus governed selective payload.
with full_payload as (
  select jsonb_agg(
    jsonb_build_object(
      'family_code',family_code,
      'applicability',applicability,
      'story_ready_status',story_ready_status,
      'implementation_ready_status',implementation_ready_status,
      'qa_ready_status',qa_ready_status,
      'production_ready_status',production_ready_status,
      'source_refs',source_refs,
      'blockers',blockers,
      'negative_requirements',negative_requirements,
      'validator_outcome',validator_outcome
    ) order by family_code
  ) j
  from programacion.input_family_assessments
  where run_id=183
), selected5 as (
  select jsonb_agg(
    jsonb_build_object(
      'family_code',family_code,
      'applicability',applicability,
      'story_ready_status',story_ready_status,
      'implementation_ready_status',implementation_ready_status,
      'qa_ready_status',qa_ready_status,
      'production_ready_status',production_ready_status,
      'source_refs',source_refs,
      'blockers',blockers,
      'negative_requirements',negative_requirements,
      'validator_outcome',validator_outcome
    ) order by family_code
  ) j
  from programacion.input_family_assessments
  where run_id=183
    and family_code in (
      'APPLICABILITY_READINESS',
      'SOURCE_AUTHORITY_PROVENANCE',
      'FRESHNESS_INVALIDATION',
      'NEGATIVE_REQUIREMENTS',
      'CONFLICT_PRECEDENCE'
    )
), selected2 as (
  select jsonb_agg(
    jsonb_build_object(
      'family_code',family_code,
      'applicability',applicability,
      'story_ready_status',story_ready_status,
      'source_refs',source_refs,
      'validator_outcome',validator_outcome
    ) order by family_code
  ) j
  from programacion.input_family_assessments
  where run_id=183
    and family_code in ('APPLICABILITY_READINESS','SOURCE_AUTHORITY_PROVENANCE')
)
select
  octet_length(full_payload.j::text) as full_47_bytes,
  octet_length(selected5.j::text) as selected_5_bytes,
  round((1-octet_length(selected5.j::text)::numeric/nullif(octet_length(full_payload.j::text),0))*100,1) as selected5_reduction_pct,
  octet_length(selected2.j::text) as selected_2_bytes,
  round((1-octet_length(selected2.j::text)::numeric/nullif(octet_length(full_payload.j::text),0))*100,1) as selected2_reduction_pct
from full_payload,selected5,selected2;

-- 3) Deterministic read-path microbenchmark.
-- TEMP only; no persistent table/function is created.
create temp table _ig_l2_bench(kind text, ms numeric) on commit drop;
do $$
declare
  i integer;
  t0 timestamptz;
  dummy jsonb;
  c integer;
begin
  for i in 1..50 loop
    t0:=clock_timestamp();
    dummy:=programacion.fn_input_governance_worker_spec(51,'STORY_CREATOR');
    insert into _ig_l2_bench values ('worker_spec',extract(epoch from (clock_timestamp()-t0))*1000);

    t0:=clock_timestamp();
    perform programacion.fn_input_stage_gate_summary(183);
    insert into _ig_l2_bench values ('stage_gate',extract(epoch from (clock_timestamp()-t0))*1000);

    t0:=clock_timestamp();
    select count(*) into c
    from programacion.input_family_assessments
    where run_id=183
      and family_code in (
        'APPLICABILITY_READINESS',
        'SOURCE_AUTHORITY_PROVENANCE',
        'FRESHNESS_INVALIDATION',
        'NEGATIVE_REQUIREMENTS',
        'CONFLICT_PRECEDENCE'
      )
      and validator_outcome='PASS';
    insert into _ig_l2_bench values ('select_5_families',extract(epoch from (clock_timestamp()-t0))*1000);
  end loop;
end $$;
select
  kind,
  count(*) as n,
  round(percentile_cont(0.5) within group(order by ms)::numeric,3) as p50_ms,
  round(percentile_cont(0.95) within group(order by ms)::numeric,3) as p95_ms,
  round(max(ms),3) as max_ms
from _ig_l2_bench
group by kind
order by kind;
