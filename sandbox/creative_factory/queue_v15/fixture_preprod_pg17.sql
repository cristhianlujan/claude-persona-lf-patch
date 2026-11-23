-- Disposable PG17 fixture adapter for V05 original candidate regression.
-- Main queue_v02/fixture_pg17.sql + V06 will be loaded before this.
\set ON_ERROR_STOP on
DO $roles$
BEGIN
 IF to_regrole('anon') IS NULL THEN CREATE ROLE anon; END IF;
 IF to_regrole('service_role') IS NULL THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS visual;
CREATE TABLE visual.source_assets (
 id bigint PRIMARY KEY,brand_code text NOT NULL,
 asset_code text NOT NULL,source_kind text NOT NULL,
 provider text NOT NULL,file_ref text NOT NULL,source_sha256 text NOT NULL,
 independent_sha_verified boolean NOT NULL,
 approval_status text NOT NULL,metadata jsonb NOT NULL);
CREATE TABLE saly.creative_item_sources (
 order_id bigint NOT NULL,item_id bigint NOT NULL,
 source_asset_id bigint NOT NULL,purpose text NOT NULL,source_sha256 text NOT NULL);
ALTER TABLE saly.creative_orders
 ADD COLUMN request_kind text NOT NULL DEFAULT 'APP_SCREEN_BATCH';
INSERT INTO saly.creative_orders(code,status,scope_json,request_kind,created_at)
VALUES
('SALY_HOME_V015_SINGLE_20261123','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","review_only":true,"render_authorized":false,"rendering_authority":false}',
 'APP_SCREEN_SINGLE','2026-11-23'),
('SALY_ADELANTO_V015_SINGLE_20261123','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","review_only":true,"render_authorized":false,"rendering_authority":false}',
 'APP_SCREEN_SINGLE','2026-11-23');
INSERT INTO saly.creative_order_items(order_id,code,ordinal,status)
SELECT id,CASE WHEN code='SALY_HOME_V015_SINGLE_20261123' THEN 'HOME'
 ELSE 'SOLICITAR_ADELANTO' END,1,'PENDIENTE'
FROM saly.creative_orders WHERE request_kind='APP_SCREEN_SINGLE';
