-- Isolated synthetic PG17. ONLY after queue_v02/fixture_pg17.sql and V12 DDL.
-- Existing fixture has READY items; ensure none can hijack scoped V12 claim.
UPDATE saly.creative_order_items SET status='BLOQUEADO' WHERE status='LISTO';

INSERT INTO saly.creative_orders(code,status,scope_json)
VALUES
 ('V12_CHAT','PLANIFICADO',
  '{"queue_mode":"SERIAL_V1","rendering_authority":true,"review_only":false}'::jsonb),
 ('V12_OTHER','PLANIFICADO',
  '{"queue_mode":"SERIAL_V1","rendering_authority":true,"review_only":false}'::jsonb),
 ('V12_REVIEW','PLANIFICADO',
  '{"queue_mode":"SERIAL_V1","rendering_authority":true,"review_only":true}'::jsonb),
 ('V12_EMPTY','PLANIFICADO',
  '{"queue_mode":"SERIAL_V1","rendering_authority":true,"review_only":false}'::jsonb);

INSERT INTO saly.creative_order_items(order_id,code,ordinal,status)
SELECT o.id, x.code,x.ordinal,'PENDIENTE'
FROM saly.creative_orders o
JOIN (VALUES ('HOME',1),('ADELANTO',2),('REWARDS',3))
 AS x(code,ordinal) ON true
WHERE o.code='V12_CHAT';

INSERT INTO saly.creative_order_items(order_id,code,ordinal,status)
SELECT id,'HOME',1,'PENDIENTE'
FROM saly.creative_orders WHERE code IN ('V12_OTHER','V12_REVIEW');
