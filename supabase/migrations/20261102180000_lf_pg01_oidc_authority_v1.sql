-- LF / H1-C2 / PG-01: GitHub OIDC authority for PG-01 D-A (subject verification) and
-- D-B (review attestation), aligned with PROG-ADR-AUTH-001/002/003 (no dedicated
-- PostgreSQL login as authority). Reuses the LF OIDC pattern of
-- lf_runtime_readback_oidc_receipts (fixed claim policy, run/token uniqueness), the existing
-- PG-01 tables, readback logic and append-only trigger. Separate audiences, workflows,
-- environments and receipt table: deploy readback receipts are NOT PG-01 authority.
--
-- Trust boundary: the RS256 signature is verified INSIDE PostgreSQL (private.fn_lf_pg01_rs256_verify_v1)
-- against GitHub signing keys pinned in private.lf_pg01_oidc_jwks_v1, which only a governed
-- migration (Train) can write. A BEFORE INSERT trigger on the receipt table enforces it, so neither
-- the Edge function nor a direct service_role call can record an unverified token. The Edge
-- function verifies too (first gate). With no pinned key every intake fails closed
-- (PG01_OIDC_KID_NOT_PINNED); keys are pinned by a separate migration generated from the live
-- GitHub JWKS (scripts/lf_pg01_oidc_jwks_pin_sql.py).
--
-- The legacy external-login path of the guards is preserved unchanged (no consumer break);
-- retiring it is a separate decision once the OIDC path has an authentic positive.
BEGIN;

DO $pre$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='lf_pg01_oidc_recorder') THEN
   RAISE EXCEPTION 'PG01_OIDC_RECORDER_ALREADY_EXISTS';
 END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='private' AND c.relname IN ('lf_pg01_subject_verifications_v1','lf_pg01_review_attestations_v1',
            'lf_evidence_ledger_v1','lf_decision_context_asof_v1')) <> 4
 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='private' AND p.proname IN ('fn_lf_pg01_subject_verification_guard_v1',
            'fn_lf_pg01_review_attestation_guard_v1','fn_lf_pg01_judge_digest_v1','fn_lf_pg01_attestation_append_only_v1')) <> 4 THEN
   RAISE EXCEPTION 'PG01_OIDC_CONSUMERS_MISSING';
 END IF;
END $pre$;

-- Recorder: NOLOGIN owner of the SECURITY DEFINER core (ADR-EKB-030: no login, no inherit).
CREATE ROLE lf_pg01_oidc_recorder NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
COMMENT ON ROLE lf_pg01_oidc_recorder IS 'PG-01 GitHub OIDC recorder (H1-C2). NOLOGIN; reachable only through public.lf_pg01_oidc_authority_record_v1.';

