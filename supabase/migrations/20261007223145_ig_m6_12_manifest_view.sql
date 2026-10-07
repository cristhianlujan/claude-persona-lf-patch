-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M6.12 / MANIFEST_VIEW
-- Manifest = ordered union of the compact receipts actually stored by each IG run.
-- Do not infer receipts from unrelated provenance channels or synthesize absent evidence.
-- Project legacy full observations to compact fields, never expose 'observed'.
-- Preserve distinct observations; deduplicate only fully identical JSONB receipts.

create or replace view programacion.v_input_run_manifest
with (security_invoker = true)
as
with used_receipts as (
  select r.id as run_id,
         jsonb_strip_nulls(jsonb_build_object(
           'schema_version', coalesce(e.value->>'schema_version','IG_SOURCE_RECEIPT_V1'),
           'ref', e.value->'ref',
           'authority', e.value->'authority',
           'lifecycle', e.value->'lifecycle',
           'observed_sha256', e.value->>'observed_sha256',
           'archive_contract', e.value->'archive_contract'
         )) as receipt
  from programacion.input_readiness_runs r
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(r.source_manifest) = 'array'
         then r.source_manifest else '[]'::jsonb end
  ) e(value)
  where jsonb_typeof(e.value) = 'object'
    and jsonb_typeof(e.value->'ref') = 'object'
    and e.value ? 'authority'
    and coalesce(e.value->>'observed_sha256','') ~ '^[0-9a-f]{64}$'
), unique_receipts as (
  select distinct run_id, receipt from used_receipts
), canonical as (
  select run_id,
         count(*)::integer as receipt_count,
         jsonb_agg(
           receipt
           order by (receipt->'ref')::text,
                    receipt->>'observed_sha256',
                    receipt::text
         ) as source_manifest
  from unique_receipts
  group by run_id
)
select run_id,
       receipt_count,
       source_manifest,
       programacion.fn_v09_sha256_jsonb(source_manifest) as manifest_sha256
from canonical;

comment on view programacion.v_input_run_manifest is
  'M6.12: deterministic deduplicated union of per-run compact receipts actually used; never invent provenance or merge conflicting observed values; security invoker.';

-- Migration-local readback: one existing run; exact reproduction from stored receipts,
-- stable canonical digest, and no full observed payload in the result.
do $m612_verify$
declare
  v_run_id bigint;
  v_legacy_run_id bigint;
  v_m jsonb;
  v_m_again jsonb;
  v_count integer;
  v_unique_count integer;
  v_digest text;
begin
  select id into v_run_id
  from programacion.input_readiness_runs
  where jsonb_typeof(source_manifest) = 'array'
    and jsonb_array_length(source_manifest) > 0
  order by id desc limit 1;

  if v_run_id is null then
    raise exception 'M6_12_NO_EXISTING_SOURCE_RECEIPTS_FOR_READBACK';
  end if;

  select source_manifest, receipt_count, manifest_sha256
    into v_m, v_count, v_digest
  from programacion.v_input_run_manifest
  where run_id = v_run_id;

  select source_manifest into v_m_again
  from programacion.v_input_run_manifest
  where run_id = v_run_id;

  select count(distinct e.value)
    into v_unique_count
  from programacion.input_readiness_runs r
  cross join lateral jsonb_array_elements(r.source_manifest) e(value)
  where r.id = v_run_id;

  if v_m is null or v_count <> v_unique_count
     or v_count <> jsonb_array_length(v_m)
     or v_m is distinct from v_m_again
     or v_digest is distinct from programacion.fn_v09_sha256_jsonb(v_m)
     or v_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'M6_12_MANIFEST_NOT_REPRODUCIBLE_FOR_RUN:%',v_run_id;
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_m) e(value)
    where e.value ? 'observed'
  ) then
    raise exception 'M6_12_FULL_OBSERVED_PAYLOAD_FORBIDDEN:%',v_run_id;
  end if;

  -- Negative regression: legacy runs may store full observations, but the view
  -- must expose only their compact receipt projection.
  select r.id into v_legacy_run_id
  from programacion.input_readiness_runs r
  cross join lateral jsonb_array_elements(r.source_manifest) e(value)
  where e.value ? 'observed'
  order by r.id desc
  limit 1;

  if v_legacy_run_id is not null and exists (
    select 1
    from programacion.v_input_run_manifest m
    cross join lateral jsonb_array_elements(m.source_manifest) e(value)
    where m.run_id = v_legacy_run_id and e.value ? 'observed'
  ) then
    raise exception 'M6_12_LEGACY_PAYLOAD_LEAK:%',v_legacy_run_id;
  end if;
end;
$m612_verify$;
