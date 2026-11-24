-- Owner-authorized self QA for delivery, not independent review or owner approval.
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
COMMIT;
