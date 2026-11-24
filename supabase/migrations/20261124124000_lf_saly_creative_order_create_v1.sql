-- Governed SALY single-screen intake; no grants, no existing order edits.
BEGIN;
CREATE FUNCTION saly.creative_order_create_v1(
 p_project_id bigint, p_context_set_id bigint, p_code text, p_request_key text,
 p_title text, p_requested_by text, p_scope_json jsonb,
 p_item_code text, p_item_title text, p_acceptance_json jsonb, p_context_json jsonb
) RETURNS TABLE(order_id bigint,item_id bigint)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog,saly,pg_temp
AS $f$
DECLARE v_order bigint; v_item bigint;
BEGIN
 INSERT INTO saly.creative_orders(project_id,context_set_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status)
 VALUES(p_project_id,p_context_set_id,p_code,p_request_key,p_title,'APP_SCREEN_SINGLE','EXPLORE',p_requested_by,p_scope_json,'{}'::jsonb,'PLANIFICADO')
 RETURNING id INTO v_order;
 INSERT INTO saly.creative_order_items(order_id,code,ordinal,kind,title,acceptance_json,context_json,status)
 VALUES(v_order,p_item_code,1,'SCREEN',p_item_title,p_acceptance_json,p_context_json,'PENDIENTE')
 RETURNING id INTO v_item;
 RETURN QUERY SELECT v_order,v_item;
END $f$;
REVOKE ALL ON FUNCTION saly.creative_order_create_v1(bigint,bigint,text,text,text,text,jsonb,text,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
