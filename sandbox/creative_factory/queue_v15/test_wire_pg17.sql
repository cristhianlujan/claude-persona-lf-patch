-- Disposable PG17 test fixture; `queue_v02/fixture_pg17.sql` already applied.
-- All new rows are inside ROLLBACK. No real SALY orders used.
\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS visual;
CREATE TABLE IF NOT EXISTS visual.source_assets (
  id bigint PRIMARY KEY, brand_code text NOT NULL,
  asset_code text NOT NULL,source_kind text NOT NULL,
  provider text NOT NULL,file_ref text NOT NULL,
  source_sha256 text NOT NULL,independent_sha_verified boolean NOT NULL,
  approval_status text NOT NULL,metadata jsonb NOT NULL);
CREATE TABLE IF NOT EXISTS saly.creative_item_sources (
  order_id bigint NOT NULL,item_id bigint NOT NULL,
  source_asset_id bigint NOT NULL,purpose text NOT NULL,
  source_sha256 text NOT NULL);
INSERT INTO visual.source_assets
  (id,brand_code,asset_code,source_kind,provider,file_ref,source_sha256,
   independent_sha_verified,approval_status,metadata)
VALUES
  (777,'SALY','SALY_HOME','SCREEN','GOOGLE_DRIVE','test-drive-file',
   encode(extensions.digest(convert_to('synthetic fixture only','UTF8'),'sha256'),'hex'),
   true,'CANDIDATE','{"source_filename":"SALY_HOME_TEST.png","mime_type":"image/png"}'::jsonb);

UPDATE saly.creative_orders
SET scope_json=scope_json||'{"render_authorized":true,"review_only":false}'::jsonb
WHERE code='ACTIVE_A';

DO $run$
DECLARE
  v_order bigint;v_item bigint;v_token uuid;v_run bigint;v_claim bigint;
  v_ref jsonb;v_contract jsonb;v_manifest jsonb;v_snapshot jsonb;v_result jsonb;
  v_prompt text:='Reproducir SALY con las referencias congeladas. No inventar activos.';
  v_payload jsonb;v_wire bytea;
