BEGIN;
DO $intake$
DECLARE pid bigint; cid bigint; result record;
BEGIN
 SELECT id INTO STRICT pid FROM saly.proyecto WHERE id=3 AND codigo='LF';
 SELECT id INTO STRICT cid FROM saly.creative_context_sets WHERE project_id=pid AND code='LF_DS_V1_TEST' AND state='SEALED';
 SELECT * INTO STRICT result FROM saly.creative_order_create_v1(pid,cid,'LF_TU_OFERTA_V1_20261126','LF_TU_OFERTA_V1_20261126','Tu oferta','CHAT_USER',$j${"literal_request":"Pantalla de app móvil (390 x 844) de Libertad Financiera, plataforma peruana de negociación de deuda castigada. Pantalla Tu oferta: título Tu oferta; la cuota mensual como elemento visualmente dominante (marcadores literales S/ [CUOTA], por [N] meses, total S/ [TOTAL]; no inventar cifras) y el total con menos peso; explicación visual del traslado de la deuda de BBVA a Finanty con la frase Tu deuda de BBVA pasa a Finanty; la carta de no adeudo como algo tangible y visible antes del botón, con el texto Te la entregamos al cerrar tu deuda; botón principal con el texto exacto Cerrar mi deuda y recibir mi carta ahora.","literal_origin":"OWNER_LITERAL_CHAT","module":"Tu oferta","state_code":"TU_OFERTA","rendering_authority":true,"render_authorized":true,"review_only":false,"queue_mode":"SERIAL_V1"}$j$::jsonb,'TU_OFERTA','Tu oferta',$j{"qa_checklist":{"literal_fidelity":true,"placeholders_exact":true,"lf_identity":true,"monthly_payment_dominant":true,"debt_transfer":true,"letter_visible_before_cta":true,"cta_exact":true},"qa_required":true}$j$::jsonb,$j{"screen_spec":{"screen":"TU_OFERTA","width":390,"height":844},"reference_only":false}$j$::jsonb);
 RAISE NOTICE 'LF_TU_OFERTA_ORDER_ID % ITEM_ID %',result.order_id,result.item_id;
END $intake$;
COMMIT;
