-- SALY V17: Private idempotent pre-dispatch reservation (NOT actual Native).
-- Governed route. No grant, no RUN, no activation of user orders.
-- Candidate V10 pinned to main blob 5567374b2ed4a35b4d139b2e0079d0f9b4892cef. Existing V14/V15/V16 are prerequisites.
BEGIN;
DO $prelive$
BEGIN
 IF to_regprocedure('saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)') IS NULL
 OR to_regprocedure('saly.creative_native_render_wire_v1(uuid,bigint,text)') IS NULL
 OR to_regclass('saly.creative_queue_native_delivery_evidence_v1') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_V17_REQUIRED_RUNTIME_NOT_PRESENT'; END IF;
 IF (SELECT count(*) FROM saly.creative_orders
  WHERE code IN ('SALY_HOME_V015_SINGLE_20261123',
                 'SALY_ADELANTO_V015_SINGLE_20261123')
  AND status='PLANIFICADO'
  AND scope_json->>'render_authorized'='false'
  AND scope_json->>'review_only'='true')<>2
 THEN RAISE EXCEPTION 'CREATIVE_V17_USER_ORDERS_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_runs)
 OR EXISTS(SELECT 1 FROM saly.creative_queue_claims_v1)
 THEN RAISE EXCEPTION 'CREATIVE_V17_ACTIVE_EXECUTION_BLOCK'; END IF;
END $prelive$;

