-- Owner complement 2026-11-24 01:27 Lima. Simulation data only.
BEGIN;
DO $$
DECLARE v_values jsonb := '{"disponible":580,"opciones":[300,450,570],"seleccionado":570,"solicitado":570.00,"cargos":12.00,"a_recibir":558.00,"fecha_descuento":"30 de noviembre","nota":"montos de ejemplo, simulación para imágenes"}'::jsonb;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.creative_order_items WHERE id=11 AND order_id=8 AND status='LISTO')
 OR NOT EXISTS (SELECT 1 FROM saly.creative_plan_pre_qa_v2 WHERE item_id=11 AND plan_sha256='7ae12ff84494e2735a2ffde9c76a04f61401bcfd5a0d305e8c51ae099159e5df' AND verdict='PASS')
 THEN RAISE EXCEPTION 'SALY_ITEM11_EXPECTED_PLAN_OR_STATE_MISSING'; END IF;
 UPDATE saly.creative_orders
 SET scope_json=scope_json||jsonb_build_object('example_values',v_values,
  'example_values_source','OWNER_CHAT_CLAUDE_2026-11-24T01:27-05:00',
  'example_values_plan_sha256','7ae12ff84494e2735a2ffde9c76a04f61401bcfd5a0d305e8c51ae099159e5df'),updated_at=now()
 WHERE id=8 AND scope_json->'example_values' IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_ITEM11_EXAMPLE_VALUES_NOT_EMPTY'; END IF;
END $$;
COMMIT;
