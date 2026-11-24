\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database()<>'saly_creative_order_ci' OR current_setting('server_version_num')::int/10000<>17 THEN RAISE EXCEPTION 'UNSAFE_TARGET_NOT_DISPOSABLE_PG17'; END IF;
END $$;
BEGIN;
INSERT INTO saly.proyecto(id) VALUES(2);
INSERT INTO saly.identity_versions(id) SELECT generate_series(1,55);
INSERT INTO saly.creative_context_sets(id,project_id,code,version_label,mode,state,sealed_at,provenance)
VALUES(5,2,'SALY_FULL_ACTIVE_DS_20261124','v1','EXPLORE','SEALED',now(),'fixture');
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
SELECT 5,id,CASE WHEN id IN(7,8) THEN 'OFFICIAL' ELSE 'EXISTING' END,repeat('a',64) FROM saly.identity_versions;
INSERT INTO saly.creative_orders(id,project_id,context_set_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status)
SELECT id,2,5,'OLD_ORDER_'||id,'old'||id,'Old '||id,'APP_SCREEN_SINGLE','EXPLORE','CHAT_USER',jsonb_build_object('literal_request','old '||id),'{}','PLANIFICADO' FROM generate_series(8,10) id;
SELECT setval(pg_get_serial_sequence('saly.creative_orders','id'),10,true);
INSERT INTO saly.creative_order_items(order_id,code,ordinal,kind,title,status) SELECT id,'OLD_SCREEN_'||id,1,'SCREEN','Old '||id,'PENDIENTE' FROM generate_series(8,10) id;
CREATE TEMP TABLE before_orders AS SELECT * FROM saly.creative_orders;
CREATE TEMP TABLE before_items AS SELECT * FROM saly.creative_order_items;
\i /tmp/saly_11_intake_body.sql
DO $$ BEGIN
 IF (SELECT count(*) FROM saly.creative_orders WHERE id>10 AND context_set_id=5 AND status='PLANIFICADO' AND request_kind='APP_SCREEN_SINGLE')<>11 THEN RAISE EXCEPTION 'INTAKE_COUNT_OR_CONTEXT_MISMATCH'; END IF;
 IF (SELECT count(*) FROM saly.creative_order_items WHERE order_id>10 AND kind='SCREEN' AND ordinal=1 AND status='PENDIENTE')<>11 OR EXISTS(SELECT order_id FROM saly.creative_order_items WHERE order_id>10 GROUP BY order_id HAVING count(*)<>1) THEN RAISE EXCEPTION 'INTAKE_ITEM_MISMATCH'; END IF;
 IF (SELECT count(*) FROM saly.creative_orders WHERE id>10 AND scope_json->>'literal_origin'='CLAUDE_PROPOSED_PENDING_OWNER_CONFIRMATION')<>3 THEN RAISE EXCEPTION 'INTAKE_PROPOSED_ORIGIN_MISMATCH'; END IF;
 IF EXISTS(SELECT * FROM before_orders EXCEPT SELECT * FROM saly.creative_orders WHERE id IN(8,9,10)) OR EXISTS(SELECT * FROM before_items EXCEPT SELECT * FROM saly.creative_order_items WHERE order_id IN(8,9,10)) THEN RAISE EXCEPTION 'EXISTING_ORDERS_CHANGED'; END IF;
 RAISE NOTICE 'PASS_11_INTAKE_CONTEXT_5_AND_ORDERS_8_9_10_UNCHANGED';
END $$;
ROLLBACK;
