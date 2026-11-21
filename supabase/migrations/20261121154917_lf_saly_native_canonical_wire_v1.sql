BEGIN;
DO $pre$ BEGIN
 IF md5(pg_get_functiondef('saly.creative_capture_append_v1(bigint,text,text,text)'::regprocedure)) IS DISTINCT FROM '2fbb39f919b68b3ba5852c266191bfab'
 OR to_regprocedure('saly.creative_native_canonical_wire_v1(bigint)') IS NOT NULL
 OR EXISTS(SELECT 1 FROM saly.creative_native_capture_evidence_v1)
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_PREIMAGE_DRIFT'; END IF;
END $pre$;

-- Emit exactly the bytes whose hash the deployed V2 authority already validates.
CREATE FUNCTION saly.creative_native_canonical_wire_v1(p_item_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,saly,extensions,pg_temp AS $fn$
DECLARE pkt jsonb; v jsonb; raw_bytes bytea; wire_sha text;
BEGIN
 pkt:=saly.creative_item_work_packet_l2c(p_item_id);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_REVIEW_ONLY'
 OR pkt->'native_execution_authorized' IS DISTINCT FROM 'false'::jsonb
 OR pkt->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_NOT_REVIEW'; END IF;
 v:=saly.creative_assert_native_transport_v2(pkt->'native_transport');
 IF v->>'status' IS DISTINCT FROM 'PAYLOAD_MATCH_REVIEW_ONLY'
 OR v->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR v->'transmitted' IS DISTINCT FROM 'false'::jsonb
 OR v->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_NOT_REVIEW'; END IF;
 raw_bytes:=convert_to((pkt#>'{native_transport,payload}')::text,'UTF8');
 wire_sha:=encode(extensions.digest(raw_bytes,'sha256'),'hex');
 IF wire_sha IS DISTINCT FROM v->>'payload_sha256'
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_HASH_DRIFT'; END IF;
 RETURN jsonb_build_object(
  'schema_version','SALY_CANONICAL_NATIVE_WIRE_V1',
  'status','CANONICAL_WIRE_REVIEW_ONLY',
  'item_id',p_item_id,'contract_sha256',v->>'contract_sha256',
  'prompt_sha256',v->>'prompt_sha256','payload_sha256',v->>'payload_sha256',
  'wire_base64',replace(encode(raw_bytes,'base64'),chr(10),''),
  'wire_sha256',wire_sha,'render_authorized',false,
  'native_transmitted',false,'provider_receipt',NULL,'qa_verdict','NOT_EVALUATED');
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_native_canonical_wire_v1(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION saly.creative_native_canonical_wire_v1(bigint) TO service_role;

CREATE OR REPLACE FUNCTION saly.creative_capture_append_v1(
 p_item_id bigint,p_request_id text,p_wire_base64 text,p_readback_base64 text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog,saly,extensions,pg_temp AS $fn$
DECLARE
 pkt jsonb; preflight jsonb; expected jsonb;
 wire_bytes bytea; readback_bytes bytea;
 wire_object jsonb; wire_sha text; v_id uuid;
BEGIN
 IF p_item_id IS NULL OR p_item_id<=0
 OR p_request_id IS NULL OR length(p_request_id) NOT BETWEEN 1 AND 128
 OR p_request_id IS DISTINCT FROM btrim(p_request_id)
 OR p_request_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]*$'
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_INPUT_INVALID'; END IF;
 IF p_wire_base64 IS NULL OR p_readback_base64 IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_WIRE_REQUIRED'; END IF;

 pkt:=saly.creative_item_work_packet_l2c(p_item_id);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_REVIEW_ONLY'
 OR pkt->'native_execution_authorized' IS DISTINCT FROM 'false'::jsonb
 OR pkt->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_RENDER_NOT_AUTHORIZED'; END IF;

 expected:=pkt#>'{native_transport,payload}';
 preflight:=saly.creative_assert_native_transport_v2(pkt->'native_transport');
 IF preflight->>'status' IS DISTINCT FROM 'PAYLOAD_MATCH_REVIEW_ONLY'
 OR preflight->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR preflight->'transmitted' IS DISTINCT FROM 'false'::jsonb
 OR preflight->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_PREFLIGHT_NOT_REVIEW'; END IF;

 -- Decode both independent byte streams; the server hashes real captured bytes.
 wire_bytes:=decode(p_wire_base64,'base64');
 readback_bytes:=decode(p_readback_base64,'base64');
 IF octet_length(wire_bytes)>1048576 OR octet_length(wire_bytes)=0
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_WIRE_SIZE'; END IF;
 IF wire_bytes IS DISTINCT FROM readback_bytes
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_READBACK_DRIFT'; END IF;
 -- The value from the existing sealed packet is the sole serialization authority.
 IF wire_bytes IS DISTINCT FROM convert_to(expected::text,'UTF8')
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_NONCANONICAL_WIRE'; END IF;
 wire_object:=(convert_from(wire_bytes,'UTF8'))::jsonb;
 IF jsonb_typeof(wire_object) IS DISTINCT FROM 'object'
 OR (SELECT count(*) FROM jsonb_object_keys(wire_object))<>2
 OR wire_object IS DISTINCT FROM expected
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_PAYLOAD_DRIFT'; END IF;
 wire_sha:=encode(extensions.digest(wire_bytes,'sha256'),'hex');
 IF wire_sha IS DISTINCT FROM preflight->>'payload_sha256'
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_PAYLOAD_HASH_DRIFT'; END IF;

 INSERT INTO saly.creative_native_capture_evidence_v1(
  item_id,request_id,contract_sha256,prompt_sha256,payload_sha256,
  wire_sha256,readback_sha256
 ) VALUES(
  p_item_id,p_request_id,
  preflight->>'contract_sha256',
  preflight->>'prompt_sha256',
  preflight->>'payload_sha256',
  wire_sha,wire_sha
 ) RETURNING id INTO v_id;

 RETURN jsonb_build_object(
   'id',v_id,'status','LOCAL_READBACK_MATCH_REVIEW_ONLY',
   'item_id',p_item_id,'request_id',p_request_id,
   'wire_sha256',wire_sha,'readback_sha256',wire_sha,
   'prompt_sha256',preflight->>'prompt_sha256',
   'contract_sha256',preflight->>'contract_sha256',
   'native_transmitted',false,'provider_receipt',NULL,
   'qa_verdict','NOT_EVALUATED','render_authorized',false);
END $fn$;

-- Existing ACL, inmutable ledger and review-only status remain unchanged.
DO $test$
DECLARE
 pkt jsonb; payload jsonb; wire_b64 text; changed_b64 text; receipt jsonb; canonical jsonb; duplicate_b64 text;
 request_key text:='TEST-MACRO5-'||pg_current_xact_id()::text;
 rejected integer:=0;
BEGIN
 pkt:=saly.creative_item_work_packet_l2c(9);
 payload:=pkt#>'{native_transport,payload}';
 IF pkt->>'readiness_code'<>'READY_FOR_REVIEW_ONLY' OR payload IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_TEST_SOURCE_MISSING'; END IF;
 canonical:=saly.creative_native_canonical_wire_v1(9);
 wire_b64:=canonical->>'wire_base64';
 IF canonical->>'status' IS DISTINCT FROM 'CANONICAL_WIRE_REVIEW_ONLY'
 OR canonical->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR canonical->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
 OR canonical->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 OR canonical->>'qa_verdict' IS DISTINCT FROM 'NOT_EVALUATED'
 OR position(chr(10) in wire_b64)>0
 OR decode(wire_b64,'base64') IS DISTINCT FROM convert_to(payload::text,'UTF8')
 OR canonical->>'wire_sha256' IS DISTINCT FROM canonical->>'payload_sha256'
 OR canonical->>'wire_sha256' IS DISTINCT FROM encode(extensions.digest(decode(wire_b64,'base64'),'sha256'),'hex')
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_POSITIVE_FAILED'; END IF;
 duplicate_b64:=encode(convert_to('{"prompt": "discarded", '||substring(payload::text from 2),'UTF8'),'base64');
 changed_b64:=encode(convert_to(payload::text||' ','UTF8'),'base64');

 BEGIN
  receipt:=saly.creative_capture_append_v1(9,request_key,wire_b64,wire_b64);
  IF receipt->>'status'<>'LOCAL_READBACK_MATCH_REVIEW_ONLY'
    OR receipt->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
    OR receipt->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
    OR receipt->>'qa_verdict'<>'NOT_EVALUATED'
  THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_LOCAL_RECEIPT_BAD'; END IF;

  BEGIN
   PERFORM saly.creative_capture_append_v1(9,request_key,wire_b64,wire_b64);
   RAISE EXCEPTION 'TEST_DUPLICATE_UNEXPECTED_PASS';
  EXCEPTION WHEN unique_violation THEN rejected:=rejected+1;
  END;
  BEGIN
   PERFORM saly.creative_capture_append_v1(9,request_key||'-bad',wire_b64,changed_b64);
   RAISE EXCEPTION 'TEST_READBACK_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_CAPTURE_READBACK_DRIFT' THEN RAISE; END IF;
   rejected:=rejected+1;
  END;
  BEGIN
   PERFORM saly.creative_capture_append_v1(9,request_key||'-noncanonical',changed_b64,changed_b64);
   RAISE EXCEPTION 'TEST_NONCANONICAL_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_CAPTURE_NONCANONICAL_WIRE' THEN RAISE; END IF;
   rejected:=rejected+1;
  END;
  BEGIN
   PERFORM saly.creative_capture_append_v1(9,request_key||'-duplicate-key',duplicate_b64,duplicate_b64);
   RAISE EXCEPTION 'TEST_DUPLICATE_KEY_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_CAPTURE_NONCANONICAL_WIRE' THEN RAISE; END IF;
   rejected:=rejected+1;
  END;
  BEGIN
   UPDATE saly.creative_native_capture_evidence_v1 SET status='FAKE_PROVIDER_PASS'
   WHERE item_id=9 AND request_id=request_key;
   RAISE EXCEPTION 'TEST_MUTATION_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_NATIVE_CAPTURE_IMMUTABLE' THEN RAISE; END IF;
   rejected:=rejected+1;
  END;
  IF rejected<>5 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_NEGATIVE_COUNT'; END IF;
  RAISE EXCEPTION 'CREATIVE_CAPTURE_TEST_ROLLBACK';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_CAPTURE_TEST_ROLLBACK' THEN RAISE; END IF;
 END;

 IF EXISTS(SELECT 1 FROM saly.creative_native_capture_evidence_v1)
 OR has_table_privilege('service_role','saly.creative_native_capture_evidence_v1','INSERT')
 OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
           WHERE p.oid='saly.creative_native_canonical_wire_v1(bigint)'::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE')
 OR has_function_privilege('anon','saly.creative_native_canonical_wire_v1(bigint)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_native_canonical_wire_v1(bigint)','EXECUTE')
 OR NOT has_function_privilege('service_role','saly.creative_native_canonical_wire_v1(bigint)','EXECUTE')
 OR has_function_privilege('anon','saly.creative_capture_append_v1(bigint,text,text,text)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_capture_append_v1(bigint,text,text,text)','EXECUTE')
 OR NOT has_function_privilege('service_role','saly.creative_capture_append_v1(bigint,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'CREATIVE_CAPTURE_TEST_READBACK_FAILED'; END IF;
 RAISE NOTICE 'SALY NATIVE LOCAL CAPTURE: positive, 5 negatives, canonical wire, append-only, rollback, ACL PASS. Zero provider receipt.';
END $test$;

COMMIT;
