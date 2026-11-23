-- SALY Creative Factory: guarded queue infrastructure (NOT Native host).
-- Source provenance: main sandbox/creative_factory/queue_v02 and queue_v06.
-- Scope authorized 2026-11-23: one SCREEN/order and Home -> Adelanto.
-- This deploy does not authorize Native render, grant a worker or change
-- any production order from REVIEW_ONLY. B1/B2/B3/B4/B6/B7/B11/B25/B30.
BEGIN;
DO $pre$
BEGIN
 IF to_regclass('saly.creative_queue_claims_v1') IS NOT NULL
 OR to_regclass('saly.creative_queue_native_delivery_evidence_v1') IS NOT NULL
 OR to_regclass('saly.creative_order_sequence_v1') IS NULL
 OR to_regprocedure('saly.creative_order_sequence_dependency_met_v1(bigint)') IS NULL
 OR to_regprocedure('saly.creative_execution_policy_v1(timestamptz)') IS NULL
 OR to_regprocedure('saly.creative_run_guard_l1()') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_PRECONDITION'; END IF;
 IF (SELECT count(*) FROM saly.creative_runs)<>0
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_EXISTING_RUNS_NOT_ALLOWED'; END IF;
 IF (SELECT count(*) FROM saly.creative_orders
      WHERE code IN ('SALY_HOME_V015_SINGLE_20261123',
                    'SALY_ADELANTO_V015_SINGLE_20261123')
        AND request_kind='APP_SCREEN_SINGLE' AND status='PLANIFICADO'
        AND scope_json->>'review_only'='true'
        AND scope_json->>'render_authorized'='false'
        AND scope_json->>'rendering_authority'='false')<>2
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_ORDERS_OR_AUTHORITY_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.creative_order_items
      WHERE order_id IN (SELECT id FROM saly.creative_orders
      WHERE code IN ('SALY_HOME_V015_SINGLE_20261123',
                     'SALY_ADELANTO_V015_SINGLE_20261123'))
        AND status='PENDIENTE')<>2
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_ITEM_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.config_global
      WHERE scope='CREATIVE_FACTORY' AND value_type='INTEGER'
        AND value_status='REAL' AND config_key IN
          ('QUEUE_MAX','MAX_ATTEMPTS','QUEUE_TIMEOUT_SECONDS','LEASE_SECONDS'))<>4
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_CONFIG_DRIFT'; END IF;
END $pre$;

-- V02: serial claim, fenced RUN, no direct worker privileges.
-- SALY - serial queue admission, CANDIDATE, not deployed.
-- PostgreSQL 17. Must be tested on isolated fixture before governed PR/merge.
-- No modification of existing orders/items. No autonomous render authorization.
BEGIN;

CREATE TABLE saly.creative_queue_claims_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id bigint NOT NULL REFERENCES saly.creative_orders(id) ON DELETE RESTRICT,
  item_id bigint NOT NULL REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT,
  worker_ref text NOT NULL CHECK (length(btrim(worker_ref)) BETWEEN 1 AND 128),
  claim_token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  state text NOT NULL CHECK (state IN ('ACTIVE','DONE','FAILED','BLOCKED','EXPIRED')),
  claimed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  lease_until timestamptz NOT NULL,
  finished_at timestamptz,
  note text,
  CHECK ((state='ACTIVE') = (finished_at IS NULL)),
  CHECK (lease_until > claimed_at)
);
CREATE UNIQUE INDEX creative_queue_one_active_v1
  ON saly.creative_queue_claims_v1 ((1)) WHERE state='ACTIVE';
CREATE INDEX creative_queue_item_history_v1
  ON saly.creative_queue_claims_v1 (item_id,id DESC);

