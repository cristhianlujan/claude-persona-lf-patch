-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M8.2 / TIMING_SINK
-- Performance evidence is a typed receipt in the EXISTING provenance authority.
-- It must not enter input_family_assessments.curator_evidence, curator_sha256,
-- validator_evidence, or a semantic fingerprint. No new shared engine or table.
-- This is a sink contract, NOT a claim that per-run timings are already emitted.
-- Only the preexisting EVIDENCE_VERIFIER_V1 channel can issue the receipt through
-- programacion.issue_provenance_receipt with its existing authorization token.

alter table programacion.provenance_receipts
  add constraint provenance_receipts_ig_performance_timing_sink_v1
  check (
    subject_type is distinct from 'IG_PERFORMANCE_TIMING'
    or coalesce(
      (
        receipt_kind = 'EVIDENCE_VERIFICATION'
        and issuer_channel = 'EVIDENCE_VERIFIER_V1'
        and payload->>'schema_version' = 'IG_PERFORMANCE_TIMING_RECEIPT_V1'
        and payload->>'verification_status' in ('VERIFIED','REJECTED')
        and nullif(btrim(payload->>'verifier_identity'),'') is not null
        and payload->>'subject_type' = subject_type
        and payload->>'subject_ref' = subject_ref
        and payload->>'subject_sha256' = subject_sha256
        and payload->>'head_sha' = head_sha
        and payload->>'run_id' ~ '^[1-9][0-9]*$'
        and subject_ref = 'input-readiness-run:'||(payload->>'run_id')
        and payload->>'source_snapshot_sha256' ~ '^[0-9a-f]{64}$'
        and payload->>'measurement_method' in ('MONOTONIC_ELAPSED_OBSERVED','CLOCK_TIMESTAMP_OBSERVED')
        and payload->>'phase' in ('CURATOR','VALIDATOR','TOTAL','FAMILY')
        and (payload->>'phase' <> 'FAMILY'
             or nullif(btrim(payload->>'family_code'),'') is not null)
        and jsonb_typeof(payload->'elapsed_ms') = 'number'
        and payload->>'elapsed_ms' ~ '^[0-9]{1,12}$'
        and nullif(btrim(payload->>'measurement_ref'),'') is not null
        and nullif(btrim(payload->>'measured_at'),'') is not null
        and payload->>'semantic_sha_excluded' = 'true'
      ),false
    )
  );

create index if not exists provenance_receipts_ig_performance_timing_by_run_v1
  on programacion.provenance_receipts
  ((payload->>'run_id'),(payload->>'phase'),created_at desc)
  where subject_type='IG_PERFORMANCE_TIMING';

comment on constraint provenance_receipts_ig_performance_timing_sink_v1
  on programacion.provenance_receipts is
  'M8.2 typed timing sink. EVIDENCE_VERIFICATION channel token remains mandatory; source SHA and real measured ms are payload-bound. Semantic hashes and assessments are never mutated by timing receipts. VERIFIED means provenance verification, not SLO acceptance.';

do $m82_guard$
begin
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid='programacion.provenance_receipts'::regclass
      and c.conname='provenance_receipts_ig_performance_timing_sink_v1'
      and c.convalidated
  ) then raise exception 'M8_2_TIMING_SINK_GUARD_NOT_VALID'; end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname='programacion'
      and tablename='provenance_receipts'
      and indexname='provenance_receipts_ig_performance_timing_by_run_v1'
  ) then raise exception 'M8_2_TIMING_SINK_INDEX_MISSING'; end if;
  if exists (
    select 1 from programacion.provenance_receipts p
    where p.subject_type='IG_PERFORMANCE_TIMING'
      and (p.receipt_kind<>'EVIDENCE_VERIFICATION'
      or p.payload->>'schema_version'<>'IG_PERFORMANCE_TIMING_RECEIPT_V1')
  ) then raise exception 'M8_2_TIMING_SINK_PREEXISTING_DRIFT'; end if;
end;
$m82_guard$;
