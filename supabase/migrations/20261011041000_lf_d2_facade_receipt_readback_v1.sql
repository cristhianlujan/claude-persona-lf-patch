-- LF D2 evidence ledger readback for a future business facade receipt.
-- Reuses private.lf_evidence_ledger_v1, its append-only guard and exact digest.
-- No ledger grants or RLS changes. NOT business answer admission.
CREATE OR REPLACE FUNCTION private.fn_lf_d2_facade_receipt_readback_v1(
 p_receipt_id uuid,p_expected_source_ref text,p_expected_execution_id text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $f$
DECLARE
 v_r private.lf_evidence_ledger_v1%rowtype;
 v_hash text;
 v_policy_sha text;
 v_policy_count integer;
 v_gate jsonb;
 v_state text:='BLOCK_UNVERIFIED_FACADE_RECEIPT';
 v_attestation jsonb;
BEGIN
 IF p_receipt_id IS NULL OR p_expected_source_ref IS NULL OR
    p_expected_source_ref !~ '^db://[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*$' OR
    p_expected_execution_id IS NULL OR pg_catalog.length(pg_catalog.btrim(p_expected_execution_id))<5 THEN
    v_state:='BLOCK_RECEIPT_LOOKUP_PARAMETERS_INVALID';
 ELSE
   SELECT r.* INTO v_r FROM private.lf_evidence_ledger_v1 r
   WHERE r.receipt_id=p_receipt_id
     AND r.execution_id=p_expected_execution_id
     AND r.subject_ref=p_expected_source_ref
     AND r.provider='SUPABASE'
     AND r.receipt_kind='LF_BUSINESS_FACADE_READ_V1';
   IF NOT FOUND THEN
     v_state:='BLOCK_CANONICAL_RECEIPT_NOT_FOUND';
   ELSIF v_r.verification_state IS DISTINCT FROM 'VERIFIED' OR v_r.verified_at IS NULL OR
       v_r.verification_payload->'provider_readback_verified' IS DISTINCT FROM 'true'::jsonb OR
       v_r.verification_payload->'digest_recomputed' IS DISTINCT FROM 'true'::jsonb THEN
     v_state:='BLOCK_CANONICAL_RECEIPT_NOT_VERIFIED';
   ELSE
     v_attestation:=v_r.receipt_payload->'business_read_attestation';
     SELECT count(*)::integer,max(policy_sha) INTO v_policy_count,v_policy_sha
     FROM public.lf_policy_versions WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE';
     IF v_policy_count<>1 OR v_policy_sha !~ '^[0-9a-f]{64}$' OR
        v_attestation IS NULL OR pg_catalog.jsonb_typeof(v_attestation)<>'object' OR
        v_attestation->>'source_ref' IS DISTINCT FROM p_expected_source_ref OR
        v_attestation->>'policy_sha' IS DISTINCT FROM v_policy_sha OR
        v_attestation->>'execution_id' IS DISTINCT FROM p_expected_execution_id OR
        coalesce(v_attestation->>'actor_auth_user_id','') !~
              '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' OR
        coalesce(v_attestation->>'company_id','') !~
              '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' OR
        coalesce(v_attestation->>'row_set_sha256','') !~ '^[0-9a-f]{64}$' OR
        v_attestation->>'read_facade_ref' IS NULL OR
        v_attestation->>'rls_verified' IS DISTINCT FROM 'true' OR
        v_attestation->>'tenant_permission_verified' IS DISTINCT FROM 'true' THEN
       v_state:='BLOCK_BUSINESS_READ_ATTESTATION_INCOMPLETE';
     ELSE
       v_hash:=encode(extensions.digest(convert_to(
         pg_catalog.jsonb_build_object(
          'schema_version','LF_EVIDENCE_LEDGER_RECEIPT_V1',
          'execution_id',v_r.execution_id,'capability_code',v_r.capability_code,
          'gate_code',v_r.gate_code,'receipt_kind',v_r.receipt_kind,
          'subject_type',v_r.subject_type,'subject_ref',v_r.subject_ref,
          'subject_sha256',v_r.subject_sha256,'source_head_sha',v_r.source_head_sha,
          'authority_ref',v_r.authority_ref,'resolver_id',v_r.resolver_id,
          'provider',v_r.provider,'provider_ref',v_r.provider_ref,
          'verification_method',v_r.verification_method,
          'verification_state',v_r.verification_state,
          'verification_payload',v_r.verification_payload,
          'receipt_payload',v_r.receipt_payload,
          'created_by_execution_id',v_r.created_by_execution_id)::text,
         'UTF8'),'sha256'),'hex');
       v_gate:=private.fn_lf_d2_binding_readback_v1(p_expected_source_ref);
       IF v_hash IS DISTINCT FROM v_r.receipt_sha256 THEN
         v_state:='BLOCK_RECEIPT_DIGEST_DIVERGENCE';
       ELSIF v_gate->>'decision' IS DISTINCT FROM
          'STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION' THEN
         v_state:='BLOCK_CANONICAL_SOURCE_BINDING_NO_LONGER_CURRENT';
       ELSE
         -- Never allow business answer here: actor/tenant attestations must
         -- additionally be re-verified by the actor-scoped data-plane gate.
         v_state:='STRUCTURAL_RECEIPT_VERIFIED_ACTOR_RECHECK_REQUIRED';
       END IF;
     END IF;
   END IF;
 END IF;
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D2_FACADE_RECEIPT_READBACK_V1',
  'decision',v_state,'receipt_id',p_receipt_id,
  'source_ref',p_expected_source_ref,
  'actor_session_reverified',false,
  'tenant_permission_reverified',false,
  'business_answer_authorized',false,
  'business_rows_returned',false,
  'effects_executed',false);
EXCEPTION WHEN insufficient_privilege THEN
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D2_FACADE_RECEIPT_READBACK_V1',
  'decision','BLOCK_LEDGER_ACL_DENIED',
  'actor_session_reverified',false,
  'tenant_permission_reverified',false,
  'business_answer_authorized',false,
  'business_rows_returned',false,
  'effects_executed',false);
END $f$;
COMMENT ON FUNCTION private.fn_lf_d2_facade_receipt_readback_v1(uuid,text,text)
IS 'Readback of existing governed evidence ledger only. Structural proof can never authorize business answer without actor/tenant recheck.';
REVOKE ALL ON FUNCTION private.fn_lf_d2_facade_receipt_readback_v1(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d2_facade_receipt_readback_v1(uuid,text,text) TO service_role;
