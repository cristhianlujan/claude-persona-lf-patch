-- Reconcile actual chat artifacts, item 11 only. No fabricated RUN or approval.
BEGIN;
DO $$
DECLARE v_examples jsonb; v_receipt jsonb;
BEGIN
 SELECT scope_json->'example_values' INTO STRICT v_examples FROM saly.creative_orders WHERE id=8 AND status='PLANIFICADO' FOR UPDATE;
 IF v_examples IS NULL OR NOT EXISTS (SELECT 1 FROM saly.creative_order_items WHERE id=11 AND order_id=8 AND status='LISTO' AND qa_receipt='{}'::jsonb)
 THEN RAISE EXCEPTION 'SALY_ITEM11_EXPECTED_STATE_MISSING'; END IF;
 v_receipt:=jsonb_build_object(
 'generator','GPT','reviewer','Claude','production_approved',false,
 'official_run_verified',false,'chat_delivery_observed',true,'avoid_regeneration',true,
 'terminal_semantics','IMAGE_DELIVERED_NOT_OWNER_APPROVED',
 'closure_pending_reason','CREATIVE_ITEM_NOT_IN_QA',
 'example_values',v_examples,
 'plan_sha256','7ae12ff84494e2735a2ffde9c76a04f61401bcfd5a0d305e8c51ae099159e5df',
 'current_generation_id','57e2a5d1-4603-4783-bfce-b7a5321306fe',
 'iterations',jsonb_build_array(
 jsonb_build_object('iteration',1,'status','REEMPLAZADA','generation_id','f02daad9-2225-426e-a57d-f6412385b2df','file_ref','file_00000000fe50820e9e09eb3bcba9d96c','filename','a_clean_product_style_phone_ui_screenshot_a_front.png','format','PNG','sha256','67e37a89a99a556fc223ee24b0e85c483113ebf4679ae4e0557614bccc77114a','bytes',1368250,'width',1024,'height',1536,'content_verdict','PASS','design_verdict','MEDIO','reviewer','Claude','generator','GPT','observations',jsonb_build_array('Identidad SALY insuficiente','Jerarquía plana','Tipografía pequeña','Poco aire y cabecera apretada')),
 jsonb_build_object('iteration',2,'status','VIGENTE','generation_id','57e2a5d1-4603-4783-bfce-b7a5321306fe','file_ref','file_000000008474820e9f67068a0faa20ed','filename','mockup_de_iphone_con_adelanto_saly.png','format','PNG','sha256','490d86dc8b95b621ab6f3ee69b954900a50e089b4abd1e25da4b2a322ff5e669','bytes',1450515,'width',1024,'height',1536,'content_verdict','PASS','design_verdict','BUENO_ALTO_VALOR_PROTOTIPO','reviewer','Claude','generator','GPT','delivery_verdict','ACEPTADA_COMO_ENTREGADA','semantic_qa_source','CLAUDE_REVIEW_RELAYED_IN_CHAT','production_approved',false,'observations',jsonb_build_array('Logo oficial Drive no contrastado','Cabecera algo apretada'))));
 UPDATE saly.creative_order_items SET qa_receipt=jsonb_build_object('chat_iterations_v1',v_receipt),updated_at=now() WHERE id=11 AND order_id=8;
 -- Prevent accidental second dispatch while actual chat delivery is reconciled.
 UPDATE saly.creative_orders SET scope_json=scope_json||jsonb_build_object('render_authorized',false,'block_reason','CHAT_ARTIFACT_DELIVERED_PENDING_GOVERNED_CLOSURE'),updated_at=now() WHERE id=8;
END $$;
COMMIT;
