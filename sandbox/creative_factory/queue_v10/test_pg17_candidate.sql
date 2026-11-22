-- Test V10 in one transaction: positive SIMULATED owner reservation, negatives
-- with exact codes, and ROLLBACK. Real SQL V05 is used, not mocked.
\set ON_ERROR_STOP on
BEGIN;
DO $verify$
DECLARE
 c record;r jsonb; n int:=0; current_id bigint;
BEGIN
 SELECT * INTO STRICT c FROM saly.test_v10_context LIMIT 1;
 r:=saly.creative_queue_native_reserve_dispatch_v1(
  c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
 IF r->>'schema_version' IS DISTINCT FROM 'SALY_NATIVE_DISPATCH_RESERVATION_V1'
    OR r->>'status' IS DISTINCT FROM 'RESERVED_NOT_DISPATCHED'
    OR r->'dispatch_authorized' IS DISTINCT FROM 'false'::jsonb
    OR r->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
    OR r->'db_done_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'V10_TEST_RESERVATION_MISREPORTED'; END IF;
 current_id:=(r->>'reservation_id')::bigint;
 r:=saly.creative_queue_native_reserve_dispatch_v1(
  c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
 IF r->>'status' IS DISTINCT FROM 'ALREADY_RESERVED_NOT_DISPATCHED'
    OR (r->>'reservation_id')::bigint IS DISTINCT FROM current_id
 THEN RAISE EXCEPTION 'V10_TEST_IDEMPOTENCY_MISSING'; END IF;
 IF (SELECT count(*) FROM saly.creative_queue_native_dispatch_reservations_v1)<>1
 THEN RAISE EXCEPTION 'V10_TEST_DUPLICATE_RESERVATION'; END IF;
 IF (SELECT count(*) FROM saly.creative_queue_native_delivery_evidence_v1)<>0
 OR (SELECT count(*) FROM saly.creative_runs WHERE state='EJECUTANDO')<>1
 THEN RAISE EXCEPTION 'V10_TEST_FALSE_DELIVERY_OR_RUN_TRANSITION'; END IF;
 RAISE NOTICE 'PASS V10 positive synthetic + idem: exactly one RESERVED_NOT_DISPATCHED, zero delivery';

 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'REMOTE_API',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_REMOTE_API_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_ARGUMENT_INVALID' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'GPT_NATIVE',repeat('0',64),c.archive_sha256,'V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_BAD_WIRE_HASH_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_WIRE_DRIFT' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,'not-a-hash','V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_BAD_ARCHIVE_PIN_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_HASH_PIN_INVALID' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   gen_random_uuid(),c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_FAKE_CLAIM_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_RUN_CLAIM_NOT_BOUND' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-002');
  RAISE EXCEPTION 'V10_TEST_REPLAY_MISMATCH_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'CLAUDE_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_CROSS_MODE_REPLAY_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  UPDATE saly.creative_orders SET scope_json=scope_json||'{"review_only":true}'::jsonb
  WHERE id=c.order_id;
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_REVIEW_ONLY_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_ORDER_AUTHORITY_MISSING' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  DELETE FROM saly.config_global WHERE scope='CREATIVE_FACTORY' AND config_key='LEASE_SECONDS';
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_MISSING_POLICY_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_CONFIG_MISSING:LEASE_SECONDS' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  UPDATE saly.creative_queue_claims_v1
    SET claimed_at=clock_timestamp()-interval '2 hours',
        lease_until=clock_timestamp()-interval '1 hour'
  WHERE id=c.claim_id;
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-IDEMPOTENT-001');
  RAISE EXCEPTION 'V10_TEST_EXPIRED_LEASE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_CLAIM_NOT_ACTIVE' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  UPDATE saly.creative_queue_native_dispatch_reservations_v1
     SET state='RESERVED_NOT_DISPATCHED' WHERE id=current_id;
  RAISE EXCEPTION 'V10_TEST_UPDATE_RESERVATION_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_RESERVATION_IMMUTABLE' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  DELETE FROM saly.creative_queue_native_dispatch_reservations_v1 WHERE id=current_id;
  RAISE EXCEPTION 'V10_TEST_DELETE_RESERVATION_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_RESERVATION_IMMUTABLE' THEN RAISE; END IF;
 END; n:=n+1;

 BEGIN
  PERFORM saly.creative_queue_release_v1(c.claim_token,'DONE');
  RAISE EXCEPTION 'V10_TEST_INTENT_ENABLED_DONE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
 END; n:=n+1;

 IF has_function_privilege('PUBLIC','saly.creative_queue_native_reserve_dispatch_v1(uuid,bigint,text,text,text,text)','EXECUTE') THEN
  RAISE EXCEPTION 'V10_TEST_PUBLIC_EXECUTE_GRANT'; END IF;
 IF has_table_privilege('PUBLIC','saly.creative_queue_native_dispatch_reservations_v1','INSERT') THEN
  RAISE EXCEPTION 'V10_TEST_PUBLIC_INSERT_GRANT'; END IF;
 RAISE NOTICE 'PASS V10 12 exact-code negatives, ACL, and V06 DONE remains blocked';
END $verify$;
ROLLBACK;
