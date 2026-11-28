CREATE OR REPLACE FUNCTION saly.creative_order_dispatch_plan_l2c(p_order_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_order record;
 v_items jsonb:='[]'::jsonb;
 v_ready integer:=0;
 v_blocked integer:=0;
BEGIN
 SELECT o.id,o.code,o.status,p.codigo AS project_code
 INTO v_order FROM saly.creative_orders o
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE o.id=p_order_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_L2C_ORDER_NOT_FOUND'; END IF;
 IF v_order.project_code<>'SALY-001' THEN
   RAISE EXCEPTION 'SALY_L2C_PROJECT_NOT_ALLOWED'; END IF;

 SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'item_id',i.id,'code',i.code,'ordinal',i.ordinal,'status',i.status,
   'readiness_code',pkt.result->>'readiness_code',
   'blocking_dependencies',pkt.result->'blocking_dependencies')
   ORDER BY i.ordinal),'[]'::jsonb),
   count(*) FILTER(WHERE pkt.result->>'readiness_code'='READY_FOR_NATIVE_HANDOFF'),
   count(*) FILTER(WHERE pkt.result->>'readiness_code'<>'READY_FOR_NATIVE_HANDOFF')
 INTO v_items,v_ready,v_blocked
 FROM saly.creative_order_items i
 CROSS JOIN LATERAL (SELECT saly.creative_item_work_packet_l2c(i.id) AS result) pkt
 WHERE i.order_id=v_order.id;

 RETURN jsonb_build_object(
   'schema_version','SALY_DISPATCH_PLAN_L2C_V1','business_code','SALY',
   'order_id',v_order.id,'order_code',v_order.code,'order_status',v_order.status,
   'items',v_items,'ready_items',v_ready,'blocked_items',v_blocked,
   'native_execution_authorized',false,'image_generation_allowed',false,
   'next_action','SELECT_READY_ITEM_AND_REQUEST_GOVERNED_NATIVE_HANDOFF');
