\set ON_ERROR_STOP on
DO $$ BEGIN
IF current_database()<>'saly_creative_order_ci' OR current_setting('server_version_num')::int/10000<>17 THEN RAISE EXCEPTION 'UNSAFE_TARGET_NOT_DISPOSABLE_PG17'; END IF;
END $$;
BEGIN;
INSERT INTO saly.proyecto(id) VALUES(2);
INSERT INTO saly.identity_versions(id) VALUES(7),(8),(11),(12),(14);
INSERT INTO saly.creative_context_sets(id,project_id,code,version_label,mode,state,sealed_at,provenance) VALUES(4,2,'TEST_SEALED','v1','EXPLORE','SEALED',now(),'fixture'),(5,2,'TEST_DRAFT','v1','EXPLORE','DRAFT',NULL,'fixture');
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256) SELECT 4,id,CASE WHEN id IN(7,8) THEN 'OFFICIAL' ELSE 'EXISTING' END,repeat('a',64) FROM saly.identity_versions;
DO $cases$
DECLARE o bigint; i bigint;
BEGIN
 SELECT order_id,item_id INTO STRICT o,i FROM saly.creative_order_create_v1(2,4,'TEST_POS','test-pos','Test','CHAT_USER','{"literal_request":"test"}','SCREEN','Test','{}','{}');
 IF NOT EXISTS(SELECT 1 FROM saly.creative_orders WHERE id=o AND status='PLANIFICADO' AND context_set_id=4 AND jsonb_array_length(identity_snapshot->'selected_versions')=5)
 OR NOT EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=i AND order_id=o AND ordinal=1 AND kind='SCREEN' AND status='PENDIENTE') THEN RAISE EXCEPTION 'POSITIVE_FAILED'; END IF;
 RAISE NOTICE 'PASS_POSITIVE';
 BEGIN
 PERFORM saly.creative_order_create_v1(2,4,'TEST_NEG1','test-neg1','Test','CHAT_USER','{"literal_request":""}','SCREEN','Test','{}','{}');
 RAISE EXCEPTION 'NEGATIVE_LITERAL_ADMITTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING' THEN RAISE; END IF; RAISE NOTICE 'PASS_NEGATIVE: %',SQLERRM; END;
 BEGIN
 PERFORM saly.creative_order_create_v1(2,5,'TEST_NEG2','test-neg2','Test','CHAT_USER','{"literal_request":"test"}','SCREEN','Test','{}','{}');
 RAISE EXCEPTION 'NEGATIVE_CONTEXT_ADMITTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_ORDER_CONTEXT_NOT_SEALED' THEN RAISE; END IF; RAISE NOTICE 'PASS_NEGATIVE: %',SQLERRM; END;
 IF (SELECT count(*) FROM saly.creative_orders)<>1 OR (SELECT count(*) FROM saly.creative_order_items)<>1 THEN RAISE EXCEPTION 'UNEXPECTED_ROWS'; END IF;
 IF has_function_privilege('anon','saly.creative_order_create_v1(bigint,bigint,text,text,text,text,jsonb,text,text,jsonb,jsonb)','EXECUTE') OR has_function_privilege('authenticated','saly.creative_order_create_v1(bigint,bigint,text,text,text,text,jsonb,text,text,jsonb,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'UNEXPECTED_CLIENT_GRANT'; END IF;
END $cases$;
ROLLBACK;
