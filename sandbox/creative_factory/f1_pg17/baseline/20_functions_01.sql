CREATE OR REPLACE FUNCTION saly.creative_assert_dual_qa_l3c(p_acceptance jsonb, p_receipt jsonb, p_snapshot jsonb, p_output jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_sem jsonb:=p_acceptance->'semantic_qa';
 v_visual jsonb:=p_snapshot->'visual_contract';
 v_contract_sha text;
 v_original_sha text;
 v_semantic_sha text;
 v_artifact_sha text;
 v_group text;
 v_expected jsonb;
 v_actual jsonb;
 v_n integer;
BEGIN
 IF jsonb_typeof(p_acceptance) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_receipt) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_snapshot) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_output) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_INPUT_SHAPE'; END IF;
 IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_sem->'original_messages') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_sem->'original_messages')=0
    OR jsonb_typeof(v_sem->'interpretation') IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_sem->'checks') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_sem->'checks')<>5
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_INPUT_INVALID'; END IF;
 v_original_sha:=encode(extensions.digest(convert_to((v_sem->'original_messages')::text,'UTF8'),'sha256'),'hex');
 v_semantic_sha:=encode(extensions.digest(convert_to(v_sem::text,'UTF8'),'sha256'),'hex');
 IF v_sem->>'original_request_sha256' IS DISTINCT FROM v_original_sha
    OR jsonb_typeof(v_visual) IS DISTINCT FROM 'object'
    OR v_visual->'acceptance_criteria' IS DISTINCT FROM p_acceptance
    OR jsonb_typeof(v_visual->'qa_checks') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_visual->'qa_checks')<>5
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CONTRACT_MISMATCH'; END IF;
 v_contract_sha:=encode(extensions.digest(convert_to(v_visual::text,'UTF8'),'sha256'),'hex');
 v_artifact_sha:=p_output->>'sha256';

 IF jsonb_typeof(p_snapshot->'visual_contract_sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_receipt->'contract_sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_output->'sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_receipt->'artifact_sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_receipt->'artifact_ref') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_output->'artifact_ref') IS DISTINCT FROM 'string'
    OR p_snapshot->>'visual_contract_sha256' IS DISTINCT FROM v_contract_sha
    OR p_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
    OR v_artifact_sha IS NULL OR v_artifact_sha !~ '^[0-9a-f]{64}$'
    OR p_receipt->>'artifact_sha256' IS DISTINCT FROM v_artifact_sha
    OR p_receipt->>'artifact_ref' IS DISTINCT FROM p_output->>'artifact_ref'
    OR nullif(btrim(p_output->>'artifact_ref'),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_ARTIFACT_OR_HASH_MISMATCH'; END IF;

 IF p_receipt#>>'{semantic_qa,original_request_sha256}' IS DISTINCT FROM v_original_sha
    OR p_receipt#>>'{semantic_qa,semantic_contract_sha256}' IS DISTINCT FROM v_semantic_sha
    OR jsonb_typeof(p_receipt#>'{semantic_qa,independent_interpretation}') IS DISTINCT FROM 'string'
    OR nullif(btrim(p_receipt#>>'{semantic_qa,independent_interpretation}'),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_REVIEW_MISSING'; END IF;

 FOREACH v_group IN ARRAY ARRAY['semantic_qa','technical_qa'] LOOP
   IF p_receipt#>>ARRAY[v_group,'verdict'] IS DISTINCT FROM 'PASS'
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_NOT_PASS'; END IF;
   v_expected:=CASE v_group WHEN 'semantic_qa' THEN v_sem->'checks' ELSE v_visual->'qa_checks' END;
   v_actual:=p_receipt#>ARRAY[v_group,'checks'];
   IF jsonb_typeof(v_actual) IS DISTINCT FROM 'array'
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECKS_MISSING'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_expected) AS x(c)
     WHERE jsonb_typeof(c) IS DISTINCT FROM 'object'
       OR jsonb_typeof(c->'code') IS DISTINCT FROM 'string'
       OR nullif(btrim(c->>'code'),'') IS NULL)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_INVALID_EXPECTED_CODES'; END IF;
   IF (SELECT count(DISTINCT check_item->>'code') FROM jsonb_array_elements(v_expected) AS t(check_item))<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_INVALID_EXPECTED_CODES'; END IF;
   IF jsonb_array_length(v_actual)<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECK_COUNT'; END IF;
   SELECT count(*) INTO v_n
    FROM jsonb_array_elements(v_expected) AS exp(check_item)
    WHERE (SELECT count(*) FROM jsonb_array_elements(v_actual) AS act(check_item)
      WHERE act.check_item->>'code'=exp.check_item->>'code'
       AND act.check_item->>'verdict'='PASS'
       AND jsonb_typeof(act.check_item->'code')='string'
       AND jsonb_typeof(act.check_item->'evidence')='string'
       AND nullif(btrim(act.check_item->>'evidence'),'') IS NOT NULL)=1;
   IF v_n<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECK_FAILED_OR_MISSING'; END IF;
 END LOOP;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_assert_native_transport_v1(p_item bigint, p_prompt text, p_attachments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE pkt jsonb; h jsonb; actual_sha text; expected_sha text;
BEGIN
 pkt:=saly.creative_item_work_packet_l2c(p_item);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_REVIEW_ONLY'
 OR pkt->'native_execution_authorized' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'NATIVE_TRANSPORT_NOT_IN_REVIEW'; END IF;
 h:=pkt#>'{review_contract,contract,handoff}';
 expected_sha:=h->>'prompt_sha256';
 actual_sha:=encode(extensions.digest(convert_to(p_prompt,'UTF8'),'sha256'),'hex');
 IF p_prompt IS NULL OR actual_sha IS DISTINCT FROM expected_sha
 OR convert_to(p_prompt,'UTF8') IS DISTINCT FROM convert_to(h->>'native_prompt','UTF8')
 THEN RAISE EXCEPTION 'NATIVE_TRANSPORT_PROMPT_DRIFT'; END IF;
 IF p_attachments IS DISTINCT FROM h->'attachments'
 THEN RAISE EXCEPTION 'NATIVE_TRANSPORT_ATTACHMENT_DRIFT'; END IF;
 RETURN jsonb_build_object('status','PAYLOAD_MATCH_REVIEW_ONLY','item_id',p_item,
   'prompt_sha256',actual_sha,'contract_sha256',pkt#>>'{review_contract,contract_sha256}',
   'attachments',p_attachments,'render_authorized',false,'transmitted',false,
   'provider_receipt',NULL);
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_assert_native_transport_v2(p_envelope jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE p jsonb; v_id bigint; receipt jsonb;
BEGIN
 IF jsonb_typeof(p_envelope) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_SHAPE'; END IF;
 IF NOT (p_envelope ?& ARRAY['schema_version','item_id','contract_sha256','prompt_sha256','payload'])
 OR (SELECT count(*) FROM jsonb_object_keys(p_envelope))<>5
 OR jsonb_typeof(p_envelope->'schema_version') IS DISTINCT FROM 'string'
 OR p_envelope->>'schema_version' IS DISTINCT FROM 'SALY_NATIVE_TRANSPORT_V2'
 OR jsonb_typeof(p_envelope->'item_id') IS DISTINCT FROM 'number'
 OR coalesce(p_envelope->>'item_id','') !~ '^[1-9][0-9]*$'
 OR jsonb_typeof(p_envelope->'contract_sha256') IS DISTINCT FROM 'string'
 OR coalesce(p_envelope->>'contract_sha256','') !~ '^[0-9a-f]{64}$'
 OR jsonb_typeof(p_envelope->'prompt_sha256') IS DISTINCT FROM 'string'
 OR coalesce(p_envelope->>'prompt_sha256','') !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_FIELDS'; END IF;
 IF (p_envelope->>'item_id')::numeric > 9223372036854775807::numeric THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_FIELDS'; END IF;
 p:=p_envelope->'payload';
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'NATIVE_PAYLOAD_SHAPE'; END IF;
 IF NOT (p ?& ARRAY['prompt','attachments']) OR (SELECT count(*) FROM jsonb_object_keys(p))<>2
 OR jsonb_typeof(p->'prompt') IS DISTINCT FROM 'string'
 OR nullif(btrim(p->>'prompt'),'') IS NULL
 OR jsonb_typeof(p->'attachments') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'NATIVE_PAYLOAD_FIELDS'; END IF;
 v_id:=(p_envelope->>'item_id')::bigint;
 receipt:=saly.creative_assert_native_transport_v1(v_id,p->>'prompt',p->'attachments');
 IF receipt->>'contract_sha256' IS DISTINCT FROM p_envelope->>'contract_sha256'
 OR receipt->>'prompt_sha256' IS DISTINCT FROM p_envelope->>'prompt_sha256'
 THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_BINDING_DRIFT'; END IF;
 RETURN receipt||jsonb_build_object('schema_version','SALY_NATIVE_TRANSPORT_VALIDATION_V2',
   'payload_sha256',encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex'),
   'provider_receipt',NULL,'transmitted',false);
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_assert_run_snapshot_v1(p_item bigint, p_snapshot jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE pkt jsonb; visual jsonb; expected jsonb;
BEGIN
 pkt:=saly.creative_item_work_packet_l2c(p_item);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF'
 OR jsonb_typeof(pkt->'input_snapshot') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_SNAPSHOT_NOT_READY'; END IF;
 visual:=saly.creative_item_visual_contract_l3b(p_item);
 expected:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',visual->'contract','visual_contract_sha256',visual->>'contract_sha256');
 IF p_snapshot IS DISTINCT FROM expected THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_NOT_CANONICAL'; END IF;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_capture_append_v1(p_item_id bigint, p_request_id text, p_wire_base64 text, p_readback_base64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
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
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_capture_immutable_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
 RAISE EXCEPTION 'CREATIVE_NATIVE_CAPTURE_IMMUTABLE';
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_chat_begin_pending_v1(p_order_code text, p_allowed_item_codes text[], p_worker_ref text, p_idempotency_key text, p_input_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
 v_order record;
 v_item record;
 v_claim jsonb;
 v_run jsonb;
 v_attempt integer;
 v_now timestamptz;
BEGIN
 IF p_order_code IS NULL OR p_order_code !~ '^[A-Z][A-Z0-9_-]{2,63}$'
 OR p_allowed_item_codes IS NULL OR cardinality(p_allowed_item_codes) NOT BETWEEN 1 AND 50
 OR EXISTS (SELECT 1 FROM unnest(p_allowed_item_codes) c
            WHERE c IS NULL OR c !~ '^[A-Z][A-Z0-9_-]{1,63}$')
 OR (SELECT count(DISTINCT c) FROM unnest(p_allowed_item_codes) c)
    IS DISTINCT FROM cardinality(p_allowed_item_codes)
 OR p_worker_ref IS NULL OR length(btrim(p_worker_ref)) NOT BETWEEN 1 AND 128
 OR p_idempotency_key IS NULL OR length(btrim(p_idempotency_key)) NOT BETWEEN 1 AND 128
 OR jsonb_typeof(p_input_snapshot) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_BAD_INPUT'; END IF;

 -- Same global lock as V02. SQL attempts, claims and policy must be checked
 -- by the V02 RPCs, not duplicated here in a second writer.
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT id,code,status,scope_json,request_kind INTO v_order FROM saly.creative_orders
 WHERE code=p_order_code FOR UPDATE;
 IF NOT FOUND OR v_order.status NOT IN ('PLANIFICADO','EN_PROCESO')
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_ORDER_NOT_ACTIVE'; END IF;
 IF v_order.request_kind='APP_SCREEN_SINGLE' THEN
   IF cardinality(p_allowed_item_codes)<>1
   THEN RAISE EXCEPTION 'CREATIVE_CHAT_SINGLE_ORDER_EXACTLY_ONE_SCREEN'; END IF;
   IF NOT saly.creative_order_sequence_dependency_met_v1(v_order.id)
   THEN RAISE EXCEPTION 'CREATIVE_CHAT_ORDER_PREDECESSOR_NOT_TERMINADO'; END IF;
 END IF;

  IF v_order.scope_json->>'queue_mode' IS DISTINCT FROM 'SERIAL_V1'
 OR v_order.scope_json->>'rendering_authority' IS DISTINCT FROM 'true'
 OR coalesce(v_order.scope_json->>'review_only','false') IS DISTINCT FROM 'false'
 OR coalesce(v_order.scope_json->>'render_authorized','true') IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_RENDER_NOT_AUTHORIZED'; END IF;

 SELECT i.id,i.code,i.order_id INTO v_item
 FROM saly.creative_order_items i
 WHERE i.order_id=v_order.id AND i.code=ANY(p_allowed_item_codes)
 AND i.status='PENDIENTE'
 AND (v_order.request_kind<>'APP_SCREEN_SINGLE'
      OR (i.kind='SCREEN' AND i.ordinal=1))
 AND NOT EXISTS (
   SELECT 1 FROM saly.creative_item_dependencies d
   JOIN saly.creative_order_items prior ON prior.id=d.depends_on_item_id
   WHERE d.order_id=i.order_id AND d.item_id=i.id
     AND prior.status<>'APROBADO'
 )
 AND NOT EXISTS (
   SELECT 1 FROM saly.creative_runs r
   WHERE r.item_id=i.id AND r.state IN ('EN_COLA','EJECUTANDO','EXITOSO')
 )
 ORDER BY i.ordinal,i.id LIMIT 1 FOR UPDATE OF i;
 IF NOT FOUND
 THEN RETURN jsonb_build_object('status','NO_PENDING_IN_SCOPE',
  'order_code',v_order.code,'selected_count',0); END IF;

 -- No other eligible LISTO item is allowed to hijack the global v02 claim.
 -- Explicitly reject and roll back instead of claiming an unrelated order.
 IF EXISTS (
  SELECT 1 FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE i.status='LISTO'
   AND o.status IN ('PLANIFICADO','EN_PROCESO')
   AND o.scope_json->>'queue_mode'='SERIAL_V1'
   AND o.scope_json->>'rendering_authority'='true'
   AND coalesce(o.scope_json->>'review_only','false')='false'
   AND coalesce(o.scope_json->>'render_authorized','true')='true'
 ) THEN RAISE EXCEPTION 'CREATIVE_CHAT_OTHER_READY_ITEM_MUST_BE_RECONCILED'; END IF;

 UPDATE saly.creative_order_items SET status='LISTO' WHERE id=v_item.id
 AND status='PENDIENTE';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_PENDING_LOST'; END IF;

 -- Reuse V02's lease, max queue, exclusion and fencing gate.
 v_claim:=saly.creative_queue_claim_next_v1(p_worker_ref,NULL);
 IF v_claim->>'status' IS DISTINCT FROM 'CLAIMED'
 OR (v_claim->>'order_id')::bigint IS DISTINCT FROM v_order.id
 OR (v_claim->>'item_id')::bigint IS DISTINCT FROM v_item.id
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_CLAIM_SCOPE_OR_POLICY_BLOCKED'; END IF;

 SELECT coalesce(max(attempt_number),0)+1 INTO v_attempt
 FROM saly.creative_runs WHERE item_id=v_item.id;
 v_run:=saly.creative_queue_admit_run_v1(
  (v_claim->>'claim_token')::uuid,v_attempt,p_idempotency_key,p_input_snapshot);
 IF (v_run->>'run_id') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_RUN_NOT_ADMITTED'; END IF;
 PERFORM saly.creative_queue_advance_run_v1(
  (v_claim->>'claim_token')::uuid,(v_run->>'run_id')::bigint,'EJECUTANDO',
  '{}'::jsonb,NULL);
 UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.id
  AND status='LISTO';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_NOT_PROCESSING'; END IF;
 UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_order.id
 AND status IN ('PLANIFICADO','EN_PROCESO');
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_ORDER_NOT_PROCESSING'; END IF;

 RETURN jsonb_build_object(
  'schema_version','SALY_CREATIVE_CHAT_BEGIN_V1',
  'status','PROCESSING_STARTED','order_id',v_order.id,'order_code',v_order.code,
  'item_id',v_item.id,'item_code',v_item.code,
  'run_id',(v_run->>'run_id')::bigint,
  'item_state','PRODUCIENDO','order_state','EN_PROCESO',
  'native_transmitted',false,'qa_completed',false,
  'db_done_allowed',false);
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_chat_finalize_after_verified_delivery_v1(p_token uuid, p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE c record; r record; i record; v_result jsonb;
BEGIN
 IF p_token IS NULL OR p_run_id IS NULL OR p_run_id<1
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_FINISH_BAD_INPUT'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO c FROM saly.creative_queue_claims_v1
 WHERE claim_token=p_token FOR UPDATE;
 SELECT * INTO r FROM saly.creative_runs WHERE id=p_run_id FOR UPDATE;
 SELECT * INTO i FROM saly.creative_order_items
 WHERE id=c.item_id AND order_id=c.order_id FOR UPDATE;
 IF c.id IS NULL OR r.id IS NULL OR i.id IS NULL
 OR c.state<>'ACTIVE' OR r.queue_claim_id IS DISTINCT FROM c.id
 OR r.state<>'EXITOSO' OR i.status<>'TERMINADO'
 OR i.qa_receipt->>'verdict' IS DISTINCT FROM 'PASS'
 OR nullif(btrim(i.qa_receipt->>'comment'),'') IS NULL
 OR i.qa_receipt->>'artifact_sha256' IS DISTINCT FROM r.output_evidence->>'sha256'
 OR NOT EXISTS(SELECT 1 FROM saly.creative_run_detection_v1 d
       WHERE d.run_id=r.id AND d.order_id=c.order_id AND d.item_id=i.id
         AND d.claim_id=c.id AND d.artifact_sha256=r.output_evidence->>'sha256'
         AND d.artifact_ref=r.output_evidence->>'artifact_ref')
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_FINISH_QA_NOT_SAVED'; END IF;
 -- V06 verifies actual evidence. A textual "generated" or a worker receipt
 -- does not suffice. On absence the transaction fails and remains pending.
 v_result:=saly.creative_queue_release_v1(p_token,'DONE');
 IF v_result->>'status' IS DISTINCT FROM 'RELEASED'
 OR v_result->>'result' IS DISTINCT FROM 'DONE'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_FINISH_NOT_VERIFIED'; END IF;
 -- The user-approved single-screen contract requires a REAL order
 -- TERMINADO, never just a conversational alias for COMPLETADO.
 IF EXISTS (
  SELECT 1 FROM saly.creative_orders o WHERE o.id=c.order_id
    AND o.request_kind='APP_SCREEN_SINGLE'
    AND (o.status<>'TERMINADO' OR v_result->'order_closed'<>'true'::jsonb)
 ) THEN RAISE EXCEPTION 'CREATIVE_CHAT_SINGLE_ORDER_NOT_TERMINADO'; END IF;
  RETURN jsonb_build_object('status','TERMINADO','run_id',p_run_id,
    'item_id',i.id,'db_item_state','TERMINADO','db_claim_state','DONE',
    'qa_comment',i.qa_receipt->>'comment',
    'order_closed',v_result->'order_closed');
END $function$
;
