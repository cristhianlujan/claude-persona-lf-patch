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

-- Defense in depth against direct parallel RUN admissions from different items.
-- Existing RUNs = 0 on 2026-11-22. Migration must independently verify this.
CREATE UNIQUE INDEX creative_runs_one_active_globally_v1
  ON saly.creative_runs ((1)) WHERE state IN ('EN_COLA','EJECUTANDO');

CREATE OR REPLACE FUNCTION saly.creative_queue_claim_next_v1(
  p_worker_ref text, p_lease_seconds integer DEFAULT 900)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
DECLARE
  v_item record;
  v_active record;
  v_claim record;
  v_now timestamptz;
BEGIN
  IF length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
     OR p_lease_seconds IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 3600
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
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
    AND i.status IN ('PENDIENTE','LISTO')
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
  LIMIT 1;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>p_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $f$;

CREATE OR REPLACE FUNCTION saly.creative_queue_heartbeat_v1(
  p_token uuid, p_extend_seconds integer DEFAULT 900)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, saly, pg_temp
AS $f$
DECLARE v_claim record; v_now timestamptz;
BEGIN
  IF p_token IS NULL OR p_extend_seconds IS NULL OR p_extend_seconds NOT BETWEEN 60 AND 3600
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=v_now
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  UPDATE saly.creative_queue_claims_v1
  SET lease_until=v_now+make_interval(secs=>p_extend_seconds)
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
        AND r.state='EXITOSO'
        AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
        AND nullif(r.output_evidence->>'worker_receipt','') IS NOT NULL
        AND r.output_evidence->>'sha256' ~ '^[0-9a-f]{64}$'
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
REVOKE ALL ON FUNCTION saly.creative_queue_claim_next_v1(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_heartbeat_v1(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_queue_release_v1(uuid,text,text) FROM PUBLIC;
-- No GRANT to a runtime role until governed executor ownership is verified.
COMMIT;