-- Pinned GitHub Actions OIDC signing keys. Written only by governed migrations (table owner);
-- no API role can read or write it except the recorder (read).
CREATE TABLE private.lf_pg01_oidc_jwks_v1(
 kid text PRIMARY KEY,
 kty text NOT NULL CHECK (kty='RSA'),
 n bytea NOT NULL CHECK (length(n) >= 256),
 e bytea NOT NULL,
 issuer text NOT NULL CHECK (issuer='https://token.actions.githubusercontent.com'),
 source_ref text NOT NULL,
 active boolean NOT NULL DEFAULT true,
 pinned_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE private.lf_pg01_oidc_jwks_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.lf_pg01_oidc_jwks_v1 FROM PUBLIC, anon, authenticated, service_role;
CREATE POLICY pol_lf_pg01_oidc_jwks_recorder_select ON private.lf_pg01_oidc_jwks_v1 FOR SELECT TO lf_pg01_oidc_recorder USING (active);

CREATE FUNCTION private.fn_lf_pg01_b64url_v1(p text) RETURNS bytea
LANGUAGE sql IMMUTABLE STRICT SET search_path TO pg_catalog AS $fn$
 SELECT decode(rpad(translate(p,'-_','+/'),((length(p)+3)/4)*4,'='),'base64')
$fn$;
CREATE FUNCTION private.fn_lf_pg01_bytes_to_num_v1(b bytea) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE STRICT SET search_path TO pg_catalog AS $fn$
DECLARE r numeric := 0; i int;
BEGIN FOR i IN 0..length(b)-1 LOOP r := r*256 + get_byte(b,i); END LOOP; RETURN r; END $fn$;
CREATE FUNCTION private.fn_lf_pg01_modpow_v1(b numeric, e numeric, m numeric) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE STRICT SET search_path TO pg_catalog AS $fn$
DECLARE r numeric := 1;
BEGIN
 b := mod(b,m);
 WHILE e > 0 LOOP
   IF mod(e,2) = 1 THEN r := mod(r*b,m); END IF;
   e := div(e,2);
   IF e > 0 THEN b := mod(b*b,m); END IF;
 END LOOP;
 RETURN r;
END $fn$;
-- RSASSA-PKCS1-v1_5 / SHA-256 (RFC 8017 sec. 8.2.2) over "<header>.<payload>". Returns the kid or raises.
CREATE FUNCTION private.fn_lf_pg01_rs256_verify_v1(p_token text) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO pg_catalog, private AS $fn$
DECLARE h jsonb; k record; sig bytea; nlen int; s numeric; nn numeric; em bytea;
BEGIN
 IF coalesce(p_token,'') !~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' THEN RAISE EXCEPTION 'PG01_OIDC_TOKEN_MALFORMED'; END IF;
 BEGIN h := private.fn_lf_pg01_jwt_part_v1(p_token,1);
 EXCEPTION WHEN others THEN RAISE EXCEPTION 'PG01_OIDC_TOKEN_MALFORMED'; END;
 IF h->>'alg' IS DISTINCT FROM 'RS256' OR coalesce(h->>'kid','') = '' THEN RAISE EXCEPTION 'PG01_OIDC_ALG_INVALID'; END IF;
 SELECT * INTO k FROM private.lf_pg01_oidc_jwks_v1 WHERE kid = h->>'kid' AND active AND kty='RSA';
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_OIDC_KID_NOT_PINNED'; END IF;
 BEGIN sig := private.fn_lf_pg01_b64url_v1(split_part(p_token,'.',3));
 EXCEPTION WHEN others THEN RAISE EXCEPTION 'PG01_OIDC_SIGNATURE_INVALID'; END;
 nlen := length(k.n);
 IF length(sig) <> nlen THEN RAISE EXCEPTION 'PG01_OIDC_SIGNATURE_INVALID'; END IF;
 s := private.fn_lf_pg01_bytes_to_num_v1(sig); nn := private.fn_lf_pg01_bytes_to_num_v1(k.n);
 IF s >= nn THEN RAISE EXCEPTION 'PG01_OIDC_SIGNATURE_INVALID'; END IF;
 em := '\x0001'::bytea || decode(repeat('ff', nlen-3-51),'hex') || '\x00'::bytea
       || '\x3031300d060960864801650304020105000420'::bytea
       || sha256(convert_to(split_part(p_token,'.',1)||'.'||split_part(p_token,'.',2),'UTF8'));
 IF private.fn_lf_pg01_modpow_v1(s, private.fn_lf_pg01_bytes_to_num_v1(k.e), nn) <> private.fn_lf_pg01_bytes_to_num_v1(em) THEN
   RAISE EXCEPTION 'PG01_OIDC_SIGNATURE_INVALID'; END IF;
 RETURN k.kid;
END $fn$;

CREATE TABLE private.lf_pg01_oidc_authority_receipts_v1(
 oidc_receipt_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 kind text NOT NULL CHECK (kind IN ('SUBJECT_VERIFICATION','REVIEW_ATTESTATION')),
 subject_key text NOT NULL,
 token text NOT NULL,
 token_sha256 text NOT NULL UNIQUE CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
 claims jsonb NOT NULL,
 principal text NOT NULL,
 workflow_run_id text NOT NULL,
 workflow_run_attempt text NOT NULL,
 payload jsonb NOT NULL,
 authenticated_by text NOT NULL DEFAULT 'GITHUB_OIDC' CHECK (authenticated_by='GITHUB_OIDC'),
 signature_kid text NOT NULL,
 signature_verifier text NOT NULL CHECK (signature_verifier='LF_PG_RS256_V1'),
 recorded_txid bigint NOT NULL DEFAULT txid_current(),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE (workflow_run_id, workflow_run_attempt),
 UNIQUE (kind, subject_key));
ALTER TABLE private.lf_pg01_oidc_authority_receipts_v1 ENABLE ROW LEVEL SECURITY;
-- Authoritative boundary: every receipt row is signature-verified in the DB and its token-derived
-- fields are recomputed from the token, whoever inserts it.
CREATE FUNCTION private.fn_lf_pg01_oidc_receipt_signature_guard_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path TO pg_catalog, private AS $fn$
BEGIN
 NEW.signature_kid := private.fn_lf_pg01_rs256_verify_v1(NEW.token);
 NEW.signature_verifier := 'LF_PG_RS256_V1';
 NEW.claims := private.fn_lf_pg01_jwt_part_v1(NEW.token,2);
 NEW.token_sha256 := encode(sha256(convert_to(NEW.token,'UTF8')),'hex');
 IF NEW.workflow_run_id IS DISTINCT FROM NEW.claims->>'run_id' OR NEW.workflow_run_attempt IS DISTINCT FROM NEW.claims->>'run_attempt' THEN
   RAISE EXCEPTION 'PG01_OIDC_RUN_BINDING_MISMATCH'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER trg_00_lf_pg01_oidc_receipt_signature_guard_v1 BEFORE INSERT ON private.lf_pg01_oidc_authority_receipts_v1
 FOR EACH ROW EXECUTE FUNCTION private.fn_lf_pg01_oidc_receipt_signature_guard_v1();
CREATE TRIGGER trg_01_lf_pg01_oidc_receipt_append_only_v1 BEFORE UPDATE OR DELETE ON private.lf_pg01_oidc_authority_receipts_v1
 FOR EACH ROW EXECUTE FUNCTION private.fn_lf_pg01_attestation_append_only_v1();
REVOKE ALL ON private.lf_pg01_oidc_authority_receipts_v1 FROM PUBLIC, anon, authenticated, service_role;
CREATE POLICY pol_lf_pg01_oidc_receipts_recorder_insert ON private.lf_pg01_oidc_authority_receipts_v1
 FOR INSERT TO lf_pg01_oidc_recorder WITH CHECK (authenticated_by='GITHUB_OIDC' AND recorded_txid=txid_current());
CREATE POLICY pol_lf_pg01_oidc_receipts_recorder_select ON private.lf_pg01_oidc_authority_receipts_v1
 FOR SELECT TO lf_pg01_oidc_recorder USING (true);
CREATE POLICY pol_lf_pg01_oidc_receipts_authority_select ON private.lf_pg01_oidc_authority_receipts_v1
 FOR SELECT TO programacion_verifier, programacion_auditor USING (true);
GRANT USAGE ON SCHEMA private TO lf_pg01_oidc_recorder;
GRANT SELECT, INSERT ON private.lf_pg01_oidc_authority_receipts_v1 TO lf_pg01_oidc_recorder;
GRANT SELECT ON private.lf_pg01_oidc_jwks_v1 TO lf_pg01_oidc_recorder;
GRANT SELECT ON private.lf_pg01_oidc_authority_receipts_v1 TO programacion_verifier, programacion_auditor;

-- Same reads/writes the existing guards need, granted to the recorder (no new privilege class).
GRANT SELECT ON private.lf_evidence_ledger_v1, private.lf_decision_context_asof_v1 TO lf_pg01_oidc_recorder;
GRANT SELECT ON public.lf_operation_execution, public.lf_operation_execution_steps TO lf_pg01_oidc_recorder;
GRANT SELECT ON private.lf_pg01_subject_verifications_v1 TO lf_pg01_oidc_recorder;
GRANT INSERT (receipt_id, context_id) ON private.lf_pg01_subject_verifications_v1 TO lf_pg01_oidc_recorder;
GRANT INSERT (judge_execution_id) ON private.lf_pg01_review_attestations_v1 TO lf_pg01_oidc_recorder;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_judge_digest_v1(text) TO lf_pg01_oidc_recorder;
CREATE POLICY pol_lf_pg01_subject_verifications_v1_insert_oidc ON private.lf_pg01_subject_verifications_v1
 FOR INSERT TO lf_pg01_oidc_recorder WITH CHECK (true);
CREATE POLICY pol_lf_pg01_subject_verifications_v1_select_oidc ON private.lf_pg01_subject_verifications_v1
 FOR SELECT TO lf_pg01_oidc_recorder USING (true);
CREATE POLICY pol_lf_pg01_review_attestations_v1_insert_oidc ON private.lf_pg01_review_attestations_v1
 FOR INSERT TO lf_pg01_oidc_recorder WITH CHECK (true);

-- JWT segment decoder (no signature claim: signature is verified at the Edge and re-verifiable offline).
CREATE FUNCTION private.fn_lf_pg01_jwt_part_v1(p_token text, p_idx int) RETURNS jsonb
LANGUAGE sql IMMUTABLE STRICT SET search_path TO pg_catalog AS $fn$
 SELECT convert_from(decode(rpad(translate(split_part(p_token,'.',p_idx),'-_','+/'),
        ((length(split_part(p_token,'.',p_idx))+3)/4)*4,'='),'base64'),'UTF8')::jsonb
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_pg01_jwt_part_v1(text,int) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_jwt_part_v1(text,int) TO lf_pg01_oidc_recorder;

REVOKE ALL ON FUNCTION private.fn_lf_pg01_b64url_v1(text), private.fn_lf_pg01_bytes_to_num_v1(bytea),
 private.fn_lf_pg01_modpow_v1(numeric,numeric,numeric), private.fn_lf_pg01_rs256_verify_v1(text),
 private.fn_lf_pg01_oidc_receipt_signature_guard_v1() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_b64url_v1(text), private.fn_lf_pg01_bytes_to_num_v1(bytea),
 private.fn_lf_pg01_modpow_v1(numeric,numeric,numeric), private.fn_lf_pg01_rs256_verify_v1(text),
 private.fn_lf_pg01_oidc_receipt_signature_guard_v1() TO lf_pg01_oidc_recorder;

-- Principal resolver used by both guards: OIDC receipt recorded in this same transaction by the
-- recorder, otherwise the unchanged legacy external-login assertion.
CREATE FUNCTION private.fn_lf_pg01_authority_principal_v1(p_kind text, p_subject text) RETURNS text
LANGUAGE plpgsql SET search_path TO pg_catalog, private AS $fn$
DECLARE v text;
BEGIN
 IF current_user = 'lf_pg01_oidc_recorder' THEN
   SELECT principal INTO v FROM private.lf_pg01_oidc_authority_receipts_v1
    WHERE kind=p_kind AND subject_key=p_subject AND recorded_txid=txid_current();
   IF v IS NULL THEN RAISE EXCEPTION 'PG01_OIDC_RECEIPT_NOT_IN_TRANSACTION'; END IF;
   RETURN v;
 END IF;
 PERFORM programacion.fn_assert_external_authority_session(
   ARRAY[CASE p_kind WHEN 'SUBJECT_VERIFICATION' THEN 'programacion_verifier' ELSE 'programacion_auditor' END]);
 RETURN session_user;
END $fn$;
REVOKE ALL ON FUNCTION private.fn_lf_pg01_authority_principal_v1(text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_authority_principal_v1(text,text) TO programacion_verifier, programacion_auditor, lf_pg01_oidc_recorder;

-- Guards: identical logic; only the principal source changes (legacy path behaves as before).
CREATE OR REPLACE FUNCTION private.fn_lf_pg01_subject_verification_guard_v1()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
DECLARE v private.lf_evidence_ledger_v1%rowtype; c record; observed text; principal text;
BEGIN
 principal:=private.fn_lf_pg01_authority_principal_v1('SUBJECT_VERIFICATION',NEW.receipt_id::text);
 SELECT * INTO v FROM private.lf_evidence_ledger_v1 WHERE receipt_id=NEW.receipt_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_RECEIPT_MISSING'; END IF;
 SELECT * INTO c FROM private.lf_decision_context_asof_v1 WHERE context_id=NEW.context_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_SUBJECT_VERIFY_READBACK_UNAVAILABLE'; END IF;
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
 NEW.authority_role:=CASE WHEN current_user='lf_pg01_oidc_recorder' THEN 'GITHUB_OIDC_SUBJECT_VERIFIER' ELSE current_user END;
 NEW.db_principal:=current_user; NEW.session_principal:=principal;
 NEW.verified_at:=clock_timestamp();
 NEW.verification_sha256:=encode(sha256(convert_to(jsonb_build_object('schema_version','LF_PG01_SUBJECT_VERIFICATION_V1',
  'receipt_id',NEW.receipt_id::text,'context_id',NEW.context_id::text,'subject_ref',NEW.subject_ref,'observed_subject_sha256',observed,
  'source_head_sha',NEW.source_head_sha,'producer_execution_id',NEW.producer_execution_id,'resolver_id',NEW.resolver_id,
  'authority_role',NEW.authority_role,'session_principal',NEW.session_principal)::text,'UTF8')),'hex');
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION private.fn_lf_pg01_review_attestation_guard_v1()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
DECLARE j public.lf_operation_execution%rowtype; sv private.lf_pg01_subject_verifications_v1%rowtype; d jsonb; ctx text; principal text;
BEGIN
 principal:=private.fn_lf_pg01_authority_principal_v1('REVIEW_ATTESTATION',NEW.judge_execution_id);
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
 IF sv.session_principal IS NOT DISTINCT FROM principal THEN RAISE EXCEPTION 'PG01_REVIEW_ATTEST_SAME_PRINCIPAL_AS_VERIFIER'; END IF;
 d:=private.fn_lf_pg01_judge_digest_v1(NEW.judge_execution_id);
 NEW.context_id:=sv.context_id; NEW.subject_receipt_id:=sv.receipt_id; NEW.producer_execution_id:=sv.producer_execution_id;
 NEW.manifest_sha256:=d->>'manifest_sha256'; NEW.steps_sha256:=d->>'steps_sha256'; NEW.verifier_session_principal:=sv.session_principal;
 NEW.authority_role:=CASE WHEN current_user='lf_pg01_oidc_recorder' THEN 'GITHUB_OIDC_REVIEW_AUDITOR' ELSE current_user END;
 NEW.db_principal:=current_user; NEW.session_principal:=principal; NEW.attested_at:=clock_timestamp();
 NEW.attestation_sha256:=encode(sha256(convert_to(jsonb_build_object('schema_version','LF_PG01_REVIEW_ATTESTATION_V1',
  'judge_execution_id',NEW.judge_execution_id,'context_id',NEW.context_id::text,'subject_receipt_id',NEW.subject_receipt_id::text,
  'producer_execution_id',NEW.producer_execution_id,'manifest_sha256',NEW.manifest_sha256,'steps_sha256',NEW.steps_sha256,
  'verifier_session_principal',NEW.verifier_session_principal,'authority_role',NEW.authority_role,
  'session_principal',NEW.session_principal)::text,'UTF8')),'hex');
 RETURN NEW;
END $function$;

-- Core recorder (runs as lf_pg01_oidc_recorder). Fixed claim policy; DB readback via the guards.
CREATE FUNCTION private.fn_lf_pg01_oidc_record_core_v1(p_kind text, p_token text, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, private, public AS $fn$
DECLARE
 h jsonb; c jsonb; v_aud text; v_wf text; v_env text; v_principal text; v_tsha text; v_now bigint;
 v_run text; v_att text; v_id bigint; v_subject text; r record; v_prod text; v_ledger_prod text; sv_tok text;
 c_repo constant text := 'cristhianlujan/claude-persona-lf-patch';
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('SUBJECT_VERIFICATION','REVIEW_ATTESTATION') THEN RAISE EXCEPTION 'PG01_OIDC_KIND_INVALID'; END IF;
 IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN RAISE EXCEPTION 'PG01_OIDC_PAYLOAD_INVALID'; END IF;
 IF coalesce(p_token,'') !~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' THEN RAISE EXCEPTION 'PG01_OIDC_TOKEN_MALFORMED'; END IF;
 BEGIN
   h:=private.fn_lf_pg01_jwt_part_v1(p_token,1); c:=private.fn_lf_pg01_jwt_part_v1(p_token,2);
 EXCEPTION WHEN others THEN RAISE EXCEPTION 'PG01_OIDC_TOKEN_MALFORMED';
 END;
 IF h->>'alg' IS DISTINCT FROM 'RS256' OR coalesce(h->>'kid','')='' THEN RAISE EXCEPTION 'PG01_OIDC_ALG_INVALID'; END IF;
 PERFORM private.fn_lf_pg01_rs256_verify_v1(p_token);  -- cryptographic gate before any policy or write
 v_aud := CASE p_kind WHEN 'SUBJECT_VERIFICATION' THEN 'lf-pg01-subject-verification' ELSE 'lf-pg01-review-attestation' END;
 v_wf := c_repo||'/.github/workflows/'||CASE p_kind WHEN 'SUBJECT_VERIFICATION' THEN 'lf-pg01-oidc-subject-verifier.yml'
          ELSE 'lf-pg01-oidc-review-auditor.yml' END||'@refs/heads/main';
 v_env := CASE p_kind WHEN 'SUBJECT_VERIFICATION' THEN 'lf-pg01-verifier' ELSE 'lf-pg01-auditor' END;
 v_now := extract(epoch FROM clock_timestamp())::bigint;
 IF c->>'iss' IS DISTINCT FROM 'https://token.actions.githubusercontent.com' THEN RAISE EXCEPTION 'PG01_OIDC_ISSUER_MISMATCH'; END IF;
 IF c->>'aud' IS DISTINCT FROM v_aud THEN RAISE EXCEPTION 'PG01_OIDC_AUDIENCE_MISMATCH'; END IF;
 IF c->>'repository' IS DISTINCT FROM c_repo OR c->>'repository_id' IS DISTINCT FROM '1244397752' THEN RAISE EXCEPTION 'PG01_OIDC_REPOSITORY_MISMATCH'; END IF;
 IF c->>'ref' IS DISTINCT FROM 'refs/heads/main' THEN RAISE EXCEPTION 'PG01_OIDC_REF_MISMATCH'; END IF;
 IF c->>'event_name' IS DISTINCT FROM 'workflow_dispatch' THEN RAISE EXCEPTION 'PG01_OIDC_EVENT_MISMATCH'; END IF;
 IF c->>'workflow_ref' IS DISTINCT FROM v_wf OR c->>'job_workflow_ref' IS DISTINCT FROM v_wf THEN RAISE EXCEPTION 'PG01_OIDC_WORKFLOW_MISMATCH'; END IF;
 IF c->>'environment' IS DISTINCT FROM v_env THEN RAISE EXCEPTION 'PG01_OIDC_ENVIRONMENT_MISMATCH'; END IF;
 v_run := coalesce(c->>'run_id',''); v_att := coalesce(c->>'run_attempt','');
 IF v_run !~ '^[0-9]+$' OR v_att !~ '^[0-9]+$' THEN RAISE EXCEPTION 'PG01_OIDC_RUN_INVALID'; END IF;
 IF coalesce(c->>'exp','') !~ '^[0-9]+$' OR (c->>'exp')::bigint <= v_now THEN RAISE EXCEPTION 'PG01_OIDC_TOKEN_EXPIRED'; END IF;
 IF coalesce(c->>'iat','') !~ '^[0-9]+$' OR (c->>'iat')::bigint > v_now + 60 THEN RAISE EXCEPTION 'PG01_OIDC_IAT_INVALID'; END IF;
 IF p_payload->>'workflow_run_id' IS DISTINCT FROM v_run OR p_payload->>'workflow_run_attempt' IS DISTINCT FROM v_att THEN
   RAISE EXCEPTION 'PG01_OIDC_RUN_BINDING_MISMATCH'; END IF;
 v_tsha := encode(sha256(convert_to(p_token,'UTF8')),'hex');
 v_principal := 'GITHUB_OIDC:'||v_wf||'#environment='||v_env;

 IF p_kind = 'SUBJECT_VERIFICATION' THEN
   IF coalesce(p_payload->>'receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   OR coalesce(p_payload->>'context_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   OR coalesce(p_payload->>'subject_sha256','') !~ '^[0-9a-f]{64}$'
   OR coalesce(p_payload->>'source_head_sha','') !~ '^[0-9a-f]{40}$' THEN RAISE EXCEPTION 'PG01_OIDC_SUBJECT_PAYLOAD_INVALID'; END IF;
   IF p_payload->'github_readback'->>'head_commit_verified' IS DISTINCT FROM 'true'
   OR p_payload->'github_readback'->>'head_sha' IS DISTINCT FROM p_payload->>'source_head_sha' THEN
     RAISE EXCEPTION 'PG01_OIDC_GITHUB_READBACK_MISSING'; END IF;
   SELECT created_by_execution_id INTO v_prod FROM private.lf_decision_context_asof_v1 WHERE context_id=(p_payload->>'context_id')::uuid;
   SELECT created_by_execution_id INTO v_ledger_prod FROM private.lf_evidence_ledger_v1 WHERE receipt_id=(p_payload->>'receipt_id')::uuid;
   IF coalesce(v_prod,'') ~ ('(^|[^0-9])'||v_run||'([^0-9]|$)') OR coalesce(v_ledger_prod,'') ~ ('(^|[^0-9])'||v_run||'([^0-9]|$)') THEN
     RAISE EXCEPTION 'PG01_OIDC_PRODUCER_SELF_VERIFICATION'; END IF;
   v_subject := p_payload->>'receipt_id';
   INSERT INTO private.lf_pg01_oidc_authority_receipts_v1(kind,subject_key,token,token_sha256,claims,principal,workflow_run_id,workflow_run_attempt,payload)
   VALUES (p_kind,v_subject,p_token,v_tsha,c,v_principal,v_run,v_att,p_payload) RETURNING oidc_receipt_id INTO v_id;
   INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id)
   VALUES ((p_payload->>'receipt_id')::uuid,(p_payload->>'context_id')::uuid)
   RETURNING observed_subject_sha256, source_head_sha, verification_sha256 INTO r;
   IF r.observed_subject_sha256 IS DISTINCT FROM p_payload->>'subject_sha256' OR r.source_head_sha IS DISTINCT FROM p_payload->>'source_head_sha' THEN
     RAISE EXCEPTION 'PG01_OIDC_PAYLOAD_READBACK_MISMATCH'; END IF;
   RETURN jsonb_build_object('decision','VERIFIED_RECORDED','kind',p_kind,'oidc_receipt_id',v_id,'principal',v_principal,
     'token_sha256',v_tsha,'verification_sha256',r.verification_sha256,'signature_verifier','LF_PG_RS256_V1');
 END IF;

 -- REVIEW_ATTESTATION: the auditor names the verifier run it read back on GitHub; the DB accepts it only
 -- if that run is exactly the one whose DB-verified token recorded this judge's subject verification.
 IF coalesce(p_payload->>'judge_execution_id','') = '' OR coalesce(p_payload->>'verifier_run_id','') !~ '^[0-9]+$' THEN
   RAISE EXCEPTION 'PG01_OIDC_REVIEW_PAYLOAD_INVALID'; END IF;
 IF p_payload->>'verifier_run_id' = v_run THEN RAISE EXCEPTION 'PG01_OIDC_SAME_RUN_NOT_INDEPENDENT'; END IF;
 IF p_payload->'verifier_run_readback'->>'workflow_path' IS DISTINCT FROM '.github/workflows/lf-pg01-oidc-subject-verifier.yml'
 OR p_payload->'verifier_run_readback'->>'conclusion' IS DISTINCT FROM 'success'
 OR p_payload->'verifier_run_readback'->>'head_branch' IS DISTINCT FROM 'main'
 OR p_payload->'verifier_run_readback'->>'run_id' IS DISTINCT FROM p_payload->>'verifier_run_id' THEN
   RAISE EXCEPTION 'PG01_OIDC_VERIFIER_RUN_READBACK_MISSING'; END IF;
 SELECT o.workflow_run_id INTO sv_tok FROM public.lf_operation_execution j
   JOIN private.lf_pg01_oidc_authority_receipts_v1 o ON o.kind='SUBJECT_VERIFICATION' AND o.subject_key=j.manifest->>'subject_receipt_id'
  WHERE j.execution_id=p_payload->>'judge_execution_id' AND o.signature_verifier='LF_PG_RS256_V1';
 IF sv_tok IS DISTINCT FROM p_payload->>'verifier_run_id' THEN RAISE EXCEPTION 'PG01_OIDC_VERIFIER_RECEIPT_MISMATCH'; END IF;
 v_subject := p_payload->>'judge_execution_id';
 INSERT INTO private.lf_pg01_oidc_authority_receipts_v1(kind,subject_key,token,token_sha256,claims,principal,workflow_run_id,workflow_run_attempt,payload)
 VALUES (p_kind,v_subject,p_token,v_tsha,c,v_principal,v_run,v_att,p_payload) RETURNING oidc_receipt_id INTO v_id;
 INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES (v_subject);
 RETURN jsonb_build_object('decision','ATTESTED_RECORDED','kind',p_kind,'oidc_receipt_id',v_id,'principal',v_principal,'token_sha256',v_tsha,'signature_verifier','LF_PG_RS256_V1');
END $fn$;
REVOKE ALL ON FUNCTION private.fn_lf_pg01_oidc_record_core_v1(text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- Hand the core to the NOLOGIN recorder (temporary SET membership + CREATE, both removed), then let
-- the recorder grant EXECUTE to the applying principal, which owns the PostgREST wrapper below.
DO $own$
DECLARE app text := current_user;
BEGIN
 EXECUTE format('GRANT lf_pg01_oidc_recorder TO %I WITH INHERIT FALSE, SET TRUE', app);
 GRANT CREATE ON SCHEMA private TO lf_pg01_oidc_recorder;
 ALTER FUNCTION private.fn_lf_pg01_oidc_record_core_v1(text,text,jsonb) OWNER TO lf_pg01_oidc_recorder;
 SET LOCAL ROLE lf_pg01_oidc_recorder;
 EXECUTE format('GRANT EXECUTE ON FUNCTION private.fn_lf_pg01_oidc_record_core_v1(text,text,jsonb) TO %I', app);
 RESET ROLE;
 REVOKE CREATE ON SCHEMA private FROM lf_pg01_oidc_recorder;
 EXECUTE format('REVOKE lf_pg01_oidc_recorder FROM %I', app);
END $own$;

-- PostgREST entry for the Edge function only (service_role stays inside Edge).
CREATE FUNCTION public.lf_pg01_oidc_authority_record_v1(p_kind text, p_token text, p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path TO pg_catalog AS $fn$
 SELECT private.fn_lf_pg01_oidc_record_core_v1(p_kind, p_token, p_payload)
$fn$;
REVOKE ALL ON FUNCTION public.lf_pg01_oidc_authority_record_v1(text,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_pg01_oidc_authority_record_v1(text,text,jsonb) TO service_role;

COMMENT ON TABLE private.lf_pg01_oidc_authority_receipts_v1 IS
 'PG-01 H1-C2 GitHub OIDC receipts; each row RS256-verified in the DB against pinned keys (LF_PG_RS256_V1). Raw token kept (expired, single-use, not API-readable) for independent re-verification. Distinct from deploy readback receipts.';
COMMENT ON TABLE private.lf_pg01_oidc_jwks_v1 IS
 'Pinned GitHub Actions OIDC signing keys for PG-01. Write only via governed migration generated by scripts/lf_pg01_oidc_jwks_pin_sql.py from the live JWKS.';

DO $post$
BEGIN
 IF has_table_privilege('service_role','private.lf_pg01_oidc_authority_receipts_v1','INSERT')
 OR has_table_privilege('service_role','private.lf_pg01_subject_verifications_v1','INSERT')
 OR has_table_privilege('service_role','private.lf_pg01_review_attestations_v1','INSERT')
 OR has_function_privilege('service_role','private.fn_lf_pg01_oidc_record_core_v1(text,text,jsonb)','EXECUTE')
 OR has_table_privilege('service_role','private.lf_pg01_oidc_jwks_v1','INSERT')
 OR has_table_privilege('service_role','private.lf_pg01_oidc_jwks_v1','UPDATE')
 OR has_table_privilege('service_role','private.lf_pg01_oidc_jwks_v1','SELECT') THEN
   RAISE EXCEPTION 'PG01_OIDC_PERMISSIONS_INVALID'; END IF;
 IF EXISTS (SELECT 1 FROM pg_auth_members m JOIN pg_roles g ON g.oid=m.roleid
             WHERE g.rolname='lf_pg01_oidc_recorder' AND (m.set_option OR m.inherit_option)) THEN
   RAISE EXCEPTION 'PG01_OIDC_RECORDER_MEMBERSHIP_NOT_ADMIN_ONLY'; END IF;
 IF (SELECT r.rolname FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
      WHERE p.oid='private.fn_lf_pg01_oidc_record_core_v1(text,text,jsonb)'::regprocedure) <> 'lf_pg01_oidc_recorder' THEN
   RAISE EXCEPTION 'PG01_OIDC_CORE_OWNER_INVALID'; END IF;
END $post$;

COMMIT;
