BEGIN;
-- Skill-only planning adapter. Existing L2C and canonical wire are authoritative.
-- No Router, profile, runtime registration, order mutation, or provider call.
DO $pre$
BEGIN
 IF to_regprocedure('saly.creative_skill_prepare_v1(jsonb)') IS NOT NULL
 OR to_regprocedure('saly.creative_item_work_packet_l2c(bigint)') IS NULL
 OR to_regprocedure('saly.creative_native_canonical_wire_v1(bigint)') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_SKILL_PREPARE_PREIMAGE_DRIFT'; END IF;
END $pre$;

CREATE FUNCTION saly.creative_skill_prepare_v1(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,saly,extensions,pg_temp AS $fn$
DECLARE
 base jsonb:=jsonb_build_object('schema_version','CREATIVE_SKILL_PLAN_V1',
    'status','BLOCKED','native_execution_authorized',false,
    'image_generation_allowed',false,'native_transmitted',false,
    'provider_receipt',NULL,'qa_verdict','NOT_EVALUATED',
    'router_invoked',false,'profile_invoked',false,'database_written',false);
 k text; item record; n bigint; pkt jsonb; contract jsonb; qa jsonb;
 handoff jsonb; wire jsonb; msg_hash text; contract_hash text; request_hash text;
BEGIN
 IF jsonb_typeof(p_request) IS DISTINCT FROM 'object'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_REQUEST_INVALID'); END IF;
 IF NOT(p_request ?& ARRAY['schema_version','mode','business_code','project_code',
       'order_code','item_code','literal_request'])
 OR (SELECT count(*) FROM jsonb_object_keys(p_request))<>7
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_REQUEST_FIELDS_INVALID'); END IF;
 FOREACH k IN ARRAY ARRAY['schema_version','mode','business_code','project_code',
       'order_code','item_code','literal_request'] LOOP
   IF jsonb_typeof(p_request->k) IS DISTINCT FROM 'string'
   OR nullif(btrim(p_request->>k),'') IS NULL
   THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_REQUEST_FIELDS_INVALID'); END IF;
 END LOOP;
 IF p_request->>'schema_version'<>'CREATIVE_SKILL_PREPARE_REQUEST_V1'
 OR p_request->>'mode'<>'PLAN_ONLY'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_MODE_INVALID'); END IF;
 IF p_request->>'business_code'<>'SALY'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE'); END IF;
 IF p_request->>'project_code'<>'SALY-001'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PROJECT_NOT_ADMITTED'); END IF;

 -- Exact target binding, not a similarity guess across projects.
 SELECT count(*) INTO n
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE p.codigo=p_request->>'project_code' AND o.code=p_request->>'order_code'
   AND i.code=p_request->>'item_code';
 IF n<>1 THEN RETURN base||jsonb_build_object('blocking_code',
       CASE WHEN n=0 THEN 'SKILL_TARGET_NOT_FOUND' ELSE 'SKILL_TARGET_AMBIGUOUS' END); END IF;
 SELECT i.id,i.order_id,i.code AS item_code,o.code AS order_code,o.scope_json
 INTO STRICT item
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE p.codigo=p_request->>'project_code' AND o.code=p_request->>'order_code'
   AND i.code=p_request->>'item_code';

 IF item.scope_json->'review_only' IS DISTINCT FROM 'true'::jsonb
 OR item.scope_json->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_TARGET_NOT_REVIEW_ONLY'); END IF;

 -- A different literal is a new intent, not authority to reuse the old strategy.
 IF convert_to(p_request->>'literal_request','UTF8') IS DISTINCT FROM
    convert_to(item.scope_json->>'literal_request','UTF8')
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_NEW_INTENT_REQUIRES_INTERPRETATION'); END IF;

 pkt:=saly.creative_item_work_packet_l2c(item.id);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_REVIEW_ONLY'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_SOURCE_NOT_READY',
               'source_readiness',pkt->>'readiness_code','item_id',item.id); END IF;
 IF pkt->>'business_code' IS DISTINCT FROM 'SALY'
 OR pkt->>'item_id' IS DISTINCT FROM item.id::text
 OR pkt->>'order_id' IS DISTINCT FROM item.order_id::text
 OR pkt->>'item_code' IS DISTINCT FROM item.item_code
 OR pkt->>'order_code' IS DISTINCT FROM item.order_code
 OR pkt->'native_execution_authorized' IS DISTINCT FROM 'false'::jsonb
 OR pkt->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'SKILL_PLAN_CANONICAL_PACKET_DRIFT'; END IF;

 contract:=pkt#>'{review_contract,contract}';
 handoff:=contract->'handoff';
 qa:=contract#>'{acceptance_criteria,semantic_qa}';
 msg_hash:=encode(extensions.digest(convert_to((qa->'original_messages')::text,'UTF8'),'sha256'),'hex');
 contract_hash:=encode(extensions.digest(convert_to(contract::text,'UTF8'),'sha256'),'hex');
 request_hash:=encode(extensions.digest(convert_to(p_request->>'literal_request','UTF8'),'sha256'),'hex');
 IF pkt#>>'{review_contract,state}' IS DISTINCT FROM 'REVIEW_CONTRACT_PREPARED'
 OR contract_hash IS NULL
 OR contract_hash IS DISTINCT FROM pkt#>>'{review_contract,contract_sha256}'
 OR qa->>'source_type' IS DISTINCT FROM 'PERSISTED_ORDER_LITERAL_REQUEST'
 OR qa#>>'{original_messages,0,speaker}' IS DISTINCT FROM 'USER'
 OR qa#>>'{original_messages,0,text}' IS DISTINCT FROM p_request->>'literal_request'
 OR msg_hash IS NULL OR msg_hash IS DISTINCT FROM qa->>'original_request_sha256'
 OR qa#>>'{interpretation,origin}' IS DISTINCT FROM 'ASSISTANT_INTERPRETATION_SEPARATE_FROM_USER_LITERAL'
 OR qa#>'{interpretation,strategy}' IS DISTINCT FROM item.scope_json->'strategy'
 OR qa#>>'{interpretation,mode}' IS DISTINCT FROM 'REVIEW_ONLY'
 OR jsonb_typeof(qa->'checks') IS DISTINCT FROM 'array'
 OR jsonb_array_length(qa->'checks')=0
 OR jsonb_typeof(contract->'qa_checks') IS DISTINCT FROM 'array'
 OR jsonb_array_length(contract->'qa_checks')=0
 OR handoff->>'mode' IS DISTINCT FROM 'REVIEW_ONLY'
 OR handoff->'transmitted' IS DISTINCT FROM 'false'::jsonb
 OR jsonb_typeof(handoff->'trace') IS DISTINCT FROM 'array'
 OR jsonb_array_length(handoff->'trace')=0
 OR jsonb_typeof(handoff#>'{composition,asset_refs}') IS DISTINCT FROM 'object'
 OR jsonb_typeof(handoff#>'{composition,logo_ref}') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'SKILL_PLAN_INTERPRETATION_OR_CONTRACT_DRIFT'; END IF;

 -- Existing DB wire resolver owns serialization and checks exact prompt/attachments.
 wire:=saly.creative_native_canonical_wire_v1(item.id);
 IF wire->>'status' IS DISTINCT FROM 'CANONICAL_WIRE_REVIEW_ONLY'
 OR wire->>'contract_sha256' IS DISTINCT FROM contract_hash
 OR wire->>'prompt_sha256' IS DISTINCT FROM handoff->>'prompt_sha256'
 OR wire->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
 OR wire->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR wire->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'SKILL_PLAN_WIRE_DRIFT'; END IF;

 -- One canonical packet; stages only summarize it and point to exact source paths.
 RETURN base||jsonb_build_object(
   'status','PLAN_PREPARED_REVIEW_ONLY','blocking_code',NULL,
   'source','saly.creative_item_work_packet_l2c+saly.creative_native_canonical_wire_v1',
   'business_code','SALY','project_code',p_request->>'project_code',
   'order_code',item.order_code,'item_code',item.item_code,'item_id',item.id,
   'request_sha256',request_hash,'original_messages_sha256',msg_hash,
   'interpretation_status','PERSISTED_INTERPRETATION_VERIFIED',
   'discovery_status','CANONICAL_PACKET_SOURCE_REVALIDATED',
   'blueprint_status','EXACT_HANDOFF_PREPARED_NOT_SENT',
   'contract_sha256',contract_hash,
   'prompt_sha256',handoff->>'prompt_sha256',
   'template',handoff->>'template','template_version',handoff->>'template_version',
   'token_trace_count',jsonb_array_length(handoff->'trace'),
   'svg_asset_count',(SELECT count(*) FROM jsonb_object_keys(pkt->'composition_svg_assets')),
   'logo_ref',handoff#>'{composition,logo_ref}',
   'technical_check_count',jsonb_array_length(contract->'qa_checks'),
   'semantic_check_count',jsonb_array_length(qa->'checks'),
   'work_packet',pkt,'canonical_wire',wire,
   'next_action','REVIEW_PLAN_NO_RENDER');
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_skill_prepare_v1(jsonb)
 FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION saly.creative_skill_prepare_v1(jsonb) TO service_role;
COMMENT ON FUNCTION saly.creative_skill_prepare_v1(jsonb) IS
'Standalone SALY skill planning adapter; reuses sealed interpretation, L2C and canonical wire, never starts a RUN or renders.';

DO $test$
DECLARE
 req jsonb; outj jsonb; x record; negatives int:=0;
 before_counts jsonb; after_counts jsonb;
BEGIN
 SELECT jsonb_build_array(
  (SELECT count(*) FROM saly.creative_orders),
  (SELECT count(*) FROM saly.creative_order_items),
  (SELECT count(*) FROM saly.creative_runs),
  (SELECT count(*) FROM saly.creative_native_capture_evidence_v1),
  (SELECT count(*) FROM saly.creative_order_items WHERE qa_receipt<>'{}'::jsonb)
 ) INTO before_counts;
 SELECT jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1',
  'mode','PLAN_ONLY','business_code','SALY','project_code',p.codigo,
  'order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request')
 INTO STRICT req
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=9 AND i.code='HOME_B';
 outj:=saly.creative_skill_prepare_v1(req);
 IF outj->>'status' IS DISTINCT FROM 'PLAN_PREPARED_REVIEW_ONLY'
 OR outj->>'interpretation_status' IS DISTINCT FROM 'PERSISTED_INTERPRETATION_VERIFIED'
 OR outj->'work_packet' IS DISTINCT FROM saly.creative_item_work_packet_l2c(9)
 OR outj->'canonical_wire' IS DISTINCT FROM saly.creative_native_canonical_wire_v1(9)
 OR outj->>'qa_verdict' IS DISTINCT FROM 'NOT_EVALUATED'
 OR outj->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
 OR outj->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
 OR outj->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_SKILL_PLAN_POSITIVE_FAILED'; END IF;

 FOR x IN SELECT * FROM (VALUES
 ('null'::jsonb,'SKILL_PLAN_REQUEST_INVALID'),
 (req-'literal_request','SKILL_PLAN_REQUEST_FIELDS_INVALID'),
 (req||jsonb_build_object('router_context','SALY'),'SKILL_PLAN_REQUEST_FIELDS_INVALID'),
 (req||jsonb_build_object('literal_request',false),'SKILL_PLAN_REQUEST_FIELDS_INVALID'),
 (req||jsonb_build_object('mode','RENDER'),'SKILL_PLAN_MODE_INVALID'),
 (req||jsonb_build_object('business_code','LF'),'SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE'),
 (req||jsonb_build_object('business_code','FUTURO'),'SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE'),
 (req||jsonb_build_object('project_code','LF-001'),'SKILL_PROJECT_NOT_ADMITTED'),
 (req||jsonb_build_object('order_code','DOES_NOT_EXIST'),'SKILL_TARGET_NOT_FOUND'),
 (req||jsonb_build_object('item_code','DOES_NOT_EXIST'),'SKILL_TARGET_NOT_FOUND'),
 (req||jsonb_build_object('literal_request',(req->>'literal_request')||' '),'SKILL_NEW_INTENT_REQUIRES_INTERPRETATION'),
 (req||jsonb_build_object('item_code','HOME_A'),'SKILL_PLAN_SOURCE_NOT_READY'),
 (req||jsonb_build_object('order_code','SALY_HOME_BATCH_001','item_code','HOME'),'SKILL_PLAN_TARGET_NOT_REVIEW_ONLY')
 ) v(request,expected) LOOP
  outj:=saly.creative_skill_prepare_v1(x.request);
  IF outj->>'status' IS DISTINCT FROM 'BLOCKED'
  OR outj->>'blocking_code' IS DISTINCT FROM x.expected
  OR outj ? 'work_packet'
  OR outj->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
  THEN RAISE EXCEPTION 'CREATIVE_SKILL_PLAN_NEGATIVE_FAILED:%:%',x.expected,outj->>'blocking_code'; END IF;
  negatives:=negatives+1;
 END LOOP;
 SELECT jsonb_build_array(
  (SELECT count(*) FROM saly.creative_orders),
  (SELECT count(*) FROM saly.creative_order_items),
  (SELECT count(*) FROM saly.creative_runs),
  (SELECT count(*) FROM saly.creative_native_capture_evidence_v1),
  (SELECT count(*) FROM saly.creative_order_items WHERE qa_receipt<>'{}'::jsonb)
 ) INTO after_counts;
 IF negatives<>13 OR before_counts IS DISTINCT FROM after_counts
 OR has_function_privilege('anon','saly.creative_skill_prepare_v1(jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_skill_prepare_v1(jsonb)','EXECUTE')
 OR has_function_privilege('supabase_read_only_user','saly.creative_skill_prepare_v1(jsonb)','EXECUTE')
 OR NOT has_function_privilege('service_role','saly.creative_skill_prepare_v1(jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'CREATIVE_SKILL_PLAN_POSTCHECK_FAILED'; END IF;
 RAISE NOTICE 'CREATIVE SKILL PLAN: 1 canonical positive, 13 negatives, ACL, no mutations PASS';
END $test$;
COMMIT;
