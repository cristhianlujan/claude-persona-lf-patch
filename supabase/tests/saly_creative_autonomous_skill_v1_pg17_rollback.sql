\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA saly;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE saly.proyecto(id bigint,codigo text);
CREATE TABLE saly.creative_context_sets(id bigint,state text);
CREATE TABLE saly.creative_orders(id bigint,project_id bigint,code text,scope_json jsonb,status text,context_set_id bigint);
CREATE TABLE saly.creative_order_items(id bigint,order_id bigint,code text);
CREATE TABLE saly.creative_context_tokens(context_set_id bigint,identity_version_id bigint,role text,value_sha256 text);
CREATE TABLE saly.identity_versions(id bigint,element_id bigint,value_json jsonb);
CREATE TABLE saly.identity_elements(id bigint,code text);
CREATE TABLE saly.brand_assets(id bigint,project_id bigint,code text,version_number int,sha256 text,file_provider text,external_file_id text,metadata jsonb,approval_status text);
\i /tmp/saly_autonomous_skill_body.sql
INSERT INTO saly.proyecto VALUES(2,'SALY-001');
INSERT INTO saly.creative_context_sets VALUES(5,'SEALED'),(6,'DRAFT');
INSERT INTO saly.creative_orders VALUES(1,2,'TEST','{"literal_request":"test","compiled_prompt":"compiled"}','PLANIFICADO',5);
INSERT INTO saly.creative_order_items VALUES(1,1,'SCREEN');
INSERT INTO saly.identity_elements VALUES(1,'color.brand.primary');
INSERT INTO saly.identity_versions VALUES(1,1,'{"value":"#00C853"}');
INSERT INTO saly.creative_context_tokens VALUES(5,1,'OFFICIAL',repeat('a',64));
INSERT INTO saly.brand_assets VALUES(9,2,'logo.primary.transparent',1,repeat('b',64),'GOOGLE_DRIVE','fixture','{"filename":"01_SALY_PRINCIPAL_TRANSPARENTE.png"}','APPROVED');
DO $$ DECLARE req jsonb:='{"schema_version":"CREATIVE_SKILL_PREPARE_REQUEST_V1","mode":"AUTONOMOUS","business_code":"SALY","project_code":"SALY-001","order_code":"TEST","item_code":"SCREEN","literal_request":"test"}'; res jsonb; BEGIN
 res:=saly.creative_skill_prepare_v1(req);
 IF res->>'status'<>'AUTONOMOUS_PREPARED' OR res->'image_generation_allowed' IS DISTINCT FROM 'true'::jsonb OR res#>>'{logo_ref,asset_id}'<>'9' OR jsonb_array_length(res->'tokens')<>1 OR res->>'compiled_prompt'<>'compiled' OR res->'native_transmitted' IS DISTINCT FROM 'false'::jsonb THEN RAISE EXCEPTION 'TEST_AUTONOMOUS_PREPARE_FAILED: %',res; END IF;
 UPDATE saly.creative_orders SET context_set_id=6;
 IF saly.creative_skill_prepare_v1(req)->>'blocking_code'<>'SKILL_AUTONOMOUS_TARGET_NOT_READY' THEN RAISE EXCEPTION 'TEST_DRAFT_CONTEXT_ADMITTED'; END IF;
 UPDATE saly.creative_orders SET context_set_id=5,status='TERMINADO';
 IF saly.creative_skill_prepare_v1(req)->>'blocking_code'<>'SKILL_AUTONOMOUS_TARGET_NOT_READY' THEN RAISE EXCEPTION 'TEST_TERMINAL_TARGET_ADMITTED'; END IF;
 UPDATE saly.creative_orders SET status='PLANIFICADO';
 IF saly.creative_skill_prepare_v1(req||'{"literal_request":"different"}')->>'blocking_code'<>'SKILL_NEW_INTENT_REQUIRES_INTERPRETATION' THEN RAISE EXCEPTION 'TEST_LITERAL_MISMATCH_ADMITTED'; END IF;
 IF saly.creative_skill_prepare_v1(req||'{"mode":"PLAN_ONLY"}')->>'blocking_code'<>'SKILL_PLAN_TARGET_NOT_REVIEW_ONLY' THEN RAISE EXCEPTION 'TEST_LEGACY_MODE_DRIFT'; END IF;
 RAISE NOTICE 'PASS_AUTONOMOUS_PREPARE_AND_LEGACY_COMPATIBILITY';
END $$;
ROLLBACK;
