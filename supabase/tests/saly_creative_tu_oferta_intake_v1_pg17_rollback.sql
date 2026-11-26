\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA saly;
CREATE TABLE saly.proyecto(id bigint primary key,codigo text);
CREATE TABLE saly.creative_context_sets(id bigint primary key,project_id bigint,code text,state text);
CREATE TABLE saly.creative_orders(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,project_id bigint,context_set_id bigint,code text,request_key text,title text,request_kind text,design_mode text,requested_by text,scope_json jsonb,identity_snapshot jsonb,status text);
CREATE TABLE saly.creative_order_items(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,order_id bigint,code text,ordinal int,kind text,title text,acceptance_json jsonb,context_json jsonb,status text);
CREATE OR REPLACE FUNCTION saly.creative_order_create_v1(p_project_id bigint, p_context_set_id bigint, p_code text, p_request_key text, p_title text, p_requested_by text, p_scope_json jsonb, p_item_code text, p_item_title text, p_acceptance_json jsonb, p_context_json jsonb)
 RETURNS TABLE(order_id bigint, item_id bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_order bigint; v_item bigint;
BEGIN
 INSERT INTO saly.creative_orders(project_id,context_set_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status)
 VALUES(p_project_id,p_context_set_id,p_code,p_request_key,p_title,'APP_SCREEN_SINGLE','EXPLORE',p_requested_by,p_scope_json,'{}'::jsonb,'PLANIFICADO')
 RETURNING id INTO v_order;
 INSERT INTO saly.creative_order_items(order_id,code,ordinal,kind,title,acceptance_json,context_json,status)
 VALUES(v_order,p_item_code,1,'SCREEN',p_item_title,p_acceptance_json,p_context_json,'PENDIENTE')
 RETURNING id INTO v_item;
 RETURN QUERY SELECT v_order,v_item;
END $function$
;
INSERT INTO saly.proyecto VALUES(2,'SALY-001'),(3,'LF');
INSERT INTO saly.creative_context_sets VALUES(6,3,'LF_DS_V1_TEST','SEALED');
\i /tmp/lf_offer_intake_body.sql
DO $$ BEGIN
 IF (SELECT count(*) FROM saly.creative_orders WHERE project_id=3 AND context_set_id=6 AND code='LF_TU_OFERTA_V1_20261126' AND status='PLANIFICADO' AND scope_json->>'literal_request' LIKE '%S/ [CUOTA]%')<>1 OR (SELECT count(*) FROM saly.creative_order_items WHERE code='TU_OFERTA')<>1 OR EXISTS(SELECT 1 FROM saly.creative_orders WHERE project_id=2) THEN RAISE EXCEPTION 'LF_INTAKE_REGRESSION'; END IF;
END $$;
ROLLBACK;
