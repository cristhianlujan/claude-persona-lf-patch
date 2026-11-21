BEGIN;
DO $guard$ BEGIN
 IF md5(pg_get_functiondef('saly.creative_item_work_packet_l2c(bigint)'::regprocedure))<>'a296a2c6b5bcc477b4e1e0e20736b942'
 OR md5(pg_get_functiondef('saly.creative_order_live_summary_l3b(bigint)'::regprocedure))<>'732886093253731eb2bccdb18fdba740'
 THEN RAISE EXCEPTION 'SALY_REVIEW_CONSUMER_BASE_CHANGED'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION saly.creative_item_work_packet_l2c(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_item record;
 v_blockers jsonb:='[]'::jsonb;
 v_latest_state text;
 v_attempt integer:=0;
 v_readiness text;
 v_context jsonb;
 v_snapshot jsonb;
 v_review jsonb; v_assets jsonb; v_review_status text;
BEGIN
 SELECT i.id AS item_id,i.order_id,i.code AS item_code,i.ordinal,
   i.status AS item_status,i.kind,i.required,i.context_json,i.acceptance_json,
   o.code AS order_code,o.status AS order_status,o.context_set_id,o.design_mode,o.scope_json,
   p.codigo AS project_code
 INTO v_item
 FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_L2C_ITEM_NOT_FOUND'; END IF;
 IF v_item.project_code<>'SALY-001' THEN
   RAISE EXCEPTION 'SALY_L2C_PROJECT_NOT_ALLOWED'; END IF;

 SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'item_id',prereq.id,'code',prereq.code,'status',prereq.status)
    ORDER BY prereq.ordinal),'[]'::jsonb)
 INTO v_blockers
 FROM saly.creative_item_dependencies d
 JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
 WHERE d.order_id=v_item.order_id AND d.item_id=v_item.item_id
   AND prereq.status<>'APROBADO';

 SELECT COALESCE(max(attempt_number),0) INTO v_attempt
 FROM saly.creative_runs WHERE order_id=v_item.order_id AND item_id=v_item.item_id;
 SELECT state INTO v_latest_state
 FROM saly.creative_runs
 WHERE order_id=v_item.order_id AND item_id=v_item.item_id
 ORDER BY attempt_number DESC LIMIT 1;

 v_readiness:=CASE
   WHEN v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA')
     THEN 'ORDER_NOT_ELIGIBLE'
   WHEN v_item.item_status NOT IN ('PENDIENTE','LISTO')
     THEN 'ITEM_NOT_ELIGIBLE'
   WHEN jsonb_array_length(v_blockers)>0
     THEN 'DEPENDENCIES_NOT_APPROVED'
   WHEN v_latest_state IN ('EN_COLA','EJECUTANDO')
     THEN 'RUN_ALREADY_ACTIVE'
   WHEN v_latest_state='EXITOSO'
     THEN 'AWAITING_INDEPENDENT_QA'
   ELSE 'READY_FOR_NATIVE_HANDOFF'
 END;

 IF v_readiness<>'READY_FOR_NATIVE_HANDOFF' THEN
   RETURN jsonb_build_object(
     'schema_version','SALY_WORK_PACKET_L2C_V1',
     'business_code','SALY',
     'order_id',v_item.order_id,'order_code',v_item.order_code,
     'item_id',v_item.item_id,'item_code',v_item.item_code,
     'readiness_code',v_readiness,'blocking_dependencies',v_blockers,
     'latest_run_state',v_latest_state,'input_snapshot',NULL,
     'native_execution_authorized',false,'image_generation_allowed',false);
 END IF;

 -- Explicit review-only lane; never advertise native dispatch readiness.
 IF v_item.scope_json->'review_only'='true'::jsonb OR v_item.context_json#>>'{screen_spec,mode}'='TEMPLATE_REVIEW' THEN
   IF v_item.scope_json->'review_only' IS DISTINCT FROM 'true'::jsonb
     OR v_item.scope_json->'render_authorized' IS DISTINCT FROM 'false'::jsonb
     OR v_item.context_json#>>'{screen_spec,mode}' IS DISTINCT FROM 'TEMPLATE_REVIEW'
   THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_AUTHORITY_MISMATCH'; END IF;
   v_review_status:='REVIEW_TEMPLATE_INCOMPLETE';
   IF v_item.context_json ? 'preflight_review' THEN
     v_review:=saly.creative_template_preflight_v1(p_item_id);
     IF v_review IS DISTINCT FROM v_item.context_json->'preflight_review'
       OR v_review#>'{contract,handoff}' IS DISTINCT FROM v_item.context_json->'handoff_review'
       OR v_review#>>'{contract,qa_verdict}' IS DISTINCT FROM 'NOT_EVALUATED'
       OR v_review#>'{contract,image_generation_allowed}' IS DISTINCT FROM 'false'::jsonb
       OR v_review#>'{contract,native_execution_authorized}' IS DISTINCT FROM 'false'::jsonb
     THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_CONTRACT_DRIFT'; END IF;
     SELECT jsonb_object_agg(r.key,jsonb_build_object('ref',r.value,'svg_utf8',a.metadata->>'svg')) INTO v_assets
     FROM jsonb_each(v_review#>'{contract,handoff,composition,asset_refs}') r
     JOIN visual.source_assets a ON a.id=(r.value->>'asset_id')::bigint
     AND a.source_sha256=r.value->>'sha256'
     AND a.source_sha256=encode(extensions.digest(convert_to(a.metadata->>'svg','UTF8'),'sha256'),'hex');
     IF v_assets IS NULL OR (SELECT count(*) FROM jsonb_object_keys(v_assets))<>5
     THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_ASSET_BYTES_MISMATCH'; END IF;
     v_review_status:='READY_FOR_REVIEW_ONLY';
   END IF;
   RETURN jsonb_build_object('schema_version','SALY_WORK_PACKET_L2C_V1','business_code','SALY',
     'order_id',v_item.order_id,'order_code',v_item.order_code,'item_id',v_item.item_id,'item_code',v_item.item_code,
     'readiness_code',v_review_status,'blocking_dependencies','[]'::jsonb,'latest_run_state',v_latest_state,
     'input_snapshot',NULL,'review_contract',v_review,'composition_svg_assets',v_assets,
     'native_execution_authorized',false,'image_generation_allowed',false,
     'next_action',CASE WHEN v_review IS NULL THEN 'COMPLETE_TEMPLATE_REVIEW' ELSE 'REVIEW_EXACT_HANDOFF_NO_RENDER' END);
 END IF;

 -- The L2A compiler rechecks SEALED context, frozen identity/version hashes,
 -- candidate opt-in and source status/SHA on every call. No copy of tokens in code.
 v_context:=saly.creative_item_context_l2a(v_item.item_id);
 IF v_context->>'business_code'<>'SALY'
    OR v_context->>'image_generation_allowed'<>'false'
    OR v_context->>'context_set_id' IS DISTINCT FROM v_item.context_set_id::text
    OR jsonb_typeof(v_context->'tokens')<>'array'
    OR jsonb_array_length(v_context->'tokens')<2
    OR (SELECT count(*) FROM jsonb_array_elements(v_context->'tokens') AS tok(value)
       WHERE tok.value->>'role'='OFFICIAL')<>2
 THEN RAISE EXCEPTION 'SALY_L2C_COMPILED_CONTEXT_INVALID'; END IF;
 IF jsonb_typeof(v_context->'source_refs')<>'array'
    OR jsonb_array_length(v_context->'source_refs')<1
 THEN RAISE EXCEPTION 'SALY_L2C_VERIFIED_SOURCE_REQUIRED'; END IF;
 IF jsonb_typeof(v_item.context_json->'screen_spec')<>'object'
    OR jsonb_typeof(v_item.acceptance_json)<>'object'
    OR v_item.acceptance_json->>'qa_required'<>'true'
 THEN RAISE EXCEPTION 'SALY_L2C_SCREEN_SPEC_OR_QA_MISSING'; END IF;

 -- Matches existing creative_runs input_snapshot fields and success constraints.
 -- This is a proposal for the owning native executor, NOT a run reservation,
 -- rendering receipt, deployment authority or visual approval.
 v_snapshot:=jsonb_build_object(
    'schema_version','SALY_NATIVE_INPUT_SNAPSHOT_L2C_V1',
    'business_code','SALY',
    'order_id',v_item.order_id,
    'item_id',v_item.item_id,
    'item_code',v_item.item_code,
    'design_mode',v_item.design_mode,
    'context_set_id',v_item.context_set_id,
    'identity_versions',v_context->'tokens',
    'source_refs',v_context->'source_refs',
    'screen_spec',v_item.context_json->'screen_spec',
    'acceptance_criteria',v_item.acceptance_json,
    'context_sha256',encode(extensions.digest(
        convert_to(v_context::text,'UTF8'),'sha256'),'hex'),
    'native_execution_authorized',false);

 RETURN jsonb_build_object(
    'schema_version','SALY_WORK_PACKET_L2C_V1',
    'business_code','SALY',
    'order_id',v_item.order_id,'order_code',v_item.order_code,
    'item_id',v_item.item_id,'item_code',v_item.item_code,
    'readiness_code','READY_FOR_NATIVE_HANDOFF',
    'blocking_dependencies','[]'::jsonb,
    'next_attempt_hint',v_attempt+1,
    'idempotency_key_hint','SALY-'||v_item.order_id||'-'||v_item.item_id||
       '-'||(v_attempt+1),
    'latest_run_state',v_latest_state,
    'input_snapshot',v_snapshot,
    'native_execution_authorized',false,
    'image_generation_allowed',false,
    'next_action','GOVERNED_NATIVE_EXECUTOR_AND_WORKER_RECEIPT_REQUIRED');
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_order_live_summary_l3b(p_order_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE v_order record; v_items jsonb; v_all integer; v_ready integer; v_blocked integer;
BEGIN
 SELECT o.id,o.code,o.status,o.scope_json,p.codigo AS project_code INTO v_order
 FROM saly.creative_orders o JOIN saly.proyecto p ON p.id=o.project_id
 WHERE o.id=p_order_id;
 IF NOT FOUND OR v_order.project_code<>'SALY-001'
 THEN RAISE EXCEPTION 'SALY_L3B_ORDER_NOT_ADMITTED'; END IF;

 IF v_order.scope_json->'review_only'='true'::jsonb THEN
   WITH entries AS (
    SELECT i.ordinal,i.id,i.code,i.status,pkt.result,
      pkt.result#>'{review_contract,contract,acceptance_criteria,semantic_qa}' AS sem,
      pkt.result#>'{review_contract,contract,handoff}' AS h,
      pkt.result#>'{review_contract,contract,qa_checks}' AS tech
    FROM saly.creative_order_items i
    CROSS JOIN LATERAL (SELECT saly.creative_item_work_packet_l2c(i.id) AS result) pkt
    WHERE i.order_id=v_order.id)
   SELECT coalesce(jsonb_agg(jsonb_build_object('ordinal',ordinal,'item_id',id,'screen',code,'status',status,
    'readiness',result->>'readiness_code','blocked_dependencies',jsonb_array_length(result->'blocking_dependencies'),
    'visual_contract_sha256',result#>>'{review_contract,contract_sha256}',
    'template_version',h->>'template_version','prompt_sha256',h->>'prompt_sha256','native_prompt',h->>'native_prompt',
    'composition',h->'composition','trace',h->'trace','technical_checks',tech,
    'semantic_qa',sem,'qa_status','NOT_EVALUATED','transmitted',false) ORDER BY ordinal),'[]'::jsonb),
    count(*)::int,count(*) FILTER(WHERE result->>'readiness_code'='READY_FOR_REVIEW_ONLY')::int
   INTO v_items,v_all,v_ready FROM entries;
   RETURN jsonb_build_object('schema_version','SALY_ORDER_LIVE_SUMMARY_L3B_V1','order_id',v_order.id,
    'order_code',v_order.code,'order_status',v_order.status,'total_screens',v_all,
    'ready_for_handoff',0,'blocked',v_all,'ready_for_review',v_ready,'items',v_items,
    'actual_generation_count',(SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order.id),
    'qa_pass_count',(SELECT count(*) FROM saly.creative_order_items WHERE order_id=v_order.id AND status='APROBADO'),
    'visual_generation_enabled',false,'batch_status','REVIEW_ONLY_NOT_RENDERED');
 END IF;

 WITH entries AS (
 SELECT i.ordinal,i.id,i.code,i.status,
    i.acceptance_json->'semantic_qa' AS semantic_contract, i.qa_receipt,
    pkt.result->>'readiness_code' AS readiness,
    COALESCE(jsonb_array_length(pkt.result->'blocking_dependencies'),0) AS deps,
    vc.info->>'contract_sha256' AS contract_sha256,
    (SELECT count(*) FROM saly.creative_runs r WHERE r.item_id=i.id) AS runs,
    (SELECT count(*) FROM saly.creative_item_sources s WHERE s.item_id=i.id) AS sources
 FROM saly.creative_order_items i
 CROSS JOIN LATERAL (SELECT saly.creative_item_work_packet_l2c(i.id) AS result) pkt
 CROSS JOIN LATERAL (SELECT saly.creative_item_visual_contract_l3b(i.id) AS info) vc
 WHERE i.order_id=v_order.id)
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'ordinal',ordinal,'item_id',id,'screen',code,'status',status,
    'readiness',readiness,'blocked_dependencies',deps,
    'sources',sources,'runs',runs,
    'visual_contract_sha256',contract_sha256,
    'qa_status',COALESCE(qa_receipt->>'verdict','NOT_EVALUATED'),
    'semantic_qa',CASE WHEN semantic_contract IS NULL THEN NULL ELSE
      jsonb_build_object('request_original',semantic_contract->'original_messages',
        'original_request_sha256',semantic_contract->>'original_request_sha256',
        'interpretation',semantic_contract->'interpretation',
        'checks',semantic_contract->'checks',
        'verdict',COALESCE(qa_receipt#>>'{semantic_qa,verdict}','NOT_EVALUATED'),
        'technical_verdict',COALESCE(qa_receipt#>>'{technical_qa,verdict}','NOT_EVALUATED'))
      END)
    ORDER BY ordinal),'[]'::jsonb),
 count(*)::integer,
 count(*) FILTER(WHERE readiness='READY_FOR_NATIVE_HANDOFF')::integer,
 count(*) FILTER(WHERE readiness<>'READY_FOR_NATIVE_HANDOFF')::integer
 INTO v_items,v_all,v_ready,v_blocked FROM entries;
 RETURN jsonb_build_object(
 'schema_version','SALY_ORDER_LIVE_SUMMARY_L3B_V1',
 'order_id',v_order.id,'order_code',v_order.code,'order_status',v_order.status,
 'total_screens',v_all,'ready_for_handoff',v_ready,'blocked',v_blocked,
 'items',v_items,
 'actual_generation_count',(SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order.id),
 'qa_pass_count',(SELECT count(*) FROM saly.creative_order_items WHERE order_id=v_order.id AND status='APROBADO'),
 'visual_generation_enabled',false,
 'batch_status','PREPARED_NOT_RENDERED');
END $function$;
DO $test$
DECLARE old_packet jsonb; a jsonb; b jsonb; plan jsonb; live jsonb; n int;
BEGIN
 old_packet:=saly.creative_item_work_packet_l2c(5);
 IF old_packet->>'readiness_code' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF' OR old_packet->'input_snapshot' IS NULL
 OR old_packet ? 'review_contract' THEN RAISE EXCEPTION 'LEGACY_PACKET_REGRESSION'; END IF;
 IF saly.creative_item_work_packet_l2c(6)->>'readiness_code' IS DISTINCT FROM 'DEPENDENCIES_NOT_APPROVED'
 OR saly.creative_item_work_packet_l2c(7)->>'readiness_code' IS DISTINCT FROM 'DEPENDENCIES_NOT_APPROVED'
 THEN RAISE EXCEPTION 'LEGACY_DAG_REGRESSION'; END IF;
 a:=saly.creative_item_work_packet_l2c(8); b:=saly.creative_item_work_packet_l2c(9);
 IF a->>'readiness_code' IS DISTINCT FROM 'REVIEW_TEMPLATE_INCOMPLETE'
 OR b->>'readiness_code' IS DISTINCT FROM 'READY_FOR_REVIEW_ONLY'
 OR b->'input_snapshot' IS DISTINCT FROM 'null'::jsonb
 OR b->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
 OR b->'native_execution_authorized' IS DISTINCT FROM 'false'::jsonb
 OR b->'review_contract' IS DISTINCT FROM (SELECT context_json->'preflight_review' FROM saly.creative_order_items WHERE id=9)
 THEN RAISE EXCEPTION 'REVIEW_PACKET_MISMATCH'; END IF;
 SELECT count(*) INTO n FROM jsonb_each(b->'composition_svg_assets') r
 WHERE r.value#>>'{ref,sha256}'=encode(extensions.digest(convert_to(r.value->>'svg_utf8','UTF8'),'sha256'),'hex');
 IF n<>5 THEN RAISE EXCEPTION 'REVIEW_SVG_HASH_MISMATCH'; END IF;
 plan:=saly.creative_order_dispatch_plan_l2c(5); live:=saly.creative_order_live_summary_l3b(5);
 IF plan->>'ready_items' IS DISTINCT FROM '0' OR plan->>'blocked_items' IS DISTINCT FROM '2'
 OR live->>'ready_for_review' IS DISTINCT FROM '1' OR live->>'ready_for_handoff' IS DISTINCT FROM '0'
 OR live->>'actual_generation_count' IS DISTINCT FROM '0'
 OR live#>>'{items,1,prompt_sha256}' IS DISTINCT FROM b#>>'{review_contract,contract,handoff,prompt_sha256}'
 OR live#>>'{items,1,qa_status}' IS DISTINCT FROM 'NOT_EVALUATED'
 THEN RAISE EXCEPTION 'REVIEW_SUMMARY_MISMATCH'; END IF;
 IF NOT has_function_privilege('service_role','saly.creative_item_work_packet_l2c(bigint)','EXECUTE')
 OR NOT has_function_privilege('service_role','saly.creative_order_live_summary_l3b(bigint)','EXECUTE')
 OR has_function_privilege('anon','saly.creative_item_work_packet_l2c(bigint)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_item_work_packet_l2c(bigint)','EXECUTE')
 OR has_function_privilege('service_role','saly.creative_template_preflight_v1(bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'REVIEW_ACL_DRIFT'; END IF;
END $test$;
COMMIT;