END $function$
;

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
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_order_sequence_dependency_met_v1(p_order_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
 SELECT EXISTS(SELECT 1 FROM saly.creative_orders o
  WHERE o.id=p_order_id AND o.request_kind='APP_SCREEN_SINGLE'
  AND NOT EXISTS(SELECT 1 FROM saly.creative_order_sequence_v1 s
   JOIN saly.creative_orders prior ON prior.id=s.depends_on_order_id
   WHERE s.order_id=o.id AND prior.status<>'TERMINADO'));
$function$
;

CREATE OR REPLACE FUNCTION saly.creative_order_sequence_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE n integer; lo bigint; hi bigint; only_screens boolean; cycle_found boolean;
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'CREATIVE_ORDER_SEQUENCE_IMMUTABLE'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:order_sequence:v1',0));
 PERFORM id FROM saly.creative_orders WHERE id IN
  (NEW.order_id,NEW.depends_on_order_id) ORDER BY id FOR UPDATE;
 SELECT count(*),min(project_id),max(project_id),
  bool_and(request_kind='APP_SCREEN_SINGLE')
 INTO n,lo,hi,only_screens FROM saly.creative_orders
 WHERE id IN(NEW.order_id,NEW.depends_on_order_id);
 IF n<>2 OR lo IS DISTINCT FROM NEW.project_id
    OR hi IS DISTINCT FROM NEW.project_id OR NOT coalesce(only_screens,false)
 THEN RAISE EXCEPTION 'CREATIVE_ORDER_SEQUENCE_SCOPE_MISMATCH'; END IF;
 WITH RECURSIVE walk(order_id) AS (
   SELECT NEW.depends_on_order_id
   UNION
   SELECT d.depends_on_order_id FROM saly.creative_order_sequence_v1 d
   JOIN walk w ON w.order_id=d.order_id
 )
 SELECT EXISTS(SELECT 1 FROM walk WHERE order_id=NEW.order_id) INTO cycle_found;
 IF cycle_found THEN RAISE EXCEPTION 'CREATIVE_ORDER_SEQUENCE_CYCLE'; END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_order_sequence_start_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE target_id bigint; entering boolean;
BEGIN
 IF TG_TABLE_NAME='creative_orders' THEN
  target_id:=NEW.id;
  entering:=NEW.status IN ('EN_PROCESO','EN_QA','COMPLETADO','TERMINADO')
    AND (TG_OP='INSERT' OR NEW.status IS DISTINCT FROM OLD.status);
 ELSE
  target_id:=NEW.order_id;
  entering:=NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO');
 END IF;
 IF entering AND EXISTS(SELECT 1 FROM saly.creative_order_sequence_v1 seq
   JOIN saly.creative_orders prior ON prior.id=seq.depends_on_order_id
   WHERE seq.order_id=target_id AND prior.status<>'TERMINADO')
 THEN RAISE EXCEPTION 'CREATIVE_ORDER_PREREQUISITE_NOT_TERMINADO'; END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_owner_approve_v1(p_item_id bigint, p_decision text, p_comment text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'auth', 'pg_temp'
AS $function$
DECLARE uid uuid; row_i record; row_o record;
BEGIN
 uid:=auth.uid();
 IF uid IS NULL OR p_item_id IS NULL OR p_item_id<1
 OR p_decision NOT IN ('APROBADO','RECHAZADO')
 OR nullif(btrim(coalesce(p_comment,'')),'') IS NULL
 THEN RAISE EXCEPTION 'SALY_OWNER_DECISION_INPUT_INVALID'; END IF;
 SELECT * INTO row_i FROM saly.creative_order_items
 WHERE id=p_item_id FOR UPDATE;
 IF NOT FOUND OR row_i.status<>'TERMINADO'
 THEN RAISE EXCEPTION 'SALY_OWNER_REQUIRES_TERMINADO'; END IF;
 SELECT * INTO row_o FROM saly.creative_orders WHERE id=row_i.order_id;
 IF NOT EXISTS (SELECT 1 FROM saly.creative_owner_accounts_v1 a
 WHERE a.requested_by=row_o.requested_by AND a.owner_uid=uid)
 THEN RAISE EXCEPTION 'SALY_OWNER_DECISION_UNAUTHORIZED'; END IF;
 INSERT INTO saly.creative_owner_decisions_v1(item_id,owner_uid,decision,comment)
 VALUES (p_item_id,uid,p_decision,p_comment);
 IF p_decision='APROBADO' THEN
   UPDATE saly.creative_order_items
   SET status='APROBADO', approved_at=clock_timestamp(),approved_by=uid::text,
       updated_at=clock_timestamp()
   WHERE id=p_item_id AND status='TERMINADO';
   IF NOT FOUND THEN RAISE EXCEPTION 'SALY_OWNER_APPROVAL_UPDATE_FAILED'; END IF;
 END IF;
 RETURN jsonb_build_object('item_id',p_item_id,'decision',p_decision,
    'item_state',(SELECT status FROM saly.creative_order_items WHERE id=p_item_id),
    'owner_uid',uid,'recorded',true);
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_plan_review_v2(p_item_id bigint, p_plan_sha256 text, p_verdict text, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'auth', 'extensions', 'pg_temp'
AS $function$
DECLARE v_row saly.creative_plan_pre_qa_v2%ROWTYPE;
BEGIN
 SELECT * INTO STRICT v_row FROM saly.creative_plan_pre_qa_v2
 WHERE item_id=p_item_id AND plan_sha256=p_plan_sha256 FOR UPDATE;
 IF v_row.verdict<>'PENDING' OR
 encode(extensions.digest(v_row.plan_json::text,'sha256'),'hex')<>v_row.plan_sha256
 THEN RAISE EXCEPTION 'SALY_PREQA_PLAN_IMMUTABLE_OR_ALREADY_REVIEWED'; END IF;
 IF p_verdict NOT IN ('PASS','FAIL','NO_EVALUADO') OR p_verdict IS NULL
 OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object' OR p_evidence='{}'::jsonb
 OR (p_verdict='PASS' AND (
  jsonb_typeof(p_evidence->'checks') IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_evidence->'checks')=0
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_evidence->'checks') c
    WHERE c->>'verdict' IS DISTINCT FROM 'PASS' OR nullif(btrim(c->>'evidence'),'') IS NULL)))
 THEN RAISE EXCEPTION 'SALY_PREQA_REVIEW_EVIDENCE_INVALID'; END IF;
 UPDATE saly.creative_plan_pre_qa_v2
 SET verdict=p_verdict,reviewer_uid=NULL,review_json=p_evidence||jsonb_build_object(
   'review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO','independent_pass',false,
   'decision_source','OWNER_CHAT_CLAUDE_2026-11-24T01:25-05:00'),reviewed_at=now()
 WHERE item_id=p_item_id AND plan_sha256=p_plan_sha256;
 RETURN jsonb_build_object('status',p_verdict,'plan_sha256',p_plan_sha256,
   'reviewer_uid',NULL,'independent_pass',false,'usable',p_verdict='PASS',
   'review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO');
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_plan_submit_v2(p_item_id bigint, p_plan_json jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'auth', 'extensions', 'pg_temp'
AS $function$
DECLARE v_sha text;
BEGIN
 IF jsonb_typeof(p_plan_json) IS DISTINCT FROM 'object' OR p_plan_json='{}'::jsonb
 OR NOT EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=p_item_id)
 THEN RAISE EXCEPTION 'SALY_PREQA_PLAN_MISSING'; END IF;
 v_sha:=encode(extensions.digest(p_plan_json::text,'sha256'),'hex');
 INSERT INTO saly.creative_plan_pre_qa_v2(item_id,plan_sha256,plan_json,author_uid,verdict,reviewer_uid,review_json,reviewed_at)
 VALUES(p_item_id,v_sha,p_plan_json,NULL,'PASS',NULL,
  jsonb_build_object('review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO',
    'decision_source','OWNER_CHAT_CLAUDE_2026-11-24T01:25-05:00',
    'automatic_pass',true,'independent_pass',false,'visual_qa','NO_EVALUADO',
    'plan_sha256',v_sha),now());
 RETURN jsonb_build_object('status','PASS','plan_sha256',v_sha,'author_uid',NULL,
   'reviewer_uid',NULL,'independent_pass',false,'usable',true,
   'review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO');
END; $function$
;
