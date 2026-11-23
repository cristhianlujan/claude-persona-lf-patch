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
      SET status='COMPLETADO',completed_at=v_now
      WHERE id=v_claim.order_id AND status IN ('PLANIFICADO','EN_PROCESO','EN_QA');
    v_closed := FOUND;
  END IF;
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
COMMIT;
