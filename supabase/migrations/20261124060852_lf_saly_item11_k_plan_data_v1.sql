-- SALY item 11: K01-K06 planning evidence only; no pre-QA mutation.
BEGIN;
DO $$
DECLARE
 v_plan jsonb := $plan${"item_id":11,"source":"OWNER_CHAT_CLAUDE_2026-11-24T00:31-05:00","presentation":"mockup frontal iPhone 16 Pro centrado, fondo gris muy claro, luz suave, sin manos ni perspectiva","content":"Volver, Solicitar adelanto, ayuda; disponible S/ 580; ¿Cuánto necesitas? S/ 300, S/ 450, S/ 570 seleccionado, entrada manual; solicitado S/ 570.00, cargos S/ 12.00, recibir S/ 558.00, descuento 30 de noviembre; Continuar.","decisions":[{"module":"K01","step":"5","alternatives":["Dirección transaccional sobria","Dirección promocional con ilustración"],"choice":"Transaccional sobria","reason":"El colaborador necesita entender importes y condiciones antes de continuar; la promoción compite con esa finalidad."},{"module":"K02","step":"5","alternatives":["Franja de disponible y resumen abierto","Tarjetas separadas para saldo y resumen"],"choice":"Franja y resumen abierto","reason":"Reduce contenedores redundantes y conserva diferenciación de importes."},{"module":"K03","step":"6","alternatives":["Saldo dominante y CTA final","Monto a recibir dominante desde el encabezado"],"choice":"Saldo dominante al inicio y monto a recibir destacado en resumen","reason":"Respeta la secuencia de decisión sin confundir saldo con desembolso."},{"module":"K04","step":"6","alternatives":["Tres opciones en fila y entrada manual debajo","Tres opciones apiladas"],"choice":"Fila de tres opciones y entrada manual debajo","reason":"Aprovecha ancho y reduce altura; cabida estimada, no medida; mantener legibilidad."},{"module":"K05","step":"7","alternatives":["Handoff por componentes con copy literal","Narración libre"],"choice":"Handoff por componentes","reason":"Conserva asociación entre montos, cargos, fecha y CTA; no hay envío todavía."},{"module":"K06","step":"8","alternatives":["Lista de requisitos por componente","Puntuación estética global"],"choice":"Lista por componente","reason":"Permite detectar omisiones y contradicciones sin afirmar evaluación independiente ni visual."}],"qa_visual":"NO_EVALUADO","independent_review":"PENDING","handoff_sent":false}$plan$::jsonb;
 v_sha text;
 v_k jsonb;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.creative_order_items WHERE id=11 AND order_id=8 AND status='LISTO') THEN
  RAISE EXCEPTION 'SALY_ITEM11_EXPECTED_STATE_MISSING';
 END IF;
 PERFORM saly.creative_task_select_once_v2(11,'NEW_SCREEN',false);
 v_sha := encode(extensions.digest(v_plan::text,'sha256'),'hex');
 FOR v_k IN SELECT value FROM jsonb_array_elements(v_plan->'decisions')
 LOOP
  PERFORM saly.creative_k_record_once_v2(11,'PLAN',v_sha,v_k->>'module','EJECUTADO',v_k->>'step',
   jsonb_build_object('plan_snapshot',v_plan,'alternatives',v_k->'alternatives','source','OWNER_CHAT_CLAUDE_2026-11-24T00:31-05:00'),
   jsonb_build_object('choice',v_k->>'choice','reason',v_k->>'reason','qa_visual','NO_EVALUADO','independent_review','PENDING'));
 END LOOP;
END $$;
COMMIT;
