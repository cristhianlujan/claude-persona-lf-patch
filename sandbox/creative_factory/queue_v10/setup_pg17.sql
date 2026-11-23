-- Synthetic candidate seed for PG17 disposable database only.
-- MUST run AFTER V02 fixture, V05 and V06, V10 candidate.
\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS visual;
-- The V02 reset drops saly only; explicitly discard this DISPOSABLE fixture
-- across mutation iterations to prevent false failures on duplicate tables.
DROP TABLE IF EXISTS visual.source_assets CASCADE;
CREATE TABLE visual.source_assets (
  id bigint PRIMARY KEY, brand_code text NOT NULL, asset_code text NOT NULL,
  source_kind text NOT NULL,provider text NOT NULL,file_ref text NOT NULL,
  source_sha256 text NOT NULL,independent_sha_verified boolean NOT NULL,
  approval_status text NOT NULL,metadata jsonb NOT NULL
);
CREATE TABLE saly.creative_item_sources (
  order_id bigint NOT NULL, item_id bigint NOT NULL, source_asset_id bigint NOT NULL,
  purpose text NOT NULL,source_sha256 text NOT NULL
);
INSERT INTO visual.source_assets
 (id,brand_code,asset_code,source_kind,provider,file_ref,source_sha256,
  independent_sha_verified,approval_status,metadata)
 VALUES (888,'SALY','SALY_HOME','SCREEN','GOOGLE_DRIVE','fixture-ref-v10',
   encode(extensions.digest(convert_to('synthetic v10 source only','UTF8'),'sha256'),'hex'),
   true,'CANDIDATE','{"source_filename":"SALY_HOME_V10.png","mime_type":"image/png"}'::jsonb);
UPDATE saly.creative_orders
 SET scope_json=scope_json||'{"render_authorized":true,"review_only":false}'::jsonb
 WHERE code='ACTIVE_A';
CREATE TABLE saly.test_v10_context (
 run_id bigint PRIMARY KEY,
 claim_token uuid NOT NULL,
 claim_id bigint NOT NULL,
 wire_sha256 text NOT NULL,
 prompt_sha256 text NOT NULL,
 archive_sha256 text NOT NULL,
 order_id bigint NOT NULL,item_id bigint NOT NULL
);
DO $test_seed$
DECLARE
 o bigint;i bigint; ref jsonb; v_manifest jsonb; v_contract jsonb; v_snapshot jsonb;
 v_token uuid;v_run bigint;v_claim bigint; res jsonb; wire jsonb;
 v_prompt text:='SALY V10 synthetic only, do not invoke a real image generator.';
BEGIN
 SELECT co.id,it.id INTO STRICT o,i
 FROM saly.creative_orders co JOIN saly.creative_order_items it ON it.order_id=co.id
 WHERE co.code='ACTIVE_A' AND it.code='HOME';
 INSERT INTO saly.creative_item_sources(order_id,item_id,source_asset_id,purpose,source_sha256)
 SELECT o,i,id,'VISUAL_REFERENCE',source_sha256 FROM visual.source_assets WHERE id=888;
 SELECT jsonb_build_object('asset_id',id,'asset_code',asset_code,'source_kind',source_kind,
         'provider',provider,'file_ref',file_ref,'source_sha256',source_sha256,
         'approval_status',approval_status,'purpose','VISUAL_REFERENCE')
 INTO STRICT ref FROM visual.source_assets WHERE id=888;
 v_manifest:=jsonb_build_object('schema_version','CREATIVE_UNIT_HANDOFF_V1',
   'order_id',o,'item_id',i,'mode','PLAN_ONLY',
   'dispatch_readiness','READY_FOR_NATIVE_HANDOFF','prompt_utf8',v_prompt,
   'prompt_sha256',encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex'),
   'transmitted',false,'qa','NOT_TESTED');
 v_contract:=jsonb_build_object('schema_version','SALY_VISUAL_CONTRACT_L3B_V1',
   'order_id',o,'item_id',i,'production_manifest',v_manifest,
   'visual_generation_state','NOT_EXECUTED','native_execution_authorized',false);
 v_snapshot:=jsonb_build_object(
   'schema_version','SALY_NATIVE_INPUT_SNAPSHOT_L2C_V1','business_code','SALY',
   'order_id',o,'item_id',i,
   'identity_versions',jsonb_build_array(jsonb_build_object('version_id',7)),
   'source_refs',jsonb_build_array(ref),'screen_spec',jsonb_build_object('screen','HOME'),
   'visual_contract',v_contract,
   'visual_contract_sha256',encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex'));
 res:=saly.creative_queue_claim_next_v1('V10-WORKER');
 IF res->>'status' IS DISTINCT FROM 'CLAIMED' THEN RAISE EXCEPTION 'V10_FIXTURE_NO_CLAIM'; END IF;
 v_token:=(res->>'claim_token')::uuid;v_claim:=(res->>'claim_id')::bigint;
 res:=saly.creative_queue_admit_run_v1(v_token,1,'V10-SYNTHETIC',v_snapshot);
 v_run:=(res->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(v_token,v_run,'EJECUTANDO');
 wire:=saly.creative_native_render_wire_v1(v_token,v_run,'GPT_NATIVE');
 IF wire->>'status' IS DISTINCT FROM 'RENDER_WIRE_FROZEN_AUTHORIZED'
 THEN RAISE EXCEPTION 'V10_FIXTURE_NO_VALID_WIRE'; END IF;
 INSERT INTO saly.test_v10_context
 VALUES(v_run,v_token,v_claim,wire->>'wire_sha256',wire->>'prompt_sha256',
        encode(extensions.digest(convert_to('worker-reported-synthetic-archive','UTF8'),'sha256'),'hex'),
        o,i);
 RAISE NOTICE 'V10_FIXTURE_READY: synthetic RUN and claim, not production';
END $test_seed$;
