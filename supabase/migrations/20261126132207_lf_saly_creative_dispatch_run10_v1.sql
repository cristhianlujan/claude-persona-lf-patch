BEGIN;
DO $dispatch$
DECLARE v_token uuid; v_wire jsonb; v_reserved jsonb; v_readback record;
BEGIN
 SELECT c.claim_token INTO STRICT v_token
 FROM saly.creative_queue_claims_v1 c JOIN saly.creative_runs r ON r.queue_claim_id=c.id
 WHERE r.id=10 AND r.order_id=22 AND r.item_id=26 AND r.state='EJECUTANDO'
 AND c.order_id=22 AND c.item_id=26 AND c.state='ACTIVE';
 v_wire:=saly.creative_native_render_wire_v1(v_token,10,'GPT_NATIVE');
 IF v_wire->>'status' IS DISTINCT FROM 'RENDER_WIRE_FROZEN_AUTHORIZED'
 OR v_wire->>'order_id' IS DISTINCT FROM '22' OR v_wire->>'item_id' IS DISTINCT FROM '26'
 OR encode(extensions.digest(decode(v_wire->>'wire_base64','base64'),'sha256'),'hex') IS DISTINCT FROM v_wire->>'wire_sha256'
 THEN RAISE EXCEPTION 'SALY_22_WIRE_INVALID'; END IF;
 -- Host downloaded the original reference and independently measured this SHA-256.
 -- Protected logo bytes independently verified as well; not a second L3B source.
 v_reserved:=saly.creative_queue_native_reserve_dispatch_v1(v_token,10,'GPT_NATIVE',v_wire->>'wire_sha256',
 '3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e','SALY-22-RUN10-DISPATCH-1');
 IF v_reserved->>'status' NOT IN ('RESERVED_NOT_DISPATCHED','ALREADY_RESERVED_NOT_DISPATCHED')
 THEN RAISE EXCEPTION 'SALY_22_RESERVATION_FAILED'; END IF;
 SELECT * INTO STRICT v_readback FROM saly.creative_queue_native_dispatch_reservations_v1
 WHERE run_id=10 AND order_id=22 AND item_id=26 AND request_key='SALY-22-RUN10-DISPATCH-1';
 IF v_readback.wire_sha256 IS DISTINCT FROM v_wire->>'wire_sha256'
 OR v_readback.archive_reported_sha256 IS DISTINCT FROM '3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e'
 OR v_readback.prompt_sha256 IS DISTINCT FROM v_wire->>'prompt_sha256'
 THEN RAISE EXCEPTION 'SALY_22_RESERVATION_READBACK_DRIFT'; END IF;
 RAISE NOTICE 'SALY_22_RESERVED run=10 reservation=% wire_sha=% prompt_sha=%',v_readback.id,v_readback.wire_sha256,v_readback.prompt_sha256;
END $dispatch$;
COMMIT;
