BEGIN;
-- Extend the existing consumer without changing the legacy output or the sealed handoff.
DO $patch$
DECLARE d text; before_legacy jsonb; before_a jsonb; before_b jsonb; after_b jsonb;
 old_chunk text:=$old$'input_snapshot',NULL,'review_contract',v_review,'composition_svg_assets',v_assets,$old$;
 new_chunk text:=$new$'input_snapshot',NULL,'review_contract',v_review,'composition_svg_assets',v_assets,
     'native_transport',CASE WHEN v_review_status='READY_FOR_REVIEW_ONLY' THEN
       jsonb_build_object('schema_version','SALY_NATIVE_TRANSPORT_V2','item_id',p_item_id,
         'contract_sha256',v_review->>'contract_sha256',
         'prompt_sha256',v_review#>>'{contract,handoff,prompt_sha256}',
         'payload',jsonb_build_object('prompt',v_review#>>'{contract,handoff,native_prompt}',
          'attachments',v_review#>'{contract,handoff,attachments}'))
       ELSE NULL END,$new$;
BEGIN
 d:=pg_get_functiondef('saly.creative_item_work_packet_l2c(bigint)'::regprocedure);
 IF md5(d)<>'21f237db9aa97141db2b6a00f1a10145'
 OR md5(pg_get_functiondef('saly.creative_assert_native_transport_v1(bigint,text,jsonb)'::regprocedure))<>'5ffc534a32ff846197f2c05dd1a29292'
 THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_BASE_CHANGED'; END IF;
 IF length(d)-length(replace(d,old_chunk,''))<>length(old_chunk) THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_PATCH_ANCHOR'; END IF;
 SELECT jsonb_agg(saly.creative_item_work_packet_l2c(id) ORDER BY id) INTO before_legacy FROM saly.creative_order_items WHERE id IN (5,6,7);
 before_a:=saly.creative_item_work_packet_l2c(8); before_b:=saly.creative_item_work_packet_l2c(9);
 EXECUTE replace(d,old_chunk,new_chunk);
 after_b:=saly.creative_item_work_packet_l2c(9);
 IF before_legacy IS DISTINCT FROM (SELECT jsonb_agg(saly.creative_item_work_packet_l2c(id) ORDER BY id) FROM saly.creative_order_items WHERE id IN (5,6,7))
 OR before_a IS DISTINCT FROM (saly.creative_item_work_packet_l2c(8)-'native_transport')
 OR before_b IS DISTINCT FROM (after_b-'native_transport')
 THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_LEGACY_REGRESSION'; END IF;
END $patch$;
-- Versioned structured adapter; sole existing byte-level validator remains v1.
CREATE FUNCTION saly.creative_assert_native_transport_v2(p_envelope jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,saly,visual,extensions,pg_temp AS $fn$
DECLARE p jsonb; v_id bigint; receipt jsonb;
BEGIN
 IF jsonb_typeof(p_envelope) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_SHAPE'; END IF;
 IF NOT (p_envelope ?& ARRAY['schema_version','item_id','contract_sha256','prompt_sha256','payload'])
 OR (SELECT count(*) FROM jsonb_object_keys(p_envelope))<>5
 OR jsonb_typeof(p_envelope->'schema_version') IS DISTINCT FROM 'string'
 OR p_envelope->>'schema_version' IS DISTINCT FROM 'SALY_NATIVE_TRANSPORT_V2'
 OR jsonb_typeof(p_envelope->'item_id') IS DISTINCT FROM 'number'
 OR coalesce(p_envelope->>'item_id','') !~ '^[1-9][0-9]{0,17}$'
 OR jsonb_typeof(p_envelope->'contract_sha256') IS DISTINCT FROM 'string'
 OR coalesce(p_envelope->>'contract_sha256','') !~ '^[0-9a-f]{64}$'
 OR jsonb_typeof(p_envelope->'prompt_sha256') IS DISTINCT FROM 'string'
 OR coalesce(p_envelope->>'prompt_sha256','') !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_FIELDS'; END IF;
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
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_assert_native_transport_v2(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION saly.creative_assert_native_transport_v2(jsonb) TO service_role;
DO $test$
DECLARE e jsonb; h jsonb; actual jsonb; c record; passed int:=0;
BEGIN
 e:=saly.creative_item_work_packet_l2c(9)->'native_transport';
 h:=(SELECT context_json->'handoff_review' FROM saly.creative_order_items WHERE id=9);
 actual:=saly.creative_assert_native_transport_v2(e);
 IF e#>>'{payload,prompt}' IS DISTINCT FROM h->>'native_prompt'
 OR e#>'{payload,attachments}' IS DISTINCT FROM h->'attachments'
 OR actual->>'status' IS DISTINCT FROM 'PAYLOAD_MATCH_REVIEW_ONLY'
 OR actual->'transmitted' IS DISTINCT FROM 'false'::jsonb OR actual->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR actual->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 OR saly.creative_item_work_packet_l2c(8)->'native_transport' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_POSITIVE_FAILED'; END IF;
 FOR c IN SELECT * FROM (VALUES
   ('shape','[]'::jsonb,'NATIVE_ENVELOPE_SHAPE'),
   ('version',jsonb_set(e,'{schema_version}','"obsolete"'),'NATIVE_ENVELOPE_FIELDS'),
   ('id_type',jsonb_set(e,'{item_id}','"9"'),'NATIVE_ENVELOPE_FIELDS'),
   ('missing',e-'contract_sha256','NATIVE_ENVELOPE_FIELDS'),
   ('extra',e||'{"unexpected":true}'::jsonb,'NATIVE_ENVELOPE_FIELDS'),
   ('payload_shape',jsonb_set(e,'{payload}','"serialized"'),'NATIVE_PAYLOAD_SHAPE'),
   ('extra_payload',jsonb_set(e,'{payload}',(e->'payload')||'{"composition":{}}'::jsonb),'NATIVE_PAYLOAD_FIELDS'),
   ('empty',jsonb_set(e,'{payload,prompt}','""'),'NATIVE_PAYLOAD_FIELDS'),
   ('wrong_attachment_type',jsonb_set(e,'{payload,attachments}','{}'),'NATIVE_PAYLOAD_FIELDS'),
   ('prompt_drift',jsonb_set(e,'{payload,prompt}',to_jsonb(h->>'native_prompt'||' ')),'NATIVE_TRANSPORT_PROMPT_DRIFT'),
   ('attachment_drift',jsonb_set(e,'{payload,attachments}','[{"role":"extra"}]'),'NATIVE_TRANSPORT_ATTACHMENT_DRIFT'),
   ('contract_drift',jsonb_set(e,'{contract_sha256}',to_jsonb(repeat('0',64))),'NATIVE_ENVELOPE_BINDING_DRIFT'),
   ('prompt_hash_drift',jsonb_set(e,'{prompt_sha256}',to_jsonb(repeat('0',64))),'NATIVE_ENVELOPE_BINDING_DRIFT')
 ) t(name,input,expected) LOOP
  BEGIN
   PERFORM saly.creative_assert_native_transport_v2(c.input);
   RAISE EXCEPTION 'NATIVE_ENVELOPE_NEGATIVE_UNEXPECTED_PASS:%',c.name;
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM c.expected THEN RAISE; END IF;
   passed:=passed+1;
  END;
 END LOOP;
 IF passed<>13 OR EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=9)
 OR has_function_privilege('anon','saly.creative_assert_native_transport_v2(jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_assert_native_transport_v2(jsonb)','EXECUTE')
 OR NOT has_function_privilege('service_role','saly.creative_assert_native_transport_v2(jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'NATIVE_ENVELOPE_TEST_FAILED'; END IF;
 RAISE NOTICE 'NATIVE_ENVELOPE: positive PASS; negatives=%; legacy exact PASS; zero render',passed;
END $test$;
COMMIT;
