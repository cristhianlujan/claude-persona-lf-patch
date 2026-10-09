-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M8.2 / TERMINAL
-- Publishes the per-family / per-resolver timings the Curator already measures (IG_CURATOR_PER_FAMILY_TIMING_V1) as
-- IG_PERFORMANCE_TIMING receipts through the existing EVIDENCE_VERIFIER_V1 channel, the same in-database mechanism used by
-- the Curator handoff receipt and the release-bundle receipt. Timings never enter curator_sha256 / validator_evidence.
-- 1) sink: phase RESOLVER accepted (requires resolver_code). 2) emitter. 3) governed SQL dispatcher emits after the Curator.

alter table programacion.provenance_receipts
  drop constraint provenance_receipts_ig_performance_timing_sink_v1,
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
        and payload->>'phase' in ('CURATOR','VALIDATOR','TOTAL','FAMILY','RESOLVER')
        and (payload->>'phase' <> 'FAMILY'
             or nullif(btrim(payload->>'family_code'),'') is not null)
        and (payload->>'phase' <> 'RESOLVER'
             or nullif(btrim(payload->>'resolver_code'),'') is not null)
        and jsonb_typeof(payload->'elapsed_ms') = 'number'
        and payload->>'elapsed_ms' ~ '^[0-9]{1,12}$'
        and nullif(btrim(payload->>'measurement_ref'),'') is not null
        and nullif(btrim(payload->>'measured_at'),'') is not null
        and payload->>'semantic_sha_excluded' = 'true'
      ),false
    )
  );

CREATE OR REPLACE FUNCTION programacion.fn_ig_timing_receipts_emit_v1(p_run_id bigint, p_observation jsonb, p_source_graph_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $fn$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_head constant text := '42cc13e35a11b9fe7ab711ad2ee666778c765f91';
  v_issuer constant text := 'SUPABASE:INPUT_GOVERNANCE_TIMING_V1';
  v_ref text; v_token text; v_span jsonb; v_item record; v_n integer:=0; v_expected integer;
  v_now text:=to_char(clock_timestamp() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if p_observation is null or p_observation->>'schema_version' is distinct from 'IG_CURATOR_PER_FAMILY_TIMING_V1'
     or p_observation->>'capture_status' is distinct from 'OBSERVED'
     or p_observation->>'measurement_method' is distinct from 'CLOCK_TIMESTAMP_OBSERVED' then
    raise exception 'IG_TIMING_EMIT_OBSERVATION_NOT_OBSERVED';
  end if;
  if (p_observation->>'run_id')::bigint is distinct from p_run_id then raise exception 'IG_TIMING_EMIT_RUN_MISMATCH:%',p_run_id; end if;
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  -- A run being curated has no validator-stamped source_snapshot_sha256 yet; the timing receipt binds the canonical source graph
  -- digest the Curator actually read (request_context_summary.graph_sha256) and says so in source_snapshot_kind.
  if not found or coalesce(p_source_graph_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'IG_TIMING_EMIT_RUN_OR_SOURCE_DIGEST_INVALID:%',p_run_id; end if;
  v_ref:='input-readiness-run:'||p_run_id::text;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='EVIDENCE_VERIFIER_V1_TOKEN' order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'IG_TIMING_EMIT_EVIDENCE_VERIFIER_TOKEN_MISSING'; end if;
  v_expected:=(p_observation->>'expected_family_count')::integer;
  if jsonb_array_length(p_observation->'per_family_resolver_spans') is distinct from v_expected or v_expected<=0 then
    raise exception 'IG_TIMING_EMIT_SPAN_COUNT_MISMATCH:%',p_run_id;
  end if;

  for v_item in
    select 'FAMILY'::text phase, s->>'family_code' family_code, null::text resolver_code,
           round(coalesce((s->>'deterministic_elapsed_ms')::numeric,0)+coalesce((s->>'semantic_elapsed_ms')::numeric,0))::bigint ms
      from jsonb_array_elements(p_observation->'per_family_resolver_spans') s
    union all
    select 'RESOLVER', s->>'family_code', s->>'deterministic_resolver', round(coalesce((s->>'deterministic_elapsed_ms')::numeric,0))::bigint
      from jsonb_array_elements(p_observation->'per_family_resolver_spans') s
    union all
    select 'RESOLVER', s->>'family_code', s->>'semantic_resolver', round(coalesce((s->>'semantic_elapsed_ms')::numeric,0))::bigint
      from jsonb_array_elements(p_observation->'per_family_resolver_spans') s
     where coalesce((s->>'semantic_invoked')::boolean,false)
    union all
    select 'TOTAL', null, null, greatest(0,(p_observation->>'sql_total_elapsed_ms')::numeric)::bigint
  loop
    declare
      v_subject jsonb; v_sha text; v_payload jsonb; v_id bigint;
    begin
      v_subject:=jsonb_build_object('schema_version','IG_PERFORMANCE_TIMING_SUBJECT_V1','run_id',p_run_id,'phase',v_item.phase,
        'family_code',v_item.family_code,'resolver_code',v_item.resolver_code,'elapsed_ms',v_item.ms,
        'source_snapshot_sha256',p_source_graph_sha256);
      v_sha:=programacion.fn_v09_sha256_jsonb(v_subject);
      if exists(select 1 from programacion.provenance_receipts r where r.subject_type='IG_PERFORMANCE_TIMING' and r.subject_ref=v_ref
                and r.subject_sha256=v_sha and r.head_sha=v_head) then continue; end if;
      v_payload:=jsonb_strip_nulls(jsonb_build_object('schema_version','IG_PERFORMANCE_TIMING_RECEIPT_V1','head_sha',v_head,
        'subject_type','IG_PERFORMANCE_TIMING','subject_ref',v_ref,'subject_sha256',v_sha,'verification_status','VERIFIED',
        'verifier_identity',v_issuer,'verification_method','SUPABASE_CURATOR_CLOCK_TIMESTAMP_SPAN_V1','run_id',p_run_id::text,
        'source_snapshot_sha256',p_source_graph_sha256,'source_snapshot_kind','CURATOR_CANONICAL_SOURCE_GRAPH_SHA256','measurement_method','CLOCK_TIMESTAMP_OBSERVED','phase',v_item.phase,
        'family_code',case when v_item.phase='FAMILY' then v_item.family_code end,'covered_family_code',case when v_item.phase='RESOLVER' then v_item.family_code end,
        'resolver_code',v_item.resolver_code,'elapsed_ms',v_item.ms,
        'measurement_ref','supabase://programacion.input_readiness_runs/'||p_run_id::text||'#curator-timing',
        'measured_at',v_now,'semantic_sha_excluded',true));
      select r.id into v_id from programacion.issue_provenance_receipt('EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',null,v_head,
        'IG_PERFORMANCE_TIMING',v_ref,v_sha,v_issuer,'supabase://programacion.input_readiness_runs/'||p_run_id::text||'#curator-timing',v_payload) r;
      v_n:=v_n+1;
    end;
  end loop;
  return jsonb_build_object('status','PERSISTED','schema_version','IG_TIMING_RECEIPTS_EMIT_V1','run_id',p_run_id,'receipts_issued',v_n,
    'semantic_sha_excluded',true);
end;
$fn$;
