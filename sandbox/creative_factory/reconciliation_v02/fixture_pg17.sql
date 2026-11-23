-- PG17 disposable minimal projection of existing SALY creative L1 status/guard contract.
-- Does not require a live service-role credential or touch Supabase.
DROP SCHEMA IF EXISTS saly CASCADE;
CREATE SCHEMA saly;
CREATE TABLE saly.creative_orders (
 id bigint PRIMARY KEY,code text NOT NULL UNIQUE,status text NOT NULL,
 completed_at timestamptz NULL,
 CONSTRAINT creative_orders_status_check CHECK (status=ANY(ARRAY[
 'BORRADOR','PLANIFICADO','EN_PROCESO','EN_QA','COMPLETADO','BLOQUEADO','CANCELADO']::text[])),
 CONSTRAINT creative_orders_closure_chk CHECK ((status='COMPLETADO')=(completed_at IS NOT NULL))
);
CREATE TABLE saly.creative_order_items (
 id bigint PRIMARY KEY,order_id bigint NOT NULL REFERENCES saly.creative_orders(id),
 code text NOT NULL,status text NOT NULL,required boolean NOT NULL DEFAULT true,
 title text NOT NULL,acceptance_json jsonb NOT NULL DEFAULT '{}'::jsonb,
 context_json jsonb NOT NULL DEFAULT '{}'::jsonb,
 qa_receipt jsonb NOT NULL DEFAULT '{}'::jsonb,
 approved_at timestamptz NULL,approved_by text NULL,
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT creative_order_items_status_check CHECK (status=ANY(ARRAY[
 'PENDIENTE','LISTO','PRODUCIENDO','EN_QA','APROBADO','BLOQUEADO','OMITIDO']::text[]))
);
CREATE TABLE saly.creative_runs (
 id bigint PRIMARY KEY,order_id bigint,item_id bigint,
 state text NOT NULL
);
CREATE TABLE saly.creative_item_dependencies (
 order_id bigint NOT NULL,item_id bigint NOT NULL,
 depends_on_item_id bigint NOT NULL,
 PRIMARY KEY(order_id,item_id,depends_on_item_id)
);
-- Preserve baseline hard gating on APROBADO and COMPLETADO.
CREATE FUNCTION saly.creative_item_guard_l1()
RETURNS trigger LANGUAGE plpgsql AS $old$
DECLARE v_order_status text;
BEGIN
 SELECT status INTO v_order_status FROM saly.creative_orders WHERE id=NEW.order_id FOR UPDATE;
 IF v_order_status IN ('COMPLETADO','CANCELADO') THEN
  RAISE EXCEPTION 'CREATIVE_CLOSED_ORDER_IMMUTABLE_ITEMS'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='APROBADO'
 THEN RAISE EXCEPTION 'CREATIVE_APPROVED_ITEM_IMMUTABLE'; END IF;
 IF NEW.status='APROBADO' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
  IF TG_OP='INSERT' OR OLD.status<>'EN_QA' THEN
   RAISE EXCEPTION 'CREATIVE_ITEM_NOT_IN_QA'; END IF;
  IF NOT EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.order_id=NEW.order_id
      AND r.item_id=NEW.id AND r.state='EXITOSO') THEN
   RAISE EXCEPTION 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING'; END IF;
 END IF;
 RETURN NEW;
END $old$;
CREATE TRIGGER trg_creative_item_guard_l1
 BEFORE INSERT OR UPDATE ON saly.creative_order_items
 FOR EACH ROW EXECUTE FUNCTION saly.creative_item_guard_l1();