-- Bind every queued RUN to a single worker claim, without mutating the canonical
-- input_snapshot checked by creative_assert_run_snapshot_v1.
ALTER TABLE saly.creative_runs ADD COLUMN queue_claim_id bigint
  REFERENCES saly.creative_queue_claims_v1(id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX creative_runs_one_per_claim_v1
  ON saly.creative_runs(queue_claim_id) WHERE queue_claim_id IS NOT NULL;

CREATE TABLE saly.creative_queue_delivery_receipts_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_id bigint NOT NULL UNIQUE REFERENCES saly.creative_queue_claims_v1(id) ON DELETE RESTRICT,
  run_id bigint NOT NULL UNIQUE REFERENCES saly.creative_runs(id) ON DELETE RESTRICT,
  artifact_ref text NOT NULL CHECK (length(btrim(artifact_ref)) > 0),
  artifact_sha256 text NOT NULL CHECK (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  delivery_channel text NOT NULL CHECK (length(btrim(delivery_channel)) > 0),
  delivery_receipt text NOT NULL CHECK (length(btrim(delivery_receipt)) > 0),
  delivered_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- A queue-enabled order rejects direct RUN writes. A token is transported only
-- by the controlled executor transaction, never injected into the input snapshot.
CREATE OR REPLACE FUNCTION saly.creative_queue_run_binding_guard_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, saly, pg_temp
AS $f$
DECLARE v_mode text; v_claim record; v_token text; v_now timestamptz;
BEGIN
  SELECT scope_json->>'queue_mode' INTO v_mode
  FROM saly.creative_orders WHERE id=NEW.order_id;
  IF v_mode IS DISTINCT FROM 'SERIAL_V1' THEN
    -- Legacy lane is not retroactively changed. It cannot use queue claims.
    IF NEW.queue_claim_id IS NOT NULL
    THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEGACY_CLAIM_FORBIDDEN'; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='UPDATE' AND NEW.queue_claim_id IS DISTINCT FROM OLD.queue_claim_id
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_BINDING_IMMUTABLE'; END IF;
  IF NEW.queue_claim_id IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_CLAIM_REQUIRED'; END IF;
  -- Cancellation/failure on expired leases is permitted for recovery; never
  -- permit such a run to start or successfully finish without a live lease.
  IF TG_OP='UPDATE' AND NEW.state IN ('FALLIDO','BLOQUEADO','CANCELADO')
  THEN RETURN NEW; END IF;
  v_token:=nullif(current_setting('saly.creative_queue_token',true),'');
  IF v_token IS NULL OR v_token !~ '^[0-9a-fA-F-]{36}$'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_TOKEN_REQUIRED'; END IF;
  v_now:=clock_timestamp();
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE id=NEW.queue_claim_id FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=v_now
    OR v_claim.claim_token::text IS DISTINCT FROM lower(v_token)
    OR v_claim.order_id IS DISTINCT FROM NEW.order_id
    OR v_claim.item_id IS DISTINCT FROM NEW.item_id
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_CLAIM_INVALID'; END IF;
  IF NEW.state IN ('EJECUTANDO','EXITOSO')
    AND NEW.worker_ref IS DISTINCT FROM v_claim.worker_ref
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_WORKER_MISMATCH'; END IF;
  RETURN NEW;
END $f$;
CREATE TRIGGER trg_creative_queue_run_binding_guard_v1
BEFORE INSERT OR UPDATE ON saly.creative_runs
FOR EACH ROW EXECUTE FUNCTION saly.creative_queue_run_binding_guard_v1();

-- Admission endpoint. Runtime role receives EXECUTE only after ownership review.
CREATE OR REPLACE FUNCTION saly.creative_queue_admit_run_v1(
  p_token uuid, p_attempt integer, p_idempotency_key text, p_input_snapshot jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
DECLARE v_claim record; v_run_id bigint;
BEGIN
  IF p_token IS NULL OR p_attempt IS NULL OR p_attempt<1
    OR nullif(btrim(coalesce(p_idempotency_key,'')),'') IS NULL
    OR jsonb_typeof(p_input_snapshot) IS DISTINCT FROM 'object'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  PERFORM set_config('saly.creative_queue_token',p_token::text,true);
  INSERT INTO saly.creative_runs(
      id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot,queue_claim_id)
  VALUES (nextval('saly.creative_runs_id_seq'::regclass),
      v_claim.order_id,v_claim.item_id,p_attempt,p_idempotency_key,'EN_COLA',
      p_input_snapshot,v_claim.id)
  RETURNING id INTO v_run_id;
  RETURN jsonb_build_object('run_id',v_run_id,'claim_id',v_claim.id,'state','EN_COLA');
END $f$;

CREATE OR REPLACE FUNCTION saly.creative_queue_advance_run_v1(
  p_token uuid, p_run_id bigint, p_next_state text,
  p_output_evidence jsonb DEFAULT '{}'::jsonb, p_error_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
DECLARE v_claim record; v_run record;
BEGIN
  IF p_token IS NULL OR p_run_id IS NULL
    OR p_next_state NOT IN ('EJECUTANDO','EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
    OR jsonb_typeof(p_output_evidence) IS DISTINCT FROM 'object'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  SELECT * INTO v_run FROM saly.creative_runs
  WHERE id=p_run_id AND queue_claim_id=v_claim.id
    AND order_id=v_claim.order_id AND item_id=v_claim.item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_NOT_BOUND'; END IF;
  IF (p_next_state='EJECUTANDO' AND v_run.state<>'EN_COLA')
     OR (p_next_state IN ('EXITOSO','FALLIDO','BLOQUEADO') AND v_run.state<>'EJECUTANDO')
     OR (p_next_state='CANCELADO' AND v_run.state NOT IN ('EN_COLA','EJECUTANDO'))
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_INVALID_TRANSITION'; END IF;
  PERFORM set_config('saly.creative_queue_token',p_token::text,true);
  IF p_next_state='EJECUTANDO' THEN
    UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref=v_claim.worker_ref,
      updated_at=clock_timestamp() WHERE id=v_run.id;
  ELSE
    UPDATE saly.creative_runs SET state=p_next_state,
      output_evidence=CASE WHEN p_next_state='EXITOSO' THEN p_output_evidence ELSE output_evidence END,
      error_code=p_error_code,updated_at=clock_timestamp()
      WHERE id=v_run.id;
  END IF;
  RETURN jsonb_build_object('run_id',v_run.id,'state',p_next_state,'claim_id',v_claim.id);
END $f$;

-- Called only by the trusted delivery adapter, after actual user-facing
-- delivery. The DB checks references but cannot itself prove external delivery.
CREATE OR REPLACE FUNCTION saly.creative_queue_record_delivery_v1(
  p_token uuid, p_run_id bigint, p_channel text, p_delivery_receipt text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
DECLARE v_claim record; v_run record;
BEGIN
  IF p_token IS NULL OR p_run_id IS NULL
    OR nullif(btrim(coalesce(p_channel,'')),'') IS NULL
    OR nullif(btrim(coalesce(p_delivery_receipt,'')),'') IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  SELECT * INTO v_run FROM saly.creative_runs WHERE id=p_run_id
    AND queue_claim_id=v_claim.id AND order_id=v_claim.order_id
    AND item_id=v_claim.item_id AND state='EXITOSO' FOR UPDATE;
  IF NOT FOUND OR nullif(v_run.output_evidence->>'artifact_ref','') IS NULL
      OR (v_run.output_evidence->>'sha256') !~ '^[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_ARTIFACT_NOT_READY'; END IF;
  INSERT INTO saly.creative_queue_delivery_receipts_v1
    (claim_id,run_id,artifact_ref,artifact_sha256,delivery_channel,delivery_receipt)
  VALUES (v_claim.id,v_run.id,v_run.output_evidence->>'artifact_ref',
    v_run.output_evidence->>'sha256',p_channel,p_delivery_receipt);
  RETURN jsonb_build_object('status','DELIVERY_RECORDED','run_id',v_run.id);
END $f$;

-- Defense in depth against direct parallel RUN admissions from different items.
-- Existing RUNs = 0 on 2026-11-22. Migration must independently verify this.
CREATE UNIQUE INDEX creative_runs_one_active_globally_v1
  ON saly.creative_runs ((1)) WHERE state IN ('EN_COLA','EJECUTANDO');

CREATE OR REPLACE FUNCTION saly.creative_queue_claim_next_v1(
  p_worker_ref text, p_lease_seconds integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
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
    AND i.status='LISTO'
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
  ORDER BY o.created_at, o.id, i.ordinal, i.id
  LIMIT 1 FOR UPDATE OF i SKIP LOCKED;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>v_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $f$;

CREATE OR REPLACE FUNCTION saly.creative_queue_heartbeat_v1(
  p_token uuid, p_extend_seconds integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
DECLARE v_claim record; v_now timestamptz; v_policy jsonb; v_lease_seconds integer;
BEGIN
  IF p_token IS NULL THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  IF p_extend_seconds IS NOT NULL AND p_extend_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=v_now
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  UPDATE saly.creative_queue_claims_v1
  SET lease_until=v_now+make_interval(secs=>v_lease_seconds)
  WHERE id=v_claim.id;
  RETURN jsonb_build_object('status','EXTENDED','claim_id',v_claim.id);
END $f$;

CREATE OR REPLACE FUNCTION saly.creative_queue_release_v1(
  p_token uuid, p_outcome text, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
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
    IF v_item_status<>'APROBADO' OR NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=v_claim.item_id AND r.order_id=v_claim.order_id
        AND r.state='EXITOSO' AND r.queue_claim_id=v_claim.id
        AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
        AND nullif(r.output_evidence->>'worker_receipt','') IS NOT NULL
        AND r.output_evidence->>'sha256' ~ '^[0-9a-f]{64}$'
        AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
                        WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number)
        AND EXISTS (
          SELECT 1 FROM saly.creative_queue_delivery_receipts_v1 delivery
          WHERE delivery.claim_id=v_claim.id AND delivery.run_id=r.id
            AND delivery.artifact_ref=r.output_evidence->>'artifact_ref'
            AND delivery.artifact_sha256=r.output_evidence->>'sha256'
        )
    ) THEN RAISE EXCEPTION 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED'; END IF;
  ELSE
    IF v_item_status<>'BLOQUEADO'
    THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FAILURE_NOT_BLOCKED'; END IF;
  END IF;

  UPDATE saly.creative_queue_claims_v1
  SET state=p_outcome, finished_at=v_now, note=left(p_note,1000)
  WHERE id=v_claim.id;

  IF p_outcome='DONE' AND NOT EXISTS (
    SELECT 1 FROM saly.creative_order_items i
    WHERE i.order_id=v_claim.order_id
      AND (i.status<>'APROBADO' AND (i.required OR i.status<>'OMITIDO'))
  ) AND EXISTS (
    SELECT 1 FROM saly.creative_order_items i
    WHERE i.order_id=v_claim.order_id AND i.required
  ) THEN
    UPDATE saly.creative_orders
      SET status='COMPLETADO',completed_at=v_now
      WHERE id=v_claim.order_id AND status IN ('PLANIFICADO','EN_PROCESO','EN_QA');
    v_closed := FOUND;
  END IF;
  RETURN jsonb_build_object('status','RELEASED','result',p_outcome,
    'claim_id',v_claim.id,'order_closed',v_closed);
END $f$;

-- Never expose mutable claim ownership directly to app roles.
REVOKE ALL ON saly.creative_queue_claims_v1 FROM PUBLIC;
REVOKE ALL ON saly.creative_queue_delivery_receipts_v1 FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_admit_run_v1(uuid,integer,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_advance_run_v1(uuid,bigint,text,jsonb,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_record_delivery_v1(uuid,bigint,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_claim_next_v1(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_heartbeat_v1(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_release_v1(uuid,text,text) FROM PUBLIC;
-- No GRANT to a runtime role until governed executor ownership is verified.

-- V06: exact-host-delivery binding and final QA gate.
-- Replaces V02 text receipts with unconditional rejection.
-- SALY Native delivery hardening V06. CANDIDATE: no GRANT, no deploy.
-- queue_v02's former text-only receipt must not be considered host delivery.
-- Dependencies: queue_v02 isolated fixture. All DDL is candidate source only.
BEGIN;
DO $pre$
DECLARE src text;
BEGIN
 IF to_regclass('saly.creative_queue_native_delivery_evidence_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'CREATIVE_DELIVERY_NATIVE_ALREADY_EXISTS'; END IF;
 IF to_regprocedure('saly.creative_queue_release_v1(uuid,text,text)') IS NULL
 OR to_regprocedure('saly.creative_queue_record_delivery_v1(uuid,bigint,text,text)') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_DELIVERY_LEGACY_QUEUE_MISSING'; END IF;
 src:=pg_get_functiondef('saly.creative_queue_release_v1(uuid,text,text)'::regprocedure);
 IF strpos(src,'creative_queue_delivery_receipts_v1')=0
    OR strpos(src,'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED')=0
    OR strpos(src,'CREATIVE_QUEUE_FAILURE_NOT_BLOCKED')=0
 THEN RAISE EXCEPTION 'CREATIVE_DELIVERY_RELEASE_SOURCE_DRIFT'; END IF;
END $pre$;

-- Only an authenticated future host-verifier can publish VERIFIED rows.
-- This lot intentionally registers NO grant or public verification RPC.
-- STAGED is not an effective delivery. Provider attestations are NOT assumed:
-- host-side byte readback + delivered message identity are separate evidence.
CREATE TABLE saly.creative_queue_native_delivery_evidence_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_id bigint NOT NULL UNIQUE
    REFERENCES saly.creative_queue_claims_v1(id) ON DELETE RESTRICT,
  run_id bigint NOT NULL UNIQUE
    REFERENCES saly.creative_runs(id) ON DELETE RESTRICT,
  order_id bigint NOT NULL REFERENCES saly.creative_orders(id) ON DELETE RESTRICT,
  item_id bigint NOT NULL REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT,
  artifact_ref text NOT NULL CHECK (length(btrim(artifact_ref))>0),
  artifact_sha256 text NOT NULL CHECK (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  host_surface text NOT NULL CHECK (length(btrim(host_surface))>0),
  message_id text NOT NULL CHECK (length(btrim(message_id))>0),
  executor_mode text NOT NULL CHECK (executor_mode IN ('GPT_NATIVE','CLAUDE_NATIVE')),
  host_evidence_ref text NOT NULL CHECK (length(btrim(host_evidence_ref))>0),
  host_evidence_sha256 text NOT NULL
    CHECK (host_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  state text NOT NULL DEFAULT 'STAGED' CHECK (state IN ('STAGED','VERIFIED')),
  verifier_ref text,
  verified_at timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CONSTRAINT creative_native_delivery_verified_pair_v1 CHECK (
    (state='VERIFIED') =
    (verified_at IS NOT NULL AND nullif(btrim(coalesce(verifier_ref,'')),'') IS NOT NULL)
  ),
  CONSTRAINT creative_native_delivery_message_unique_v1 UNIQUE (host_surface,message_id)
);

CREATE FUNCTION saly.creative_queue_native_delivery_guard_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO pg_catalog,saly,pg_temp
AS $guard$
DECLARE c record; r record; i record;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' THEN
   IF OLD.state='VERIFIED' THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_IMMUTABLE'; END IF;
   IF OLD.state<>'STAGED' OR NEW.state<>'VERIFIED'
      OR NEW.id IS DISTINCT FROM OLD.id OR NEW.claim_id IS DISTINCT FROM OLD.claim_id
      OR NEW.run_id IS DISTINCT FROM OLD.run_id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id
      OR NEW.artifact_ref IS DISTINCT FROM OLD.artifact_ref
      OR NEW.artifact_sha256 IS DISTINCT FROM OLD.artifact_sha256
      OR NEW.host_surface IS DISTINCT FROM OLD.host_surface
      OR NEW.message_id IS DISTINCT FROM OLD.message_id
      OR NEW.executor_mode IS DISTINCT FROM OLD.executor_mode
      OR NEW.host_evidence_ref IS DISTINCT FROM OLD.host_evidence_ref
      OR NEW.host_evidence_sha256 IS DISTINCT FROM OLD.host_evidence_sha256
      OR NEW.recorded_at IS DISTINCT FROM OLD.recorded_at
   THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_PROMOTION_INVALID'; END IF;
 ELSE
   IF NEW.state<>'STAGED' OR NEW.verified_at IS NOT NULL OR NEW.verifier_ref IS NOT NULL
   THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_STAGED_ONLY'; END IF;
 END IF;

 SELECT * INTO c FROM saly.creative_queue_claims_v1 WHERE id=NEW.claim_id FOR UPDATE;
 SELECT * INTO r FROM saly.creative_runs WHERE id=NEW.run_id FOR UPDATE;
 SELECT status INTO i FROM saly.creative_order_items
 WHERE id=NEW.item_id AND order_id=NEW.order_id FOR UPDATE;
 IF NOT FOUND OR c.id IS NULL OR r.id IS NULL
 OR c.order_id IS DISTINCT FROM NEW.order_id OR c.item_id IS DISTINCT FROM NEW.item_id
 OR r.order_id IS DISTINCT FROM NEW.order_id OR r.item_id IS DISTINCT FROM NEW.item_id
 OR r.queue_claim_id IS DISTINCT FROM c.id
 OR c.state IS DISTINCT FROM 'ACTIVE' OR c.lease_until<=clock_timestamp()
 OR r.state IS DISTINCT FROM 'EXITOSO' OR i.status IS DISTINCT FROM 'APROBADO'
 OR r.output_evidence->>'artifact_ref' IS DISTINCT FROM NEW.artifact_ref
 OR r.output_evidence->>'sha256' IS DISTINCT FROM NEW.artifact_sha256
 THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_BINDING_NOT_READY'; END IF;
 IF TG_OP='UPDATE' THEN
    IF lower(btrim(NEW.verifier_ref))=lower(btrim(c.worker_ref))
    THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_SELF_VERIFICATION'; END IF;
 END IF;
 RETURN NEW;
END $guard$;
CREATE TRIGGER trg_creative_queue_native_delivery_guard_v1
BEFORE INSERT OR UPDATE OR DELETE ON saly.creative_queue_native_delivery_evidence_v1
FOR EACH ROW EXECUTE FUNCTION saly.creative_queue_native_delivery_guard_v1();

-- Old function is intentionally retained for compatibility of signature but
-- fail-closed: passing 'channel/message-id' can never manufacture delivery.
CREATE OR REPLACE FUNCTION saly.creative_queue_record_delivery_v1(
  p_token uuid,p_run_id bigint,p_channel text,p_delivery_receipt text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,saly,pg_temp
AS $blocked$
BEGIN
 RAISE EXCEPTION 'CREATIVE_QUEUE_UNATTESTED_TEXT_RECEIPT_FORBIDDEN';
END $blocked$;

-- Preserve the rest of DONE/FAILED/BLOCKED and auto-order close exactly as V02.
CREATE OR REPLACE FUNCTION saly.creative_queue_release_v1(
  p_token uuid, p_outcome text, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
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
    IF v_item_status<>'APROBADO' OR NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=v_claim.item_id AND r.order_id=v_claim.order_id
        AND r.state='EXITOSO' AND r.queue_claim_id=v_claim.id
        AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
        AND nullif(r.output_evidence->>'worker_receipt','') IS NOT NULL
        AND r.output_evidence->>'sha256' ~ '^[0-9a-f]{64}$'
        AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
                        WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number)
        AND EXISTS (
          SELECT 1 FROM saly.creative_queue_native_delivery_evidence_v1 delivery
          WHERE delivery.claim_id=v_claim.id AND delivery.run_id=r.id
            AND delivery.order_id=v_claim.order_id
            AND delivery.item_id=v_claim.item_id
            AND delivery.artifact_ref=r.output_evidence->>'artifact_ref'
            AND delivery.artifact_sha256=r.output_evidence->>'sha256'
            AND delivery.state='VERIFIED'
            AND delivery.verified_at IS NOT NULL
            AND nullif(btrim(delivery.verifier_ref),'') IS NOT NULL
            AND lower(btrim(delivery.verifier_ref))<>lower(btrim(v_claim.worker_ref))
            AND nullif(btrim(delivery.host_evidence_ref),'') IS NOT NULL
            AND delivery.host_evidence_sha256 ~ '^[0-9a-f]{64}$'
            AND nullif(btrim(delivery.message_id),'') IS NOT NULL
        )
    ) THEN RAISE EXCEPTION 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED'; END IF;
  ELSE
    IF v_item_status<>'BLOQUEADO'
    THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FAILURE_NOT_BLOCKED'; END IF;
  END IF;

  UPDATE saly.creative_queue_claims_v1
  SET state=p_outcome, finished_at=v_now, note=left(p_note,1000)
  WHERE id=v_claim.id;

  IF p_outcome='DONE' AND NOT EXISTS (
    SELECT 1 FROM saly.creative_order_items i
    WHERE i.order_id=v_claim.order_id
      AND (i.status<>'APROBADO' AND (i.required OR i.status<>'OMITIDO'))
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
END $f$;


-- End-user and service roles cannot publish evidence or call the text endpoint.
REVOKE ALL ON saly.creative_queue_native_delivery_evidence_v1
 FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_native_delivery_guard_v1()
 FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_record_delivery_v1(uuid,bigint,text,text)
 FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_release_v1(uuid,text,text)
 FROM PUBLIC;
DO $acl$
DECLARE p text;
BEGIN
 FOREACH p IN ARRAY ARRAY['anon','authenticated','service_role','supabase_read_only_user'] LOOP
  IF to_regrole(p) IS NOT NULL THEN
   EXECUTE format('REVOKE ALL ON saly.creative_queue_native_delivery_evidence_v1 FROM %I',p);
   EXECUTE format('REVOKE ALL ON FUNCTION saly.creative_queue_record_delivery_v1(uuid,bigint,text,text) FROM %I',p);
   EXECUTE format('REVOKE ALL ON FUNCTION saly.creative_queue_release_v1(uuid,text,text) FROM %I',p);
  END IF;
 END LOOP;
END $acl$;
DO $post$
DECLARE f text;
BEGIN
 f:=pg_get_functiondef('saly.creative_queue_release_v1(uuid,text,text)'::regprocedure);
 IF strpos(f,'creative_queue_native_delivery_evidence_v1')=0
 OR strpos(f,'delivery.state=''VERIFIED''')=0
 OR strpos(f,'creative_queue_delivery_receipts_v1')<>0
 THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_RELEASE_POSTCHECK'; END IF;
 f:=pg_get_functiondef('saly.creative_queue_record_delivery_v1(uuid,bigint,text,text)'::regprocedure);
 IF strpos(f,'CREATIVE_QUEUE_UNATTESTED_TEXT_RECEIPT_FORBIDDEN')=0
 THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_TEXT_BYPASS_REMAINING'; END IF;
END $post$;

-- Respect the newer TERMINADO lifecycle: only an externally authenticated
-- host and independent QA can pass the V06 VERIFIED gate. False release
-- of a single screen is rolled back transactionally.
ALTER TABLE saly.creative_queue_claims_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.creative_queue_claims_v1 FORCE ROW LEVEL SECURITY;
ALTER TABLE saly.creative_queue_delivery_receipts_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.creative_queue_delivery_receipts_v1 FORCE ROW LEVEL SECURITY;
ALTER TABLE saly.creative_queue_native_delivery_evidence_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.creative_queue_native_delivery_evidence_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON saly.creative_queue_claims_v1,
  saly.creative_queue_delivery_receipts_v1,
  saly.creative_queue_native_delivery_evidence_v1
 FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_run_binding_guard_v1() FROM PUBLIC;
DO $roles$
DECLARE role_name text; proc regprocedure;
BEGIN
 FOREACH role_name IN ARRAY ARRAY[
   'anon','authenticated','service_role','supabase_read_only_user'
 ] LOOP
  IF to_regrole(role_name) IS NOT NULL THEN
   EXECUTE format('REVOKE ALL ON saly.creative_queue_claims_v1, saly.creative_queue_delivery_receipts_v1, saly.creative_queue_native_delivery_evidence_v1 FROM %I',role_name);
   FOR proc IN SELECT p.oid::regprocedure FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='saly' AND p.proname IN (
      'creative_queue_claim_next_v1','creative_queue_admit_run_v1',
      'creative_queue_advance_run_v1','creative_queue_record_delivery_v1',
      'creative_queue_heartbeat_v1','creative_queue_release_v1',
      'creative_queue_run_binding_guard_v1','creative_queue_native_delivery_guard_v1')
   LOOP
     EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',proc,role_name);
   END LOOP;
  END IF;
 END LOOP;
END $roles$;
DO $post$
DECLARE f text; claim_result jsonb;
BEGIN
 f:=pg_get_functiondef('saly.creative_queue_claim_next_v1(text,integer)'::regprocedure);
 IF position('creative_order_sequence_dependency_met_v1' in f)=0
 OR position('SKIP LOCKED' in f)=0
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_DEPENDENCY_NOT_ENFORCED'; END IF;
 f:=pg_get_functiondef('saly.creative_queue_release_v1(uuid,text,text)'::regprocedure);
 IF position('creative_queue_native_delivery_evidence_v1' in f)=0
 OR position('TERMINADO' in f)=0
 OR position('CREATIVE_SINGLE_SCREEN_DID_NOT_TERMINATE' in f)=0
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_CLOSURE_NOT_HARDENED'; END IF;
 claim_result:=saly.creative_queue_claim_next_v1('GOVERNED_ACTIVATION_POSTCHECK',NULL);
 IF claim_result->>'status' IS DISTINCT FROM 'EMPTY'
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_FALSE_EXECUTION',claim_result; END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_queue_claims_v1)
 THEN RAISE EXCEPTION 'CREATIVE_SERIAL_QUEUE_PHANTOM_CLAIM'; END IF;
END $post$;
COMMIT;
