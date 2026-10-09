-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M8.11 / RECEIPT_PER_RUN
-- Every COMPLETED run gets a VERIFIED IG_PERFORMANCE_TIMING receipt for the VALIDATOR phase (wall-clock plus the compute/wait split
-- from input_validator_chunk_timings), bound to the release head and the run source snapshot, through the same in-database
-- EVIDENCE_VERIFIER_V1 channel as the Curator timing receipts. Timings never enter curator_sha256 / validator_evidence.
-- Idempotent per (run, measured values). The dispatcher emits it after COMPLETED; an emission failure never changes the outcome.
CREATE OR REPLACE FUNCTION programacion.fn_ig_validator_timing_receipt_emit_v1(p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $fn$
declare
  v_head constant text := '42cc13e35a11b9fe7ab711ad2ee666778c765f91';
  v_issuer constant text := 'SUPABASE:INPUT_GOVERNANCE_TIMING_V1';
  v_ref text := 'input-readiness-run:'||p_run_id::text;
  v_run programacion.input_readiness_runs%rowtype;
  v_token text; v_subject jsonb; v_sha text; v_payload jsonb; v_id bigint; v_existing bigint;
  v_chunks integer; v_compute bigint; v_wait bigint;
  v_now text:=to_char(clock_timestamp() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found or v_run.status is distinct from 'COMPLETED' or v_run.validator_completed_at is null
     or v_run.curator_completed_at is null or coalesce(v_run.source_snapshot_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'IG_VALIDATOR_TIMING_RUN_NOT_COMPLETED:%',p_run_id;
  end if;
  select count(*), coalesce(sum(duration_ms),0), coalesce(sum(wait_resume_ms),0)
    into v_chunks, v_compute, v_wait from programacion.input_validator_chunk_timings where run_id=p_run_id;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='EVIDENCE_VERIFIER_V1_TOKEN' order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'IG_VALIDATOR_TIMING_EVIDENCE_VERIFIER_TOKEN_MISSING'; end if;

  v_subject:=jsonb_build_object('schema_version','IG_PERFORMANCE_TIMING_SUBJECT_V1','run_id',p_run_id,'phase','VALIDATOR',
    'elapsed_ms',v_run.validator_duration_ms,'chunk_count',v_chunks,'compute_ms',v_compute,'wait_resume_ms',v_wait,
    'source_snapshot_sha256',v_run.source_snapshot_sha256);
  v_sha:=programacion.fn_v09_sha256_jsonb(v_subject);
  select id into v_existing from programacion.provenance_receipts
   where subject_type='IG_PERFORMANCE_TIMING' and subject_ref=v_ref and subject_sha256=v_sha and head_sha=v_head order by id desc limit 1;
  if v_existing is not null then
    return jsonb_build_object('status','ALREADY_PERSISTED','run_id',p_run_id,'receipt_id',v_existing);
  end if;
  v_payload:=jsonb_strip_nulls(jsonb_build_object('schema_version','IG_PERFORMANCE_TIMING_RECEIPT_V1','head_sha',v_head,
    'subject_type','IG_PERFORMANCE_TIMING','subject_ref',v_ref,'subject_sha256',v_sha,'verification_status','VERIFIED',
    'verifier_identity',v_issuer,'verification_method','SUPABASE_VALIDATOR_PHASE_TIMESTAMPS_V1','run_id',p_run_id::text,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,'source_snapshot_kind','RUN_SOURCE_SNAPSHOT_SHA256',
    'measurement_method','CLOCK_TIMESTAMP_OBSERVED','phase','VALIDATOR','elapsed_ms',v_run.validator_duration_ms,
    'chunk_count',v_chunks,'compute_ms',v_compute,'wait_resume_ms',v_wait,
    'measurement_ref','supabase://programacion.input_readiness_runs/'||p_run_id::text||'#validator-timing',
    'measured_at',v_now,'semantic_sha_excluded',true));
  select r.id into v_id from programacion.issue_provenance_receipt('EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',null,v_head,
    'IG_PERFORMANCE_TIMING',v_ref,v_sha,v_issuer,'supabase://programacion.input_readiness_runs/'||p_run_id::text||'#validator-timing',v_payload) r;
  return jsonb_build_object('status','PERSISTED','run_id',p_run_id,'receipt_id',v_id,'elapsed_ms',v_run.validator_duration_ms,
    'compute_ms',v_compute,'wait_resume_ms',v_wait,'chunk_count',v_chunks);
end;
$fn$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_direct_step_v1(p_pantalla_id integer, p_consumer text DEFAULT 'STORY_CREATOR'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
declare
 v_read jsonb;
 v_curator jsonb;
 v_validation jsonb;
 v_status text;
 v_version bigint;
 v_run record;
 v_receipt_id bigint;
 v_identity text;
 v_timing jsonb;
 v_lineage jsonb;
 v_vtiming jsonb;
begin
 if p_pantalla_id is null or p_pantalla_id<1
    or p_consumer is null or length(btrim(p_consumer))=0 then
   raise exception 'IG_DIRECT_STEP_BAD_INPUT';
 end if;
 perform pg_advisory_xact_lock(
   hashtextextended('IG_DIRECT_STEP:'||p_pantalla_id::text,0));
 -- Existing EKB/consumer/screen/currentness gates remain authoritative.
 v_read:=programacion.fn_input_governance_execute(p_pantalla_id,p_consumer);
 v_status:=v_read->>'status';
 if v_status not in ('CURATOR_RUNTIME_REQUIRED','VALIDATOR_RUNTIME_REQUIRED') then
   return jsonb_build_object('status',v_status,'step','READBACK',
     'run_id',coalesce(v_read->'run_id',v_read->'latest_run_id'),
     'result',v_read,'next_action','NONE',
     'promotion_authorized',false,'production_authorized',false);
 end if;
 v_version:=(v_read->>'version_id')::bigint;
 select r.id,r.status,r.validator_identity,r.curator_identity into v_run
 from programacion.input_readiness_runs r
 where r.pantalla_id=p_pantalla_id and r.version_id=v_version
 order by r.id desc limit 1;
 if found and v_run.status in ('CURATING','VALIDATING') then
   select receipt.id into v_receipt_id
   from programacion.provenance_receipts receipt
   where receipt.receipt_kind='EVIDENCE_VERIFICATION'
     and receipt.issuer_channel='EVIDENCE_VERIFIER_V1'
     and receipt.subject_type='input_governance_curator_handoff'
     and receipt.subject_ref='input-readiness-run:'||v_run.id::text
     and receipt.payload->>'verification_status'='VERIFIED'
   order by receipt.id desc limit 1;
   if v_receipt_id is not null then
     if v_run.status='VALIDATING' then
       v_identity:=v_run.validator_identity;
       if v_identity is null then
         raise exception 'IG_DIRECT_STEP_RESUME_IDENTITY_MISSING:%',v_run.id;
       end if;
     else
       v_identity:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
     end if;
     v_validation:=programacion.fn_input_governance_validator_validate_handoff_v1(
       v_run.id,v_identity,v_receipt_id);
     v_status:=v_validation->>'status';
     if v_status not in ('VALIDATOR_CONTINUE_REQUIRED','COMPLETED','NOOP_COMPLETED') then
       raise exception 'IG_DIRECT_STEP_VALIDATOR_STATUS_UNSUPPORTED:%',
          coalesce(v_status,'NULL');
     end if;
     -- N-17: typed causal edge Curator handoff -> Validator completion (explicit receipts, never name/time).
     if v_status in ('COMPLETED','NOOP_COMPLETED') then
       begin
         v_lineage:=jsonb_build_object('status','EMITTED','receiver_readback',
           programacion.fn_ig_causal_lineage_receipts_emit_v1(v_run.id)->'receiver_readback');
       exception when others then
         v_lineage:=jsonb_build_object('status','EMIT_FAILED','error',left(sqlerrm,300));
       end;
     else
       v_lineage:=jsonb_build_object('status','NOT_APPLICABLE_UNTIL_COMPLETED');
     end if;
     -- M8.11: per-run Validator performance receipt (compute vs wait), same never-rollback contract as the lineage emission.
     if v_status in ('COMPLETED','NOOP_COMPLETED') then
       begin
         v_vtiming:=programacion.fn_ig_validator_timing_receipt_emit_v1(v_run.id);
       exception when others then
         v_vtiming:=jsonb_build_object('status','EMIT_FAILED','error',left(sqlerrm,300));
       end;
     else
       v_vtiming:=jsonb_build_object('status','NOT_APPLICABLE_UNTIL_COMPLETED');
     end if;
     return jsonb_build_object('status',v_status,'step','VALIDATOR_ONE_CHUNK',
       'run_id',v_run.id,'result',v_validation,'causal_lineage',v_lineage,'validator_timing',v_vtiming,
       'next_action',case when v_status='VALIDATOR_CONTINUE_REQUIRED'
         then 'REINVOKE_SAME_SCREEN' else 'READBACK' end,
       'promotion_authorized',false,'production_authorized',false);
   end if;
 end if;
 if v_status='VALIDATOR_RUNTIME_REQUIRED' then
   raise exception 'IG_DIRECT_STEP_VERIFIED_HANDOFF_REQUIRED:%',
     coalesce(v_run.id::text,'NO_RUN');
 end if;
 v_identity:='INPUT_CURATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
 v_curator:=programacion.fn_input_governance_curator_materialize_v1(
    p_pantalla_id,p_consumer,v_identity,false);
 if v_curator->'curator_handoff_receipt'->>'status' is distinct from 'PERSISTED' then
    if v_curator->>'status' in ('NOOP_CURRENT_RUN','BLOCKED',
      'CONTRACT_CHANGED_SEMANTIC_REVIEW_REQUIRED') then
      return jsonb_build_object('status',v_curator->>'status',
        'step','CURATOR_NONWRITE','result',v_curator,'next_action','NONE',
        'promotion_authorized',false,'production_authorized',false);
    end if;
    raise exception 'IG_DIRECT_STEP_CURATOR_HANDOFF_MISSING:%',
       coalesce(v_curator->>'status','NULL');
 end if;
 -- M8.2: publish the measured per-family/per-resolver timings as verified receipts (outside every semantic hash).
 if v_curator->'performance_observation'->>'capture_status'='OBSERVED' then
   v_timing:=programacion.fn_ig_timing_receipts_emit_v1((v_curator->>'run_id')::bigint,v_curator->'performance_observation',v_curator->'request_context_summary'->>'graph_sha256');
 else
   v_timing:=jsonb_build_object('status','NOT_EMITTED','capture_status',v_curator->'performance_observation'->>'capture_status');
 end if;
 return jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED',
   'step','CURATOR_MATERIALIZED','run_id',v_curator->'run_id',
   'result',v_curator,'timing_receipts',v_timing,'next_action','REINVOKE_SAME_SCREEN',
   'promotion_authorized',false,'production_authorized',false);
end;
$function$;
