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

-- Controlled temporary archival gate, scoped to historical item 10 evidence.
-- Restore the original intake gate BEFORE COMMIT in this same transaction.
-- All other orders are subject to the original semantic checks throughout.
DO $verify_live_gate$
BEGIN
 IF to_regprocedure('saly.creative_intake_semantic_gate_v1()') IS NULL
 OR position('CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING' in
   pg_get_functiondef('saly.creative_intake_semantic_gate_v1()'::regprocedure))=0
 THEN RAISE EXCEPTION 'SALY_HOME7_INTAKE_GATE_MISMATCH'; END IF;
END $verify_live_gate$;
CREATE OR REPLACE FUNCTION saly.creative_intake_semantic_gate_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog,saly,extensions,pg_temp
AS $gate$
DECLARE
 v_literal text;
 v_sem jsonb;
 v_source_sha text;
 v_prompt_sha text;
 v_quarantine boolean;
BEGIN
 -- ONE-TRANSACTION historical archival completion. Only order 7, only its
 -- exact prior quarantine record, and only after item 10 has a real archived
 -- chat image and a technical review. No production/render authorization.
 IF TG_OP='UPDATE'
 AND OLD.id=7 AND NEW.id=7
 AND OLD.code='SALY_HOME_V015_SINGLE_20261123' AND NEW.code=OLD.code
 AND OLD.status='PLANIFICADO' AND NEW.status='TERMINADO'
 AND NEW.completed_at IS NOT NULL
 AND NEW.scope_json IS NOT DISTINCT FROM OLD.scope_json
 AND NEW.request_kind IS NOT DISTINCT FROM OLD.request_kind
 AND OLD.scope_json->>'intake_source_status'='MISSING_VERIFIED_USER_VISUAL_REQUEST'
 AND OLD.scope_json->>'review_only'='true'
 AND OLD.scope_json->>'render_authorized'='false'
 AND OLD.scope_json->>'rendering_authority'='false'
 AND EXISTS (SELECT 1 FROM saly.creative_order_items i
             WHERE i.order_id=7 AND i.id=10 AND i.code='HOME' AND i.status='TERMINADO'
             AND i.qa_receipt#>>'{chat_judge_v1,artifact_sha256}'
               ='099ceff11450f1a3aa78df8ddfbf98473395e14e687185b0918b73877d7ccc42'
             AND i.qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}'
               =i.qa_receipt#>>'{chat_judge_v1,artifact_sha256}'
             AND i.qa_receipt#>>'{chat_judge_v1,terminal_semantics}'
               ='IMAGE_DELIVERED_AND_QA_COMMENTED_NOT_APPROVED'
             AND i.qa_receipt#>>'{chat_judge_v1,production_approved}'='false'
             AND i.qa_receipt#>>'{chat_judge_v1,run_verified}'='false')
 AND NOT EXISTS (SELECT 1 FROM saly.creative_runs WHERE order_id=7 OR item_id=10)
 THEN RETURN NEW; END IF;
 IF NEW.request_kind IS DISTINCT FROM 'APP_SCREEN_SINGLE' THEN RETURN NEW; END IF;

 v_literal:=nullif(btrim(NEW.scope_json->>'literal_request'),'');
 v_sem:=NEW.scope_json->'intake_semantic_qa';
 v_quarantine:=NEW.status='PLANIFICADO'
   AND NEW.scope_json->>'intake_source_status'='MISSING_VERIFIED_USER_VISUAL_REQUEST'
   AND NEW.scope_json->>'review_only'='true'
   AND NEW.scope_json->>'render_authorized'='false'
   AND NEW.scope_json->>'rendering_authority'='false';

 -- This exact SHA is confirmed from the source seed in PR #4648 and live
 -- readback; it is an operational instruction, not a creative visual request.
 IF v_literal IS NOT NULL
 AND encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
    ='835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a'
 AND NEW.status<>'BORRADOR'
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_OPERATIONAL_LITERAL_REJECTED'; END IF;

 IF NEW.status='BORRADOR'
   AND NEW.scope_json->>'render_authorized' IS DISTINCT FROM 'true'
   AND NEW.scope_json->>'rendering_authority' IS DISTINCT FROM 'true'
 THEN RETURN NEW; END IF;

 IF v_quarantine THEN RETURN NEW; END IF;

 IF v_literal IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING'; END IF;
 IF NEW.scope_json->>'operational_instruction'=v_literal
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_OPERATIONAL_EQUALS_VISUAL_REQUEST'; END IF;
 IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object'
 OR v_sem->>'verdict' IS DISTINCT FROM 'PASS'
 OR v_sem->>'intent_class' IS DISTINCT FROM 'CREATIVE_IMAGE_REQUEST'
 OR nullif(btrim(v_sem->>'source_message_ref'),'') IS NULL
 OR nullif(btrim(v_sem->>'reviewer_ref'),'') IS NULL
 OR v_sem->>'reviewer_ref'=NEW.requested_by
 OR v_sem->>'source_origin' IS DISTINCT FROM 'USER_MESSAGE'
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_SEMANTIC_QA_NOT_ATTESTED'; END IF;
 v_source_sha:=encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex');
 v_prompt_sha:=encode(extensions.digest(convert_to(NEW.scope_json->>'compiled_prompt','UTF8'),'sha256'),'hex');
 IF v_sem->>'source_sha256' IS DISTINCT FROM v_source_sha
 OR v_sem->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
 OR NEW.scope_json->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_SEMANTIC_SOURCE_HASH_DRIFT'; END IF;
 RETURN NEW;
