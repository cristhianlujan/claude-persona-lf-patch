-- Disposable PG17 compatibility layer for V16 entry preflight.
-- Extends V02 fixture only; does not recreate customer data.
\set ON_ERROR_STOP on
DO $roles$
BEGIN
 IF to_regrole('anon') IS NULL THEN CREATE ROLE anon; END IF;
 IF to_regrole('authenticated') IS NULL THEN CREATE ROLE authenticated; END IF;
 IF to_regrole('service_role') IS NULL THEN CREATE ROLE service_role; END IF;
 IF to_regrole('supabase_read_only_user') IS NULL
 THEN CREATE ROLE supabase_read_only_user; END IF;
END $roles$;
ALTER TABLE saly.creative_orders
 ADD COLUMN request_kind text NOT NULL DEFAULT 'APP_SCREEN_BATCH';
ALTER TABLE saly.creative_order_items
 ADD COLUMN kind text NOT NULL DEFAULT 'SCREEN';
CREATE TABLE saly.creative_order_sequence_v1(
 order_id bigint PRIMARY KEY REFERENCES saly.creative_orders(id),
 depends_on_order_id bigint NOT NULL UNIQUE REFERENCES saly.creative_orders(id));
CREATE FUNCTION saly.creative_order_sequence_dependency_met_v1(p_order_id bigint)
RETURNS boolean LANGUAGE sql STABLE
AS $f$
 SELECT EXISTS(SELECT 1 FROM saly.creative_orders o WHERE o.id=p_order_id
  AND o.request_kind='APP_SCREEN_SINGLE'
  AND NOT EXISTS(SELECT 1 FROM saly.creative_order_sequence_v1 s
   JOIN saly.creative_orders prior ON prior.id=s.depends_on_order_id
   WHERE s.order_id=o.id AND prior.status<>'TERMINADO'));
$f$;
INSERT INTO saly.creative_orders(code,status,scope_json,request_kind)
VALUES
('SALY_HOME_V015_SINGLE_20261123','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","render_authorized":false,"review_only":true,"rendering_authority":false}'::jsonb,'APP_SCREEN_SINGLE'),
('SALY_ADELANTO_V015_SINGLE_20261123','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","render_authorized":false,"review_only":true,"rendering_authority":false}'::jsonb,'APP_SCREEN_SINGLE');
INSERT INTO saly.creative_order_items(order_id,code,ordinal,status)
SELECT id,CASE WHEN code='SALY_HOME_V015_SINGLE_20261123' THEN 'HOME'
 ELSE 'SOLICITAR_ADELANTO' END,1,'PENDIENTE' FROM saly.creative_orders
WHERE request_kind='APP_SCREEN_SINGLE';
INSERT INTO saly.creative_order_sequence_v1(order_id,depends_on_order_id)
SELECT second.id,first.id FROM saly.creative_orders second
 CROSS JOIN saly.creative_orders first
WHERE second.code='SALY_ADELANTO_V015_SINGLE_20261123'
 AND first.code='SALY_HOME_V015_SINGLE_20261123';
