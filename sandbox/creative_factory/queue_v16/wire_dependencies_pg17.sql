-- Disposable PG17-only compatibility objects for V05 production wire schema.
\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS visual;
CREATE TABLE visual.source_assets(
 id bigint PRIMARY KEY,brand_code text NOT NULL,asset_code text NOT NULL,
 source_kind text NOT NULL,provider text NOT NULL,file_ref text NOT NULL,
 source_sha256 text NOT NULL,independent_sha_verified boolean NOT NULL,
 approval_status text NOT NULL,metadata jsonb NOT NULL);
CREATE TABLE saly.creative_item_sources(
 order_id bigint NOT NULL,item_id bigint NOT NULL,
 source_asset_id bigint NOT NULL,purpose text NOT NULL,
 source_sha256 text NOT NULL);
