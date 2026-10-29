-- PG-01 D-A / D-B: authenticated subject verification and reviewer attestation.
-- Reuses programacion.fn_assert_external_authority_session (distinct least-privilege LOGIN with
-- SET-only membership to exactly one authority role; service_role/authenticator/postgres forbidden).
-- Additive only: no change to Fase 1 functions or to service_role privileges.
BEGIN;

-- Shared digest of the judge state an auditor attests (manifest + review steps).
CREATE FUNCTION private.fn_lf_pg01_judge_digest_v1(p_judge_execution_id text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'pg_catalog','public' AS $fn$
 SELECT jsonb_build_object(
  'manifest_sha256',encode(sha256(convert_to(coalesce((SELECT e.manifest FROM public.lf_operation_execution e
     WHERE e.execution_id=p_judge_execution_id),'null'::jsonb)::text,'UTF8')),'hex'),
  'steps_sha256',encode(sha256(convert_to(coalesce((SELECT jsonb_agg(jsonb_build_array(s.step_id,s.status,s.evidence_payload,s.created_by_execution_id)
     ORDER BY s.step_id,s.status) FROM public.lf_operation_execution_steps s WHERE s.execution_id=p_judge_execution_id
     AND s.step_id IN ('semantic_review','judge_record')),'[]'::jsonb)::text,'UTF8')),'hex'))
$fn$;

-- D-A: Supabase readback of the PG-01 subject (resolver LF_SUPABASE_READBACK_V1).
CREATE TABLE private.lf_pg01_subject_verifications_v1(
 verification_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 receipt_id uuid NOT NULL UNIQUE,
 context_id uuid NOT NULL,
 subject_ref text,
 observed_subject_sha256 text,
 source_head_sha text,
 producer_execution_id text,
 resolver_id text,
 authority_role text,
 db_principal text,
 session_principal text,
 verification_sha256 text,
 verified_at timestamptz NOT NULL DEFAULT clock_timestamp());

CREATE FUNCTION private.fn_lf_pg01_subject_verification_guard_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog','private','public' AS $fn$
DECLARE v private.lf_evidence_ledger_v1%rowtype; c record; observed text;
BEGIN
 PERFORM programacion.fn_assert_external_authority_session(ARRAY['programacion_verifier']);
 SELECT * INTO v FROM private.lf_evidence_ledger_v1 WHERE receipt_id=NEW.receipt_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_RECEIPT_MISSING'; END IF;
 SELECT * INTO c FROM private.lf_decision_context_asof_v1 WHERE context_id=NEW.context_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_READBACK_UNAVAILABLE'; END IF;
 -- Real readback: recompute the snapshot digest from the stored payload.
 observed:=encode(sha256(convert_to(c.context_payload::text,'UTF8')),'hex');
 IF observed IS DISTINCT FROM c.context_sha256 THEN RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_SNAPSHOT_DIGEST_MISMATCH'; END IF;
 IF v.subject_type IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE'
 OR v.subject_ref IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE/'||NEW.context_id::text
 OR v.subject_sha256 IS DISTINCT FROM observed THEN RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_SUBJECT_MISMATCH'; END IF;
 IF coalesce(v.source_head_sha,'') !~ '^[0-9a-f]{40}$' THEN RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_HEAD_INVALID'; END IF;
 IF v.created_by_execution_id IS NOT DISTINCT FROM c.created_by_execution_id THEN
   RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_ANCHORED_BY_PRODUCER'; END IF;
 NEW.subject_ref:=v.subject_ref; NEW.observed_subject_sha256:=observed; NEW.source_head_sha:=v.source_head_sha;
 NEW.producer_execution_id:=c.created_by_execution_id; NEW.resolver_id:='LF_SUPABASE_READBACK_V1';
 NEW.authority_role:=current_user; NEW.db_principal:=current_user; NEW.session_principal:=session_user;
 NEW.verified_at:=clock_timestamp();
 NEW.verification_sha256:=encode(sha256(convert_to(jsonb_build_object('schema_version','LF_PG01_SUBJECT_VERIFICATION_V1',
  'receipt_id',NEW.receipt_id::text,'context_id',NEW.context_id::text,'subject_ref',NEW.subject_ref,'observed_subject_sha256',observed,
  'source_head_sha',NEW.source_head_sha,'producer_execution_id',NEW.producer_execution_id,'resolver_id',NEW.resolver_id,
  'authority_role',NEW.authority_role,'session_principal',NEW.session_principal)::text,'UTF8')),'hex');
 RETURN NEW;
END $fn$;

-- D-B: independent reviewer attestation over the exact judge state.
CREATE TABLE private.lf_pg01_review_attestations_v1(
 attestation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 judge_execution_id text NOT NULL UNIQUE,
 context_id uuid,
 subject_receipt_id uuid,
 producer_execution_id text,
 manifest_sha256 text,
 steps_sha256 text,
 verifier_session_principal text,
 authority_role text,
 db_principal text,
 session_principal text,
 attestation_sha256 text,
 attested_at timestamptz NOT NULL DEFAULT clock_timestamp());

CREATE FUNCTION private.fn_lf_pg01_review_attestation_guard_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog','private','public' AS $fn$
DECLARE j public.lf_operation_execution%rowtype; sv private.lf_pg01_subject_verifications_v1%rowtype; d jsonb; ctx text;
BEGIN
 PERFORM programacion.fn_assert_external_authority_session(ARRAY['programacion_auditor']);
 SELECT * INTO j FROM public.lf_operation_execution WHERE execution_id=NEW.judge_execution_id;
 IF NOT FOUND OR j.operation_code IS DISTINCT FROM 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' OR j.status IS DISTINCT FROM 'COMPLETED'
 OR j.manifest->>'capability_code' IS DISTINCT FROM 'INDEPENDENT_ASSURANCE'
 OR j.manifest->>'subject_type' IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE'
 OR coalesce(j.manifest->>'subject_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'PG01_REVIEW_ATTEST_JUDGE_INVALID'; END IF;
 ctx:=split_part(j.manifest->>'subject_ref','/',2);
 SELECT * INTO sv FROM private.lf_pg01_subject_verifications_v1 WHERE receipt_id=(j.manifest->>'subject_receipt_id')::uuid;
 IF NOT FOUND OR sv.context_id::text IS DISTINCT FROM ctx OR sv.observed_subject_sha256 IS DISTINCT FROM j.manifest->>'subject_sha256'
 OR sv.source_head_sha IS DISTINCT FROM j.manifest->>'source_head_sha'
 OR sv.producer_execution_id IS DISTINCT FROM j.manifest->>'producer_execution_id' THEN
   RAISE EXCEPTION 'PG01_REVIEW_ATTEST_SUBJECT_NOT_VERIFIED'; END IF;
 IF sv.session_principal IS NOT DISTINCT FROM session_user THEN RAISE EXCEPTION 'PG01_REVIEW_ATTEST_SAME_PRINCIPAL_AS_VERIFIER'; END IF;
 d:=private.fn_lf_pg01_judge_digest_v1(NEW.judge_execution_id);
 NEW.context_id:=sv.context_id; NEW.subject_receipt_id:=sv.receipt_id; NEW.producer_execution_id:=sv.producer_execution_id;
 NEW.manifest_sha256:=d->>'manifest_sha256'; NEW.steps_sha256:=d->>'steps_sha256'; NEW.verifier_session_principal:=sv.session_principal;
 NEW.authority_role:=current_user; NEW.db_principal:=current_user; NEW.session_principal:=session_user; NEW.attested_at:=clock_timestamp();
 NEW.attestation_sha256:=encode(sha256(convert_to(jsonb_build_object('schema_version','LF_PG01_REVIEW_ATTESTATION_V1',
  'judge_execution_id',NEW.judge_execution_id,'context_id',NEW.context_id::text,'subject_receipt_id',NEW.subject_receipt_id::text,
  'producer_execution_id',NEW.producer_execution_id,'manifest_sha256',NEW.manifest_sha256,'steps_sha256',NEW.steps_sha256,
  'verifier_session_principal',NEW.verifier_session_principal,'authority_role',NEW.authority_role,
  'session_principal',NEW.session_principal)::text,'UTF8')),'hex');
 RETURN NEW;
END $fn$;

CREATE FUNCTION private.fn_lf_pg01_attestation_append_only_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog' AS $fn$
BEGIN RAISE EXCEPTION 'PG01_ATTESTATION_APPEND_ONLY'; END $fn$;

CREATE TRIGGER trg_00_lf_pg01_subject_verification_guard_v1 BEFORE INSERT ON private.lf_pg01_subject_verifications_v1
 FOR EACH ROW EXECUTE FUNCTION private.fn_lf_pg01_subject_verification_guard_v1();
CREATE TRIGGER trg_01_lf_pg01_subject_verification_append_only_v1 BEFORE UPDATE OR DELETE ON private.lf_pg01_subject_verifications_v1
 FOR EACH ROW EXECUTE FUNCTION private.fn_lf_pg01_attestation_append_only_v1();
CREATE TRIGGER trg_00_lf_pg01_review_attestation_guard_v1 BEFORE INSERT ON private.lf_pg01_review_attestations_v1
 FOR EACH ROW EXECUTE FUNCTION private.fn_lf_pg01_review_attestation_guard_v1();
CREATE TRIGGER trg_01_lf_pg01_review_attestation_append_only_v1 BEFORE UPDATE OR DELETE ON private.lf_pg01_review_attestations_v1
 FOR EACH ROW EXECUTE FUNCTION private.fn_lf_pg01_attestation_append_only_v1();

-- Privileges: only the two authority roles may insert (through their guards); nobody may update.
REVOKE ALL ON private.lf_pg01_subject_verifications_v1, private.lf_pg01_review_attestations_v1 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_lf_pg01_judge_digest_v1(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_lf_pg01_subject_verification_guard_v1() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_lf_pg01_review_attestation_guard_v1() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_lf_pg01_attestation_append_only_v1() FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA private TO programacion_verifier, programacion_auditor;
GRANT INSERT (receipt_id, context_id) ON private.lf_pg01_subject_verifications_v1 TO programacion_verifier;
GRANT SELECT ON private.lf_pg01_subject_verifications_v1 TO programacion_verifier, programacion_auditor;
GRANT INSERT (judge_execution_id) ON private.lf_pg01_review_attestations_v1 TO programacion_auditor;
GRANT SELECT ON private.lf_evidence_ledger_v1, private.lf_decision_context_asof_v1 TO programacion_verifier;
GRANT SELECT ON public.lf_operation_execution, public.lf_operation_execution_steps TO programacion_auditor;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_judge_digest_v1(text) TO programacion_auditor;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_subject_verification_guard_v1() TO programacion_verifier;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_review_attestation_guard_v1() TO programacion_auditor;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_attestation_append_only_v1() TO programacion_verifier, programacion_auditor;

COMMENT ON TABLE private.lf_pg01_subject_verifications_v1 IS 'PG-01 D-A: authenticated Supabase readback (LF_SUPABASE_READBACK_V1) of a PROGRAMMING_ANALYSIS_PACKAGE evidence receipt. Inserted only by a programacion_verifier external login.';
COMMENT ON TABLE private.lf_pg01_review_attestations_v1 IS 'PG-01 D-B: independent reviewer attestation over the exact judge manifest and review steps. Inserted only by a programacion_auditor external login.';

DO $after$
BEGIN
 IF has_table_privilege('service_role','private.lf_pg01_subject_verifications_v1','INSERT')
 OR has_table_privilege('service_role','private.lf_pg01_review_attestations_v1','INSERT')
 OR has_table_privilege('service_role','private.lf_pg01_review_attestations_v1','UPDATE') THEN
  RAISE EXCEPTION 'PG01_ATTESTATION_PERMISSIONS_INVALID'; END IF;
END $after$;
COMMIT;
