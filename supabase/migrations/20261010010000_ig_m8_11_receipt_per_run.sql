-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M8.11 / RECEIPT_PER_RUN
-- Reuse the existing EVIDENCE_VERIFIER_V1 provenance sink; no timing store or semantic-hash mutation.
-- Only service_role may call this function. The caller MUST supply its verified deployed
-- release commit SHA from the Edge deployment manifest, never a guessed code constant.
-- M8.2 already publishes FAMILY, RESOLVER and TOTAL; this function deliberately issues
-- only CURATOR and VALIDATOR phases to avoid counting two different TOTAL definitions.
CREATE OR REPLACE FUNCTION programacion.fn_ig_run_phase_receipts_emit_v1(p_run_id bigint,p_release_sha text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','public' AS $fn$
DECLARE
  v_run programacion.input_readiness_runs%rowtype;
  v_token text;
  v_item record;
  v_ref text;
  v_subject jsonb;
  v_subject_sha text;
  v_payload jsonb;
  v_count integer := 0;
BEGIN
  IF coalesce(p_release_sha,'') !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'IG_RUN_TIMING_RELEASE_SHA_REQUIRED';
  END IF;
  SELECT * INTO v_run FROM programacion.input_readiness_runs WHERE id=p_run_id FOR SHARE;
  IF NOT FOUND OR v_run.status <> 'COMPLETED' OR v_run.validator_completed_at IS NULL
     OR v_run.curator_completed_at IS NULL
     OR coalesce(v_run.source_snapshot_sha256,'') !~ '^[0-9a-f]{64}$'
     OR v_run.curator_duration_ms IS NULL OR v_run.validator_duration_ms IS NULL
     OR v_run.curator_duration_ms <= 0 OR v_run.validator_duration_ms <= 0 THEN
    RAISE EXCEPTION 'IG_RUN_TIMING_CANONICAL_RUN_NOT_COMPLETE:%',p_run_id;
  END IF;
  SELECT decrypted_secret INTO v_token FROM vault.decrypted_secrets
    WHERE name='EVIDENCE_VERIFIER_V1_TOKEN' ORDER BY created_at DESC LIMIT 1;
  IF length(coalesce(v_token,''))<32 THEN
    RAISE EXCEPTION 'IG_RUN_TIMING_VERIFIER_TOKEN_MISSING';
  END IF;
  v_ref := 'input-readiness-run:'||p_run_id::text;
  FOR v_item IN
    SELECT 'CURATOR'::text phase, v_run.curator_duration_ms::bigint ms, v_run.curator_completed_at measured_at
    UNION ALL SELECT 'VALIDATOR',v_run.validator_duration_ms::bigint,v_run.validator_completed_at
  LOOP
    v_subject:=jsonb_build_object('schema_version','IG_PERFORMANCE_TIMING_SUBJECT_V1',
      'run_id',p_run_id,'phase',v_item.phase,'elapsed_ms',v_item.ms,
      'source_snapshot_sha256',v_run.source_snapshot_sha256);
    v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject);
    IF EXISTS(SELECT 1 FROM programacion.provenance_receipts
      WHERE subject_type='IG_PERFORMANCE_TIMING' AND subject_ref=v_ref
      AND subject_sha256=v_subject_sha AND head_sha=p_release_sha) THEN CONTINUE; END IF;
    IF EXISTS(SELECT 1 FROM programacion.provenance_receipts
      WHERE subject_type='IG_PERFORMANCE_TIMING' AND subject_ref=v_ref
      AND payload->>'phase'=v_item.phase AND head_sha<>p_release_sha) THEN
      RAISE EXCEPTION 'IG_RUN_TIMING_RELEASE_REBIND_FORBIDDEN:%/%',p_run_id,v_item.phase;
    END IF;
    v_payload:=jsonb_build_object('schema_version','IG_PERFORMANCE_TIMING_RECEIPT_V1',
      'head_sha',p_release_sha,'subject_type','IG_PERFORMANCE_TIMING',
      'subject_ref',v_ref,'subject_sha256',v_subject_sha,
      'verification_status','VERIFIED','verifier_identity','SUPABASE:IG_RUN_PHASE_TIMING_V1',
      'verification_method','RUN_PERSISTED_DURATION_MS_V1','run_id',p_run_id::text,
      'source_snapshot_sha256',v_run.source_snapshot_sha256,
      'measurement_method','CLOCK_TIMESTAMP_OBSERVED','phase',v_item.phase,
      'elapsed_ms',v_item.ms,
      'measurement_ref','supabase://programacion.input_readiness_runs/'||p_run_id::text||'#phase-timing',
      'measured_at',to_char(v_item.measured_at at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'semantic_sha_excluded',true);
    PERFORM 1 FROM programacion.issue_provenance_receipt('EVIDENCE_VERIFIER_V1',
      v_token,'EVIDENCE_VERIFICATION',NULL,p_release_sha,'IG_PERFORMANCE_TIMING',
      v_ref,v_subject_sha,'SUPABASE:IG_RUN_PHASE_TIMING_V1',
      'supabase://programacion.input_readiness_runs/'||p_run_id::text||'#phase-timing',v_payload);
    v_count:=v_count+1;
  END LOOP;
  RETURN jsonb_build_object('status','PERSISTED','run_id',p_run_id,
    'receipts_issued',v_count,'semantic_sha_excluded',true);
END;
$fn$;
REVOKE ALL ON FUNCTION programacion.fn_ig_run_phase_receipts_emit_v1(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_run_phase_receipts_emit_v1(bigint,text) TO service_role;
COMMENT ON FUNCTION programacion.fn_ig_run_phase_receipts_emit_v1(bigint,text)
 IS 'M8.11: emit verified CURATOR and VALIDATOR run-phase receipts from canonical observed durations; release SHA is supplied by a verified deployment manifest, never a hardcoded constant.';
