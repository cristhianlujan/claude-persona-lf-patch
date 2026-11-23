-- Exact live source from pg_get_functiondef of current production
-- used ONLY in disposable PG17 fixture; no replacement or mutation of prod.
CREATE OR REPLACE FUNCTION saly.creative_chat_terminal_order_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status='TERMINADO' THEN
   RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_IMMUTABLE'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP<>'UPDATE' THEN RETURN NEW; END IF;
 IF OLD.status='TERMINADO' THEN
  RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_IMMUTABLE'; END IF;
 IF NEW.status='TERMINADO' AND OLD.status IS DISTINCT FROM NEW.status THEN
  IF OLD.status NOT IN ('PLANIFICADO','EN_PROCESO')
  OR NEW.completed_at IS NULL
  OR NOT EXISTS (SELECT 1 FROM saly.creative_order_items i
                 WHERE i.order_id=NEW.id AND i.required)
  OR EXISTS (
   SELECT 1 FROM saly.creative_order_items i WHERE i.order_id=NEW.id AND
      (i.status NOT IN ('TERMINADO','APROBADO','OMITIDO')
       OR (i.required AND i.status NOT IN ('TERMINADO','APROBADO'))
       OR (i.status='TERMINADO' AND
         (i.qa_receipt#>>'{chat_judge_v1,artifact_sha256}' IS DISTINCT FROM
            i.qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}'
          OR nullif(btrim(i.qa_receipt#>>'{chat_judge_v1,qa_comment}'),'') IS NULL)))
  )
  OR EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.order_id=NEW.id
              AND r.state IN ('EN_COLA','EJECUTANDO'))
  THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_DETAILS_INCOMPLETE'; END IF;
 END IF;
 RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_chat_terminal_item_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_j jsonb;
  v_a jsonb;
  v_order_status text;
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status='TERMINADO' OR EXISTS (
   SELECT 1 FROM saly.creative_orders o WHERE o.id=OLD.order_id AND o.status='TERMINADO'
  ) THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ITEM_IMMUTABLE'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP<>'UPDATE' THEN RETURN NEW; END IF;
 SELECT status INTO v_order_status FROM saly.creative_orders
 WHERE id=NEW.order_id FOR UPDATE;
 IF OLD.status='TERMINADO' OR v_order_status='TERMINADO' THEN
  RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ITEM_IMMUTABLE'; END IF;
 IF NEW.status='TERMINADO' AND OLD.status IS DISTINCT FROM NEW.status THEN
  IF OLD.status<>'PENDIENTE' OR NEW.order_id<>OLD.order_id
  OR NEW.code<>OLD.code OR NEW.acceptance_json IS DISTINCT FROM OLD.acceptance_json
  OR NEW.context_json IS DISTINCT FROM OLD.context_json
  OR EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.item_id=NEW.id)
  THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_NOT_ARCHIVED_PENDING'; END IF;
  v_a:=OLD.qa_receipt->'chat_artifact_reconciliation_v1';
  v_j:=NEW.qa_receipt->'chat_judge_v1';
  IF v_a IS NULL OR v_j IS NULL
  OR NEW.qa_receipt->'chat_artifact_reconciliation_v1' IS DISTINCT FROM v_a
  OR v_a->>'status' IS DISTINCT FROM 'ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE'
  OR v_a->>'avoid_regeneration' IS DISTINCT FROM 'true'
  OR v_a->>'chat_delivery_observed' IS DISTINCT FROM 'true'
  OR v_a->>'sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'artifact_sha256' IS DISTINCT FROM v_a->>'sha256'
  OR v_j->>'judge_receipt_sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'source_manifest_input_sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'judge_kind' IS DISTINCT FROM 'DETERMINISTIC_TECHNICAL_SEPARATE_PROCESS'
  OR v_j->>'technical_verdict' NOT IN ('PASS_TECHNICAL','PASS_TECHNICAL_WITH_OBSERVATIONS')
  OR v_j->>'technical_verdict' IS NULL
  OR v_j->>'semantic_independence_proven' IS DISTINCT FROM 'false'
  OR v_j->>'semantic_verdict' IS DISTINCT FROM 'NOT_INDEPENDENTLY_EVALUATED'
  OR v_j->>'production_approved' IS DISTINCT FROM 'false'
  OR v_j->>'run_verified' IS DISTINCT FROM 'false'
  OR v_j->>'terminal_semantics' IS DISTINCT FROM 'IMAGE_DELIVERED_AND_QA_COMMENTED_NOT_APPROVED'
  OR nullif(btrim(v_j->>'qa_comment'),'') IS NULL
  OR jsonb_typeof(v_j->'observations') IS DISTINCT FROM 'array'
  OR NEW.approved_at IS NOT NULL OR NEW.approved_by IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM saly.creative_item_dependencies d
    JOIN saly.creative_order_items p ON p.id=d.depends_on_item_id
    WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id
      AND p.status NOT IN ('TERMINADO','APROBADO')
  ) THEN
   RAISE EXCEPTION 'SALY_CHAT_TERMINAL_JUDGE_OR_DEPENDENCY_MISSING';
  END IF;
 END IF;
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
CREATE TRIGGER trg_saly_creative_chat_terminal_order_guard_v1
BEFORE UPDATE ON saly.creative_orders FOR EACH ROW
EXECUTE FUNCTION saly.creative_chat_terminal_order_guard_v1();
CREATE TRIGGER trg_saly_creative_chat_terminal_item_guard_v1
BEFORE UPDATE ON saly.creative_order_items FOR EACH ROW
EXECUTE FUNCTION saly.creative_chat_terminal_item_guard_v1();
CREATE TRIGGER trg_creative_00_order_sequence_start_guard_v1
BEFORE UPDATE OF status ON saly.creative_orders FOR EACH ROW
EXECUTE FUNCTION saly.creative_order_sequence_start_guard_v1();
CREATE TRIGGER trg_creative_00_run_sequence_start_guard_v1
BEFORE INSERT OR UPDATE OF state ON saly.creative_runs FOR EACH ROW
EXECUTE FUNCTION saly.creative_order_sequence_start_guard_v1();
