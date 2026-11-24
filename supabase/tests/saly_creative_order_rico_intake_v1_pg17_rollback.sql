\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database()<>'saly_creative_order_ci' OR current_setting('server_version_num')::int/10000<>17 THEN RAISE EXCEPTION 'UNSAFE_TARGET_NOT_DISPOSABLE_PG17'; END IF;
END $$;
BEGIN;
INSERT INTO saly.proyecto(id) VALUES(2);
INSERT INTO saly.identity_versions(id) VALUES(7),(8),(11),(12),(14);
INSERT INTO saly.creative_context_sets(id,project_id,code,version_label,mode,state,sealed_at,provenance)
VALUES(4,2,'SALY_ADELANTO_V015_CONTEXT_20261123','v1','EXPLORE','SEALED',now(),'fixture');
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
SELECT 4,id,CASE WHEN id IN(7,8) THEN 'OFFICIAL' ELSE 'EXISTING' END,repeat('a',64) FROM saly.identity_versions;
INSERT INTO saly.creative_orders(id,project_id,context_set_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status)
VALUES(8,2,4,'OLD_ORDER_8','old8','Old 8','APP_SCREEN_SINGLE','EXPLORE','CHAT_USER','{"literal_request":"old 8"}','{}','PLANIFICADO'),
(9,2,4,'OLD_ORDER_9','old9','Old 9','APP_SCREEN_SINGLE','EXPLORE','CHAT_USER','{"literal_request":"old 9"}','{}','BORRADOR');
SELECT setval(pg_get_serial_sequence('saly.creative_orders','id'),9,true);
INSERT INTO saly.creative_order_items(order_id,code,ordinal,kind,title,status) VALUES(8,'OLD_SCREEN_8',1,'SCREEN','Old 8','PENDIENTE'),(9,'OLD_SCREEN_9',1,'SCREEN','Old 9','PENDIENTE');
CREATE TEMP TABLE before_orders AS SELECT * FROM saly.creative_orders WHERE id IN(8,9);
CREATE TEMP TABLE before_items AS SELECT * FROM saly.creative_order_items WHERE order_id IN(8,9);
\i /tmp/saly_creative_rico_candidate_body.sql
DO $checks$
DECLARE o bigint;
BEGIN
 SELECT id INTO STRICT o FROM saly.creative_orders WHERE code='SALY_ADELANTO_RICO_V1_20261124' AND status='PLANIFICADO' AND context_set_id=4 AND request_kind='APP_SCREEN_SINGLE' AND scope_json->>'literal_request'=scope_json->>'content_prompt' AND scope_json->>'content_prompt'=scope_json->>'compiled_prompt';
 IF o<=9 OR (SELECT count(*) FROM saly.creative_order_items WHERE order_id=o AND kind='SCREEN' AND ordinal=1 AND status='PENDIENTE')<>1 OR (SELECT count(*) FROM saly.creative_order_items WHERE order_id=o)<>1 THEN RAISE EXCEPTION 'RICO_ORDER_ITEM_INVALID'; END IF;
 IF EXISTS(SELECT * FROM before_orders EXCEPT SELECT * FROM saly.creative_orders WHERE id IN(8,9)) OR EXISTS(SELECT * FROM saly.creative_orders WHERE id IN(8,9) EXCEPT SELECT * FROM before_orders) OR EXISTS(SELECT * FROM before_items EXCEPT SELECT * FROM saly.creative_order_items WHERE order_id IN(8,9)) OR EXISTS(SELECT * FROM saly.creative_order_items WHERE order_id IN(8,9) EXCEPT SELECT * FROM before_items) THEN RAISE EXCEPTION 'EXISTING_ORDERS_CHANGED'; END IF;
 RAISE NOTICE 'PASS_RICO_NEW_ORDER_AND_ITEM';
 RAISE NOTICE 'PASS_ORDERS_8_9_UNCHANGED';
END $checks$;
ROLLBACK;
