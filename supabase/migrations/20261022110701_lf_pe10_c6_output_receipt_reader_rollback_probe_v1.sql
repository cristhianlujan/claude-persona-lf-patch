-- PE10 C6 output-receipt-reader candidate ONLY. Canonical repository candidate
-- compiled via real PostgreSQL in a rollback-only PL/pgSQL subtransaction.
-- No producer attestation, no output receipt created, no v0.2 activation.
-- Run by governed LF Migration Merge Train, never direct SQL execution.
BEGIN;
DO $pe10_reader$
DECLARE
 v_actor constant text := 'EXEC-PE10-C6-OUTPUT-READER-ROLLBACK-NONAUTHORITY-V1';
 v_code constant text := 'PE10_C6.OUTPUT_READER_ROLLBACK_PROBE.V1';
 v_receipt constant text := '9f758577-c9f6-4744-852b-a03827b466f6';
 v_slug constant text := 'systemic_root_cause_repair_lf';
 v_digest constant text := '692618756e551011b52487bc7091ed5f14f166c66f99f9ecea95619c0f5634fc';
 v_head constant text := '8dabb3a1bfd68dc90b78b09233000bce92d35ee9';
 v_original_md5 constant text := 'afaee8a72c8d8e35360ba685487600d6';
 v_acl text;
 v_subject text;
 v_true boolean;
 v_false boolean;
 v_audit jsonb;
 v_event bigint;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_code)
 OR (SELECT md5(pg_get_functiondef('public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)'::regprocedure))) IS DISTINCT FROM v_original_md5
 OR (SELECT version FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF') IS DISTINCT FROM 'v0.1'
 OR (SELECT count(*) FROM private.lf_evidence_ledger_v1
     WHERE subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE'))<>0
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'PE10_OUTPUT_READER_PRESTATE_CHANGED'; END IF;
 SELECT proacl::text INTO v_acl FROM pg_proc
   WHERE oid='public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)'::regprocedure;
 IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}'
 OR has_function_privilege('authenticated','public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)','EXECUTE')
 OR has_function_privilege('anon','public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'PE10_OUTPUT_READER_NARROW_ACL_INVALID'; END IF;
 IF NOT public.lf_profile_update_verified_receipt_v1(
    'PROFILE_ASSESSMENT',v_slug,v_receipt,v_digest,v_head)
 THEN RAISE EXCEPTION 'PE10_LEGACY_RECEIPT_PRESTATE_UNVERIFIED'; END IF;

 -- DDL stays entirely within the PostgreSQL exception subtransaction.
 -- The deliberate exception restores the deployed function and its ACL.
 BEGIN
  EXECUTE $candidate_function$
CREATE OR REPLACE FUNCTION public.lf_profile_update_verified_receipt_v1(
    p_subject_type text,
    p_subject_ref text,
    p_receipt_id text,
    p_subject_sha256 text,
    p_source_head_sha text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $lf$
DECLARE
    v_id uuid;
BEGIN
    IF p_subject_type NOT IN ('PROFILE_ASSESSMENT', 'METHOD_QUALIFICATION',
         'PROFILE_OUTPUT_VALIDATION_POSITIVE', 'PROFILE_OUTPUT_VALIDATION_NEGATIVE')
       OR NULLIF(btrim(p_subject_ref), '') IS NULL
       OR p_receipt_id IS NULL
       OR p_receipt_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR p_subject_sha256 IS NULL
       OR p_subject_sha256 !~ '^[0-9a-f]{64}$'
       OR p_source_head_sha IS NULL
       OR p_source_head_sha !~ '^[0-9a-f]{40}$'
    THEN RETURN false; END IF;
    v_id := p_receipt_id::uuid;

    RETURN EXISTS (
        SELECT 1
          FROM private.lf_evidence_ledger_v1 l
          JOIN private.lf_evidence_resolver_registry_v1 rr
            ON rr.resolver_id=l.resolver_id
           AND rr.active IS TRUE
           AND rr.trust_level='TRUSTED_PROVIDER_BOUND'
           AND rr.provider=l.provider
           AND rr.verification_method=l.verification_method
         WHERE l.receipt_id = v_id
           AND l.subject_type = p_subject_type
           AND l.subject_ref = p_subject_ref
           AND l.subject_sha256 = p_subject_sha256
           AND l.source_head_sha = p_source_head_sha
           AND l.verification_state = 'VERIFIED'
           AND l.resolver_id IN ('LF_GITHUB_SOURCE_READBACK_V1','LF_SUPABASE_READBACK_V1')
           AND NULLIF(btrim(l.provider_ref),'') IS NOT NULL
           AND l.receipt_sha256 ~ '^[0-9a-f]{64}$'
           AND l.verified_at IS NOT NULL
           -- Output-validation receipts require a real provider-bound harness
           -- execution, not a chat/worker PASS string. Existing assessment
           -- and method-qualification behavior is preserved unchanged.
           AND (
             p_subject_type NOT IN
               ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
             OR (
               l.capability_code='PACK_VALIDATION_HARNESS'
               AND l.receipt_kind='PROFILE_OUTPUT_VALIDATION_RESULT'
               AND l.gate_code='PROFILE_OUTPUT_CONTRACT_VALIDATION'
               AND l.receipt_payload->>'schema'='PROFILE_OUTPUT_VALIDATION_RESULT_V1'
               AND l.receipt_payload->>'source_readback_matched'='true'
               AND l.receipt_payload->>'structural_check_executed'='true'
               AND l.receipt_payload->>'admission_authorized'='false'
               AND l.receipt_payload->>'provider_attested'='false'
               AND l.receipt_payload->>'runtime_activation_authorized'='false'
               AND l.receipt_payload->>'raw_output_sha256'=l.subject_sha256
               AND jsonb_typeof(l.receipt_payload->'source_refs')='object'
               AND l.receipt_payload->'source_refs' ? 'schema'
               AND l.receipt_payload->'source_refs' ? 'validator'
               AND l.receipt_payload->'source_refs' ? 'raw_output'
               AND (
                 (p_subject_type='PROFILE_OUTPUT_VALIDATION_POSITIVE'
                   AND l.receipt_payload->>'status'='CANDIDATE_OUTPUT_PARITY_OBSERVED'
                   AND l.receipt_payload->>'profile_validator_executed'='true'
                   AND l.receipt_payload->>'validator_exit_code'='0'
                   AND CASE WHEN jsonb_typeof(l.receipt_payload->'validator_errors')='array'
                     THEN jsonb_array_length(l.receipt_payload->'validator_errors')=0
                     ELSE false END
                   AND l.receipt_payload->>'validator_stdout_sha256' ~ '^[0-9a-f]{64}$')
                 OR
                 (p_subject_type='PROFILE_OUTPUT_VALIDATION_NEGATIVE'
                   AND (
                     (l.receipt_payload->>'status'='EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR'
                      AND l.receipt_payload->>'profile_validator_executed'='true'
                      AND CASE WHEN jsonb_typeof(l.receipt_payload->'validator_errors')='array'
                        THEN jsonb_array_length(l.receipt_payload->'validator_errors')>0
                        ELSE false END
                      AND l.receipt_payload->>'validator_stdout_sha256' ~ '^[0-9a-f]{64}$')
                     OR
                     (l.receipt_payload->>'status'='EXPECTED_NEGATIVE_REJECTED_BY_SHAPE'
                      AND l.receipt_payload->>'profile_validator_executed'='false'
                      AND CASE WHEN jsonb_typeof(l.receipt_payload->'shape_errors')='array'
                        THEN jsonb_array_length(l.receipt_payload->'shape_errors')>0
                        ELSE false END)
                   ))
               )
             )
           )
    );
END;
$lf$;
$candidate_function$;
  IF (SELECT md5(pg_get_functiondef('public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)'::regprocedure)))=v_original_md5
  THEN RAISE EXCEPTION 'PE10_READER_CANDIDATE_NOT_INSTALLED_IN_TEST'; END IF;
  v_true := public.lf_profile_update_verified_receipt_v1(
    'PROFILE_ASSESSMENT',v_slug,v_receipt,v_digest,v_head);
  IF v_true IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'PE10_READER_LEGACY_POSITIVE_REGRESSION'; END IF;
  v_false := public.lf_profile_update_verified_receipt_v1(
    'PROFILE_ASSESSMENT',v_slug,v_receipt,repeat('0',64),v_head);
  IF v_false IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'PE10_READER_TAMPERED_DIGEST_ACCEPTED'; END IF;
  v_false := public.lf_profile_update_verified_receipt_v1(
    'PROFILE_ASSESSMENT',v_slug,v_receipt,v_digest,repeat('0',40));
  IF v_false IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'PE10_READER_TAMPERED_HEAD_ACCEPTED'; END IF;
  v_false := public.lf_profile_update_verified_receipt_v1(
    'METHOD_QUALIFICATION',v_slug,v_receipt,v_digest,v_head);
  IF v_false IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'PE10_READER_METHOD_TYPE_CONFUSION'; END IF;
  FOREACH v_subject IN ARRAY ARRAY[
    'PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE'
  ] LOOP
    v_false := public.lf_profile_update_verified_receipt_v1(
      v_subject,v_slug,v_receipt,v_digest,v_head);
    IF v_false IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'PE10_READER_OUTPUT_TYPE_CONFUSION:%',v_subject; END IF;
    v_false := public.lf_profile_update_verified_receipt_v1(
      v_subject,v_slug,'00000000-0000-0000-0000-000000000000',v_digest,v_head);
    IF v_false IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'PE10_READER_FAKE_OUTPUT_RECEIPT_ACCEPTED:%',v_subject; END IF;
  END LOOP;
  IF has_function_privilege('authenticated','public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)','EXECUTE')
   OR has_function_privilege('anon','public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)','EXECUTE')
  THEN RAISE EXCEPTION 'PE10_READER_CANDIDATE_ACL_WIDENED'; END IF;
  RAISE EXCEPTION 'PE10_EXPECTED_READER_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'PE10_EXPECTED_READER_ROLLBACK' THEN RAISE; END IF;
 END;

 IF (SELECT md5(pg_get_functiondef('public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)'::regprocedure))) IS DISTINCT FROM v_original_md5
  OR (SELECT proacl::text FROM pg_proc
       WHERE oid='public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)'::regprocedure) IS DISTINCT FROM v_acl
  OR (SELECT count(*) FROM public.lf_operation_steps
       WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active)<>15
  OR (SELECT count(*) FROM public.lf_operation_steps
       WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND active)<>0
  OR (SELECT count(*) FROM private.lf_evidence_ledger_v1
       WHERE subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE'))<>0
 THEN RAISE EXCEPTION 'PE10_READER_TRANSACTIONAL_RESIDUE'; END IF;

 v_audit:=jsonb_build_object(
  'evidence_schema_version','operational-event/v2',
  'execution_id',v_actor,'producer','LF_MIGRATION_TRAIN_PE10_C6_READER_PROBE',
  'purpose','Compile candidate receipt reader and verify negative boundaries under transactional rollback',
  'occurred_at',clock_timestamp(),'acceptance_declared',false,
  'checkpoint_code','PE10_C6','profile_slug',v_slug,
  'reader_candidate_compilation_verified',true,
  'legacy_profile_assessment_receipt_still_verified',true,
  'invalid_digest_revision_and_subject_fail_closed',true,
  'output_receipt_classes_checked',jsonb_build_array(
    'PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE'),
  'real_output_producer_receipts_present',false,
  'output_reader_cutover_admitted',false,
  'transactional_rollback_verified',true,'checkpoint_pass',false,
  'production_activation',false
 );
 IF private.fn_lf_event_acceptance_signal_v2(
  'ARTIFACT_RECONCILED',v_code,
  'PE10 C6 candidate receipt reader rollback-only rehearsal; producer not yet admitted',
  v_audit) IS NOT NULL THEN RAISE EXCEPTION 'PE10_READER_FALSE_CLOSURE_SIGNAL'; END IF;
 INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,
    severidad,origen,created_by_execution_id,payload
 ) VALUES(
    'ARTIFACT_RECONCILED','PROGRAM_PLAN',v_code,
    'PE10 C6 output receipt reader candidate compiles and rolls back; producer pending',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_audit
 ) RETURNING id INTO v_event;
 IF NOT EXISTS (
  SELECT 1 FROM public.lf_eventos WHERE id=v_event
   AND payload->>'checkpoint_pass'='false'
   AND payload->>'transactional_rollback_verified'='true'
 ) THEN RAISE EXCEPTION 'PE10_READER_AUDIT_NOT_RECORDED'; END IF;
END $pe10_reader$;
COMMIT;
