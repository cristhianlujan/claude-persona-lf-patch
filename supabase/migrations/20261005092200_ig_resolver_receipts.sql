-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M3.5
DO $m3_5$
DECLARE
  v_actor text;
  v_subject_sha text;
  v_result jsonb;
BEGIN
  SELECT min(execution_id) INTO v_actor
  FROM public.lf_operation_execution
  WHERE status='IN_PROGRESS'
    AND manifest->>'capability_code'='EVIDENCE_LEDGER';

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'M3_5_EVIDENCE_LEDGER_EXECUTION_REQUIRED';
  END IF;

  SELECT encode(extensions.digest(convert_to(jsonb_build_object(
    'resolver_id',resolver_id,
    'provider',provider,
    'verification_method',verification_method,
    'trust_level',trust_level,
    'active',active
  )::text,'UTF8'),'sha256'),'hex')
  INTO v_subject_sha
  FROM private.lf_evidence_resolver_registry_v1
  WHERE resolver_id='LF_SUPABASE_READBACK_V1' AND active;

  IF v_subject_sha IS NULL THEN
    RAISE EXCEPTION 'M3_5_SUPABASE_RESOLVER_REQUIRED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE resolver_id='LF_SUPABASE_READBACK_V1'
  ) THEN
    v_result:=public.fn_lf_evidence_ledger_anchor_v1(
      v_actor,
      'EVIDENCE_LEDGER',
      'IG_RESOLVER_RECEIPT_EMIT',
      'RESOLVER_RECEIPT',
      'EVIDENCE_RESOLVER',
      'resolver://LF_SUPABASE_READBACK_V1',
      v_subject_sha,
      '1f467cbb771372b645378960485ab0931f53eb46',
      'supabase://private/lf_evidence_resolver_registry_v1/LF_SUPABASE_READBACK_V1',
      'LF_SUPABASE_READBACK_V1',
      'SUPABASE',
      'supabase://private/lf_evidence_resolver_registry_v1/LF_SUPABASE_READBACK_V1',
      'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
      'VERIFIED',
      jsonb_build_object(
        'provider_readback_verified',true,
        'digest_recomputed',true,
        'resolver_version','v1',
        'input_sha256',v_subject_sha,
        'output_sha256',v_subject_sha
      ),
      jsonb_build_object(
        'schema_version','LF_EVIDENCE_RESOLVER_RECEIPT_V1',
        'resolver_id','LF_SUPABASE_READBACK_V1',
        'resolver_version','v1',
        'authority_ref','supabase://private/lf_evidence_resolver_registry_v1/LF_SUPABASE_READBACK_V1',
        'source_head_sha','1f467cbb771372b645378960485ab0931f53eb46',
        'input_sha256',v_subject_sha,
        'output_sha256',v_subject_sha
      ),
      v_actor
    );
    IF coalesce(v_result->>'receipt_id','')='' THEN
      RAISE EXCEPTION 'M3_5_RESOLVER_RECEIPT_NOT_EMITTED';
    END IF;
  END IF;
END
$m3_5$;
