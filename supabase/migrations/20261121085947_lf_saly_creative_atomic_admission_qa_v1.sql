BEGIN;
DO $pre$ BEGIN
 IF md5(pg_get_functiondef('saly.creative_run_guard_l1()'::regprocedure))<>'9cb8e9813df4297f99f0ac862c38619c' THEN RAISE EXCEPTION 'CREATIVE_ATOMIC_BASE_CHANGED:creative_run_guard_l1'; END IF;
 IF md5(pg_get_functiondef('saly.creative_assert_dual_qa_l3c(jsonb,jsonb,jsonb,jsonb)'::regprocedure))<>'a2fdfb50b0ab1d1252f1d79b32882a3f' THEN RAISE EXCEPTION 'CREATIVE_ATOMIC_BASE_CHANGED:creative_assert_dual_qa_l3c'; END IF;
 IF md5(pg_get_functiondef('saly.creative_item_guard_l1()'::regprocedure))<>'c646bbd249b46ec043449d202d1b642b' THEN RAISE EXCEPTION 'CREATIVE_ATOMIC_BASE_CHANGED:creative_item_guard_l1'; END IF;
 IF md5(pg_get_functiondef('saly.creative_order_close_guard_l1()'::regprocedure))<>'e96efb3bdb25fc2fd371e69a34a9bd9c' THEN RAISE EXCEPTION 'CREATIVE_ATOMIC_BASE_CHANGED:creative_order_close_guard_l1'; END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_runs) THEN RAISE EXCEPTION 'CREATIVE_ATOMIC_EXISTING_RUNS'; END IF;
END $pre$;

