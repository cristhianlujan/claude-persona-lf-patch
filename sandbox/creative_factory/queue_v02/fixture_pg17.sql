-- Isolated PostgreSQL 17 compatibility harness. Never run on production.
\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS saly CASCADE;
CREATE SCHEMA saly;
CREATE TABLE saly.creative_orders (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, code text NOT NULL,
 status text NOT NULL, scope_json jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 completed_at timestamptz
);
CREATE TABLE saly.creative_order_items (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL REFERENCES saly.creative_orders(id),
 code text NOT NULL, ordinal integer NOT NULL, status text NOT NULL,
 required boolean NOT NULL DEFAULT true
);
CREATE TABLE saly.creative_runs (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL, item_id bigint NOT NULL,
 state text NOT NULL, output_evidence jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE saly.creative_item_dependencies (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL, item_id bigint NOT NULL, depends_on_item_id bigint NOT NULL
);
\ir 001_saly_queue_serial_candidate.sql

INSERT INTO saly.creative_orders (code,status,scope_json,created_at)
VALUES
 ('LEGACY','PLANIFICADO','{"rendering_authority":false}'::jsonb,'2026-11-01'),
 ('ACTIVE_A','PLANIFICADO','{"rendering_authority":true}'::jsonb,'2026-11-02'),
 ('ACTIVE_B','PLANIFICADO','{"rendering_authority":true}'::jsonb,'2026-11-03'),
 ('ACTIVE_C','PLANIFICADO','{"rendering_authority":true}'::jsonb,'2026-11-04'),
 ('REVIEW','PLANIFICADO','{"rendering_authority":true,"review_only":true}'::jsonb,'2026-11-01'),
 ('CANCELLED','CANCELADO','{"rendering_authority":true}'::jsonb,'2026-10-01');
INSERT INTO saly.creative_order_items (order_id,code,ordinal,status)
SELECT id,'HOME',1,'PENDIENTE' FROM saly.creative_orders;
INSERT INTO saly.creative_order_items (order_id,code,ordinal,status)
SELECT id,'ADELANTO',2,'PENDIENTE' FROM saly.creative_orders WHERE code='ACTIVE_A';
INSERT INTO saly.creative_item_dependencies(order_id,item_id,depends_on_item_id)
SELECT o.id,i.id,p.id FROM saly.creative_orders o
JOIN saly.creative_order_items i ON i.order_id=o.id AND i.code='ADELANTO'
JOIN saly.creative_order_items p ON p.order_id=o.id AND p.code='HOME'
WHERE o.code='ACTIVE_A';