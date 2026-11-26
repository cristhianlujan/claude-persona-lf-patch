-- LF adapter regression: isolated PG17, no production writes.
\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA saly; CREATE SCHEMA lf_design; CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto SCHEMA extensions;
CREATE TABLE lf_design.brand_assets (asset_code text,asset_name text,asset_kind text,asset_variant text,storage_provider text,storage_bucket text,storage_object_path text,filename text,mime_type text,version text,status text,checksum_sha256 text,source_decision_id text,access_level text,is_current boolean,metadata jsonb,created_at timestamp with time zone,updated_at timestamp with time zone,brand_asset_id bigint,source_decision_number bigint);
CREATE TABLE lf_design.color_tokens (token_name text,design_system_code text,hex_value text,rgb_value text,token_group text,semantic_role text,allowed_usage text,blocked_usage text,status text,source_decision_id text,affected_components jsonb,propagation_scope jsonb,requires_qa boolean,notes text,created_at timestamp with time zone,updated_at timestamp with time zone,color_token_id bigint,source_decision_number bigint,design_system_id bigint);
CREATE TABLE lf_design.component_tokens (component_token_code text,design_system_code text,component_name text,component_state text,token_bindings jsonb,allowed_usage text,blocked_usage text,status text,source_decision_id text,notes text,created_at timestamp with time zone,updated_at timestamp with time zone,component_token_id bigint,source_decision_number bigint,design_system_id bigint);
CREATE TABLE lf_design.design_systems (design_system_code text,project_code text,name text,version text,status text,source_decision_id text,description text,created_at timestamp with time zone,updated_at timestamp with time zone,design_system_id bigint,source_decision_number bigint);
CREATE TABLE lf_design.spacing_tokens (token_name text,design_system_code text,value_px integer,token_group text,semantic_role text,allowed_usage text,status text,source_decision_id text,notes text,created_at timestamp with time zone,updated_at timestamp with time zone,spacing_token_id bigint,source_decision_number bigint,design_system_id bigint);
CREATE TABLE lf_design.theme_bindings (theme_binding_code text,design_system_code text,theme_name text,mode text,route_scope text,token_overrides jsonb,status text,source_decision_id text,notes text,created_at timestamp with time zone,updated_at timestamp with time zone,theme_binding_id bigint,source_decision_number bigint,design_system_id bigint);
CREATE TABLE lf_design.typography_tokens (token_name text,design_system_code text,font_family text,font_size_px integer,line_height_px integer,font_weight integer,letter_spacing text,semantic_role text,allowed_usage text,status text,source_decision_id text,notes text,created_at timestamp with time zone,updated_at timestamp with time zone,typography_token_id bigint,source_decision_number bigint,design_system_id bigint);
CREATE TABLE saly.creative_context_sets (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,project_id bigint,code text,version_label text,mode text,state text,sealed_at timestamp with time zone,provenance text,created_at timestamp with time zone);
CREATE TABLE saly.creative_context_tokens (context_set_id bigint,identity_version_id bigint,role text,value_sha256 text,created_at timestamp with time zone);
CREATE TABLE saly.creative_order_items (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,order_id bigint,code text,block_code text,ordinal integer,kind text,variant_of_item_id bigint,title text,required boolean,acceptance_json jsonb,context_json jsonb,qa_receipt jsonb,status text,approved_at timestamp with time zone,approved_by text,created_at timestamp with time zone,updated_at timestamp with time zone);
CREATE TABLE saly.creative_orders (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,project_id bigint,code text,request_key text,title text,request_kind text,design_mode text,requested_by text,scope_json jsonb,identity_snapshot jsonb,status text,completed_at timestamp with time zone,created_at timestamp with time zone,updated_at timestamp with time zone,context_set_id bigint);
CREATE TABLE saly.identity_elements (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,project_id bigint,code text,family text,value_type text,name text,description text,is_required boolean,is_protected boolean,status text,decision_id bigint,metadata jsonb,created_at timestamp with time zone,updated_at timestamp with time zone);
CREATE TABLE saly.identity_versions (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,element_id bigint,version_number integer,channel_code text,audience_code text,value_json jsonb,approval_status text,valid_from timestamp with time zone,valid_to timestamp with time zone,decision_id bigint,approval_reference text,change_reason text,metadata jsonb,created_at timestamp with time zone,updated_at timestamp with time zone);
CREATE TABLE saly.proyecto (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,codigo text,nombre text,significado_nombre text,fase text,estado text,objetivo text,created_at timestamp with time zone,updated_at timestamp with time zone);
INSERT INTO saly.proyecto(id,codigo) OVERRIDING SYSTEM VALUE VALUES(2,'SALY-001'),(3,'LF');
INSERT INTO lf_design.design_systems(design_system_id,design_system_code,project_code,version) VALUES(1,'LF_DS_V1','LF','v1.3');
INSERT INTO lf_design.color_tokens(design_system_id,token_name,status,hex_value) VALUES(1,'warm_surface','VIGENTE','#FDFCFA'),(1,'green_action','VIGENTE','#109044'),(1,'excluded','CANDIDATO','#000000');
INSERT INTO lf_design.brand_assets(asset_code,status,is_current) VALUES('LF_BRAND_LOGO_TEST','CANDIDATO_VISUAL',true);
CREATE VIEW saly.v_identity_current AS SELECT 'SALY-001'::text project_code, 0::bigint version_id;
CREATE FUNCTION saly.creative_context_set_guard_l2a() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NEW; END$$;
CREATE FUNCTION saly.creative_context_token_guard_l2a() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NEW; END$$;
CREATE TRIGGER lf_test_context BEFORE INSERT OR UPDATE ON saly.creative_context_sets FOR EACH ROW EXECUTE FUNCTION saly.creative_context_set_guard_l2a();
CREATE TRIGGER lf_test_token BEFORE INSERT ON saly.creative_context_tokens FOR EACH ROW EXECUTE FUNCTION saly.creative_context_token_guard_l2a();
ALTER TABLE saly.creative_context_sets ALTER COLUMN state SET DEFAULT 'DRAFT';
\i /tmp/lf_adapter_body.sql
DO $$ DECLARE cid bigint; p jsonb; BEGIN
 SELECT id INTO STRICT cid FROM saly.creative_context_sets WHERE project_id=3 AND state='SEALED';
 IF (SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=cid)<>2 THEN RAISE EXCEPTION 'LF_TOKEN_COUNT'; END IF;
 IF EXISTS(SELECT 1 FROM saly.identity_elements WHERE project_id=2 OR code LIKE '%excluded') THEN RAISE EXCEPTION 'LF_SOURCE_LEAK'; END IF;
 IF (SELECT status FROM lf_design.brand_assets WHERE asset_code='LF_BRAND_LOGO_TEST')<>'VIGENTE' THEN RAISE EXCEPTION 'LF_LOGO_NOT_ACTIVE'; END IF;
 INSERT INTO saly.creative_orders(project_id,code,context_set_id,status,scope_json) VALUES(3,'LF_TEST',cid,'PLANIFICADO','{"literal_request":"Tu oferta"}');
 INSERT INTO saly.creative_order_items(order_id,code) SELECT id,'OFFER' FROM saly.creative_orders WHERE code='LF_TEST';
 p:=saly.creative_skill_prepare_v1('{"schema_version":"CREATIVE_SKILL_PREPARE_REQUEST_V1","mode":"AUTONOMOUS","business_code":"LF","project_code":"LF","order_code":"LF_TEST","item_code":"OFFER","literal_request":"Tu oferta"}');
 IF p->>'status'<>'LF_DISCOVERY_PREPARED' OR p->>'image_generation_allowed'<>'false' THEN RAISE EXCEPTION 'LF_PREPARE_FAILED:%',p; END IF;
END $$;
ROLLBACK;