DO $pre$
BEGIN
 IF to_regclass('saly.creative_queue_native_dispatch_reservations_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_ALREADY_EXISTS'; END IF;
 IF to_regprocedure('saly.creative_native_render_wire_v1(uuid,bigint,text)') IS NULL
    OR to_regclass('saly.creative_queue_claims_v1') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_REQUIRED_V02_V05_MISSING'; END IF;
END $pre$;

-- A durable, one-time reservation. No DISPATCHED/DELIVERED/VERIFIED states exist.
-- An archive hash is a worker-reported pin, explicitly not independently attested.
CREATE TABLE saly.creative_queue_native_dispatch_reservations_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 claim_id bigint NOT NULL UNIQUE REFERENCES saly.creative_queue_claims_v1(id) ON DELETE RESTRICT,
 run_id bigint NOT NULL UNIQUE REFERENCES saly.creative_runs(id) ON DELETE RESTRICT,
 order_id bigint NOT NULL REFERENCES saly.creative_orders(id) ON DELETE RESTRICT,
 item_id bigint NOT NULL REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT,
 request_key text NOT NULL CHECK(length(btrim(request_key)) BETWEEN 1 AND 128),
 executor_mode text NOT NULL CHECK(executor_mode IN ('GPT_NATIVE','CLAUDE_NATIVE')),
 executor_provider text NOT NULL CHECK(executor_provider IN ('OPENAI_CHATGPT_NATIVE','ANTHROPIC_CLAUDE_NATIVE')),
 wire_sha256 text NOT NULL CHECK(wire_sha256 ~ '^[0-9a-f]{64}$'),
 prompt_sha256 text NOT NULL CHECK(prompt_sha256 ~ '^[0-9a-f]{64}$'),
 input_snapshot_sha256 text NOT NULL CHECK(input_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 archive_reported_sha256 text NOT NULL CHECK(archive_reported_sha256 ~ '^[0-9a-f]{64}$'),
 claim_lease_until timestamptz NOT NULL,
 run_deadline_at timestamptz NOT NULL,
 reserved_at timestamptz NOT NULL,
 state text NOT NULL DEFAULT 'RESERVED_NOT_DISPATCHED'
   CHECK (state='RESERVED_NOT_DISPATCHED'),
 CHECK (claim_lease_until > reserved_at AND run_deadline_at > reserved_at),
 CHECK ((executor_mode='GPT_NATIVE' AND executor_provider='OPENAI_CHATGPT_NATIVE')
     OR (executor_mode='CLAUDE_NATIVE' AND executor_provider='ANTHROPIC_CLAUDE_NATIVE')),
 UNIQUE(item_id,request_key)
);

CREATE FUNCTION saly.creative_queue_native_dispatch_reservation_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO pg_catalog,saly,pg_temp
AS $guard$
BEGIN
 RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_IMMUTABLE';
END $guard$;
CREATE TRIGGER trg_creative_queue_native_dispatch_reservation_immutable_v1
 BEFORE UPDATE OR DELETE ON saly.creative_queue_native_dispatch_reservations_v1
 FOR EACH ROW EXECUTE FUNCTION saly.creative_queue_native_dispatch_reservation_immutable_v1();

-- One transactional decision under the existing queue serial lock. SECURITY
-- DEFINER is intentionally PRIVATE. It authenticates NO provider or host.
-- No remote effect may use the resulting state as an execution permit.
CREATE FUNCTION saly.creative_queue_native_reserve_dispatch_v1(
  p_claim_token uuid, p_run_id bigint, p_executor_mode text,
  p_expected_wire_sha256 text, p_archive_reported_sha256 text,
  p_request_key text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog,saly,extensions,pg_temp
AS $f$
DECLARE
 v_now timestamptz;
 v_mode text;
 v_wire jsonb;
 v_claim record;
 v_existing record;
 v_rowid bigint;
 v_provider text;
BEGIN
 IF p_claim_token IS NULL OR p_run_id IS NULL OR p_run_id<1
   OR p_executor_mode IS NULL OR p_executor_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE')
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_ARGUMENT_INVALID'; END IF;
 IF p_expected_wire_sha256 IS NULL OR p_expected_wire_sha256 !~ '^[0-9a-f]{64}$'
   OR p_archive_reported_sha256 IS NULL OR p_archive_reported_sha256 !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_HASH_PIN_INVALID'; END IF;
 IF p_request_key IS NULL OR length(btrim(p_request_key)) NOT BETWEEN 1 AND 128
   OR p_request_key !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_IDEMPOTENCY_KEY_INVALID'; END IF;
 v_mode:=p_executor_mode;

 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 -- Live V05 canonical reconstruction under the same serial lock.
 -- Raises on expired claim, mismatched RUN/policy/order, source drift.
 v_wire:=saly.creative_native_render_wire_v1(p_claim_token,p_run_id,v_mode);
 IF v_wire->>'schema_version' IS DISTINCT FROM 'SALY_NATIVE_RENDER_WIRE_V1'
   OR v_wire->>'status' IS DISTINCT FROM 'RENDER_WIRE_FROZEN_AUTHORIZED'
   OR v_wire->'render_authorized' IS DISTINCT FROM 'true'::jsonb
   OR v_wire->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
   OR v_wire->'db_done_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_WIRE_NOT_READY'; END IF;
 IF v_wire->>'wire_sha256' IS DISTINCT FROM p_expected_wire_sha256
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_WIRE_DRIFT'; END IF;

 SELECT c.id AS claim_id,c.order_id,c.item_id,c.lease_until,c.state AS claim_state,
        c.worker_ref AS claim_worker,
        r.id AS run_id,r.state AS run_state,r.worker_ref AS run_worker,
        r.queue_claim_id,r.deadline_at,r.input_snapshot
 INTO v_claim
 FROM saly.creative_queue_claims_v1 c
 JOIN saly.creative_runs r ON r.queue_claim_id=c.id
 WHERE c.claim_token=p_claim_token AND r.id=p_run_id
 FOR UPDATE OF c,r;
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RUN_CLAIM_NOT_BOUND'; END IF;
 v_now:=clock_timestamp();
 IF v_claim.claim_state IS DISTINCT FROM 'ACTIVE'
   OR v_claim.run_state IS DISTINCT FROM 'EJECUTANDO'
   OR v_claim.lease_until<=v_now OR v_claim.deadline_at<=v_now
   OR v_claim.claim_worker IS DISTINCT FROM v_claim.run_worker
   OR v_wire->>'claim_id' IS DISTINCT FROM v_claim.claim_id::text
   OR v_wire->>'order_id' IS DISTINCT FROM v_claim.order_id::text
   OR v_wire->>'item_id' IS DISTINCT FROM v_claim.item_id::text
   OR v_wire->>'run_id' IS DISTINCT FROM v_claim.run_id::text
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_LIVE_FENCE_EXPIRED'; END IF;
 v_provider:=CASE v_mode WHEN 'GPT_NATIVE' THEN 'OPENAI_CHATGPT_NATIVE'
                       ELSE 'ANTHROPIC_CLAUDE_NATIVE' END;
 IF v_wire->>'executor_provider' IS DISTINCT FROM v_provider
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_PROVIDER_MISMATCH'; END IF;

 SELECT * INTO v_existing
 FROM saly.creative_queue_native_dispatch_reservations_v1
 WHERE run_id=v_claim.run_id OR claim_id=v_claim.claim_id
 FOR UPDATE;
 IF FOUND THEN
  IF v_existing.claim_id IS DISTINCT FROM v_claim.claim_id
    OR v_existing.run_id IS DISTINCT FROM v_claim.run_id
    OR v_existing.executor_mode IS DISTINCT FROM v_mode
    OR v_existing.request_key IS DISTINCT FROM p_request_key
    OR v_existing.wire_sha256 IS DISTINCT FROM p_expected_wire_sha256
    OR v_existing.archive_reported_sha256 IS DISTINCT FROM p_archive_reported_sha256
  THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT'; END IF;
  RETURN jsonb_build_object(
   'schema_version','SALY_NATIVE_DISPATCH_RESERVATION_V1',
   'status','ALREADY_RESERVED_NOT_DISPATCHED',
   'reservation_id',v_existing.id,'run_id',v_existing.run_id,
   'claim_id',v_existing.claim_id,'native_transmitted',false,
   'provider_attested',false,'host_delivery_verified',false,
   'db_done_allowed',false,'dispatch_authorized',false);
 END IF;
 INSERT INTO saly.creative_queue_native_dispatch_reservations_v1
 (claim_id,run_id,order_id,item_id,request_key,executor_mode,executor_provider,
  wire_sha256,prompt_sha256,input_snapshot_sha256,archive_reported_sha256,
  claim_lease_until,run_deadline_at,reserved_at)
 VALUES
 (v_claim.claim_id,v_claim.run_id,v_claim.order_id,v_claim.item_id,p_request_key,
  v_mode,v_provider,v_wire->>'wire_sha256',v_wire->>'prompt_sha256',
  v_wire->>'input_snapshot_sha256',p_archive_reported_sha256,
  v_claim.lease_until,v_claim.deadline_at,v_now)
 RETURNING id INTO v_rowid;
 RETURN jsonb_build_object(
  'schema_version','SALY_NATIVE_DISPATCH_RESERVATION_V1',
  'status','RESERVED_NOT_DISPATCHED','reservation_id',v_rowid,
  'run_id',v_claim.run_id,'claim_id',v_claim.claim_id,
  'wire_sha256',v_wire->>'wire_sha256',
  'native_transmitted',false,'provider_attested',false,
  'host_delivery_verified',false,'db_done_allowed',false,
  'dispatch_authorized',false);
END $f$;

-- Explicit fail-closed ACL. No role may use this in product runtime.
REVOKE ALL ON saly.creative_queue_native_dispatch_reservations_v1 FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_native_dispatch_reservation_immutable_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_native_reserve_dispatch_v1(uuid,bigint,text,text,text,text) FROM PUBLIC;
DO $acl$
DECLARE p text;
BEGIN
 FOREACH p IN ARRAY ARRAY['anon','authenticated','service_role','supabase_read_only_user'] LOOP
   IF to_regrole(p) IS NOT NULL THEN
    EXECUTE format('REVOKE ALL ON saly.creative_queue_native_dispatch_reservations_v1 FROM %I',p);
    EXECUTE format('REVOKE ALL ON FUNCTION saly.creative_queue_native_reserve_dispatch_v1(uuid,bigint,text,text,text,text) FROM %I',p);
   END IF;
 END LOOP;
END $acl$;
DO $post$
DECLARE src text;
BEGIN
 src:=pg_get_functiondef('saly.creative_queue_native_reserve_dispatch_v1(uuid,bigint,text,text,text,text)'::regprocedure);
 IF strpos(src,'creative_native_render_wire_v1')=0
   OR strpos(src,'CREATIVE_DISPATCH_LIVE_FENCE_EXPIRED')=0
   OR strpos(src,'''dispatch_authorized'',false')=0
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_POSTCHECK'; END IF;
END $post$;

-- Defensive ACL plus no visual state mutation.
ALTER TABLE saly.creative_queue_native_dispatch_reservations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.creative_queue_native_dispatch_reservations_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON saly.creative_queue_native_dispatch_reservations_v1 FROM PUBLIC;
DO $post$
DECLARE f text;
BEGIN
 f:=pg_get_functiondef('saly.creative_queue_native_reserve_dispatch_v1(uuid,bigint,text,text,text,text)'::regprocedure);
 IF strpos(f,'ALREADY_RESERVED_NOT_DISPATCHED')=0
 OR strpos(f,'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT')=0
 OR strpos(f,'''dispatch_authorized'',false')=0
 THEN RAISE EXCEPTION 'CREATIVE_V17_RESERVATION_CONTRACT_DRIFT'; END IF;
 IF has_function_privilege('service_role',
   'saly.creative_queue_native_reserve_dispatch_v1(uuid,bigint,text,text,text,text)',
   'EXECUTE')
 OR has_function_privilege('anon',
   'saly.creative_queue_native_reserve_dispatch_v1(uuid,bigint,text,text,text,text)',
   'EXECUTE')
 OR has_table_privilege('authenticated',
   'saly.creative_queue_native_dispatch_reservations_v1','INSERT')
 THEN RAISE EXCEPTION 'CREATIVE_V17_RUNTIME_AUTHORITY_LEAK'; END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_queue_native_dispatch_reservations_v1)
 OR EXISTS(SELECT 1 FROM saly.creative_runs)
 THEN RAISE EXCEPTION 'CREATIVE_V17_PHANTOM_RESERVATION_OR_RUN'; END IF;
END $post$;
COMMIT;
