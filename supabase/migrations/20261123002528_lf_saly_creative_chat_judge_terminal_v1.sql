-- SALY chat images already delivered: judge-reviewed terminal state, NOT QA approval.
-- Source: sandbox/creative_factory/reconciliation_v02/judge_manifest_v1.json
-- Creative skill: skills/creative_factory/SKILL.md, LF resguardos Parte A/2.
-- One governed historical completion of items 5..9. No fictitious RUN,
-- no provider receipt, no production_approved, no change to APROBADO gate.
BEGIN;

DO $pre$
BEGIN
 IF to_regclass('saly.creative_orders') IS NULL
 OR to_regclass('saly.creative_order_items') IS NULL
 OR to_regclass('saly.creative_runs') IS NULL
 OR to_regclass('saly.creative_item_dependencies') IS NULL
 OR to_regprocedure('saly.creative_item_guard_l1()') IS NULL
 OR to_regprocedure('saly.creative_order_close_guard_l1()') IS NULL
 THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_SCHEMA_REQUIRED'; END IF;
 IF (SELECT count(*) FROM saly.creative_order_items WHERE id=ANY(ARRAY[5,6,7,8,9]::bigint[]) AND status='PENDIENTE')<>5
 OR (SELECT count(*) FROM saly.creative_runs WHERE item_id=ANY(ARRAY[5,6,7,8,9]::bigint[]))<>0
 THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.creative_orders WHERE id IN (4,5) AND status='PLANIFICADO')<>2
 THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_PRESTATE_DRIFT'; END IF;
END $pre$;

ALTER TABLE saly.creative_order_items DROP CONSTRAINT creative_order_items_status_check;
ALTER TABLE saly.creative_order_items ADD CONSTRAINT creative_order_items_status_check
 CHECK (status=ANY(ARRAY['PENDIENTE','LISTO','PRODUCIENDO','EN_QA','APROBADO',
                        'BLOQUEADO','OMITIDO','TERMINADO']::text[]));

ALTER TABLE saly.creative_orders DROP CONSTRAINT creative_orders_status_check;
ALTER TABLE saly.creative_orders ADD CONSTRAINT creative_orders_status_check
 CHECK (status=ANY(ARRAY['BORRADOR','PLANIFICADO','EN_PROCESO','EN_QA','COMPLETADO',
                        'BLOQUEADO','CANCELADO','TERMINADO']::text[]));
ALTER TABLE saly.creative_orders DROP CONSTRAINT creative_orders_closure_chk;
ALTER TABLE saly.creative_orders ADD CONSTRAINT creative_orders_closure_chk
 CHECK ((status IN ('COMPLETADO','TERMINADO'))=(completed_at IS NOT NULL));

-- Independent rule for TERMINADO. Existing APROBADO trigger remains intact.
CREATE FUNCTION saly.creative_chat_terminal_item_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog,saly,pg_temp
AS $guard$
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
END $guard$;

CREATE TRIGGER trg_saly_creative_chat_terminal_item_guard_v1
BEFORE UPDATE OR DELETE ON saly.creative_order_items FOR EACH ROW
EXECUTE FUNCTION saly.creative_chat_terminal_item_guard_v1();

CREATE FUNCTION saly.creative_chat_terminal_order_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog,saly,pg_temp
AS $guard$
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
END $guard$;

CREATE TRIGGER trg_saly_creative_chat_terminal_order_guard_v1
BEFORE UPDATE OR DELETE ON saly.creative_orders FOR EACH ROW
EXECUTE FUNCTION saly.creative_chat_terminal_order_guard_v1();

REVOKE ALL ON FUNCTION saly.creative_chat_terminal_item_guard_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_chat_terminal_order_guard_v1() FROM PUBLIC;

