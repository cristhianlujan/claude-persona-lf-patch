-- Reuse serial queue and existing grants; scope initial rollout to owner-authorized orders 11–21.
BEGIN;
CREATE OR REPLACE FUNCTION saly.creative_queue_claim_next_v1(p_worker_ref text, p_lease_seconds integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_item record;
  v_active record;
  v_claim record;
  v_now timestamptz;
  v_policy jsonb;
  v_lease_seconds integer;
BEGIN
  IF length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  -- Fail before claiming if an operational policy has not been published.
  -- The existing creative run admission reads the same source of truth.
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  IF p_lease_seconds IS NOT NULL AND p_lease_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT id,lease_until,item_id INTO v_active
  FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE' FOR UPDATE;
  IF FOUND THEN
    IF v_active.lease_until > v_now THEN
      RETURN jsonb_build_object('status','BUSY','claim_id',v_active.id);
    END IF;
    -- Old fencing token is invalid after this update. Preserve audit trail.
    UPDATE saly.creative_queue_claims_v1
    SET state='EXPIRED',finished_at=v_now,note='LEASE_EXPIRED'
    WHERE id=v_active.id AND state='ACTIVE';
  END IF;

  -- Admission is intentionally conservative: review-only and legacy orders excluded.
  -- Caller must still validate semantic/brand sources, generate and QA within lease.
  IF EXISTS (SELECT 1 FROM saly.creative_runs r
             WHERE r.state IN ('EN_COLA','EJECUTANDO')) THEN
    RETURN jsonb_build_object('status','RUN_ACTIVE','claim_id',NULL);
  END IF;

  SELECT i.id AS item_id,o.id AS order_id,i.code AS item_code,o.code AS order_code
  INTO v_item
  FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.status IN ('PLANIFICADO','EN_PROCESO')
    AND (i.status='LISTO' OR (i.status='PENDIENTE' AND o.project_id=2 AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1' AND o.scope_json->>'module'='Solicitar adelanto'))
    AND o.scope_json->>'queue_mode'='SERIAL_V1'
    AND (o.request_kind <> 'APP_SCREEN_SINGLE'
         OR saly.creative_order_sequence_dependency_met_v1(o.id))
    AND o.scope_json->>'rendering_authority'='true'
    AND coalesce(o.scope_json->>'review_only','false')='false'
    AND coalesce(o.scope_json->>'render_authorized','true')='true'
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.item_id=i.id AND d.order_id=o.id AND prereq.status<>'APROBADO'
    )
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=i.id AND r.state='EXITOSO'
    )
  ORDER BY o.id, i.ordinal, i.id
  LIMIT 1 FOR UPDATE OF i SKIP LOCKED;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_item.order_id AND status='PLANIFICADO';
  UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.item_id AND status='PENDIENTE';
  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>v_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_skill_prepare_v1(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE
 base jsonb:=jsonb_build_object('schema_version','CREATIVE_SKILL_PLAN_V1',
    'status','BLOCKED','native_execution_authorized',false,
    'image_generation_allowed',false,'native_transmitted',false,
    'provider_receipt',NULL,'qa_verdict','NOT_EVALUATED',
    'router_invoked',false,'profile_invoked',false,'database_written',false);
 tokens jsonb; logo jsonb;
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
 OR p_request->>'mode' NOT IN ('PLAN_ONLY','AUTONOMOUS')
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
 SELECT i.id,i.order_id,i.code AS item_code,o.code AS order_code,o.scope_json,o.status AS order_status,o.context_set_id,o.project_id,
 (SELECT state FROM saly.creative_context_sets WHERE id=o.context_set_id) AS context_state
 INTO STRICT item
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE p.codigo=p_request->>'project_code' AND o.code=p_request->>'order_code'
   AND i.code=p_request->>'item_code';

 -- A different literal is a new intent, not authority to reuse the old strategy.
 IF convert_to(p_request->>'literal_request','UTF8') IS DISTINCT FROM
    convert_to(item.scope_json->>'literal_request','UTF8')
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_NEW_INTENT_REQUIRES_INTERPRETATION'); END IF;

 IF p_request->>'mode'='AUTONOMOUS' THEN
   IF item.order_status NOT IN ('PLANIFICADO','EN_PROCESO') OR item.context_state IS DISTINCT FROM 'SEALED'
   THEN RETURN base||jsonb_build_object('blocking_code','SKILL_AUTONOMOUS_TARGET_NOT_READY'); END IF;
   IF item.scope_json->>'queue_mode'='SERIAL_V1' AND NOT EXISTS (SELECT 1 FROM saly.creative_queue_claims_v1 c WHERE c.order_id=item.order_id AND c.item_id=item.id AND c.state='ACTIVE' AND c.lease_until>clock_timestamp()) THEN RETURN base||jsonb_build_object('blocking_code','SKILL_AUTONOMOUS_CLAIM_REQUIRED'); END IF;
   SELECT jsonb_agg(jsonb_build_object('code',e.code,'version_id',v.id,'value',v.value_json,'role',t.role,'sha256',t.value_sha256) ORDER BY e.code) INTO tokens
   FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=item.context_set_id;
   SELECT jsonb_build_object('asset_id',id,'code',code,'version',version_number,'sha256',sha256,'file_provider',file_provider,'external_file_id',external_file_id,'filename',metadata->>'filename') INTO logo
   FROM saly.brand_assets WHERE id=9 AND project_id=item.project_id AND approval_status='APPROVED';
   RETURN base||jsonb_build_object('status','AUTONOMOUS_PREPARED','blocking_code',NULL,'image_generation_allowed',true,
    'item_id',item.id,'order_id',item.order_id,'context_set_id',item.context_set_id,
    'literal_request',item.scope_json->>'literal_request','compiled_prompt',coalesce(item.scope_json->>'compiled_prompt',item.scope_json->>'content_prompt',item.scope_json->>'literal_request'),
    'tokens',tokens,'logo_ref',logo,'next_action','GPT_GENERATE_AND_QA');
 END IF;

 IF item.scope_json->'review_only' IS DISTINCT FROM 'true'::jsonb
 OR item.scope_json->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_TARGET_NOT_REVIEW_ONLY'); END IF;

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
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_item_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_order_status text; v_run record; v_run_id text;
BEGIN
 SELECT status INTO v_order_status FROM saly.creative_orders WHERE id=NEW.order_id FOR UPDATE;
 IF v_order_status IN ('COMPLETADO','CANCELADO')
 THEN RAISE EXCEPTION 'CREATIVE_CLOSED_ORDER_IMMUTABLE_ITEMS'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='APROBADO'
 THEN RAISE EXCEPTION 'CREATIVE_APPROVED_ITEM_IMMUTABLE'; END IF;
 -- Original input and interpretation cannot be silently replaced after capture.
 IF TG_OP='UPDATE' AND OLD.acceptance_json ? 'semantic_qa'
    AND NEW.acceptance_json->'semantic_qa' IS DISTINCT FROM OLD.acceptance_json->'semantic_qa'
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_CONTRACT_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='TERMINADO' AND NEW.status='APROBADO' THEN
   IF NEW.approved_at IS NULL OR NEW.approved_by IS DISTINCT FROM auth.uid()::text
      OR auth.uid() IS NULL
      OR NOT EXISTS (SELECT 1 FROM saly.creative_owner_decisions_v1 d
          WHERE d.item_id=NEW.id AND d.owner_uid=auth.uid() AND d.decision='APROBADO')
      OR NOT EXISTS (SELECT 1 FROM saly.creative_owner_accounts_v1 a
          JOIN saly.creative_orders o ON o.requested_by=a.requested_by
          WHERE o.id=NEW.order_id AND a.owner_uid=auth.uid())
   THEN RAISE EXCEPTION 'SALY_OWNER_APPROVAL_NOT_AUTHORIZED'; END IF;
   RETURN NEW;
 END IF;
 IF NEW.status IN ('TERMINADO','APROBADO')
 AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF TG_OP='INSERT' OR (OLD.status<>'EN_QA' AND NOT (OLD.status='LISTO' AND NEW.status='TERMINADO'))
   THEN RAISE EXCEPTION 'CREATIVE_ITEM_NOT_IN_QA'; END IF;
   IF EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id AND prereq.status NOT IN ('TERMINADO','APROBADO')
   ) THEN RAISE EXCEPTION 'CREATIVE_DEPENDENCY_NOT_APPROVED'; END IF;
   v_run_id:=NEW.qa_receipt->>'run_id';
   IF v_run_id IS NULL OR v_run_id !~ '^[0-9]+$'
      OR (NEW.qa_receipt->>'verdict') IS DISTINCT FROM 'PASS'
      OR jsonb_typeof(NEW.qa_receipt->'reviewer_ref') IS DISTINCT FROM 'string'
      OR nullif(btrim(NEW.qa_receipt->>'reviewer_ref'),'') IS NULL
   THEN RAISE EXCEPTION 'CREATIVE_QA_RECEIPT_MISSING'; END IF;
   SELECT r.id,r.worker_ref,r.input_snapshot,r.output_evidence INTO v_run
   FROM saly.creative_runs r
   WHERE r.id=v_run_id::bigint AND r.item_id=NEW.id AND r.order_id=NEW.order_id
     AND r.state='EXITOSO' AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
       WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number);
   IF NEW.status='TERMINADO' AND NOT EXISTS (
     SELECT 1 FROM saly.creative_run_detection_v1 d
     WHERE d.run_id=v_run_id::bigint AND d.item_id=NEW.id AND d.order_id=NEW.order_id
       AND d.artifact_sha256=v_run.output_evidence->>'sha256'
   ) THEN RAISE EXCEPTION 'SALY_ITEM_TERMINADO_REQUIRES_TIMER_DETECTION'; END IF;
   IF NOT FOUND OR (lower(btrim(NEW.qa_receipt->>'reviewer_ref'))=lower(btrim(v_run.worker_ref)) AND NEW.qa_receipt->>'review_mode' IS DISTINCT FROM 'GPT_SELF_QA')
      OR (NEW.status='TERMINADO' AND (NEW.approved_by IS NOT NULL OR NEW.approved_at IS NOT NULL))
      OR (NEW.status='APROBADO' AND NEW.approved_by IS DISTINCT FROM NEW.qa_receipt->>'reviewer_ref')
   THEN RAISE EXCEPTION 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING'; END IF;
   IF NEW.qa_receipt->>'review_mode'='GPT_SELF_QA' THEN
     IF NEW.status<>'TERMINADO'
       OR lower(btrim(NEW.qa_receipt->>'reviewer_ref')) IS DISTINCT FROM lower(btrim(v_run.worker_ref))
       OR NEW.qa_receipt->'semantic_independence_proven' IS DISTINCT FROM 'false'::jsonb
       OR NEW.qa_receipt->>'artifact_sha256' IS DISTINCT FROM v_run.output_evidence->>'sha256'
       OR jsonb_typeof(NEW.acceptance_json->'qa_checklist') IS DISTINCT FROM 'object'
       OR NEW.acceptance_json->'qa_checklist'='{}'::jsonb
       OR jsonb_typeof(NEW.qa_receipt->'checklist_results') IS DISTINCT FROM 'object'
       OR EXISTS (SELECT 1 FROM jsonb_object_keys(NEW.acceptance_json->'qa_checklist') AS k(code)
          WHERE NEW.qa_receipt#>>ARRAY['checklist_results',k.code,'verdict'] IS DISTINCT FROM 'PASS'
          OR nullif(btrim(NEW.qa_receipt#>>ARRAY['checklist_results',k.code,'evidence']),'') IS NULL)
       OR jsonb_typeof(NEW.qa_receipt->'preflight') IS DISTINCT FROM 'object'
       OR NEW.qa_receipt#>>'{preflight,verdict}' IS DISTINCT FROM 'PASS'
       OR nullif(btrim(NEW.qa_receipt#>>'{preflight,evidence}'),'') IS NULL
     THEN RAISE EXCEPTION 'CREATIVE_SELF_QA_CHECKLIST_INCOMPLETE'; END IF;
   END IF;
   IF NEW.qa_receipt->>'review_mode'='GPT_SELF_QA' THEN
     IF NEW.acceptance_json ? 'design_qa_v1' THEN
       IF jsonb_typeof(NEW.qa_receipt->'design_qa_v1') IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM jsonb_object_keys(NEW.acceptance_json->'design_qa_v1') k(code)
            WHERE coalesce(NEW.qa_receipt#>>ARRAY['design_qa_v1',k.code,'score'],'') NOT IN ('0','1')
             OR nullif(btrim(NEW.qa_receipt#>>ARRAY['design_qa_v1',k.code,'evidence']),'') IS NULL)
          OR (SELECT count(*) FROM jsonb_object_keys(NEW.acceptance_json->'design_qa_v1') k(code)
              WHERE NEW.qa_receipt#>>ARRAY['design_qa_v1',k.code,'score']='1')<5
       THEN RAISE EXCEPTION 'CREATIVE_DESIGN_QA_INCOMPLETE'; END IF;
     END IF;
   END IF;
   IF NEW.acceptance_json ? 'semantic_qa' THEN
     IF v_run.input_snapshot#>'{visual_contract,qa_checks}' IS DISTINCT FROM
        saly.creative_item_visual_contract_l3b(NEW.id)#>'{contract,qa_checks}'
     THEN RAISE EXCEPTION 'CREATIVE_TECHNICAL_CHECK_EXPECTATIONS_MISMATCH'; END IF;
     PERFORM saly.creative_assert_dual_qa_l3c(
        NEW.acceptance_json,NEW.qa_receipt,v_run.input_snapshot,v_run.output_evidence);
   END IF;
 END IF;
 RETURN NEW;
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_queue_release_v1(p_token uuid, p_outcome text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_claim record; v_now timestamptz; v_item_status text; v_closed boolean:=false;
BEGIN
  IF p_token IS NULL OR p_outcome NOT IN ('DONE','FAILED','BLOCKED')
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=v_now
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;

  SELECT status INTO v_item_status FROM saly.creative_order_items
  WHERE id=v_claim.item_id AND order_id=v_claim.order_id FOR UPDATE;
  IF p_outcome='DONE' THEN
    -- Internal QA is obligatory; human creative approval is not.
    IF v_item_status<>'TERMINADO' OR NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=v_claim.item_id AND r.order_id=v_claim.order_id
        AND r.state='EXITOSO' AND r.queue_claim_id=v_claim.id
        AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
        AND nullif(r.output_evidence->>'worker_receipt','') IS NOT NULL
        AND r.output_evidence->>'sha256' ~ '^[0-9a-f]{64}$'
        AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
                        WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number)
        AND EXISTS (
          SELECT 1 FROM saly.creative_run_detection_v1 d
          WHERE d.claim_id=v_claim.id AND d.run_id=r.id
            AND d.order_id=v_claim.order_id AND d.item_id=v_claim.item_id
            AND d.artifact_ref=r.output_evidence->>'artifact_ref'
            AND d.artifact_sha256=r.output_evidence->>'sha256'
            AND d.check_count BETWEEN 1 AND 7
            AND d.first_ready_elapsed_seconds=30*(d.check_count-1)
        )
    ) THEN RAISE EXCEPTION 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED'; END IF;
  ELSE
    IF v_item_status<>'BLOQUEADO'
    THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FAILURE_NOT_BLOCKED'; END IF;
  END IF;

  IF p_outcome='DONE' AND EXISTS (SELECT 1 FROM saly.creative_orders o WHERE o.id=v_claim.order_id AND o.project_id=2 AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1' AND o.scope_json->>'module'='Solicitar adelanto') AND NOT EXISTS (SELECT 1 FROM saly.creative_order_items i WHERE i.id=v_claim.item_id AND i.qa_receipt->>'review_mode'='GPT_SELF_QA') THEN RAISE EXCEPTION 'CREATIVE_SERIAL_SELF_QA_REQUIRED'; END IF;
  UPDATE saly.creative_queue_claims_v1
  SET state=p_outcome, finished_at=v_now, note=left(p_note,1000)
  WHERE id=v_claim.id;

  IF p_outcome='DONE' AND NOT EXISTS (
    SELECT 1 FROM saly.creative_order_items i
    WHERE i.order_id=v_claim.order_id
      AND (i.status NOT IN ('TERMINADO','APROBADO') AND (i.required OR i.status<>'OMITIDO'))
  ) AND EXISTS (
    SELECT 1 FROM saly.creative_order_items i
    WHERE i.order_id=v_claim.order_id AND i.required
  ) THEN
    UPDATE saly.creative_orders
      SET status=CASE WHEN request_kind='APP_SCREEN_SINGLE'
            THEN 'TERMINADO' ELSE 'COMPLETADO' END, completed_at=v_now
      WHERE id=v_claim.order_id AND status IN ('PLANIFICADO','EN_PROCESO','EN_QA');
    v_closed := FOUND;
  END IF;
  IF p_outcome='DONE' AND NOT v_closed AND EXISTS (
     SELECT 1 FROM saly.creative_orders
     WHERE id=v_claim.order_id AND request_kind='APP_SCREEN_SINGLE')
  THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_DID_NOT_TERMINATE'; END IF;
  RETURN jsonb_build_object('status','RELEASED','result',p_outcome,
    'claim_id',v_claim.id,'order_closed',v_closed);
END $function$;
UPDATE saly.creative_orders SET scope_json=scope_json||'{"queue_mode":"SERIAL_V1","rendering_authority":true,"render_authorized":true}'::jsonb WHERE id BETWEEN 11 AND 21 AND project_id=2 AND context_set_id=5 AND status='PLANIFICADO' AND code LIKE 'SALY_SOLICITAR_ADELANTO_%_20261124';
UPDATE saly.creative_order_items i SET acceptance_json=acceptance_json||jsonb_build_object('design_qa_v1','{"visual_anchor":true,"single_hero":true,"semantic_active_colors_min_2":true,"balanced_space":true,"cta_anchored_or_not_applicable":true,"max_3_accents":true}'::jsonb) FROM saly.creative_orders o WHERE o.id=i.order_id AND o.id BETWEEN 11 AND 21 AND o.project_id=2 AND o.context_set_id=5 AND o.code LIKE 'SALY_SOLICITAR_ADELANTO_%_20261124' AND i.status='PENDIENTE';
COMMIT;
