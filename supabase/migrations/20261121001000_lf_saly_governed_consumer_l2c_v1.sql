-- SALY / L2C: read-only native execution handoff, no render, run insertion or QA approval.
-- Existing L2A compiler is private to its owner. Expose ONLY two narrow SECURITY DEFINER
-- readers to service_role; do not grant base-table SELECT or expose them to client roles.
-- All writes in this file are migration DDL via LF Migration Merge Train.
BEGIN;

CREATE FUNCTION saly.creative_item_work_packet_l2c(p_item_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,saly,visual,extensions,pg_temp
AS $fn$
DECLARE
 v_item record;
 v_blockers jsonb:='[]'::jsonb;
 v_latest_state text;
 v_attempt integer:=0;
 v_readiness text;
 v_context jsonb;
 v_snapshot jsonb;
BEGIN
 SELECT i.id AS item_id,i.order_id,i.code AS item_code,i.ordinal,
   i.status AS item_status,i.kind,i.required,i.context_json,i.acceptance_json,
   o.code AS order_code,o.status AS order_status,o.context_set_id,o.design_mode,
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
END $fn$;

CREATE FUNCTION saly.creative_order_dispatch_plan_l2c(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,saly,visual,extensions,pg_temp
AS $fn$
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
END $fn$;

-- Grant only the narrow service_role access to the schema and functions.
-- Base tables remain private: no SELECT/INSERT/UPDATE grants are issued.
REVOKE ALL ON FUNCTION saly.creative_item_work_packet_l2c(bigint),
 saly.creative_order_dispatch_plan_l2c(bigint) FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA saly TO service_role;
GRANT EXECUTE ON FUNCTION saly.creative_item_work_packet_l2c(bigint),
 saly.creative_order_dispatch_plan_l2c(bigint) TO service_role;

-- Real PostgreSQL functional smoke: no fictional run or artifact receipt created.
DO $smoke$
DECLARE
 v_order bigint; v_home bigint; v_advance bigint; v_rewards bigint;
 v_home_packet jsonb; v_advance_packet jsonb; v_rewards_packet jsonb;
 v_plan jsonb; v_blocked boolean:=false;
BEGIN
 SELECT id INTO STRICT v_order FROM saly.creative_orders
 WHERE code='SALY_HOME_BATCH_001' AND status='PLANIFICADO';
 SELECT id INTO STRICT v_home FROM saly.creative_order_items
 WHERE order_id=v_order AND code='HOME';
 SELECT id INTO STRICT v_advance FROM saly.creative_order_items
 WHERE order_id=v_order AND code='ADELANTO';
 SELECT id INTO STRICT v_rewards FROM saly.creative_order_items
 WHERE order_id=v_order AND code='REWARDS';

 v_home_packet:=saly.creative_item_work_packet_l2c(v_home);
 v_advance_packet:=saly.creative_item_work_packet_l2c(v_advance);
 v_rewards_packet:=saly.creative_item_work_packet_l2c(v_rewards);
 v_plan:=saly.creative_order_dispatch_plan_l2c(v_order);

 IF v_home_packet->>'readiness_code'<>'READY_FOR_NATIVE_HANDOFF'
    OR v_home_packet->>'native_execution_authorized'<>'false'
    OR v_home_packet->>'image_generation_allowed'<>'false'
    OR jsonb_typeof(v_home_packet#>'{input_snapshot,identity_versions}')<>'array'
    OR jsonb_array_length(v_home_packet#>'{input_snapshot,identity_versions}')<2
    OR jsonb_array_length(v_home_packet#>'{input_snapshot,source_refs}')<>1
    OR v_home_packet#>>'{input_snapshot,screen_spec,screen}'<>'HOME'
 THEN RAISE EXCEPTION 'SALY_L2C_HOME_PACKET_INVALID'; END IF;

 IF v_advance_packet->>'readiness_code'<>'DEPENDENCIES_NOT_APPROVED'
    OR v_rewards_packet->>'readiness_code'<>'DEPENDENCIES_NOT_APPROVED'
    OR jsonb_array_length(v_advance_packet->'blocking_dependencies')<>1
    OR jsonb_array_length(v_rewards_packet->'blocking_dependencies')<>1
    OR v_advance_packet->'input_snapshot'<>'null'::jsonb
    OR v_rewards_packet->'input_snapshot'<>'null'::jsonb
 THEN RAISE EXCEPTION 'SALY_L2C_DEPENDENCY_GATE_FAILED'; END IF;

 IF (v_plan->>'ready_items')::integer<>1
    OR (v_plan->>'blocked_items')::integer<>2
    OR jsonb_array_length(v_plan->'items')<>3
    OR v_plan->>'native_execution_authorized'<>'false'
 THEN RAISE EXCEPTION 'SALY_L2C_BATCH_PLAN_FAILED'; END IF;

 BEGIN
   PERFORM saly.creative_item_work_packet_l2c(-1);
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='SALY_L2C_ITEM_NOT_FOUND' THEN v_blocked:=true;
   ELSE RAISE; END IF;
 END;
 IF NOT v_blocked THEN RAISE EXCEPTION 'SALY_L2C_UNKNOWN_ITEM_NOT_BLOCKED'; END IF;

 IF NOT has_schema_privilege('service_role','saly','USAGE')
  OR NOT has_function_privilege('service_role',
     'saly.creative_item_work_packet_l2c(bigint)','EXECUTE')
  OR NOT has_function_privilege('service_role',
     'saly.creative_order_dispatch_plan_l2c(bigint)','EXECUTE')
  OR has_function_privilege('anon',
     'saly.creative_item_work_packet_l2c(bigint)','EXECUTE')
  OR has_function_privilege('authenticated',
     'saly.creative_order_dispatch_plan_l2c(bigint)','EXECUTE')
  OR has_table_privilege('service_role','saly.creative_context_tokens','SELECT')
  OR has_table_privilege('service_role','saly.creative_order_items','SELECT')
 THEN RAISE EXCEPTION 'SALY_L2C_LEAST_PRIVILEGE_FAILED'; END IF;

 IF (SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order)<>0
  OR (SELECT count(*) FROM visual.standard_activations)<>0
  OR (SELECT count(*) FROM saly.creative_order_items
      WHERE order_id=v_order AND status<>'PENDIENTE')<>0
 THEN RAISE EXCEPTION 'SALY_L2C_UNEXPECTED_RUNTIME_SIDE_EFFECT'; END IF;
END $smoke$;

COMMIT;
