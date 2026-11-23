-- Disposable PostgreSQL 17 compatibility harness.
-- Includes function bodies transcribed from Supabase readback (2026-11-22)
-- for creative_run_guard_l1, creative_item_guard_l1, creative_order_close_guard_l1,
-- and creative_execution_policy_v1. Not byte-for-byte authoritative, and not a
-- full Supabase schema clone. Never use this fixture as a production migration.
\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS saly CASCADE;
CREATE SCHEMA saly;
CREATE SEQUENCE saly.creative_runs_id_seq;
CREATE TABLE saly.config_global (
 scope text NOT NULL, config_key text NOT NULL, config_value text NOT NULL,
 value_type text NOT NULL,value_status text NOT NULL,valid_from timestamptz NOT NULL,
 PRIMARY KEY(scope,config_key,valid_from));
INSERT INTO saly.config_global VALUES
 ('CREATIVE_FACTORY','QUEUE_MAX','5','INTEGER','REAL','2025-01-01'),
 ('CREATIVE_FACTORY','MAX_ATTEMPTS','3','INTEGER','REAL','2025-01-01'),
 ('CREATIVE_FACTORY','QUEUE_TIMEOUT_SECONDS','300','INTEGER','REAL','2025-01-01'),
 ('CREATIVE_FACTORY','LEASE_SECONDS','600','INTEGER','REAL','2025-01-01');
CREATE TABLE saly.creative_orders (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, code text NOT NULL,
 status text NOT NULL, scope_json jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), completed_at timestamptz);
CREATE TABLE saly.creative_order_items (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL REFERENCES saly.creative_orders(id),
 code text NOT NULL, ordinal integer NOT NULL, status text NOT NULL,
 required boolean NOT NULL DEFAULT true,
 acceptance_json jsonb NOT NULL DEFAULT '{"qa_required":true}'::jsonb,
 context_json jsonb NOT NULL DEFAULT '{}'::jsonb,
 qa_receipt jsonb NOT NULL DEFAULT '{}'::jsonb,
 approved_at timestamptz, approved_by text);
