-- Candidate-only: NOT a deployed migration or a grant of Profile Updater write authority.
-- Owner: existing ACTUALIZACION_PERFIL_LF, no parallel registry or model engine.
-- Preflight shows service_role has USAGE(private) but NO SELECT on
-- private.lf_evidence_ledger_v1. Do not grant broad SELECT to service_role.
--
-- Rollback-only trial through Train required before any adoption:
-- BEGIN; create the function; revoke/grant only EXECUTE; assert positives/negatives;
-- verify permissions (no ledger SELECT); ROLLBACK.
--
-- This reader returns only a boolean. No private ledger data leaves the function.
-- PROFILE_OUTPUT_VALIDATION_* requires a separately governed trusted producer;
-- absent verified evidence MUST block v0.2 rather than accepting a self-claim.
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
           -- v0.2 output evidence is not a caller-declared PASS. The exact
           -- recorded positive AND negative validator executions must have
           -- trusted provider-bound ledger receipts, tied to one source head.
           -- Old assessment/method qualification semantics remain unchanged.
           AND (
             p_subject_type NOT IN
               ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
             OR (
               l.receipt_kind='PROFILE_OUTPUT_VALIDATION_RESULT'
               AND l.gate_code='PROFILE_OUTPUT_CONTRACT_VALIDATION'
               AND l.receipt_payload->>'schema'='PROFILE_OUTPUT_VALIDATION_RESULT_V1'
               AND l.receipt_payload->>'status'=
                 CASE p_subject_type
                   WHEN 'PROFILE_OUTPUT_VALIDATION_POSITIVE'
                     THEN 'CANDIDATE_OUTPUT_PARITY_OBSERVED'
                   ELSE 'EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR'
                 END
               AND l.receipt_payload->>'source_readback_matched'='true'
               AND l.receipt_payload->>'profile_validator_executed'='true'
               AND l.receipt_payload->>'admission_authorized'='false'
               AND l.receipt_payload->>'runtime_activation_authorized'='false'
               AND l.receipt_payload->>'provider_attested'='false'
               AND l.receipt_payload->>'raw_output_sha256'=l.subject_sha256
               AND (l.receipt_payload->>'validator_exit_code') ~ '^[0-9]+    );
END;
$lf$;

-- Restrict access to a boolean-verification RPC only. No schema/table grants.
REVOKE ALL ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) TO service_role;

-- Do NOT apply this source by itself. Admission requires:
-- (1) check the deployment principal may read the private ledger AND resolver registry;
-- (2) prove positive/negative exact-receipt resolution under ROLLBACK;
-- (3) cross-bind receipt to actual profile target/source and method version;
-- (4) preserve 22 frozen historic execution requirements;
-- (5) activate only with the two step contracts, judge bindings, conditional
--     policy and both consumer/recorder effective-required-step logic;
-- (6) retain NO_CHANGE without write, no autonomous GPT Native claims.

               AND (l.receipt_payload->>'validator_stdout_sha256') ~ '^[0-9a-f]{64}    );
END;
$lf$;

-- Restrict access to a boolean-verification RPC only. No schema/table grants.
REVOKE ALL ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) TO service_role;

-- Do NOT apply this source by itself. Admission requires:
-- (1) check the deployment principal may read the private ledger AND resolver registry;
-- (2) prove positive/negative exact-receipt resolution under ROLLBACK;
-- (3) cross-bind receipt to actual profile target/source and method version;
-- (4) preserve 22 frozen historic execution requirements;
-- (5) activate only with the two step contracts, judge bindings, conditional
--     policy and both consumer/recorder effective-required-step logic;
-- (6) retain NO_CHANGE without write, no autonomous GPT Native claims.

               AND jsonb_typeof(l.receipt_payload->'source_refs')='object'
               AND l.receipt_payload->'source_refs' ? 'schema'
               AND l.receipt_payload->'source_refs' ? 'validator'
               AND l.receipt_payload->'source_refs' ? 'raw_output'
               AND (
                 (p_subject_type='PROFILE_OUTPUT_VALIDATION_POSITIVE'
                   AND l.receipt_payload->>'validator_exit_code'='0'
                   AND jsonb_array_length(coalesce(l.receipt_payload->'validator_errors','[]'::jsonb))=0)
                 OR
                 (p_subject_type='PROFILE_OUTPUT_VALIDATION_NEGATIVE'
                   AND l.receipt_payload->>'validator_exit_code'<>'0'
                   AND jsonb_array_length(coalesce(l.receipt_payload->'validator_errors','[]'::jsonb))>0)
               )
             )
           )
    );
END;
$lf$;

-- Restrict access to a boolean-verification RPC only. No schema/table grants.
REVOKE ALL ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) TO service_role;

-- Do NOT apply this source by itself. Admission requires:
-- (1) check the deployment principal may read the private ledger AND resolver registry;
-- (2) prove positive/negative exact-receipt resolution under ROLLBACK;
-- (3) cross-bind receipt to actual profile target/source and method version;
-- (4) preserve 22 frozen historic execution requirements;
-- (5) activate only with the two step contracts, judge bindings, conditional
--     policy and both consumer/recorder effective-required-step logic;
-- (6) retain NO_CHANGE without write, no autonomous GPT Native claims.