BEGIN
  SELECT o.id,i.id INTO STRICT v_order,v_item
  FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.code='ACTIVE_A' AND i.code='HOME';
  INSERT INTO saly.creative_item_sources(order_id,item_id,source_asset_id,purpose,source_sha256)
  SELECT v_order,v_item,id,'VISUAL_REFERENCE',source_sha256 FROM visual.source_assets WHERE id=777;
  SELECT jsonb_build_object('asset_id',id,'asset_code',asset_code,
      'source_kind',source_kind,'provider',provider,'file_ref',file_ref,
      'source_sha256',source_sha256,'approval_status',approval_status,
      'purpose','VISUAL_REFERENCE')
    INTO STRICT v_ref FROM visual.source_assets WHERE id=777;

  v_manifest:=jsonb_build_object(
      'schema_version','CREATIVE_UNIT_HANDOFF_V1',
      'order_id',v_order,'item_id',v_item,'mode','PLAN_ONLY',
      'dispatch_readiness','READY_FOR_NATIVE_HANDOFF',
      'prompt_utf8',v_prompt,
      'prompt_sha256',encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex'),
      'transmitted',false,'qa','NOT_TESTED');
  v_contract:=jsonb_build_object(
      'schema_version','SALY_VISUAL_CONTRACT_L3B_V1',
      'order_id',v_order,'item_id',v_item,'production_manifest',v_manifest,
      'visual_generation_state','NOT_EXECUTED','native_execution_authorized',false);
  v_snapshot:=jsonb_build_object(
      'schema_version','SALY_NATIVE_INPUT_SNAPSHOT_L2C_V1',
      'business_code','SALY','order_id',v_order,'item_id',v_item,
      'identity_versions',jsonb_build_array(jsonb_build_object('version_id',7)),
      'source_refs',jsonb_build_array(v_ref),'screen_spec',jsonb_build_object('screen','HOME'),
      'visual_contract',v_contract,'visual_contract_sha256',
      encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex'));

  v_result:=saly.creative_queue_claim_next_v1('NATIVE-TEST');
  IF v_result->>'status'<>'CLAIMED'
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_TEST_CLAIM_FAILED'; END IF;
  v_token:=(v_result->>'claim_token')::uuid;
  v_claim:=(v_result->>'claim_id')::bigint;
  v_result:=saly.creative_queue_admit_run_v1(v_token,1,'NATIVE-WIRE-TEST-1',v_snapshot);
  v_run:=(v_result->>'run_id')::bigint;
  v_result:=saly.creative_queue_advance_run_v1(v_token,v_run,'EJECUTANDO');
  IF v_result->>'state'<>'EJECUTANDO'
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_TEST_RUN_FAILED'; END IF;

  v_result:=saly.creative_native_render_wire_v1(v_token,v_run,'GPT_NATIVE');
  IF v_result->>'schema_version'<>'SALY_NATIVE_RENDER_WIRE_V1'
     OR v_result->>'status'<>'RENDER_WIRE_FROZEN_AUTHORIZED'
     OR v_result->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
     OR v_result->'executor_identity_attested' <> 'false'::jsonb
     OR v_result->'provider_receipt' <> 'null'::jsonb
     OR v_result->'native_transmitted' <> 'false'::jsonb
     OR v_result->'db_done_allowed' <> 'false'::jsonb
     OR (v_result->>'claim_id')::bigint <> v_claim
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_TEST_GPT_POSITIVE'; END IF;
  v_wire:=decode(v_result->>'wire_base64','base64');
  v_payload:=convert_from(v_wire,'UTF8')::jsonb;
  IF v_result->>'wire_sha256' <> encode(extensions.digest(v_wire,'sha256'),'hex')
    OR v_result->>'input_snapshot_sha256' <> encode(extensions.digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex')
    OR v_payload->>'prompt' <> v_prompt
    OR jsonb_array_length(v_payload->'attachments') <> 1
    OR v_payload#>>'{attachments,0,filename}' <> 'SALY_HOME_TEST.png'
    OR v_payload#>>'{attachments,0,file_ref}' <> 'test-drive-file'
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_TEST_GPT_HASH_OR_ATTACHMENTS'; END IF;

  v_result:=saly.creative_native_render_wire_v1(v_token,v_run,'CLAUDE_NATIVE');
  IF v_result->>'executor_mode'<>'CLAUDE_NATIVE'
     OR v_result->>'executor_provider'<>'ANTHROPIC_CLAUDE_NATIVE'
     OR v_result->>'wire_sha256' <> encode(extensions.digest(v_wire,'sha256'),'hex')
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_TEST_CLAUDE_POSITIVE'; END IF;
  RAISE NOTICE 'PASS GPT_NATIVE, CLAUDE_NATIVE, hash and source attachments; synthetic only';

  -- B25: each negative must return the exact code for the tested guard.
  BEGIN
    PERFORM saly.creative_native_render_wire_v1(v_token,v_run,'REMOTE_API');
    RAISE EXCEPTION 'EXPECTED_NATIVE_MODE_BLOCK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_EXECUTOR_MODE_INVALID' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM saly.creative_native_render_wire_v1(gen_random_uuid(),v_run,'GPT_NATIVE');
    RAISE EXCEPTION 'EXPECTED_WRONG_FENCING_TOKEN_BLOCK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_RUN_CLAIM_NOT_BOUND' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE saly.creative_orders SET scope_json=scope_json||'{"review_only":true}'::jsonb WHERE id=v_order;
    PERFORM saly.creative_native_render_wire_v1(v_token,v_run,'GPT_NATIVE');
    RAISE EXCEPTION 'EXPECTED_REVIEW_ONLY_BLOCK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_ORDER_AUTHORITY_MISSING' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE visual.source_assets SET file_ref='tampered' WHERE id=777;
    PERFORM saly.creative_native_render_wire_v1(v_token,v_run,'GPT_NATIVE');
    RAISE EXCEPTION 'EXPECTED_SOURCE_REFERENCE_DRIFT_BLOCK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_REFERENCE_DRIFT' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE visual.source_assets SET metadata='{"source_filename":"../evil.png","mime_type":"image/png"}'::jsonb WHERE id=777;
    PERFORM saly.creative_native_render_wire_v1(v_token,v_run,'GPT_NATIVE');
    RAISE EXCEPTION 'EXPECTED_ATTACHMENT_TRAVERSAL_BLOCK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_WIRE_ATTACHMENT_INVALID' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM saly.config_global WHERE scope='CREATIVE_FACTORY' AND config_key='LEASE_SECONDS';
    PERFORM saly.creative_native_render_wire_v1(v_token,v_run,'GPT_NATIVE');
    RAISE EXCEPTION 'EXPECTED_CONFIG_BLOCK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_CONFIG_MISSING:LEASE_SECONDS' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM saly.creative_queue_delivery_receipts_v1) <> 0
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_TEST_MUST_NOT_DELIVER'; END IF;
  IF (SELECT count(*) FROM saly.creative_runs WHERE state='EJECUTANDO') <> 1
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_TEST_MUST_NOT_CLOSE'; END IF;
  RAISE NOTICE 'PASS 6 exact-code negatives and no delivery or DONE; synthetic only';
END $run$;
ROLLBACK;
