-- PASE_CONTROL_SYSTEM_QUALIFICATION_AUTHORITY_V1
-- Extends the existing canonical qualification ledger. No parallel authority is created.

DO $pre$
DECLARE
  v_subject_check text;
BEGIN
  SELECT pg_get_constraintdef(c.oid)
    INTO v_subject_check
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
    AND t.relname = 'lf_qualification_receipts'
    AND c.conname = 'lf_qualification_receipts_subject_type_check';

  IF v_subject_check IS NULL THEN
    RAISE EXCEPTION 'PASE_CONTROL_SYSTEM_QUALIFICATION_SUBJECT_CHECK_MISSING';
  END IF;
  IF v_subject_check LIKE '%CONTROL_SYSTEM%' THEN
    RAISE EXCEPTION 'PASE_CONTROL_SYSTEM_QUALIFICATION_ALREADY_MATERIALIZED';
  END IF;
  IF v_subject_check NOT LIKE '%OPERATION%' OR v_subject_check NOT LIKE '%STRATEGY%' THEN
    RAISE EXCEPTION 'PASE_CONTROL_SYSTEM_QUALIFICATION_SUBJECT_CHECK_DRIFT:%', v_subject_check;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'lf_qualification_receipts'
      AND column_name IN ('qualification_authority','qualification_input','qualification_result','source_execution_id')
  ) THEN
    RAISE EXCEPTION 'PASE_CONTROL_SYSTEM_QUALIFICATION_COLUMNS_ALREADY_PRESENT';
  END IF;
END
$pre$;

ALTER TABLE public.lf_qualification_receipts
  DROP CONSTRAINT lf_qualification_receipts_subject_type_check;

ALTER TABLE public.lf_qualification_receipts
  ADD CONSTRAINT lf_qualification_receipts_subject_type_check
  CHECK (subject_type = ANY (ARRAY['OPERATION'::text, 'STRATEGY'::text, 'CONTROL_SYSTEM'::text]));

ALTER TABLE public.lf_qualification_receipts
  ADD COLUMN qualification_authority text,
  ADD COLUMN qualification_input jsonb,
  ADD COLUMN qualification_result jsonb,
  ADD COLUMN source_execution_id text;

ALTER TABLE public.lf_qualification_receipts
  ADD CONSTRAINT lf_qualification_receipts_control_system_payload_check
  CHECK (
    subject_type <> 'CONTROL_SYSTEM'
    OR (
      qualification_authority = 'PASE_CONTROL_QUALIFICATION_V1'
      AND jsonb_typeof(qualification_input) = 'object'
      AND jsonb_typeof(qualification_result) = 'object'
      AND btrim(coalesce(source_execution_id,'')) <> ''
      AND qualification_input->>'schema_version' = 'lf-pase-control-qualification/v1'
      AND qualification_result->>'schema_version' = 'lf-pase-control-qualification-result/v1'
      AND qualification_input->>'candidate_id' = subject_code
      AND qualification_result->>'candidate_id' = subject_code
      AND qualification_input->>'base_sha' ~ '^[0-9a-f]{40}$'
      AND qualification_input->>'head_sha' ~ '^[0-9a-f]{40}$'
      AND qualification_input->>'observed_main_sha' ~ '^[0-9a-f]{40}$'
      AND qualification_result->>'base_sha' = qualification_input->>'base_sha'
      AND qualification_result->>'head_sha' = qualification_input->>'head_sha'
      AND qualification_input->>'observed_main_sha' = qualification_input->>'base_sha'
      AND qualification_result->>'declared_owner' = qualification_input->>'declared_owner'
      AND qualification_result->>'verdict' = 'CANDIDATE_QUALIFIED'
      AND qualification_result->>'coverage_complete' = 'true'
      AND qualification_result->>'qualified_only' = 'true'
      AND qualification_result->>'activation_authorized' = 'false'
      AND qualification_result->>'cutover_authorized' = 'false'
      AND qualification_result->>'rebind_authorized' = 'false'
      AND qualification_result->>'legacy_retirement_authorized' = 'false'
    )
  );

