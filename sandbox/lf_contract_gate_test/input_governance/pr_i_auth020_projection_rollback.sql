-- PR-I isolated PostgreSQL 17: this is a CONFIGURATION PROJECTION TEST ONLY.
-- NOT V2 finalization, NOT real recovery runtime and NOT a Train impact receipt.
\set ON_ERROR_STOP on
CREATE SCHEMA lf_ops;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE lf_ops.reglas (
 id integer PRIMARY KEY,codigo text UNIQUE NOT NULL,categoria text NOT NULL,
 titulo text NOT NULL,descripcion text NOT NULL,razon text,valor_config jsonb,
 es_transversal boolean NOT NULL,estado text NOT NULL,origen text,
 created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,
 pendiente_decision boolean NOT NULL,pendiente_detalle text,created_by text
);
CREATE TABLE public.lf_global_config (
 scope text NOT NULL,config_key text NOT NULL,config_value text NOT NULL,
 value_type text NOT NULL,value_status text NOT NULL,
 valid_from timestamptz NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(scope,config_key,valid_from)
);
CREATE TABLE lf_ops.politicas_seguridad (
 security_policy_id integer PRIMARY KEY,
 policy_code text NOT NULL,status text NOT NULL,
 description text NOT NULL,policy_config jsonb NOT NULL,
 parameter_provenance jsonb NOT NULL
);
CREATE TABLE lf_ops.perfiles_permisos (
 profile_id integer NOT NULL,permission_id integer NOT NULL,
 access_effect text NOT NULL,status text NOT NULL,
 PRIMARY KEY(profile_id,permission_id)
);

INSERT INTO lf_ops.reglas
SELECT * FROM jsonb_populate_record(NULL::lf_ops.reglas,@@AUTH020_BASELINE_ROW@@);
INSERT INTO lf_ops.politicas_seguridad
VALUES(20,'SEC-B2B-MFA-RECOVERY','CANDIDATO',
       @@POLICY_DESCRIPTION@@,
       @@POLICY_CONFIG@@,
       @@POLICY_PROVENANCE@@);
INSERT INTO public.lf_global_config
 (scope,config_key,config_value,value_type,value_status,valid_from)
VALUES('AUTH','TEMP_KEY_TTL_HOURS','24','INTEGER','REAL',
       TIMESTAMPTZ '2026-11-18 07:39:14.76485+00');
INSERT INTO lf_ops.perfiles_permisos VALUES(1,38,'ALLOW','CANDIDATO');

