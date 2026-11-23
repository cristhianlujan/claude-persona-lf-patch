-- PG17 isolated fixture only. Validates serial single-screen flow without Native.
DO $tests$
DECLARE home_id bigint;next_id bigint;home_item bigint;next_item bigint;
 claim jsonb; token uuid;result jsonb;
BEGIN
 SELECT id INTO STRICT home_id FROM saly.creative_orders
 WHERE code='SALY_HOME_V015_SINGLE_20261123';
 SELECT id INTO STRICT next_id FROM saly.creative_orders
 WHERE code='SALY_ADELANTO_V015_SINGLE_20261123';
 SELECT id INTO STRICT home_item FROM saly.creative_order_items WHERE order_id=home_id;
 SELECT id INTO STRICT next_item FROM saly.creative_order_items WHERE order_id=next_id;
 IF (SELECT count(*) FROM saly.creative_order_items WHERE order_id IN (home_id,next_id))<>2
 THEN RAISE EXCEPTION 'TEST_SCREEN_COUNT_MISMATCH'; END IF;
 IF (SELECT count(*) FROM saly.creative_queue_claims_v1)<>0
 THEN RAISE EXCEPTION 'TEST_PASSIVE_QUEUE_FALSE_ACTIVATION'; END IF;
 result:=saly.creative_queue_claim_next_v1('WORKER_UNAUTHORIZED');
 IF result->>'status'<>'EMPTY'
 THEN RAISE EXCEPTION 'TEST_REVIEW_ONLY_WAS_CLAIMED'; END IF;

 -- Activate test fixtures ONLY; production orders must remain REVIEW_ONLY.
 UPDATE saly.creative_orders
 SET scope_json='{"queue_mode":"SERIAL_V1","review_only":false,
                   "render_authorized":true,"rendering_authority":true}'::jsonb
 WHERE id IN (home_id,next_id);
 UPDATE saly.creative_order_items SET status='LISTO'
 WHERE order_id IN (home_id,next_id);
 IF NOT saly.creative_order_sequence_dependency_met_v1(home_id)
 OR saly.creative_order_sequence_dependency_met_v1(next_id)
 THEN RAISE EXCEPTION 'TEST_PREREQUISITE_INVALID'; END IF;

 claim:=saly.creative_queue_claim_next_v1('WORKER_1');
 IF claim->>'status'<>'CLAIMED' OR (claim->>'order_id')::bigint<>home_id
 THEN RAISE EXCEPTION 'TEST_HOME_NOT_FIRST'; END IF;
 token:=(claim->>'claim_token')::uuid;
 result:=saly.creative_queue_claim_next_v1('WORKER_2');
 IF result->>'status'<>'BUSY'
 THEN RAISE EXCEPTION 'TEST_QUEUE_MAX_ONE_NOT_ENFORCED'; END IF;
 BEGIN
  PERFORM saly.creative_queue_record_delivery_v1(token,1,'FAKE_CHAT','FAKE_MSG');
  RAISE EXCEPTION 'TEST_FALSE_NATIVE_DELIVERY_ADMITTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_QUEUE_UNATTESTED_TEXT_RECEIPT_FORBIDDEN' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM saly.creative_queue_release_v1(token,'DONE','FAKE');
  RAISE EXCEPTION 'TEST_UNATTESTED_DONE_ADMITTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
 END;
 UPDATE saly.creative_order_items SET status='BLOQUEADO' WHERE id=home_item;
 result:=saly.creative_queue_release_v1(token,'BLOCKED','synthetic fixture');
 IF result->>'status'<>'RELEASED'
 THEN RAISE EXCEPTION 'TEST_FAILED_CLAIM_NOT_RELEASED'; END IF;
 result:=saly.creative_queue_claim_next_v1('WORKER_3');
 IF result->>'status'<>'EMPTY'
 THEN RAISE EXCEPTION 'TEST_ADELANTO_STARTED_BEFORE_HOME_TERMINADO'; END IF;

 -- Simulate the exact predecessor state solely in the PG17 fixture:
 -- real production TERMINADO requires independent QA and host evidence.
 UPDATE saly.creative_orders SET status='TERMINADO' WHERE id=home_id;
 IF NOT saly.creative_order_sequence_dependency_met_v1(next_id)
 THEN RAISE EXCEPTION 'TEST_SUCCESSOR_NOT_UNLOCKED'; END IF;
 claim:=saly.creative_queue_claim_next_v1('WORKER_4');
 IF claim->>'status'<>'CLAIMED' OR (claim->>'order_id')::bigint<>next_id
 THEN RAISE EXCEPTION 'TEST_SUCCESSOR_NOT_CLAIMED_AFTER_TERMINADO'; END IF;
 token:=(claim->>'claim_token')::uuid;
 UPDATE saly.creative_order_items SET status='BLOQUEADO' WHERE id=next_item;
 PERFORM saly.creative_queue_release_v1(token,'BLOCKED','synthetic fixture');
 IF (SELECT count(*) FROM saly.creative_runs)<>0
 OR (SELECT count(*) FROM saly.creative_queue_native_delivery_evidence_v1)<>0
 OR EXISTS(SELECT 1 FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE')
 THEN RAISE EXCEPTION 'TEST_FALSE_RUN_DELIVERY_OR_ACTIVE_CLAIM'; END IF;

 IF has_function_privilege('anon','saly.creative_queue_claim_next_v1(text,integer)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_queue_claim_next_v1(text,integer)','EXECUTE')
 OR has_function_privilege('service_role','saly.creative_queue_claim_next_v1(text,integer)','EXECUTE')
 OR has_function_privilege('supabase_read_only_user','saly.creative_queue_claim_next_v1(text,integer)','EXECUTE')
 OR has_function_privilege('service_role','saly.creative_queue_release_v1(uuid,text,text)','EXECUTE')
 OR has_table_privilege('anon','saly.creative_queue_claims_v1','INSERT')
 THEN RAISE EXCEPTION 'TEST_RUNTIME_ACL_LEAK'; END IF;
 RAISE NOTICE 'PASS_QUEUE_V14_7_POSITIVE_NEGATIVE_AND_ACL';
END $tests$;
