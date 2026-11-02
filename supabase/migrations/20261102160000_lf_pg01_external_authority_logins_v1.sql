-- LF / H1-C2 / PG-01: provision the two external authority LOGIN principals that
-- programacion.fn_assert_external_authority_session already requires.
-- Reuses (no new guard, table, verifier or authority role):
--   programacion_verifier, programacion_auditor (NOLOGIN groups),
--   programacion.fn_assert_external_authority_session,
--   private.fn_lf_pg01_subject_verification_guard_v1 / _review_attestation_guard_v1.
-- Logins are created WITHOUT a password: they cannot authenticate until the Supabase
-- administrator sets a secret out-of-band (never in Git, migration or logs).
-- Applied only through Router -> ACTUALIZACION_DB_LF -> PASE -> Merge Train.
BEGIN;

DO $pre$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN ('lf_pg01_verifier_login','lf_pg01_auditor_login')) THEN
   RAISE EXCEPTION 'PG01_EXTERNAL_LOGIN_ALREADY_EXISTS_REVIEW_MANUALLY';
 END IF;
 IF (SELECT count(*) FROM pg_roles
      WHERE rolname IN ('programacion_verifier','programacion_auditor') AND NOT rolcanlogin) <> 2 THEN
   RAISE EXCEPTION 'PG01_AUTHORITY_GROUP_ROLES_MISSING';
 END IF;
 -- catalog lookups (no schema USAGE needed by the applying principal)
 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='programacion' AND p.proname='fn_assert_external_authority_session')
 OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='private' AND c.relname IN ('lf_pg01_subject_verifications_v1','lf_pg01_review_attestations_v1')) <> 2
 OR (SELECT count(*) FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
      WHERE p.proname IN ('fn_lf_pg01_subject_verification_guard_v1','fn_lf_pg01_review_attestation_guard_v1')) <> 2 THEN
   RAISE EXCEPTION 'PG01_AUTHORITY_CONSUMERS_MISSING';
 END IF;
END $pre$;

CREATE ROLE lf_pg01_verifier_login LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 3 PASSWORD NULL;
CREATE ROLE lf_pg01_auditor_login LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 3 PASSWORD NULL;

GRANT programacion_verifier TO lf_pg01_verifier_login WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
GRANT programacion_auditor  TO lf_pg01_auditor_login  WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;

COMMENT ON ROLE lf_pg01_verifier_login IS
 'PG-01 D-A external verifier login (H1-C2). SET-only to programacion_verifier. Secret set out-of-band by the Supabase admin.';
COMMENT ON ROLE lf_pg01_auditor_login IS
 'PG-01 D-B external auditor login (H1-C2). SET-only to programacion_auditor. Secret set out-of-band by the Supabase admin.';

DO $post$
DECLARE n_exact int; n_all int; n_bad_attr int;
BEGIN
 -- exactly one membership each, SET only, no cross-authority
 SELECT count(*) FILTER (WHERE (g.rolname,l.rolname) IN (('programacion_verifier','lf_pg01_verifier_login'),
                                                         ('programacion_auditor','lf_pg01_auditor_login'))
                           AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option),
        count(*)
   INTO n_exact, n_all
   FROM pg_auth_members m JOIN pg_roles g ON g.oid=m.roleid JOIN pg_roles l ON l.oid=m.member
  WHERE l.rolname IN ('lf_pg01_verifier_login','lf_pg01_auditor_login');
 IF n_exact <> 2 OR n_all <> 2 THEN
   RAISE EXCEPTION 'PG01_EXTERNAL_MEMBERSHIP_NOT_EXACT exact=% all=%', n_exact, n_all;
 END IF;
 -- the exact attribute set fn_assert_external_authority_session demands
 SELECT count(*) INTO n_bad_attr FROM pg_roles
  WHERE rolname IN ('lf_pg01_verifier_login','lf_pg01_auditor_login')
    AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolreplication OR rolbypassrls);
 IF n_bad_attr <> 0 THEN RAISE EXCEPTION 'PG01_EXTERNAL_LOGIN_NOT_LEAST_PRIVILEGE'; END IF;
END $post$;

COMMIT;