CREATE OR REPLACE FUNCTION public.lf_asset_snapshot_sha_v1(
 p_asset_type text,p_code text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','extensions'
AS $function$
DECLARE v jsonb;
BEGIN
 IF p_asset_type='REGLA' THEN
  SELECT to_jsonb(r)-'created_at'-'updated_at' INTO v
  FROM lf_ops.reglas r WHERE r.codigo=p_code;
 ELSE RETURN NULL; END IF;
 IF v IS NULL THEN RETURN NULL; END IF;
 RETURN encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex');
END
$function$;

DO $pre$
DECLARE v_src text;v_md5 text;v_status text;
BEGIN
 SELECT public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020'),
        md5((to_jsonb(r)-'updated_at')::text),estado
 INTO v_src,v_md5,v_status
 FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-020';
 IF v_src<>'8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8'
    OR v_md5<>'7588d5a7de4d94a864fca9e63cd10ebe'
    OR v_status<>'VIGENTE'
 THEN RAISE EXCEPTION 'PR_I_BASELINE_SHA_MD5_DRIFT src=% md5=%',v_src,v_md5; END IF;
 IF (SELECT count(*) FROM lf_ops.perfiles_permisos
   WHERE permission_id=38 AND status='VIGENTE' AND access_effect='ALLOW')<>0
 THEN RAISE EXCEPTION 'PR_I_FIXTURE_PERMISSION_UNEXPECTEDLY_EFFECTIVE'; END IF;
 IF (SELECT count(*) FROM lf_ops.politicas_seguridad
   WHERE security_policy_id=20 AND status='CANDIDATO')<>1
 THEN RAISE EXCEPTION 'PR_I_POLICY20_ORIGINAL_STATUS_DRIFT'; END IF;
 RAISE NOTICE 'PR_I_BASELINE_PASS authentic_rule_source_sha_and_md5_match=true effective_permission38=0 policy20=CANDIDATO';
END $pre$;

BEGIN;
DO $trial$
DECLARE p jsonb:=@@RULE_PATCH@@; v_source text; v_candidate text; v_proposal text;
        v_cfg jsonb; v_descr text; v_old jsonb; v_bad int;
BEGIN
 SELECT valor_config INTO v_old FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-020';
 v_source:=public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020');
 v_proposal:=encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex');
 IF v_source<>'8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8'
 OR v_proposal<>'adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02'
 THEN RAISE EXCEPTION 'PR_I_SOURCE_OR_PATCH_SHA_DRIFT'; END IF;

 UPDATE lf_ops.reglas
 SET descripcion=p#>>'{changes,descripcion}',
     razon=p#>>'{changes,razon}',
     valor_config=p#>'{changes,valor_config}',
     pendiente_decision=false,pendiente_detalle=NULL,updated_at=now()
 WHERE id=439 AND codigo='B2B-RULE-AUTH-020' AND estado='VIGENTE';
 IF NOT FOUND THEN RAISE EXCEPTION 'PR_I_PROJECTION_UPDATE_NOT_ONE_ROW'; END IF;

 SELECT valor_config,descripcion INTO v_cfg,v_descr FROM lf_ops.reglas
 WHERE codigo='B2B-RULE-AUTH-020';
 IF v_cfg ?| ARRAY['hold_hours','human_approval_count_required',
                  'current_authorized_recovery_profile_ids']
    OR v_cfg->>'admin_recovery_mode' LIKE '%TWO_PERSON%'
    OR v_cfg->>'non_admin_recovery_mode' LIKE '%48H%'
    OR v_descr ILIKE '%48 horas%'
    OR v_cfg->>'recovery_hold_after_completion'<>'NONE'
    OR v_cfg->>'temporary_key_ttl_config_ref'<>'AUTH/TEMP_KEY_TTL_HOURS'
    OR v_cfg->>'temporary_key_delivery'<>'NEW_EMAIL_INDICATED_BY_USER'
    OR v_cfg->>'recovery_operator_permission_id'<>'38'
    OR v_cfg->>'dni_evidence_type'<>'PHOTO_OR_SCAN_SECURE_REFERENCE'
    OR v_cfg->>'temporary_key_login_scope'<>'PASSWORD_CHANGE_ONLY_NO_OPERATIONAL_SESSION'
    OR v_cfg->>'post_recovery_access'<>'FULL_UNDER_NORMAL_AUTH_AND_APPLICABLE_MFA'
 THEN RAISE EXCEPTION 'PR_I_AUTH020_POLICY_PROJECTION_DRIFT'; END IF;

 IF (v_cfg->>'temporary_key_one_time_use')::boolean IS NOT TRUE
    OR (v_cfg->>'temporary_key_reissue_invalidates_prior')::boolean IS NOT TRUE
    OR (v_cfg->>'temporary_key_expiry_requires_new_identity_check')::boolean IS NOT TRUE
    OR (v_cfg->>'new_password_required_before_operational_session')::boolean IS NOT TRUE
    OR (v_cfg->>'recovery_completion_atomic')::boolean IS NOT TRUE
    OR (v_cfg->>'change_email_after_new_password')::boolean IS NOT TRUE
    OR (v_cfg->>'temporary_key_may_create_authenticated_session')::boolean IS NOT FALSE
    OR (v_cfg->>'production_authorized')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'PR_I_AUTH020_REQUIRED_FLAGS_DRIFT'; END IF;

 IF (SELECT count(*) FROM public.lf_global_config
 WHERE scope='AUTH' AND config_key='TEMP_KEY_TTL_HOURS' AND config_value='24'
   AND value_type='INTEGER' AND value_status='REAL')<>1
 THEN RAISE EXCEPTION 'PR_I_TTL_GLOBAL_UNAVAILABLE'; END IF;

 v_candidate:=public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020');
 IF v_candidate<>'16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061'
   OR (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r
       WHERE codigo='B2B-RULE-AUTH-020')<>'9d558e62bd85cefe6dbe0f4147e59056'
 THEN RAISE EXCEPTION 'PR_I_CANDIDATE_SHA_OR_MD5_DRIFT actual=%',v_candidate; END IF;

 -- This confirms only data/config semantics; real login runtime is absent here.
 -- No token is sent, no DNI is verified, no email is changed, no session tested.
 RAISE NOTICE 'PR_I_CONFIG_PROJECTION_PASS before_sha=8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8 candidate_sha=16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061 ttl_ref=true rule_status=VIGENTE production_auth=false';
END $trial$;

ROLLBACK;
DO $post$
DECLARE v_sha text;
BEGIN
 v_sha:=public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020');
 IF v_sha<>'8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8'
    OR (SELECT count(*) FROM lf_ops.reglas)<>1
    OR (SELECT count(*) FROM lf_ops.politicas_seguridad WHERE status='CANDIDATO')<>1
    OR (SELECT count(*) FROM lf_ops.perfiles_permisos WHERE permission_id=38 AND status='CANDIDATO')<>1
 THEN RAISE EXCEPTION 'PR_I_ROLLBACK_PREIMAGE_NOT_RESTORED'; END IF;
 RAISE NOTICE 'PR_I_REAL_POST_ROLLBACK_PASS rule_source_restored=true policy20=CANDIDATO permission38=CANDIDATO no_v2_receipts_created=true';
END $post$;