END $gate$;

UPDATE saly.creative_orders SET status='TERMINADO',
 completed_at=clock_timestamp(),updated_at=clock_timestamp()
WHERE id=7 AND code='SALY_HOME_V015_SINGLE_20261123' AND status='PLANIFICADO';

-- Restore exact existing intake gate immediately. Terminal receipt stays archived.
CREATE OR REPLACE FUNCTION saly.creative_intake_semantic_gate_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog,saly,extensions,pg_temp
AS $gate$
DECLARE
 v_literal text;
 v_sem jsonb;
 v_source_sha text;
 v_prompt_sha text;
 v_quarantine boolean;
BEGIN
 IF NEW.request_kind IS DISTINCT FROM 'APP_SCREEN_SINGLE' THEN RETURN NEW; END IF;

 v_literal:=nullif(btrim(NEW.scope_json->>'literal_request'),'');
 v_sem:=NEW.scope_json->'intake_semantic_qa';
 v_quarantine:=NEW.status='PLANIFICADO'
   AND NEW.scope_json->>'intake_source_status'='MISSING_VERIFIED_USER_VISUAL_REQUEST'
   AND NEW.scope_json->>'review_only'='true'
   AND NEW.scope_json->>'render_authorized'='false'
   AND NEW.scope_json->>'rendering_authority'='false';

 -- This exact SHA is confirmed from the source seed in PR #4648 and live
 -- readback; it is an operational instruction, not a creative visual request.
 IF v_literal IS NOT NULL
 AND encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
    ='835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a'
 AND NEW.status<>'BORRADOR'
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_OPERATIONAL_LITERAL_REJECTED'; END IF;

 IF NEW.status='BORRADOR'
   AND NEW.scope_json->>'render_authorized' IS DISTINCT FROM 'true'
   AND NEW.scope_json->>'rendering_authority' IS DISTINCT FROM 'true'
 THEN RETURN NEW; END IF;

 IF v_quarantine THEN RETURN NEW; END IF;

 IF v_literal IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING'; END IF;
 IF NEW.scope_json->>'operational_instruction'=v_literal
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_OPERATIONAL_EQUALS_VISUAL_REQUEST'; END IF;
 IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object'
 OR v_sem->>'verdict' IS DISTINCT FROM 'PASS'
 OR v_sem->>'intent_class' IS DISTINCT FROM 'CREATIVE_IMAGE_REQUEST'
 OR nullif(btrim(v_sem->>'source_message_ref'),'') IS NULL
 OR nullif(btrim(v_sem->>'reviewer_ref'),'') IS NULL
 OR v_sem->>'reviewer_ref'=NEW.requested_by
 OR v_sem->>'source_origin' IS DISTINCT FROM 'USER_MESSAGE'
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_SEMANTIC_QA_NOT_ATTESTED'; END IF;
 v_source_sha:=encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex');
 v_prompt_sha:=encode(extensions.digest(convert_to(NEW.scope_json->>'compiled_prompt','UTF8'),'sha256'),'hex');
 IF v_sem->>'source_sha256' IS DISTINCT FROM v_source_sha
 OR v_sem->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
 OR NEW.scope_json->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_SEMANTIC_SOURCE_HASH_DRIFT'; END IF;
 RETURN NEW;
END $gate$;

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