CREATE OR REPLACE FUNCTION public.lf_control_system_qualification_revision_sha256_v1(p_head_sha text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $fn$
BEGIN
  IF coalesce(p_head_sha,'') !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_HEAD_INVALID';
  END IF;
  RETURN encode(extensions.digest(convert_to(p_head_sha,'UTF8'),'sha256'),'hex');
END
$fn$;

CREATE UNIQUE INDEX uq_lf_qualification_receipts_control_system_current
ON public.lf_qualification_receipts(subject_code, revision_sha256)
WHERE subject_type = 'CONTROL_SYSTEM'
  AND invalidated_at IS NULL
  AND lifecycle_state_code = 'QUAL_QUALIFIED';

CREATE OR REPLACE FUNCTION public.lf_control_system_qualification_readback_v1(
  p_candidate_id text,
  p_repository text,
  p_base_sha text,
  p_head_sha text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE
  v_revision text;
  v_qualified_state text;
  v_count integer;
  v_q public.lf_qualification_receipts%rowtype;
BEGIN
  IF btrim(coalesce(p_candidate_id,'')) = '' THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_CANDIDATE_INVALID';
  END IF;
  IF btrim(coalesce(p_repository,'')) = '' THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_REPOSITORY_INVALID';
  END IF;
  IF coalesce(p_base_sha,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_head_sha,'') !~ '^[0-9a-f]{40}$'
     OR p_base_sha = p_head_sha THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_RANGE_INVALID';
  END IF;

  v_revision := public.lf_control_system_qualification_revision_sha256_v1(p_head_sha);
  v_qualified_state := public.lf_lifecycle_action_target_state_v1('QUALIFICATION_LIFECYCLE','PASS_QUALIFICATION');

  SELECT count(*)
    INTO v_count
  FROM public.lf_qualification_receipts q
  WHERE q.subject_type = 'CONTROL_SYSTEM'
    AND q.subject_code = p_candidate_id
    AND q.revision_sha256 = v_revision
    AND q.lifecycle_state_code = v_qualified_state
    AND q.invalidated_at IS NULL;

  IF v_count = 0 THEN
    RETURN jsonb_build_object(
      'schema_version','lf-control-system-qualification-readback/v1',
      'status','MISSING',
      'candidate_id',p_candidate_id,
      'repository',p_repository,
      'base_sha',p_base_sha,
      'head_sha',p_head_sha,
      'revision_sha256',v_revision
    );
  END IF;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_CARDINALITY:%', v_count;
  END IF;

  SELECT *
    INTO v_q
  FROM public.lf_qualification_receipts q
  WHERE q.subject_type = 'CONTROL_SYSTEM'
    AND q.subject_code = p_candidate_id
    AND q.revision_sha256 = v_revision
    AND q.lifecycle_state_code = v_qualified_state
    AND q.invalidated_at IS NULL
  ORDER BY q.qualified_at DESC NULLS LAST, q.created_at DESC
  LIMIT 1;

  IF v_q.qualification_authority IS DISTINCT FROM 'PASE_CONTROL_QUALIFICATION_V1' THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_AUTHORITY_DRIFT';
  END IF;
  IF jsonb_typeof(v_q.qualification_input) IS DISTINCT FROM 'object'
     OR jsonb_typeof(v_q.qualification_result) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_PAYLOAD_INVALID';
  END IF;
  IF v_q.qualification_input->>'repository' IS DISTINCT FROM p_repository
     OR v_q.qualification_input->>'candidate_id' IS DISTINCT FROM p_candidate_id
     OR v_q.qualification_input->>'base_sha' IS DISTINCT FROM p_base_sha
     OR v_q.qualification_input->>'observed_main_sha' IS DISTINCT FROM p_base_sha
     OR v_q.qualification_input->>'head_sha' IS DISTINCT FROM p_head_sha THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_INPUT_IDENTITY_DRIFT';
  END IF;
  IF v_q.qualification_result->>'candidate_id' IS DISTINCT FROM p_candidate_id
     OR v_q.qualification_result->>'base_sha' IS DISTINCT FROM p_base_sha
     OR v_q.qualification_result->>'head_sha' IS DISTINCT FROM p_head_sha
     OR v_q.qualification_result->>'verdict' IS DISTINCT FROM 'CANDIDATE_QUALIFIED' THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_RESULT_IDENTITY_DRIFT';
  END IF;
  IF btrim(coalesce(v_q.source_execution_id,'')) = '' THEN
    RAISE EXCEPTION 'LF_CONTROL_SYSTEM_QUALIFICATION_SOURCE_EXECUTION_MISSING';
  END IF;

  RETURN jsonb_build_object(
    'schema_version','lf-control-system-qualification-readback/v1',
    'status','QUALIFIED',
    'qualification_id',v_q.qualification_id,
    'candidate_id',v_q.subject_code,
    'repository',p_repository,
    'base_sha',p_base_sha,
    'head_sha',p_head_sha,
    'revision_sha256',v_q.revision_sha256,
    'validator_revision',v_q.suite_set_fingerprint,
    'source_execution_id',v_q.source_execution_id,
    'qualification_authority',v_q.qualification_authority,
    'qualification_input',v_q.qualification_input,
    'qualification_result',v_q.qualification_result,
    'qualified_at',v_q.qualified_at
  );
END
$fn$;

COMMENT ON FUNCTION public.lf_control_system_qualification_readback_v1(text,text,text,text)
IS 'Canonical read-only exact-head PASE control-system qualification readback. Trusted consumers must still re-run PASE_CONTROL_QUALIFICATION_V1 over returned input/result.';
