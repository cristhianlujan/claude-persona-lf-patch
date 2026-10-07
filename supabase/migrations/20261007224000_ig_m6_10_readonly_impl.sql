-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M6.10 / READONLY_IMPL
-- The API describes only stored evidence for one run/family.
-- Unknown or missing receipt, digest, policy or independent validation never becomes PASS.
CREATE OR REPLACE FUNCTION programacion.fn_input_explain_family_assessment(
  p_run_id bigint,
  p_family_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, programacion
AS $m610_explain$
DECLARE
  v_run programacion.input_readiness_runs%ROWTYPE;
  v_assessment programacion.input_family_assessments%ROWTYPE;
  v_count integer;
  v_current boolean := false;
  v_sources jsonb := '[]'::jsonb;
  v_receipts jsonb := '[]'::jsonb;
  v_source_count integer := 0;
  v_source_bad integer := 0;
  v_receipt_count integer := 0;
  v_source_ok boolean := false;
  v_receipt_ok boolean := false;
  v_deterministic_sha text;
  v_det_ok boolean := false;
  v_sem_used text;
  v_sem_ok boolean := false;
  v_sem_na boolean := false;
  v_policy_ref text;
  v_policy_version text;
  v_policy_ok boolean := false;
  v_validator_ok boolean := false;
  v_missing jsonb := '[]'::jsonb;
  v_chain jsonb;
BEGIN
  IF p_run_id IS NULL OR nullif(btrim(p_family_code),'') IS NULL THEN
    RAISE EXCEPTION 'IG_EXPLAIN_IDENTITY_REQUIRED';
  END IF;

  SELECT * INTO v_run
  FROM programacion.input_readiness_runs
  WHERE id = p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IG_EXPLAIN_RUN_NOT_FOUND:%', p_run_id;
  END IF;

  SELECT count(*) INTO v_count
  FROM programacion.input_family_assessments
  WHERE run_id = p_run_id AND family_code = p_family_code;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'IG_EXPLAIN_FAMILY_IDENTITY_NOT_UNIQUE:%:%:%',
      p_run_id, p_family_code, v_count;
  END IF;

  SELECT * INTO v_assessment
  FROM programacion.input_family_assessments
  WHERE run_id = p_run_id AND family_code = p_family_code;

  -- Canonical currentness, never status / invalidated_at alone.
  v_current := (v_run.status = 'COMPLETED')
    AND programacion.fn_input_readiness_run_is_current(p_run_id);
  IF NOT v_current THEN
    v_missing := v_missing || jsonb_build_array('RUN_CURRENTNESS');
  END IF;

  -- Source receipts are persisted on the run; return only refs and fingerprints,
  -- never observed full payload. Match the family's exact source reference.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'ref',s.value->'ref',
      'authority',s.value->>'authority',
      'lifecycle',s.value->'lifecycle',
      'sha256',s.value->>'observed_sha256',
      'receipt_schema',s.value->>'schema_version',
      'archive_state',s.value#>>'{archive_contract,state}'
    )),'[]'::jsonb),
    count(*)::integer,
    count(*) FILTER (
      WHERE coalesce(s.value->>'observed_sha256','') !~ '^[0-9a-fA-F]{64}$'
      OR coalesce(s.value->>'authority','') = ''
      OR coalesce(s.value#>>'{lifecycle,resolution_state}','') <> 'RESOLVED'
      OR s.value#>>'{lifecycle,rule_authority,authoritative}' = 'false'
    )::integer
    INTO v_sources,v_source_count,v_source_bad
  FROM jsonb_array_elements(coalesce(v_run.source_manifest,'[]'::jsonb)) AS s(value)
  WHERE EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(v_assessment.source_refs,'[]'::jsonb)) AS f(value)
    WHERE s.value->'ref' @> f.value
  );

  v_source_ok := v_source_count > 0 AND v_source_bad = 0
    AND v_source_count >= jsonb_array_length(coalesce(v_assessment.source_refs,'[]'::jsonb));
  IF NOT v_source_ok THEN
    v_missing := v_missing || jsonb_build_array('SOURCE_AUTHORITY_OR_DIGEST');
  END IF;

  -- Global audit receipts must never be relabeled as family receipts.
  -- Require exact run and family identity from the persisted receipt payload.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'receipt_id',r.id,
      'receipt_kind',r.receipt_kind,
      'subject_type',r.subject_type,
      'subject_ref',r.subject_ref,
      'subject_sha256',r.subject_sha256,
      'receipt_sha256',r.receipt_sha256
    ) ORDER BY r.id),'[]'::jsonb),count(*)::integer
    INTO v_receipts,v_receipt_count
  FROM programacion.provenance_receipts r
  WHERE r.payload->>'run_id' = p_run_id::text
    AND r.payload->>'family_code' = p_family_code
    AND coalesce(r.receipt_sha256,'') ~ '^[0-9a-fA-F]{64}$'
    AND coalesce(r.subject_sha256,'') ~ '^[0-9a-fA-F]{64}$';

  v_receipt_ok := v_receipt_count > 0;
  IF NOT v_receipt_ok THEN
    v_missing := v_missing || jsonb_build_array('SOURCE_RECEIPT');
  END IF;

  v_deterministic_sha := coalesce(
    nullif(v_assessment.curator_evidence->>'deterministic_sha256',''),
    nullif(v_assessment.curator_evidence->>'deterministic_sha','')
  );
  v_det_ok := coalesce(v_deterministic_sha,'') ~ '^[0-9a-fA-F]{64}$';
  IF NOT v_det_ok THEN
    v_missing := v_missing || jsonb_build_array('DETERMINISTIC_DIGEST');
  END IF;

  v_sem_used := v_assessment.curator_evidence->>'semantic_resolver_used';
  v_sem_na := v_sem_used = 'false';
  v_sem_ok := v_sem_na OR (
    v_sem_used = 'true'
    AND coalesce(v_assessment.curator_evidence->>'semantic_resolver_id','') <> ''
    AND coalesce(v_assessment.curator_evidence->>'semantic_resolver_version','') <> ''
    AND coalesce(v_assessment.curator_evidence->>'semantic_receipt_sha256','')
      ~ '^[0-9a-fA-F]{64}$'
  );
  IF NOT coalesce(v_sem_ok,false) THEN
    v_missing := v_missing || jsonb_build_array('SEMANTIC_RESOLVER_RECEIPT_OR_USAGE');
  END IF;

  v_policy_ref := nullif(v_assessment.curator_evidence->>'policy_ref','');
  v_policy_version := nullif(v_assessment.curator_evidence->>'policy_version','');
  v_policy_ok := v_policy_ref IS NOT NULL AND v_policy_version IS NOT NULL;
  IF NOT v_policy_ok THEN
    v_missing := v_missing || jsonb_build_array('CANONICAL_POLICY_IDENTITY');
  END IF;

  v_validator_ok :=
    v_assessment.validator_outcome = 'PASS'
    AND coalesce(v_assessment.validator_sha256,'') ~ '^[0-9a-fA-F]{64}$'
    AND coalesce(v_assessment.validator_evidence->>'execution_mode','') = 'INDEPENDENT_VALIDATOR'
    AND coalesce(v_assessment.validator_evidence->>'validated_curator_execution_id','') <> ''
    AND v_assessment.validator_evidence->>'validated_curator_execution_id'
        = v_assessment.curator_evidence->>'execution_id'
    AND v_assessment.validator_evidence->>'curator_sha256'
        = v_assessment.curator_sha256;
  IF NOT coalesce(v_validator_ok,false) THEN
    v_missing := v_missing || jsonb_build_array('INDEPENDENT_VALIDATOR_PROOF');
  END IF;

  v_chain := jsonb_build_array(
    jsonb_build_object('step','SOURCE','status',CASE WHEN v_source_ok THEN 'PASS' ELSE 'INCOMPLETE' END,
      'evidence',v_sources),
    jsonb_build_object('step','SOURCE_RECEIPT','status',CASE WHEN v_receipt_ok THEN 'PASS' ELSE 'INCOMPLETE' END,
      'evidence',v_receipts),
    jsonb_build_object('step','DETERMINISTIC','status',CASE WHEN v_det_ok THEN 'PASS' ELSE 'INCOMPLETE' END,
      'sha256',v_deterministic_sha),
    jsonb_build_object('step','SEMANTIC','status',CASE WHEN v_sem_na THEN 'NOT_APPLICABLE'
      WHEN coalesce(v_sem_ok,false) THEN 'PASS' ELSE 'INCOMPLETE' END,
      'resolver_used',v_sem_used,
      'resolver_id',v_assessment.curator_evidence->>'semantic_resolver_id',
      'resolver_version',v_assessment.curator_evidence->>'semantic_resolver_version',
      'receipt_sha256',v_assessment.curator_evidence->>'semantic_receipt_sha256'),
    jsonb_build_object('step','POLICY','status',CASE WHEN v_policy_ok THEN 'PASS' ELSE 'INCOMPLETE' END,
      'policy_ref',v_policy_ref,'policy_version',v_policy_version),
    jsonb_build_object('step','VALIDATOR','status',CASE WHEN coalesce(v_validator_ok,false) THEN 'PASS' ELSE 'INCOMPLETE' END,
      'outcome',v_assessment.validator_outcome,
      'validator_sha256',v_assessment.validator_sha256,
      'validator_execution_id',v_assessment.validator_evidence->>'execution_id')
  );

  RETURN jsonb_build_object(
    'schema_version','INPUT_EXPLAIN_FAMILY_ASSESSMENT_V1',
    'run_id',p_run_id,'family_code',p_family_code,
    'run_current',v_current,
    'status',CASE WHEN v_missing = '[]'::jsonb THEN 'EXPLAINABLE' ELSE 'INCOMPLETE' END,
    'explainable',(v_missing = '[]'::jsonb),
    'missing_evidence',v_missing,
    'chain',v_chain
  );
END;
$m610_explain$;

-- Internal-only execution. No public/authenticated direct invocation.
REVOKE ALL ON FUNCTION programacion.fn_input_explain_family_assessment(bigint,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_input_explain_family_assessment(bigint,text)
  TO service_role;
