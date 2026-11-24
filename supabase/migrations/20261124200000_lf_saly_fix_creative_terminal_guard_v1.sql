-- Align generated-item terminal transition in both existing guards; retain QA checks.
BEGIN;
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
   IF NOT FOUND OR lower(btrim(NEW.qa_receipt->>'reviewer_ref'))=lower(btrim(v_run.worker_ref))
      OR (NEW.status='TERMINADO' AND (NEW.approved_by IS NOT NULL OR NEW.approved_at IS NOT NULL))
      OR (NEW.status='APROBADO' AND NEW.approved_by IS DISTINCT FROM NEW.qa_receipt->>'reviewer_ref')
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
 -- Explicit signed owner approval may follow an already completed order.
 IF OLD.status='TERMINADO' AND NEW.status='APROBADO' THEN
   IF auth.uid() IS NULL OR NEW.approved_by IS DISTINCT FROM auth.uid()::text
     OR NEW.approved_at IS NULL
     OR (to_jsonb(NEW) - 'status' - 'approved_at' - 'approved_by' - 'updated_at')
          IS DISTINCT FROM
        (to_jsonb(OLD) - 'status' - 'approved_at' - 'approved_by' - 'updated_at')
   THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_OWNER_TRANSITION_INVALID'; END IF;
   RETURN NEW;
 END IF;
 IF OLD.status='TERMINADO' OR v_order_status='TERMINADO' THEN
  RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ITEM_IMMUTABLE'; END IF;
 IF NEW.status='TERMINADO' AND OLD.status IN ('LISTO','EN_QA') THEN
   IF NEW.approved_at IS NOT NULL OR NEW.approved_by IS NOT NULL
      OR NEW.qa_receipt->>'verdict' IS DISTINCT FROM 'PASS'
      OR NOT EXISTS(SELECT 1 FROM saly.creative_runs r
        JOIN saly.creative_run_detection_v1 d ON d.run_id=r.id
        WHERE r.item_id=NEW.id AND r.order_id=NEW.order_id AND r.state='EXITOSO'
        AND d.item_id=NEW.id AND d.order_id=NEW.order_id
        AND d.artifact_sha256=r.output_evidence->>'sha256'
        AND d.artifact_ref=r.output_evidence->>'artifact_ref'
        AND r.output_evidence->>'sha256'=NEW.qa_receipt->>'artifact_sha256')
   THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_QA_RUN_MISSING'; END IF;
   RETURN NEW;
 END IF;
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
END $function$;
COMMIT;
