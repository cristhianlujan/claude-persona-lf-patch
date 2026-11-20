-- PR-J RULE_CONTRACT_LEVEL: isolated SQL model against the exact proposed JSONB.
-- NOT the production Spring Boot/Cognito consumer. Append inside PR-I BEGIN/ROLLBACK.
-- No real DNI, password, token, email delivery, session or outbound action.
CREATE TEMP TABLE pr_j_accounts (
  account_id integer PRIMARY KEY,
  email text NOT NULL UNIQUE,
  password_ref text,
  mfa_passed boolean NOT NULL DEFAULT false
) ON COMMIT DROP;
INSERT INTO pr_j_accounts(account_id,email) VALUES
 (1,'original@example.invalid'),(2,'reserved@example.invalid');
CREATE TEMP TABLE pr_j_keys(
 key_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 account_id integer NOT NULL REFERENCES pr_j_accounts(account_id),
 issued_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL,
 revoked boolean NOT NULL DEFAULT false,
 used boolean NOT NULL DEFAULT false,
 password_change_context boolean NOT NULL DEFAULT false,
 dni_secure_ref text NOT NULL,
 pending_email text NOT NULL
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.pr_j_issue(
 p_operator integer,p_document_ref text,p_dni_verified boolean,
 p_email text,p_at timestamptz
) RETURNS bigint LANGUAGE plpgsql AS $prj_issue$
DECLARE cfg jsonb; ttl integer; k bigint;
BEGIN
 SELECT valor_config INTO cfg FROM lf_ops.reglas
 WHERE codigo='B2B-RULE-AUTH-020' AND estado='VIGENTE';
 IF cfg->>'recovery_operator_permission_id'<>'38'
 OR (cfg->>'single_authorized_support_operator')::boolean IS NOT TRUE
 THEN RAISE EXCEPTION 'DENY_RULE_OPERATOR_CONFIG'; END IF;
 IF NOT EXISTS(SELECT 1 FROM lf_ops.perfiles_permisos
               WHERE profile_id=p_operator AND permission_id=38
                 AND status='VIGENTE' AND access_effect='ALLOW')
 THEN RAISE EXCEPTION 'DENY_OPERATOR_WITHOUT_PERMISSION38'; END IF;
 IF p_dni_verified IS DISTINCT FROM true
 OR coalesce(p_document_ref,'') NOT LIKE 'secure://dni/%'
 THEN RAISE EXCEPTION 'DENY_DNI_NOT_VERIFIED'; END IF;
 IF cfg->>'temporary_key_ttl_config_ref'<>'AUTH/TEMP_KEY_TTL_HOURS'
 THEN RAISE EXCEPTION 'DENY_RULE_TTL_BINDING'; END IF;
 SELECT config_value::integer INTO ttl FROM public.lf_global_config
 WHERE scope='AUTH' AND config_key='TEMP_KEY_TTL_HOURS'
   AND value_type='INTEGER' AND value_status='REAL'
 ORDER BY valid_from DESC LIMIT 1;
 IF ttl IS NULL OR ttl<=0 THEN RAISE EXCEPTION 'DENY_INVALID_TTL'; END IF;
 IF coalesce(p_email,'') NOT LIKE '%@%.%'
 THEN RAISE EXCEPTION 'DENY_NEW_EMAIL_MISSING'; END IF;
 IF (cfg->>'temporary_key_reissue_invalidates_prior')::boolean IS NOT TRUE
 THEN RAISE EXCEPTION 'DENY_REISSUE_RULE_ABSENT'; END IF;
 UPDATE pr_j_keys SET revoked=true WHERE account_id=1 AND NOT used;
 INSERT INTO pr_j_keys(account_id,issued_at,expires_at,dni_secure_ref,pending_email)
 VALUES(1,p_at,p_at+make_interval(hours=>ttl),p_document_ref,p_email)
 RETURNING key_id INTO k;
 RETURN k;
END $prj_issue$;

CREATE FUNCTION pg_temp.pr_j_use(p_key bigint,p_now timestamptz)
RETURNS void LANGUAGE plpgsql AS $prj_use$
DECLARE cfg jsonb;
BEGIN
 SELECT valor_config INTO cfg FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-020';
 IF (cfg->>'temporary_key_one_time_use')::boolean IS NOT TRUE
 OR (cfg->>'temporary_key_may_create_authenticated_session')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'DENY_RULE_ONE_USE_OR_SESSION'; END IF;
 UPDATE pr_j_keys SET used=true,password_change_context=true
 WHERE key_id=p_key AND NOT used AND NOT revoked
   AND p_now<expires_at;
 IF NOT FOUND THEN RAISE EXCEPTION 'DENY_REUSED_EXPIRED_OR_REVOKED'; END IF;
END $prj_use$;

CREATE FUNCTION pg_temp.pr_j_finish(p_key bigint,p_password text,p_new_email text)
RETURNS void LANGUAGE plpgsql AS $prj_finish$
DECLARE k pr_j_keys%ROWTYPE; cfg jsonb;
BEGIN
 SELECT * INTO k FROM pr_j_keys WHERE key_id=p_key
 FOR UPDATE;
 IF NOT FOUND OR NOT k.used OR NOT k.password_change_context
 THEN RAISE EXCEPTION 'DENY_PASSWORD_CONTEXT_REQUIRED'; END IF;
 IF char_length(coalesce(p_password,''))<8
 THEN RAISE EXCEPTION 'DENY_NEW_PASSWORD_REQUIRED'; END IF;
 SELECT valor_config INTO cfg FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-020';
 IF (cfg->>'recovery_completion_atomic')::boolean IS NOT TRUE
 OR (cfg->>'change_email_after_new_password')::boolean IS NOT TRUE
 THEN RAISE EXCEPTION 'DENY_RULE_ATOMIC_COMPLETION'; END IF;
 IF p_new_email IS DISTINCT FROM k.pending_email
 THEN RAISE EXCEPTION 'DENY_EMAIL_SOURCE_MISMATCH'; END IF;
 -- One atomic UPDATE; no real password stored in this fixture.
 UPDATE pr_j_accounts SET
   password_ref='TEST_REF_CHANGED_ONLY',email=p_new_email
 WHERE account_id=k.account_id;
 UPDATE pr_j_keys SET password_change_context=false WHERE key_id=p_key;
END $prj_finish$;

CREATE FUNCTION pg_temp.pr_j_operational_session(p_account integer,p_mfa boolean)
RETURNS boolean LANGUAGE plpgsql AS $prj_session$
DECLARE cfg jsonb; pwd text;
BEGIN
 SELECT valor_config INTO cfg FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-020';
 SELECT password_ref INTO pwd FROM pr_j_accounts WHERE account_id=p_account;
 IF pwd IS NULL OR p_mfa IS DISTINCT FROM true
 OR (cfg->>'new_password_required_before_operational_session')::boolean IS NOT TRUE
 OR cfg->>'post_recovery_access'<>'FULL_UNDER_NORMAL_AUTH_AND_APPLICABLE_MFA'
 THEN RETURN false; END IF;
 RETURN true;
END $prj_session$;

CREATE FUNCTION pg_temp.pr_j_expect_reject(p_sql text,p_contains text)
RETURNS void LANGUAGE plpgsql AS $prj_reject$
DECLARE got text;
BEGIN
 BEGIN EXECUTE p_sql;
 EXCEPTION WHEN OTHERS THEN got=SQLERRM;
 END;
 IF got IS NULL OR position(p_contains IN got)=0
 THEN RAISE EXCEPTION 'PR_J_NEGATIVE_FAILED expected=% got=%',p_contains,coalesce(got,'NO_REJECTION'); END IF;
END $prj_reject$;

DO $prj_contract$
DECLARE c jsonb; k1 bigint;k2 bigint;k3 bigint;
 t timestamptz:=TIMESTAMPTZ '2026-11-18 12:00:00+00';
 original_email text;original_password text;events jsonb;
BEGIN
 SELECT valor_config INTO c FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-020';
 IF c ?| ARRAY['hold_hours','human_approval_count_required','current_authorized_recovery_profile_ids']
    OR c->>'recovery_hold_after_completion'<>'NONE'
    OR c->>'dni_evidence_type'<>'PHOTO_OR_SCAN_SECURE_REFERENCE'
    OR c->>'temporary_key_login_scope'<>'PASSWORD_CHANGE_ONLY_NO_OPERATIONAL_SESSION'
    OR (c->>'temporary_key_expiry_requires_new_identity_check')::boolean IS NOT TRUE
    OR (c->>'recovery_audit_no_raw_secrets_or_dni_image')::boolean IS NOT TRUE
    OR (c->>'production_authorized')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'PR_J_CONTRACT_SHAPE_REJECTED'; END IF;
 events:=c->'recovery_audit_required_events';
 IF jsonb_typeof(events)<>'array' OR jsonb_array_length(events)<9
 THEN RAISE EXCEPTION 'PR_J_AUDIT_EVENTS_INCOMPLETE'; END IF;
 IF (SELECT count(*) FROM lf_ops.perfiles_permisos WHERE permission_id=38 AND status='VIGENTE')<>0
 THEN RAISE EXCEPTION 'PR_J_PERMISSION_BASELINE_DRIFT'; END IF;
 PERFORM pg_temp.pr_j_expect_reject(
  'SELECT pg_temp.pr_j_issue(1,''secure://dni/test-only'',true,''new@example.invalid'',TIMESTAMPTZ ''2026-11-18 12:00+00'')',
  'DENY_OPERATOR_WITHOUT_PERMISSION38');
 RAISE NOTICE 'PR_J_NEG_OPERATOR_PERMISSION_PASS';
 -- Permission change is only a disposable fixture and is rolled back.
 UPDATE lf_ops.perfiles_permisos SET status='VIGENTE'
 WHERE profile_id=1 AND permission_id=38;
 PERFORM pg_temp.pr_j_expect_reject(
  'SELECT pg_temp.pr_j_issue(1,''secure://dni/test-only'',false,''new@example.invalid'',TIMESTAMPTZ ''2026-11-18 12:00+00'')',
  'DENY_DNI_NOT_VERIFIED');
 RAISE NOTICE 'PR_J_NEG_DNI_PASS';
 k1:=pg_temp.pr_j_issue(1,'secure://dni/test-only',true,'new@example.invalid',t);
 IF (SELECT expires_at-issued_at FROM pr_j_keys WHERE key_id=k1)<>interval '24 hours'
 THEN RAISE EXCEPTION 'PR_J_TTL_NOT_FROM_GLOBAL'; END IF;
 IF pg_temp.pr_j_operational_session(1,true)
 THEN RAISE EXCEPTION 'PR_J_PREMATURE_SESSION'; END IF;
 RAISE NOTICE 'PR_J_POS_ISSUE_DNI_TTL_PASS';
 RAISE NOTICE 'PR_J_NEG_PREMATURE_SESSION_PASS';
 k2:=pg_temp.pr_j_issue(1,'secure://dni/test-only',true,'new@example.invalid',t+interval '1 hour');
 PERFORM pg_temp.pr_j_expect_reject(
  format('SELECT pg_temp.pr_j_use(%s,TIMESTAMPTZ ''2026-11-18 13:01+00'')',k1),
  'DENY_REUSED_EXPIRED_OR_REVOKED');
 RAISE NOTICE 'PR_J_NEG_REISSUED_OLD_KEY_PASS';
 PERFORM pg_temp.pr_j_expect_reject(
  format('SELECT pg_temp.pr_j_use(%s,TIMESTAMPTZ ''2026-11-19 13:00+00'')',k2),
  'DENY_REUSED_EXPIRED_OR_REVOKED');
 RAISE NOTICE 'PR_J_NEG_EXPIRED_KEY_PASS';
 -- Reverify DNI before issuing a replacement after expiry.
 PERFORM pg_temp.pr_j_expect_reject(
  'SELECT pg_temp.pr_j_issue(1,''secure://dni/test-only'',false,''new@example.invalid'',TIMESTAMPTZ ''2026-11-19 13:01+00'')',
  'DENY_DNI_NOT_VERIFIED');
 RAISE NOTICE 'PR_J_NEG_EXPIRED_REVERIFY_PASS';
 k3:=pg_temp.pr_j_issue(1,'secure://dni/test-only',true,'new@example.invalid',t+interval '26 hours');
 PERFORM pg_temp.pr_j_use(k3,t+interval '26 hours 1 minute');
 PERFORM pg_temp.pr_j_expect_reject(
  format('SELECT pg_temp.pr_j_use(%s,TIMESTAMPTZ ''2026-11-19 14:02+00'')',k3),
  'DENY_REUSED_EXPIRED_OR_REVOKED');
 RAISE NOTICE 'PR_J_NEG_REUSE_PASS';
 IF pg_temp.pr_j_operational_session(1,true)
 THEN RAISE EXCEPTION 'PR_J_TEMP_KEY_GRANTED_SESSION'; END IF;
 PERFORM pg_temp.pr_j_expect_reject(
  format('SELECT pg_temp.pr_j_finish(%s,'''',''new@example.invalid'')',k3),
  'DENY_NEW_PASSWORD_REQUIRED');
 RAISE NOTICE 'PR_J_NEG_PASSWORD_REQUIRED_PASS';
 SELECT email,password_ref INTO original_email,original_password
 FROM pr_j_accounts WHERE account_id=1;
 PERFORM pg_temp.pr_j_expect_reject(
  format('SELECT pg_temp.pr_j_finish(%s,''test-password-only'',''reserved@example.invalid'')',k3),
  'DENY_EMAIL_SOURCE_MISMATCH');
 -- Force a genuine unique-key violation on one atomic UPDATE, no partial field update.
 UPDATE pr_j_keys SET pending_email='reserved@example.invalid' WHERE key_id=k3;
 PERFORM pg_temp.pr_j_expect_reject(
  format('SELECT pg_temp.pr_j_finish(%s,''test-password-only'',''reserved@example.invalid'')',k3),
  'duplicate key value violates unique constraint');
 IF EXISTS(SELECT 1 FROM pr_j_accounts WHERE account_id=1 AND
           (email IS DISTINCT FROM original_email OR password_ref IS DISTINCT FROM original_password))
 THEN RAISE EXCEPTION 'PR_J_NEG_PARTIAL_ACCOUNT_MUTATION'; END IF;
 RAISE NOTICE 'PR_J_NEG_ATOMIC_ROLLBACK_PASS';
 UPDATE pr_j_keys SET pending_email='new@example.invalid' WHERE key_id=k3;
 PERFORM pg_temp.pr_j_finish(k3,'test-password-only','new@example.invalid');
 IF NOT EXISTS(SELECT 1 FROM pr_j_accounts WHERE account_id=1
     AND email='new@example.invalid' AND password_ref='TEST_REF_CHANGED_ONLY')
 THEN RAISE EXCEPTION 'PR_J_PASSWORD_EMAIL_ATOMIC_UPDATE_MISSING'; END IF;
 IF pg_temp.pr_j_operational_session(1,false)
 THEN RAISE EXCEPTION 'PR_J_MFA_BYPASS_ALLOWED'; END IF;
 IF pg_temp.pr_j_operational_session(1,true) IS NOT TRUE
 THEN RAISE EXCEPTION 'PR_J_COMPLETED_WITH_MFA_DENIED'; END IF;
 RAISE NOTICE 'PR_J_POS_ATOMIC_COMPLETION_PASS';
 RAISE NOTICE 'PR_J_NEG_MFA_BYPASS_PASS';
 RAISE NOTICE 'PR_J_RULE_CONTRACT_LEVEL_FUNCTIONAL_NEGATIVE_PASS backend_e2e=NOT_TESTED simulator=TEST_ONLY';
END $prj_contract$;