CREATE FUNCTION saly.creative_order_close_guard_l1()
RETURNS trigger LANGUAGE plpgsql AS $old$
BEGIN
 IF NEW.status='COMPLETADO' AND
  (TG_OP='INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
  IF EXISTS (SELECT 1 FROM saly.creative_order_items i WHERE i.order_id=NEW.id
   AND i.status NOT IN ('APROBADO','OMITIDO'))
  THEN RAISE EXCEPTION 'CREATIVE_ORDER_CLOSURE_WITH_INCOMPLETE_DETAILS'; END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status='COMPLETADO'
 THEN RAISE EXCEPTION 'CREATIVE_COMPLETED_ORDER_IMMUTABLE'; END IF;
 RETURN NEW;
END $old$;
CREATE TRIGGER trg_creative_order_close_guard_l1
 BEFORE UPDATE ON saly.creative_orders
 FOR EACH ROW EXECUTE FUNCTION saly.creative_order_close_guard_l1();
INSERT INTO saly.creative_orders VALUES
 (4,'SALY_HOME_BATCH_001','PLANIFICADO',NULL),
 (5,'SALY_HOME_TEMPLATE_AB_001','PLANIFICADO',NULL),
 (6,'SALY_FOREIGN_ORDER_001','PLANIFICADO',NULL);
INSERT INTO saly.creative_item_dependencies VALUES(4,6,5),(4,7,5);
INSERT INTO saly.creative_order_items
(id,order_id,code,status,title,qa_receipt)
SELECT (value->>'item_id')::bigint,
 CASE WHEN value->>'order_code'='SALY_HOME_BATCH_001' THEN 4 ELSE 5 END,
 value->>'item_code','PENDIENTE',value->>'item_code',
 jsonb_build_object('chat_artifact_reconciliation_v1',
  jsonb_build_object(
   'status','ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE',
   'filename',value->>'filename','sha256',value->>'artifact_sha256',
   'chat_delivery_observed',true,'avoid_regeneration',true,
   'qa_verdict','PENDING_INDEPENDENT','official_run_verified',false))
FROM jsonb_array_elements($images$
[{"item_id":5,"order_code":"SALY_HOME_BATCH_001","item_code":"HOME","filename":"03_HOME_PRINCIPAL_LOGO_OFICIAL.png","artifact_sha256":"cba43bc26d06f40eb037c24c7d8f2ed8fe666042e3bdf9748e0cc4cc775f0990","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL","qa_comment":"Home presentado: composición de referencia corregida y CTA verde. Coincide dimensión 1086x1448. Semántica completa y comparación de fuente quedan NO_EVALUADAS por juez independiente.","observations":[],"judge_receipt_sha256":"6d490612f690ff9a02119071a2eff1977ea8134d97b138f941037444a980f733","judge_input_sha256":"736b561352c724a038fba7883bfd782bc653569fa7f8ab6cb89ae661085dbf5c"},{"item_id":6,"order_code":"SALY_HOME_BATCH_001","item_code":"ADELANTO","filename":"04_SOLICITUD_ADELANTO.png","artifact_sha256":"9f08caec72e426bd0253bf2d28cb2c9ef70e742fb5e83d42ca9dcfd1ee283a92","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Solicitud de adelanto: arte recibido 1086x1448; blueprint requiere 1024x1536. Diferencia dimensional; no equivale a QA aprobado.","observations":["OUTPUT_DIMENSIONS_MISMATCH"],"judge_receipt_sha256":"6099e9d41bbcc136e404652397aa7c5887218a6350c493a81aa6528f801528c6","judge_input_sha256":"581b1e22696165196889eec2da2704b5df2176f568b36e4402e98faefd5d7e9c"},{"item_id":7,"order_code":"SALY_HOME_BATCH_001","item_code":"REWARDS","filename":"05_SALY_REWARDS.png","artifact_sha256":"6cbe7c336ed0e1d39ba93c37a39fe9822a54f9f288a04e1c6274cc56504b62cd","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Rewards: copy de sorteos visible. Premios S/200 y S/50 y hábitos 1/2/3 son elementos ilustrativos sin fuente aprobada verificada; no promoverlos como reglas.","observations":["UNVERIFIED_REWARDS_PRIZE_VALUES","PLACEHOLDER_REWARDS_HABITS"],"judge_receipt_sha256":"6c9b880aaff8ae3ed985044637490e752cc058d06f7cbaf9d3215e5e115a2a0e","judge_input_sha256":"23e46c210e038483cf1f416c5c2a6d1eee3a68c7d3564ecf9f791e23b35dc7c4"},{"item_id":8,"order_code":"SALY_HOME_TEMPLATE_AB_001","item_code":"HOME_A","filename":"01_HOME_A_IPHONE16PRO.png","artifact_sha256":"5d0960b46b9140da69b6157b0b6a5ae9b7de365551aaad30bc9b96550de5a3d9","width":1024,"height":1536,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Home A: imagen existente conservada, con importe de muestra S/575, CTA y navegación. Pedido origen REVIEW_ONLY: producción no acreditada.","observations":["REVIEW_ONLY_ORIGIN"],"judge_receipt_sha256":"5c2226f2bd2cafd24d5fc28bcdc6f4b7c57e3bd7e59d912ed78fe0506f15e9f5","judge_input_sha256":"4028f0333cb0953a183114ed17ef4240b89b0a57e30df46616fd97eadbb85769"},{"item_id":9,"order_code":"SALY_HOME_TEMPLATE_AB_001","item_code":"HOME_B","filename":"02_HOME_B_LOGO_FOOTER.png","artifact_sha256":"c39e2f99aa949c8bc57b12e3aa7f1ef5567a299c2ddc67ea9d7ecfb562c7319f","width":1086,"height":1448,"technical_verdict":"PASS_TECHNICAL_WITH_OBSERVATIONS","qa_comment":"Home B: imagen existente conservada, con logo, CTA y footer. Pedido origen REVIEW_ONLY: producción no acreditada.","observations":["REVIEW_ONLY_ORIGIN"],"judge_receipt_sha256":"a7d61d5c78a48837d6ecf00d0d2ca787682875b1e5bccb3bf43eb3bba728ea99","judge_input_sha256":"fd959f83679923c316436ba1d22c600da650b7df89bedb665efa0a198cb47da6"}]
$images$::jsonb) AS value;
INSERT INTO saly.creative_order_items
(id,order_id,code,status,title,qa_receipt) VALUES
(10,6,'OTHER','PENDIENTE','Foreign not in scope','{}'::jsonb);
