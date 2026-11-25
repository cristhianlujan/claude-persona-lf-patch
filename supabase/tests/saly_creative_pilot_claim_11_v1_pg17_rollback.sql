\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA saly;
CREATE TABLE saly.creative_orders(id bigint,project_id bigint,status text,code text,scope_json jsonb);
CREATE TABLE saly.creative_order_items(id bigint,order_id bigint,status text,code text);
INSERT INTO saly.creative_orders VALUES(11,2,'PLANIFICADO','ORDER11','{"literal_request":"fixture"}');
INSERT INTO saly.creative_order_items VALUES(15,11,'PENDIENTE','ITEM15');
CREATE FUNCTION saly.creative_queue_claim_next_v1(text,integer) RETURNS jsonb LANGUAGE plpgsql AS $$BEGIN UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=11; UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=15; RETURN '{"status":"CLAIMED","order_id":11,"item_id":15}'::jsonb; END$$;
CREATE FUNCTION saly.creative_skill_prepare_v1(jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$BEGIN IF $1->>'literal_request'<>'fixture' OR $1->>'item_code'<>'ITEM15' THEN RAISE EXCEPTION 'WRONG_PACKET'; END IF; RETURN '{"status":"AUTONOMOUS_PREPARED","image_generation_allowed":true,"logo_ref":{"asset_id":9},"tokens":[{}]}'::jsonb; END$$;
\i /tmp/saly_pilot_claim_body.sql
DO $$BEGIN IF (SELECT status FROM saly.creative_orders WHERE id=11)<>'EN_PROCESO' THEN RAISE EXCEPTION 'CLAIM_NOT_PERSISTED'; END IF; END$$;
ROLLBACK;