-- Canonical comparison with the existing authorities, not another compiler.
-- This check does not grant rendering, and does not accept TEMPLATE_REVIEW.
CREATE FUNCTION saly.creative_assert_run_snapshot_v1(p_item bigint,p_snapshot jsonb)
RETURNS void LANGUAGE plpgsql STABLE SET search_path TO pg_catalog,saly,pg_temp AS $fn$
DECLARE pkt jsonb; visual jsonb; expected jsonb;
BEGIN
 pkt:=saly.creative_item_work_packet_l2c(p_item);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF'
 OR jsonb_typeof(pkt->'input_snapshot') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_SNAPSHOT_NOT_READY'; END IF;
 visual:=saly.creative_item_visual_contract_l3b(p_item);
 expected:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',visual->'contract','visual_contract_sha256',visual->>'contract_sha256');
 IF p_snapshot IS DISTINCT FROM expected THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_NOT_CANONICAL'; END IF;
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_assert_run_snapshot_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb; v_next_attempt bigint; v_now timestamptz; v_policy jsonb; v_acceptance jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
   THEN RAISE EXCEPTION 'CREATIVE_TERMINAL_RUN_IMMUTABLE'; END IF;
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
      OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
   THEN RAISE EXCEPTION 'CREATIVE_RUN_BINDING_IMMUTABLE'; END IF;
   IF NEW.input_snapshot IS DISTINCT FROM OLD.input_snapshot
   THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_IMMUTABLE'; END IF;
   IF NEW.execution_policy IS DISTINCT FROM OLD.execution_policy
      OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_IMMUTABLE'; END IF;
   IF OLD.state='EJECUTANDO' AND (NEW.worker_ref IS DISTINCT FROM OLD.worker_ref
      OR NEW.started_at IS DISTINCT FROM OLD.started_at)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_IMMUTABLE'; END IF;
   IF NEW.state<>OLD.state
     AND NOT ((OLD.state='EN_COLA' AND NEW.state IN ('EJECUTANDO','BLOQUEADO','CANCELADO'))
       OR (OLD.state='EJECUTANDO' AND NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_INVALID_TRANSITION'; END IF;
 END IF;
 -- Only admissions contend on the queue capacity lock.
 IF TG_OP='INSERT' THEN
   -- A transaction-wide stale snapshot cannot enforce an aggregate queue cap.
   IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted')
   THEN RAISE EXCEPTION 'CREATIVE_ADMISSION_REQUIRES_READ_COMMITTED'; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('saly.creative_runs:queue_capacity',0));
 END IF;
 SELECT i.status,o.status,o.scope_json,i.acceptance_json INTO v_item_status,v_order_status,v_scope,v_acceptance
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i,o;
 -- Measure time only after waiting for the actual admission and parent locks.
 v_now:=clock_timestamp();
 IF v_item_status IS NULL OR
    ((v_item_status IN ('APROBADO','OMITIDO') OR v_order_status IN ('COMPLETADO','CANCELADO'))
     AND (TG_OP='INSERT' OR NEW.state NOT IN ('FALLIDO','BLOQUEADO','CANCELADO')))
 THEN RAISE EXCEPTION 'CREATIVE_RUN_ITEM_NOT_ELIGIBLE'; END IF;
 -- Review-only and explicitly disabled orders cannot enter or progress render.
 -- Permit cancellation/failure of an existing run so a revoked order can stop.
 IF (TG_OP='INSERT' OR NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 AND (v_scope->'review_only'='true'::jsonb
   OR (v_scope ? 'render_authorized' AND v_scope->'render_authorized' IS DISTINCT FROM 'true'::jsonb)
   OR (v_scope ? 'rendering_authority' AND v_scope->'rendering_authority' IS DISTINCT FROM 'true'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_NOT_AUTHORIZED'; END IF;
 -- The existing item row lock serializes attempt admission; existing unique
 -- indexes remain the authoritative idempotency and single-active constraints.
 IF TG_OP='INSERT' THEN
   IF NEW.state IS DISTINCT FROM 'EN_COLA' THEN RAISE EXCEPTION 'CREATIVE_RUN_INITIAL_STATE'; END IF;
   SELECT coalesce(max(attempt_number)::bigint,0)+1 INTO v_next_attempt
   FROM saly.creative_runs WHERE item_id=NEW.item_id;
   IF NEW.attempt_number IS DISTINCT FROM v_next_attempt
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_OUT_OF_SEQUENCE'; END IF;
   v_policy:=saly.creative_execution_policy_v1(v_now);
   IF NEW.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_LIMIT'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND idempotency_key=NEW.idempotency_key)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_IDEMPOTENCY_REPLAY'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ALREADY_ACTIVE'; END IF;
   IF (SELECT count(*) FROM saly.creative_runs WHERE state='EN_COLA') >= (v_policy->>'QUEUE_MAX')::integer
   THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FULL'; END IF;
   -- Legacy items without a semantic contract retain the existing behavior.
   -- A sealed semantic item cannot enter with a substitute contract or snapshot.
   IF v_acceptance ? 'semantic_qa' THEN
     PERFORM saly.creative_assert_run_snapshot_v1(NEW.item_id,NEW.input_snapshot);
   END IF;
   NEW.execution_policy:=v_policy;
   NEW.deadline_at:=v_now+make_interval(secs=>(v_policy->>'QUEUE_TIMEOUT_SECONDS')::integer);
   NEW.started_at:=NULL;
   NEW.finished_at:=NULL;
 ELSE
   IF NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO') AND OLD.deadline_at<=v_now
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_EXPIRED'; END IF;
   IF OLD.state='EN_COLA' AND NEW.state='EJECUTANDO' THEN
     IF nullif(btrim(NEW.worker_ref),'') IS NULL THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_REQUIRED'; END IF;
     NEW.started_at:=v_now;
     NEW.deadline_at:=v_now+make_interval(secs=>(OLD.execution_policy->>'LEASE_SECONDS')::integer);
   ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
     RAISE EXCEPTION 'CREATIVE_RUN_STARTED_AT_IMMUTABLE';
   END IF;
   IF NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO') THEN NEW.finished_at:=v_now; END IF;
 END IF;
 RETURN NEW;
END $function$;
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
 IF NEW.status='APROBADO' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF TG_OP='INSERT' OR OLD.status<>'EN_QA'
   THEN RAISE EXCEPTION 'CREATIVE_ITEM_NOT_IN_QA'; END IF;
   IF EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id AND prereq.status<>'APROBADO'
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
   IF NOT FOUND OR lower(btrim(NEW.qa_receipt->>'reviewer_ref'))=lower(btrim(v_run.worker_ref))
      OR NEW.approved_by IS DISTINCT FROM NEW.qa_receipt->>'reviewer_ref'
   THEN RAISE EXCEPTION 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING'; END IF;
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
CREATE OR REPLACE FUNCTION saly.creative_order_close_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
 IF NEW.status='COMPLETADO' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF EXISTS(SELECT 1 FROM saly.creative_runs r WHERE r.order_id=NEW.id
      AND r.state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_ORDER_CLOSURE_WITH_ACTIVE_RUNS'; END IF;
   IF NOT EXISTS (SELECT 1 FROM saly.creative_order_items i
                  WHERE i.order_id=NEW.id AND i.required)
      OR EXISTS (SELECT 1 FROM saly.creative_order_items i WHERE i.order_id=NEW.id
                 AND (i.status NOT IN ('APROBADO','OMITIDO')
                  OR (i.required AND i.status<>'APROBADO')))
   THEN RAISE EXCEPTION 'CREATIVE_ORDER_CLOSURE_WITH_INCOMPLETE_DETAILS'; END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status='COMPLETADO'
 THEN RAISE EXCEPTION 'CREATIVE_COMPLETED_ORDER_IMMUTABLE'; END IF;
 RETURN NEW;
END $function$;

-- Tests from the two actual sealed contracts. Receipts are fixtures, never provider proof.
DO $test$
DECLARE pkt jsonb; vc jsonb; snap jsonb; s jsonb; a jsonb; sem jsonb; receipt jsonb; outp jsonb;
 c record; n int:=0; o bigint; i bigint; r bigint; ctx record; t timestamptz;
BEGIN
 pkt:=saly.creative_item_work_packet_l2c(5);
 vc:=saly.creative_item_visual_contract_l3b(5);
 snap:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',vc->'contract','visual_contract_sha256',vc->>'contract_sha256');
 PERFORM saly.creative_assert_run_snapshot_v1(5,snap);
 FOR c IN SELECT * FROM (VALUES
   (5::bigint,snap-'visual_contract_sha256','CREATIVE_RUN_SNAPSHOT_NOT_CANONICAL'),
   (5::bigint,jsonb_set(snap,'{visual_contract,qa_verdict}','"PASS"'),'CREATIVE_RUN_SNAPSHOT_NOT_CANONICAL'),
   (5::bigint,snap||'{"unexpected":true}','CREATIVE_RUN_SNAPSHOT_NOT_CANONICAL'),
   (5::bigint,jsonb_set(snap,'{item_id}','6'),'CREATIVE_RUN_SNAPSHOT_NOT_CANONICAL'),
   (6::bigint,snap,'CREATIVE_SNAPSHOT_NOT_READY'),
   (9::bigint,snap,'CREATIVE_SNAPSHOT_NOT_READY')
 ) x(id,v,err) LOOP
   BEGIN
     PERFORM saly.creative_assert_run_snapshot_v1(c.id,c.v);
     RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>c.err THEN RAISE; END IF; n:=n+1; END;
 END LOOP;
 FOR c IN SELECT id,CASE WHEN id=5 THEN vc->'contract'
   ELSE context_json#>'{preflight_review,contract}' END AS contract
   FROM saly.creative_order_items WHERE id IN (5,9) ORDER BY id LOOP
   a:=c.contract->'acceptance_criteria'; sem:=a->'semantic_qa';
   s:=jsonb_build_object('visual_contract',c.contract,'visual_contract_sha256',
      encode(extensions.digest(convert_to(c.contract::text,'UTF8'),'sha256'),'hex'));
   outp:=jsonb_build_object('artifact_ref','TEST_ONLY','sha256',repeat('a',64));
   receipt:=jsonb_build_object('contract_sha256',s->>'visual_contract_sha256','artifact_ref','TEST_ONLY','artifact_sha256',repeat('a',64),
    'semantic_qa',jsonb_build_object('verdict','PASS','original_request_sha256',sem->>'original_request_sha256',
      'semantic_contract_sha256',encode(extensions.digest(convert_to(sem::text,'UTF8'),'sha256'),'hex'),
      'independent_interpretation','TEST_ONLY',
      'checks',(SELECT jsonb_agg(jsonb_build_object('code',x->>'code','verdict','PASS','evidence','TEST_ONLY')) FROM jsonb_array_elements(sem->'checks') x)),
    'technical_qa',jsonb_build_object('verdict','PASS',
      'checks',(SELECT jsonb_agg(jsonb_build_object('code',x->>'code','verdict','PASS','evidence','TEST_ONLY')) FROM jsonb_array_elements(c.contract->'qa_checks') x)));
   PERFORM saly.creative_assert_dual_qa_l3c(a,receipt,s,outp);
   BEGIN
      PERFORM saly.creative_assert_dual_qa_l3c(a,jsonb_set(receipt,'{semantic_qa,independent_interpretation}','{}'),s,outp);
      RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_SEMANTIC_REVIEW_MISSING' THEN RAISE; END IF; n:=n+1; END;
   BEGIN
      PERFORM saly.creative_assert_dual_qa_l3c(a,jsonb_set(receipt,'{technical_qa,checks,0,evidence}','true'),s,outp);
      RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_DUAL_QA_CHECK_FAILED_OR_MISSING' THEN RAISE; END IF; n:=n+1; END;
   BEGIN
      PERFORM saly.creative_assert_dual_qa_l3c(a,jsonb_set(receipt,'{semantic_qa,checks,0,evidence}','{"claimed":true}'),s,outp);
      RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_DUAL_QA_CHECK_FAILED_OR_MISSING' THEN RAISE; END IF; n:=n+1; END;
   BEGIN
      PERFORM saly.creative_assert_dual_qa_l3c(a,jsonb_set(receipt,'{artifact_sha256}',to_jsonb(repeat('b',64))),s,outp);
      RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_DUAL_QA_ARTIFACT_OR_HASH_MISMATCH' THEN RAISE; END IF; n:=n+1; END;
   BEGIN
      PERFORM saly.creative_assert_dual_qa_l3c(a,receipt,s,'[]');
      RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_DUAL_QA_INPUT_SHAPE' THEN RAISE; END IF; n:=n+1; END;
 END LOOP;
 -- End-to-end guard, synthetic run and policy; no production rendering or approval.
 SELECT id,project_id,mode INTO STRICT ctx FROM saly.creative_context_sets WHERE state='SEALED' ORDER BY id LIMIT 1;
 SELECT least(coalesce(min(id),0),0)-1 INTO o FROM saly.creative_orders;
 SELECT least(coalesce(min(id),0),0)-1 INTO i FROM saly.creative_order_items;
 SELECT least(coalesce(min(id),0),0)-1 INTO r FROM saly.creative_runs;
 BEGIN
  t:=clock_timestamp();
  INSERT INTO saly.config_global(scope,config_key,config_value,value_type,value_status,valid_from,description)
  SELECT 'CREATIVE_FACTORY',k,v,'INTEGER','REAL',t,'TEST_ONLY rolled back'
  FROM (VALUES('QUEUE_MAX','2'),('MAX_ATTEMPTS','2'),('QUEUE_TIMEOUT_SECONDS','20'),('LEASE_SECONDS','20')) z(k,v);
  INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,requested_by,design_mode,context_set_id,scope_json,status)
  VALUES(o,ctx.project_id,'TEST-ATOMIC-'||pg_current_xact_id()::text,'TEST-ATOMIC-'||pg_current_xact_id()::text,
    'Synthetic atomic fixture','TEST_ONLY',ctx.mode,ctx.id,'{"render_authorized":true}','PLANIFICADO');
  INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,status)
  VALUES(i,o,'TEST_ATOMIC',1,'SCREEN','Synthetic','PENDIENTE');
  INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key) VALUES(r,o,i,1,'test1');
  BEGIN
   UPDATE saly.creative_orders SET status='COMPLETADO',completed_at=clock_timestamp() WHERE id=o;
   RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_ORDER_CLOSURE_WITH_ACTIVE_RUNS' THEN RAISE; END IF; n:=n+1; END;
  UPDATE saly.creative_orders SET status='CANCELADO' WHERE id=o;
  BEGIN
   UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref='TEST_ONLY' WHERE id=r;
   RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_RUN_ITEM_NOT_ELIGIBLE' THEN RAISE; END IF; n:=n+1; END;
  UPDATE saly.creative_runs SET state='CANCELADO' WHERE id=r;
  IF NOT EXISTS(SELECT 1 FROM saly.creative_runs WHERE id=r AND state='CANCELADO' AND finished_at IS NOT NULL)
  THEN RAISE EXCEPTION 'TEST_CANCEL_FAILED'; END IF;
  RAISE EXCEPTION 'ATOMIC_FIXTURE_ROLLBACK';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ATOMIC_FIXTURE_ROLLBACK' THEN RAISE; END IF;
 END;
 IF n<>18 OR EXISTS(SELECT 1 FROM saly.creative_orders WHERE id=o)
 OR EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=i)
 OR EXISTS(SELECT 1 FROM saly.creative_runs)
 OR EXISTS(SELECT 1 FROM saly.config_global WHERE scope='CREATIVE_FACTORY')
 OR EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id IN(5,6,7,8,9) AND (status<>'PENDIENTE' OR qa_receipt<>'{}'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_ATOMIC_TEST_OR_ROLLBACK_FAILED:%',n; END IF;
 IF has_function_privilege('service_role','saly.creative_assert_run_snapshot_v1(bigint,jsonb)','EXECUTE')
 OR has_function_privilege('anon','saly.creative_assert_run_snapshot_v1(bigint,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_assert_run_snapshot_v1(bigint,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'CREATIVE_ATOMIC_ACL_DRIFT'; END IF;
 RAISE NOTICE 'CREATIVE_ATOMIC: 3 positive contract fixtures; 18 specific negatives; cancelled run terminal; zero persisted runs, QA or configuration';
END $test$;
COMMIT;
