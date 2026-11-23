-- Governed historical chat-image delivery completion; no native RUN or QA approval fabricated.
-- Target ONLY saly.creative_orders.id=7 + saly.creative_order_items.id=10.
-- Evidence: sandbox/creative_factory/order7_terminal_20261123/source_manifest_v1.json
--           sandbox/creative_factory/order7_terminal_20261123/judge_receipt_v1.json
-- User explicitly authorized this TERMINADO state update (2026-11-23).
-- All work must follow PR -> PASE -> Merge Train -> independent Supabase readback.
BEGIN;
DO $pre$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:chat-terminal:v1',0));
  IF (SELECT count(*) FROM saly.creative_orders o
      JOIN saly.creative_order_items i ON i.order_id=o.id
      WHERE o.id=7 AND o.code='SALY_HOME_V015_SINGLE_20261123'
        AND o.status='PLANIFICADO' AND o.completed_at IS NULL
        AND i.id=10 AND i.code='HOME' AND i.status='PENDIENTE'
        AND i.required AND i.qa_receipt='{}'::jsonb
        AND i.approved_at IS NULL AND i.approved_by IS NULL)<>1
  OR (SELECT count(*) FROM saly.creative_order_items WHERE order_id=7)<>1
  OR EXISTS (SELECT 1 FROM saly.creative_runs WHERE order_id=7 OR item_id=10)
  OR EXISTS (SELECT 1 FROM saly.creative_item_dependencies
             WHERE order_id=7 AND item_id=10)
  OR to_regprocedure('saly.creative_chat_terminal_item_guard_v1()') IS NULL
  OR to_regprocedure('saly.creative_chat_terminal_order_guard_v1()') IS NULL
  THEN RAISE EXCEPTION 'SALY_HOME7_ITEM10_TERMINAL_PRESTATE_OR_GUARDS_MISSING'; END IF;
END $pre$;

-- First persisted checkpoint for immutable OLD.qa_receipt on terminal trigger.
UPDATE saly.creative_order_items SET
 qa_receipt=jsonb_set(qa_receipt,'{chat_artifact_reconciliation_v1}',
 jsonb_build_object(
  'schema_version','SALY_CHAT_ARTIFACT_RECONCILIATION_V1',
  'filename','SALY_HOME_prueba_logo_oficial_20261123.png',
  'file_ref','file_000000000920820e8d83b62f05b15906',
  'source','PROJECT_CHAT_IMAGE_20261123',
  'sha256','099ceff11450f1a3aa78df8ddfbf98473395e14e687185b0918b73877d7ccc42',
  'width',1024,'height',1536,'bytes',1155064,
  'status','ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE',
  'avoid_regeneration',true,'chat_delivery_observed',true,
  'qa_verdict','PENDING_INDEPENDENT',
  'official_run_verified',false,'sha256_locally_verified',true,
  'terminal_item_verified',false,
  'qa_comment','Imagen entregada en chat, con desvío cromático CTA y copy Saly Plus/Beneficios. No equivale a aprobación.'
 ),true),
 updated_at=clock_timestamp()
WHERE id=10 AND order_id=7 AND status='PENDIENTE';
DO $check$ BEGIN
 IF (SELECT count(*) FROM saly.creative_order_items WHERE id=10 AND order_id=7
      AND qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}'=
        '099ceff11450f1a3aa78df8ddfbf98473395e14e687185b0918b73877d7ccc42')<>1
 THEN RAISE EXCEPTION 'SALY_HOME7_ARTIFACT_RECONCILIATION_FAILED'; END IF;
END $check$;

-- Separate deterministic technical review; not a semantic approval.
UPDATE saly.creative_order_items SET
 qa_receipt=jsonb_set(qa_receipt,'{chat_judge_v1}',
 jsonb_build_object(
  'schema_version','SALY_CREATIVE_JUDGE_RECEIPT_V1',
  'source_manifest','sandbox/creative_factory/order7_terminal_20261123/source_manifest_v1.json',
  'source_manifest_input_sha256','8bf66605590cb127e41bf5da6fc45c120adf62867aa926530335ea249fcdc8c6',
  'judge_receipt_sha256','4e9aa593ad1df3423ff9d876c67e654a859abe7fe5d50d9b5f7c07667fd208dd',
  'artifact_sha256','099ceff11450f1a3aa78df8ddfbf98473395e14e687185b0918b73877d7ccc42',
  'judge_kind','DETERMINISTIC_TECHNICAL_SEPARATE_PROCESS',
  'technical_verdict','PASS_TECHNICAL_WITH_OBSERVATIONS',
  'semantic_independence_proven',false,
  'semantic_verdict','NOT_INDEPENDENTLY_EVALUATED',
  'production_approved',false,
  'run_verified',false,
  'terminal_semantics','IMAGE_DELIVERED_AND_QA_COMMENTED_NOT_APPROVED',
  'qa_comment','La imagen HOME fue generada y mostrada en chat. PNG íntegro 1024x1536; logo oficial compuesto. CTA difiere de #008200; textos Saly Plus y Beneficios no coinciden. TERMINADO solo significa imagen entregada, no QA semántico aprobado ni producción autorizada.',
  'observations',jsonb_build_array(
   'CTA_COLOR_NOT_MATCHING_APPROVED_TOKEN','SALY_PLUS_COPY_CHANGED',
   'BENEFICIOS_COPY_CHANGED','PRODUCTION_QA_NOT_VERIFIED'),
  'completed_at',clock_timestamp()
 ),true),
 status='TERMINADO',
 updated_at=clock_timestamp()
WHERE id=10 AND order_id=7 AND status='PENDIENTE';

UPDATE saly.creative_orders SET status='TERMINADO',
 completed_at=clock_timestamp(),updated_at=clock_timestamp()
WHERE id=7 AND code='SALY_HOME_V015_SINGLE_20261123' AND status='PLANIFICADO';

DO $post$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.creative_orders WHERE id=7
                   AND status='TERMINADO' AND completed_at IS NOT NULL)
  OR NOT EXISTS (SELECT 1 FROM saly.creative_order_items i WHERE
      i.id=10 AND i.order_id=7 AND i.status='TERMINADO'
      AND i.qa_receipt#>>'{chat_judge_v1,artifact_sha256}' =
          i.qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}'
      AND i.qa_receipt#>>'{chat_judge_v1,production_approved}'='false'
      AND i.qa_receipt#>>'{chat_judge_v1,run_verified}'='false')
  OR EXISTS (SELECT 1 FROM saly.creative_runs WHERE order_id=7 OR item_id=10)
 THEN RAISE EXCEPTION 'SALY_HOME7_ITEM10_TERMINAL_READBACK_FAILED'; END IF;
END $post$;
COMMIT;
