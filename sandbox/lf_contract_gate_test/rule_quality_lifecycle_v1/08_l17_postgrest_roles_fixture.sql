-- LOTE 17 PG18 SANDBOX ONLY: simulated PostgREST role/JWT transport.
-- Never apply this file to Supabase. All subjects/roles and key material are synthetic.
SET search_path=rule_quality_l13,public;

CREATE ROLE l17_authenticator LOGIN NOINHERIT PASSWORD 'only_ephemeral_pg18_l17_fixture';
-- Explicit SET ROLE privilege; NOINHERIT login cannot use application privileges before SET ROLE.
GRANT lf_owner_role,lf_super_role,lf_reader_role,lf_no_grant_role,
      saly_owner_role,saly_super_role TO l17_authenticator WITH INHERIT FALSE, SET TRUE;

CREATE TABLE l17_actor_subjects (
 project_code text NOT NULL,
 subject_sub text NOT NULL CHECK(length(subject_sub)>4),
 app_role text NOT NULL,
 actor_code text NOT NULL,
 PRIMARY KEY(project_code,subject_sub),
 UNIQUE(project_code,subject_sub,app_role),
 FOREIGN KEY(project_code,actor_code) REFERENCES actors(project_code,actor_code),
 CHECK(app_role<>'l17_authenticator')
);
INSERT INTO l17_actor_subjects(project_code,subject_sub,app_role,actor_code) VALUES
 ('lf','lf-sub-owner-001','lf_owner_role','lf_owner_role'),
 ('lf','lf-sub-super-001','lf_super_role','lf_super_role'),
 ('lf','lf-sub-reader-001','lf_reader_role','lf_reader_role'),
 ('saly','saly-sub-owner-001','saly_owner_role','saly_owner_role'),
 ('saly','saly-sub-super-001','saly_super_role','saly_super_role');

-- Key never appears in SQL or JSON artifacts. Ephemeral 32-byte test key generated in clean PG18.
-- No privileges for authenticator, app roles, PUBLIC, or other projects.
CREATE TABLE l17_hmac_private (
 key_id text PRIMARY KEY,
 key_hex text NOT NULL CHECK(key_hex ~ '^[0-9a-f]{64}$')
);
INSERT INTO l17_hmac_private VALUES('sandbox-only',
 encode(extensions.gen_random_bytes(32),'hex'));

CREATE FUNCTION l17_sandbox_sign_claim(p_unsigned jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE secret text; sig text;
BEGIN
 -- The fixture signer is only invocable by postgres; it is NOT an API signing oracle.
 IF session_user<>'postgres' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_SIGNER_NON_FIXTURE';
 END IF;
 IF jsonb_typeof(p_unsigned) IS DISTINCT FROM 'object'
    OR p_unsigned ? 'test_signature' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L17_UNSIGNED_PAYLOAD_INVALID';
 END IF;
 SELECT key_hex INTO secret FROM l17_hmac_private WHERE key_id='sandbox-only';
 sig:=encode(extensions.hmac(convert_to(p_unsigned::text,'UTF8'),
                    decode(secret,'hex'),'sha256'),'hex');
 RETURN p_unsigned || jsonb_build_object('test_signature',sig);
END $fn$;

-- Signed JSON in request.jwt.claims models PostgREST transport, not an actual compact JWT.
-- Only postgres fixtures can mint signed claims; app roles can only present them.
CREATE FUNCTION l17_sandbox_mint(p_project text,p_sub text,p_role text,
  p_expires_seconds integer DEFAULT 3600)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_payload jsonb;v_ts bigint;
BEGIN
 IF session_user<>'postgres' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_SIGNER_NON_FIXTURE';
 END IF;
 v_ts:=floor(extract(epoch from clock_timestamp()))::bigint;
 v_payload:=jsonb_build_object(
  'iss','L17_TEST_ISSUER_NOT_SUPABASE',
  'aud','L17_TEST_AUDIENCE',
  'sub',p_sub,'role',p_role,'project_code',p_project,
  'iat',v_ts,'nbf',v_ts-1,'exp',v_ts+p_expires_seconds);
 RETURN l17_sandbox_sign_claim(v_payload);
END $fn$;

-- Harden all new objects: no direct read of secret, mappings or signer.
REVOKE ALL ON l17_hmac_private,l17_actor_subjects FROM PUBLIC;
REVOKE ALL ON FUNCTION l17_sandbox_sign_claim(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION l17_sandbox_mint(text,text,text,integer) FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA rule_quality_l13 FROM l17_authenticator;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA rule_quality_l13 FROM l17_authenticator;
-- No EXECUTE signer privilege is ever granted to app roles/authenticator.
GRANT USAGE ON SCHEMA rule_quality_l13 TO l17_authenticator;