CREATE TABLE saly.creative_runs (
 id bigint PRIMARY KEY DEFAULT nextval('saly.creative_runs_id_seq'::regclass),
 order_id bigint NOT NULL, item_id bigint NOT NULL,
 attempt_number integer NOT NULL,idempotency_key text NOT NULL,
 state text NOT NULL DEFAULT 'EN_COLA',worker_ref text,
 input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
 output_evidence jsonb NOT NULL DEFAULT '{}'::jsonb,error_code text,
 started_at timestamptz,finished_at timestamptz,
 created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),
 execution_policy jsonb NOT NULL DEFAULT '{}'::jsonb,deadline_at timestamptz,
 CONSTRAINT creative_run_success_chk CHECK (
   state <> 'EXITOSO' OR
   (started_at IS NOT NULL AND nullif(btrim(worker_ref),'') IS NOT NULL
    AND jsonb_typeof(input_snapshot->'identity_versions')='array'
    AND jsonb_array_length(input_snapshot->'identity_versions')>0
    AND jsonb_typeof(input_snapshot->'source_refs')='array'
    AND input_snapshot ? 'screen_spec'
    AND nullif(output_evidence->>'artifact_ref','') IS NOT NULL
    AND output_evidence->>'sha256' ~ '^[0-9a-f]{64}$'
    AND nullif(output_evidence->>'worker_receipt','') IS NOT NULL)),
 CONSTRAINT creative_run_terminal_chk CHECK
  ((state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')) = (finished_at IS NOT NULL)),
 UNIQUE(item_id,attempt_number),UNIQUE(item_id,idempotency_key));
CREATE UNIQUE INDEX creative_runs_one_active_per_item ON saly.creative_runs(item_id)
 WHERE state IN ('EN_COLA','EJECUTANDO');
CREATE TABLE saly.creative_item_dependencies (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL, item_id bigint NOT NULL, depends_on_item_id bigint NOT NULL);

CREATE OR REPLACE FUNCTION saly.creative_execution_policy_v1(p_asof timestamp with time zone)
 RETURNS jsonb LANGUAGE plpgsql STABLE
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE k text; c record; result jsonb:='{}'; pins jsonb:='{}';
BEGIN
 IF p_asof IS NULL THEN RAISE EXCEPTION 'CREATIVE_CONFIG_ASOF_REQUIRED'; END IF;
 FOREACH k IN ARRAY ARRAY['QUEUE_MAX','MAX_ATTEMPTS','QUEUE_TIMEOUT_SECONDS','LEASE_SECONDS'] LOOP
   SELECT config_value,value_type,value_status,valid_from INTO c FROM saly.config_global
   WHERE scope='CREATIVE_FACTORY' AND config_key=k AND valid_from<=p_asof
   ORDER BY valid_from DESC LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CONFIG_MISSING:%',k; END IF;
   IF c.value_type<>'INTEGER' OR c.value_status<>'REAL' OR c.config_value !~ '^[1-9][0-9]*$'
   THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   IF c.config_value::numeric>2147483647 THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   result:=result||jsonb_build_object(k,c.config_value::integer);
   pins:=pins||jsonb_build_object(k,c.valid_from);
 END LOOP;
 RETURN result||jsonb_build_object('schema_version','CREATIVE_EXECUTION_POLICY_V1','config_scope','CREATIVE_FACTORY','versions',pins);
END $function$;

-- Real production function body from Supabase readback.
CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger LANGUAGE plpgsql
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
 IF TG_OP='INSERT' THEN
   IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted')
   THEN RAISE EXCEPTION 'CREATIVE_ADMISSION_REQUIRES_READ_COMMITTED'; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('saly.creative_runs:queue_capacity',0));
 END IF;
 SELECT i.status,o.status,o.scope_json,i.acceptance_json INTO v_item_status,v_order_status,v_scope,v_acceptance
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i,o;
 v_now:=clock_timestamp();
 IF v_item_status IS NULL OR
    ((v_item_status IN ('APROBADO','OMITIDO') OR v_order_status IN ('COMPLETADO','CANCELADO'))
     AND (TG_OP='INSERT' OR NEW.state NOT IN ('FALLIDO','BLOQUEADO','CANCELADO')))
 THEN RAISE EXCEPTION 'CREATIVE_RUN_ITEM_NOT_ELIGIBLE'; END IF;
 IF (TG_OP='INSERT' OR NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 AND (v_scope->'review_only'='true'::jsonb
   OR (v_scope ? 'render_authorized' AND v_scope->'render_authorized' IS DISTINCT FROM 'true'::jsonb)
   OR (v_scope ? 'rendering_authority' AND v_scope->'rendering_authority' IS DISTINCT FROM 'true'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_NOT_AUTHORIZED'; END IF;
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
CREATE TRIGGER trg_creative_run_guard_l1
BEFORE INSERT OR UPDATE ON saly.creative_runs
FOR EACH ROW EXECUTE FUNCTION saly.creative_run_guard_l1();

-- Real production function body from Supabase readback.
CREATE OR REPLACE FUNCTION saly.creative_item_guard_l1()
 RETURNS trigger LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_order_status text; v_run record; v_run_id text;
BEGIN
 SELECT status INTO v_order_status FROM saly.creative_orders WHERE id=NEW.order_id FOR UPDATE;
 IF v_order_status IN ('COMPLETADO','CANCELADO')
 THEN RAISE EXCEPTION 'CREATIVE_CLOSED_ORDER_IMMUTABLE_ITEMS'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='APROBADO'
 THEN RAISE EXCEPTION 'CREATIVE_APPROVED_ITEM_IMMUTABLE'; END IF;
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
CREATE TRIGGER trg_creative_item_guard_l1
BEFORE INSERT OR UPDATE ON saly.creative_order_items
FOR EACH ROW EXECUTE FUNCTION saly.creative_item_guard_l1();

-- Real production function body from Supabase readback.
CREATE OR REPLACE FUNCTION saly.creative_order_close_guard_l1()
 RETURNS trigger LANGUAGE plpgsql
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
CREATE TRIGGER trg_creative_order_close_guard_l1
BEFORE INSERT OR UPDATE ON saly.creative_orders
FOR EACH ROW EXECUTE FUNCTION saly.creative_order_close_guard_l1();


-- Real SALY single-screen order fields and predecessor model (PR #4648).
ALTER TABLE saly.creative_orders ADD COLUMN request_kind text NOT NULL DEFAULT 'APP_SCREEN_BATCH';
CREATE TABLE saly.creative_order_sequence_v1(
 order_id bigint PRIMARY KEY REFERENCES saly.creative_orders(id),
 depends_on_order_id bigint UNIQUE NOT NULL REFERENCES saly.creative_orders(id));
CREATE FUNCTION saly.creative_order_sequence_dependency_met_v1(p_order_id bigint)
RETURNS boolean LANGUAGE sql STABLE
AS $fn$
 SELECT EXISTS(SELECT 1 FROM saly.creative_orders o
 WHERE o.id=p_order_id AND o.request_kind='APP_SCREEN_SINGLE'
 AND NOT EXISTS(
   SELECT 1 FROM saly.creative_order_sequence_v1 s
   JOIN saly.creative_orders prior ON prior.id=s.depends_on_order_id
   WHERE s.order_id=o.id AND prior.status<>'TERMINADO'));
$fn$;
-- The production seed has two independently sealed contexts; the fixture models
-- only the queue-relevant order statuses and no real customer assets.
INSERT INTO saly.creative_orders(code,status,scope_json,request_kind,created_at)
VALUES
('SALY_HOME_V015_SINGLE_20261123','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","review_only":true,"render_authorized":false,"rendering_authority":false}'::jsonb,
 'APP_SCREEN_SINGLE','2026-11-23T01:00:00Z'),
('SALY_ADELANTO_V015_SINGLE_20261123','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","review_only":true,"render_authorized":false,"rendering_authority":false}'::jsonb,
 'APP_SCREEN_SINGLE','2026-11-23T02:00:00Z');
INSERT INTO saly.creative_order_items(order_id,code,ordinal,status)
SELECT id,CASE WHEN code='SALY_HOME_V015_SINGLE_20261123' THEN 'HOME'
               ELSE 'SOLICITAR_ADELANTO' END,1,'PENDIENTE'
FROM saly.creative_orders WHERE request_kind='APP_SCREEN_SINGLE';
INSERT INTO saly.creative_order_sequence_v1(order_id,depends_on_order_id)
SELECT next.id,prior.id FROM saly.creative_orders next
CROSS JOIN saly.creative_orders prior
WHERE next.code='SALY_ADELANTO_V015_SINGLE_20261123'
 AND prior.code='SALY_HOME_V015_SINGLE_20261123';

-- Legacy batch fixture must not be modified by the opt-in new queue.
INSERT INTO saly.creative_orders(code,status,scope_json,request_kind,created_at)
VALUES('LEGACY_BATCH_QUEUE_TEST','PLANIFICADO','{}','APP_SCREEN_BATCH','2026-11-20T00:00:00Z');
INSERT INTO saly.creative_order_items(order_id,code,ordinal,status)
SELECT id,'LEGACY_SCREEN',1,'PENDIENTE'
FROM saly.creative_orders WHERE code='LEGACY_BATCH_QUEUE_TEST';