-- Exact five actual PNGs, judged as delivery/review completion, never QA approval.
DO $terminal$
DECLARE
 v jsonb;
 v_order record;
 v_item record;
 v_now timestamptz:=clock_timestamp();
 v_j jsonb;
 v_n integer:=0;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:chat-terminal:v1',0));
 FOR v IN SELECT value FROM jsonb_array_elements($images$
[{"item_id":5,"order_code":"SALY_HOME_BATCH_001","item_code":"HOME","filename":"03_HOME_PRINCIPAL_LOGO_OFICIAL.png","artifact_sha256":"cba43bc26d06f40eb037c24c7d8f2ed8fe666042e3bdf9748e0cc4cc775f0990","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL","qa_comment":"Home presentado: composición de referencia corregida y CTA verde. Coincide dimensión 1086x1448. Semántica completa y comparación de fuente quedan NO_EVALUADAS por juez independiente.","observations":[],"judge_receipt_sha256":"6d490612f690ff9a02119071a2eff1977ea8134d97b138f941037444a980f733","judge_input_sha256":"736b561352c724a038fba7883bfd782bc653569fa7f8ab6cb89ae661085dbf5c"},{"item_id":6,"order_code":"SALY_HOME_BATCH_001","item_code":"ADELANTO","filename":"04_SOLICITUD_ADELANTO.png","artifact_sha256":"9f08caec72e426bd0253bf2d28cb2c9ef70e742fb5e83d42ca9dcfd1ee283a92","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Solicitud de adelanto: arte recibido 1086x1448; blueprint requiere 1024x1536. Diferencia dimensional; no equivale a QA aprobado.","observations":["OUTPUT_DIMENSIONS_MISMATCH"],"judge_receipt_sha256":"6099e9d41bbcc136e404652397aa7c5887218a6350c493a81aa6528f801528c6","judge_input_sha256":"581b1e22696165196889eec2da2704b5df2176f568b36e4402e98faefd5d7e9c"},{"item_id":7,"order_code":"SALY_HOME_BATCH_001","item_code":"REWARDS","filename":"05_SALY_REWARDS.png","artifact_sha256":"6cbe7c336ed0e1d39ba93c37a39fe9822a54f9f288a04e1c6274cc56504b62cd","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Rewards: copy de sorteos visible. Premios S/200 y S/50 y hábitos 1/2/3 son elementos ilustrativos sin fuente aprobada verificada; no promoverlos como reglas.","observations":["UNVERIFIED_REWARDS_PRIZE_VALUES","PLACEHOLDER_REWARDS_HABITS"],"judge_receipt_sha256":"6c9b880aaff8ae3ed985044637490e752cc058d06f7cbaf9d3215e5e115a2a0e","judge_input_sha256":"23e46c210e038483cf1f416c5c2a6d1eee3a68c7d3564ecf9f791e23b35dc7c4"},{"item_id":8,"order_code":"SALY_HOME_TEMPLATE_AB_001","item_code":"HOME_A","filename":"01_HOME_A_IPHONE16PRO.png","artifact_sha256":"5d0960b46b9140da69b6157b0b6a5ae9b7de365551aaad30bc9b96550de5a3d9","width":1024,"height":1536,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Home A: imagen existente conservada, con importe de muestra S/575, CTA y navegación. Pedido origen REVIEW_ONLY: producción no acreditada.","observations":["REVIEW_ONLY_ORIGIN"],"judge_receipt_sha256":"5c2226f2bd2cafd24d5fc28bcdc6f4b7c57e3bd7e59d912ed78fe0506f15e9f5","judge_input_sha256":"4028f0333cb0953a183114ed17ef4240b89b0a57e30df46616fd97eadbb85769"},{"item_id":9,"order_code":"SALY_HOME_TEMPLATE_AB_001","item_code":"HOME_B","filename":"02_HOME_B_LOGO_FOOTER.png","artifact_sha256":"c39e2f99aa949c8bc57b12e3aa7f1ef5567a299c2ddc67ea9d7ecfb562c7319f","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Home B: imagen existente conservada, con logo, CTA y footer. Pedido origen REVIEW_ONLY: producción no acreditada.","observations":["REVIEW_ONLY_ORIGIN"],"judge_receipt_sha256":"a7d61d5c78a48837d6ecf00d0d2ca787682875b1e5bccb3bf43eb3bba728ea99","judge_input_sha256":"fd959f83679923c316436ba1d22c600da650b7df89bedb665efa0a198cb47da6"}]
$images$::jsonb) AS value ORDER BY (value->>'item_id')::bigint
 LOOP
  SELECT o.id,o.code,o.status INTO v_order
  FROM saly.creative_orders o WHERE o.code=v->>'order_code' FOR UPDATE;
  SELECT i.id,i.code,i.status,i.qa_receipt INTO v_item
  FROM saly.creative_order_items i
  WHERE i.id=(v->>'item_id')::bigint AND i.order_id=v_order.id
    AND i.code=v->>'item_code' FOR UPDATE;
  IF v_order.id IS NULL OR v_order.status<>'PLANIFICADO'
  OR v_item.id IS NULL OR v_item.status<>'PENDIENTE'
  OR v_item.qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}'
     IS DISTINCT FROM v->>'artifact_sha256'
  OR v_item.qa_receipt#>>'{chat_artifact_reconciliation_v1,filename}'
     IS DISTINCT FROM v->>'filename'
  THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_MANIFEST_OR_PRESTATE_DRIFT:item=%',v->>'item_id'; END IF;
  v_j:=jsonb_build_object(
   'schema_version','SALY_CREATIVE_JUDGE_RECEIPT_V1',
   'source_manifest','sandbox/creative_factory/reconciliation_v02/judge_manifest_v1.json',
   'source_manifest_input_sha256',v->>'judge_input_sha256',
   'judge_receipt_sha256',v->>'judge_receipt_sha256',
   'artifact_sha256',v->>'artifact_sha256',
   'judge_kind','DETERMINISTIC_TECHNICAL_SEPARATE_PROCESS',
   'technical_verdict',v->>'technical_verdict',
   'semantic_independence_proven',false,
   'semantic_verdict','NOT_INDEPENDENTLY_EVALUATED',
   'production_approved',false,
   'run_verified',false,
   'terminal_semantics','IMAGE_DELIVERED_AND_QA_COMMENTED_NOT_APPROVED',
   'qa_comment',v->>'qa_comment',
   'observations',v->'observations',
   'completed_at',v_now
  );
  UPDATE saly.creative_order_items SET
    qa_receipt=jsonb_set(qa_receipt,'{chat_judge_v1}',v_j,true),
    status='TERMINADO',updated_at=v_now WHERE id=v_item.id AND status='PENDIENTE';
  IF NOT FOUND THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_WRITE_LOST'; END IF;
  v_n:=v_n+1;
 END LOOP;
 IF v_n<>5 THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_COUNT_DRIFT'; END IF;
 UPDATE saly.creative_orders SET status='TERMINADO',completed_at=v_now
 WHERE id IN (4,5) AND status='PLANIFICADO';
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDERS_NOT_CLOSED'; END IF;
 IF (SELECT count(*) FROM saly.creative_orders WHERE id IN (4,5)
      AND status='TERMINADO' AND completed_at IS NOT NULL)<>2
 OR (SELECT count(*) FROM saly.creative_order_items WHERE id=ANY(ARRAY[5,6,7,8,9]::bigint[])
      AND status='TERMINADO' AND qa_receipt ? 'chat_judge_v1')<>5
 OR (SELECT count(*) FROM saly.creative_runs WHERE item_id=ANY(ARRAY[5,6,7,8,9]::bigint[]))<>0
 THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_FINAL_READBACK_MISMATCH'; END IF;
 RAISE NOTICE 'PASS_SALY_CHAT_TERMINAL_FIVE_ITEMS_TWO_ORDERS_NO_RUN_FABRICATED';
END $terminal$;
COMMIT;
