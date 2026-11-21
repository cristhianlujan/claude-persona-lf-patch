BEGIN;
-- One read-only validation at the existing work-packet boundary.
-- A match is not render permission and is not provider-origin evidence.
CREATE FUNCTION saly.creative_assert_native_transport_v1(p_item bigint,p_prompt text,p_attachments jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,saly,visual,extensions,pg_temp AS $fn$
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
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_assert_native_transport_v1(bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION saly.creative_assert_native_transport_v1(bigint,text,jsonb) TO service_role;
DO $test$
DECLARE h jsonb; p text; a jsonb; v jsonb; n int:=0; mutation text;
BEGIN
 h:=saly.creative_item_work_packet_l2c(9)#>'{review_contract,contract,handoff}';
 p:=h->>'native_prompt'; a:=h->'attachments';
 v:=saly.creative_assert_native_transport_v1(9,p,a);
 IF v->>'status' IS DISTINCT FROM 'PAYLOAD_MATCH_REVIEW_ONLY'
 OR v->>'prompt_sha256' IS DISTINCT FROM h->>'prompt_sha256'
 OR v->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR v->'transmitted' IS DISTINCT FROM 'false'::jsonb
 OR v->'provider_receipt' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'NATIVE_TRANSPORT_POSITIVE_FAILED'; END IF;
 FOREACH mutation IN ARRAY ARRAY[
   p||E'\nIncluye marco, logo, CTA y navegación.',
   replace(p,'Omite marco, logo, botón, navegación y adornos.','Incluye marco, logo, botón y navegación.'),
   p||' ', NULL::text
 ] LOOP
  BEGIN
   PERFORM saly.creative_assert_native_transport_v1(9,mutation,a);
   RAISE EXCEPTION 'NATIVE_TRANSPORT_BAD_PROMPT_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'NATIVE_TRANSPORT_PROMPT_DRIFT' THEN RAISE; END IF; n:=n+1;
  END;
 END LOOP;
 BEGIN
  PERFORM saly.creative_assert_native_transport_v1(9,p,'[{"role":"reference"}]'::jsonb);
  RAISE EXCEPTION 'NATIVE_TRANSPORT_BAD_ATTACHMENT_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'NATIVE_TRANSPORT_ATTACHMENT_DRIFT' THEN RAISE; END IF; n:=n+1;
 END;
 IF n<>5 OR EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=9)
 OR NOT has_function_privilege('service_role','saly.creative_assert_native_transport_v1(bigint,text,jsonb)','EXECUTE')
 OR has_function_privilege('anon','saly.creative_assert_native_transport_v1(bigint,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_assert_native_transport_v1(bigint,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'NATIVE_TRANSPORT_TEST_FAILED'; END IF;
END $test$;
COMMIT;
