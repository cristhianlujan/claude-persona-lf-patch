-- LOTE 17: JWT/HMAC verifier isolated in sandbox rule_quality_l13.
-- TEST HMAC != Supabase Auth signature verification. NEVER DEPLOY.
SET search_path=rule_quality_l13,public;

CREATE FUNCTION l17_verify_signed_claim_v2(p_project text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE raw text; claims jsonb; unsigned jsonb;
        secret text; expected_sig text; got_sig text;
        pg_role text; v_sub text; v_bound l17_actor_subjects%ROWTYPE;
        v_actor actors%ROWTYPE; v_owner text; v_epoch bigint;
BEGIN
 -- A PostgREST connection uses authenticator at session level.
 IF session_user<>'l17_authenticator' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_NOT_AUTHENTICATOR_SESSION';
 END IF;

 -- SET LOCAL ROLE is a PostgreSQL privilege-checked operation.
 -- In SECURITY DEFINER, current_user becomes function owner; the active
 -- request role is independently visible via PostgreSQL's protected role GUC.
 pg_role:=nullif(current_setting('role',true),'none');
 IF pg_role IS NULL OR pg_role='l17_authenticator' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_EFFECTIVE_ROLE_MISSING';
 END IF;

 raw:=nullif(current_setting('request.jwt.claims',true),'');
 IF raw IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_MISSING';
 END IF;
 BEGIN
   claims:=raw::jsonb;
 EXCEPTION WHEN others THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_MALFORMED';
 END;
 IF jsonb_typeof(claims) IS DISTINCT FROM 'object'
   OR coalesce(claims->>'test_signature','') !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_SIGNATURE_INVALID';
 END IF;
 unsigned:=claims - 'test_signature';
 got_sig:=claims->>'test_signature';
 SELECT key_hex INTO secret FROM l17_hmac_private WHERE key_id='sandbox-only';
 IF secret IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_SIGNING_KEY_UNAVAILABLE';
 END IF;
 expected_sig:=encode(extensions.hmac(convert_to(unsigned::text,'UTF8'),
                                        decode(secret,'hex'),'sha256'),'hex');
 IF expected_sig IS DISTINCT FROM got_sig THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_SIGNATURE_INVALID';
 END IF;

 IF unsigned->>'iss' IS DISTINCT FROM 'L17_TEST_ISSUER_NOT_SUPABASE'
    OR unsigned->>'aud' IS DISTINCT FROM 'L17_TEST_AUDIENCE' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_ISSUER_AUDIENCE';
 END IF;
 IF coalesce(unsigned->>'iat','') !~ '^[0-9]{10,12}$'
    OR coalesce(unsigned->>'nbf','') !~ '^[0-9]{10,12}$'
    OR coalesce(unsigned->>'exp','') !~ '^[0-9]{10,12}$' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_TIMES_INVALID';
 END IF;
 v_epoch:=floor(extract(epoch from clock_timestamp()))::bigint;
 IF (unsigned->>'exp')::bigint <= v_epoch
    OR (unsigned->>'nbf')::bigint > v_epoch
    OR (unsigned->>'iat')::bigint > v_epoch+60 THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_EXPIRED_OR_NOT_YET_VALID';
 END IF;
 IF unsigned->>'project_code' IS DISTINCT FROM p_project THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_PROJECT_MISMATCH';
 END IF;
 IF unsigned->>'role' IS DISTINCT FROM pg_role THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_EFFECTIVE_ROLE_MISMATCH';
 END IF;
 v_sub:=nullif(unsigned->>'sub','');
 IF v_sub IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_SUB_MISSING';
 END IF;
 SELECT * INTO v_bound FROM l17_actor_subjects
 WHERE project_code=p_project AND subject_sub=v_sub AND app_role=pg_role;
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_SUB_UNMAPPED';
 END IF;
 SELECT * INTO v_actor FROM actors
  WHERE project_code=p_project AND actor_code=v_bound.actor_code;
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_ACTOR_UNMAPPED';
 END IF;
 IF upper(v_actor.profile_code)='SUPER_ADMIN' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_SUPER_ADMIN_APPROVAL';
 END IF;
 SELECT owner_profile_code INTO v_owner FROM projects WHERE project_code=p_project;
 IF v_owner IS NULL OR v_actor.profile_code<>v_owner OR NOT v_actor.can_approve THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_NOT_PROJECT_OWNER';
 END IF;
 RETURN jsonb_build_object('status','JWT_HMAC_SANDBOX_VERIFIED',
   'project_code',p_project,'sub',v_sub,
   'role',pg_role,'actor_code',v_actor.actor_code,
   'profile_code',v_actor.profile_code,
   'session_user',session_user,'exp',(unsigned->>'exp')::bigint);
END $fn$;

-- v2 derives authority from verified, project-scoped, signed subject + PG active role.
-- External callers do NOT supply p_actor.
CREATE FUNCTION trusted_actor_role_v2(p_project text) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp
AS $fn$
 SELECT l17_verify_signed_claim_v2(p_project)->>'actor_code'
$fn$;

-- Critical: SECURITY DEFINER changes current_user. This invoker entrypoint
-- checks the actual effective PG role BEFORE entering owner-definer functions.
CREATE FUNCTION l17_assert_request_current_user_v2(p_project text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_current text:=current_user;v_setting text:=current_setting('role',true);
        v_verified jsonb;
BEGIN
 IF session_user<>'l17_authenticator' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_NOT_AUTHENTICATOR_SESSION';
 END IF;
 IF v_setting IS NULL OR v_setting='none' OR v_current IS DISTINCT FROM v_setting THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_CURRENT_USER_ROLE_MISMATCH';
 END IF;
 v_verified:=l17_verify_signed_claim_v2(p_project);
 IF v_verified->>'role' IS DISTINCT FROM v_current THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L17_JWT_EFFECTIVE_ROLE_MISMATCH';
 END IF;
 RETURN v_verified;
END $fn$;

-- The old L14 functions call trusted_actor_role(); the overlay rebinds ONLY
-- that quality function to JWT v2. Frozen public promotion gates remain identical.
CREATE OR REPLACE FUNCTION trusted_actor_role(p_project text) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp
AS $fn$
 SELECT trusted_actor_role_v2(p_project)
$fn$;

CREATE FUNCTION quality_prepare_new_v2(p_project text,p_rule text,p_family text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_context jsonb;v_result jsonb;
BEGIN
 v_context:=l17_assert_request_current_user_v2(p_project);
 v_result:=quality_prepare_new(p_project,p_rule,p_family);
 RETURN v_result || jsonb_build_object('identity_v2',
   jsonb_build_object('status',v_context->>'status','sub',v_context->>'sub',
                      'role',v_context->>'role','project_code',p_project));
END $fn$;

CREATE FUNCTION quality_propose_correction_v2(
  p_project text,p_original text,p_successor text,
  p_new_definition text,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path=rule_quality_l13,pg_temp AS $fn$
BEGIN
 PERFORM l17_assert_request_current_user_v2(p_project);
 RETURN quality_propose_correction(p_project,p_original,p_successor,p_new_definition,p_evidence);
END $fn$;

CREATE FUNCTION quality_apply_envelope_v2(
 p_project text,p_rule text,p_promotion_id text DEFAULT NULL,p_owner_run text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_ctx jsonb;v_result jsonb;
BEGIN
 v_ctx:=l17_assert_request_current_user_v2(p_project);
 v_result:=quality_apply_envelope(p_project,p_rule,p_promotion_id,p_owner_run);
 RETURN v_result || jsonb_build_object('identity_v2',
   jsonb_build_object('status',v_ctx->>'status','sub',v_ctx->>'sub',
      'role',v_ctx->>'role','project_code',p_project));
END $fn$;
