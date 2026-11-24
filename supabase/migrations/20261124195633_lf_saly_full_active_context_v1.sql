-- Owner-approved full active SALY design context. Existing contexts unchanged.
BEGIN;
CREATE OR REPLACE FUNCTION saly.creative_context_token_guard_l2a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'extensions'
AS $function$
DECLARE v_set record; v_version record; v_expected_role text;
BEGIN
 IF TG_OP<>'INSERT' THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_TOKEN_IMMUTABLE';
 END IF;
 SELECT * INTO v_set FROM saly.creative_context_sets WHERE id=NEW.context_set_id FOR UPDATE;
 IF NOT FOUND OR v_set.state<>'DRAFT' THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_NOT_DRAFT';
 END IF;
 SELECT e.project_id,e.code,v.approval_status,v.value_json INTO v_version
 FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE v.id=NEW.identity_version_id;
 IF NOT FOUND OR v_version.project_id<>v_set.project_id THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_WRONG_PROJECT_OR_VERSION';
 END IF;
 v_expected_role:=CASE
  WHEN v_version.code IN ('color.brand.primary','color.action.primary.bg')
       AND v_version.approval_status='APPROVED' THEN 'OFFICIAL'
  WHEN v_version.code LIKE 'candidate.saly_ds_v1.%'
       AND (v_version.approval_status='CANDIDATE' OR (v_version.approval_status='APPROVED' AND EXISTS (SELECT 1 FROM saly.v_identity_current c WHERE c.version_id=NEW.identity_version_id AND c.project_code='SALY-001'))) THEN 'EXISTING'
  WHEN v_version.code LIKE 'candidate.saly_home_v3.%'
       AND (v_version.approval_status='CANDIDATE' OR (v_version.approval_status='APPROVED' AND EXISTS (SELECT 1 FROM saly.v_identity_current c WHERE c.version_id=NEW.identity_version_id AND c.project_code='SALY-001'))) THEN 'HOME'
  ELSE NULL END;
 IF v_expected_role IS NULL OR NEW.role<>v_expected_role THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_ROLE_NOT_AUTHORIZED';
 END IF;
 NEW.value_sha256:=encode(extensions.digest(v_version.value_json::text,'sha256'),'hex');
 RETURN NEW;
END $function$;
DO $seed$
DECLARE ctx bigint; n integer; logo record;
BEGIN
 SELECT id,version_number,sha256 INTO STRICT logo FROM saly.brand_assets WHERE id=9 AND project_id=2 AND code='logo.primary.transparent' AND approval_status='APPROVED' AND valid_from<=now() AND (valid_to IS NULL OR now()<valid_to);
 INSERT INTO saly.creative_context_sets(project_id,code,version_label,mode,state,provenance)
 VALUES(2,'SALY_FULL_ACTIVE_DS_20261124','v1','EXPLORE','DRAFT',
 jsonb_build_object('source','saly.v_identity_current','logo_asset_id',logo.id,'logo_code','logo.primary.transparent','logo_version',logo.version_number,'logo_sha256',logo.sha256,'logo_filename','01_SALY_PRINCIPAL_TRANSPARENTE.png')::text)
 RETURNING id INTO ctx;
 INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
 SELECT ctx,version_id,CASE WHEN element_code IN ('color.brand.primary','color.action.primary.bg') THEN 'OFFICIAL' WHEN element_code LIKE 'candidate.saly_home_v3.%' THEN 'HOME' ELSE 'EXISTING' END,repeat('0',64)
 FROM saly.v_identity_current WHERE project_code='SALY-001';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>55 THEN RAISE EXCEPTION 'SALY_FULL_CONTEXT_TOKEN_COUNT: %',n; END IF;
 UPDATE saly.creative_context_sets SET state='SEALED' WHERE id=ctx;
END $seed$;
COMMIT;
