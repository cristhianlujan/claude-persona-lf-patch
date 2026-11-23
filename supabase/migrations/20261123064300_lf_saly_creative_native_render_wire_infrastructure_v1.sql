-- SALY native render wire: private producer, no actual GPT/Claude invocation.
-- Requires previously merged queue infrastructure (#4649). No worker grants.
-- No image generation, no RUN, no change to the two REVIEW_ONLY orders.
BEGIN;
DO $prelive$
BEGIN
 IF to_regclass('saly.creative_queue_native_delivery_evidence_v1') IS NULL
 OR to_regprocedure('saly.creative_queue_claim_next_v1(text,integer)') IS NULL
 OR to_regclass('visual.source_assets') IS NULL
 OR to_regclass('saly.creative_item_sources') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_NATIVE_INFRA_REQUIRED'; END IF;
 IF (SELECT count(*) FROM saly.creative_runs)<>0
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ACTIVE_RUN_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.creative_orders WHERE
 code IN ('SALY_HOME_V015_SINGLE_20261123','SALY_ADELANTO_V015_SINGLE_20261123')
 AND request_kind='APP_SCREEN_SINGLE' AND status='PLANIFICADO'
 AND scope_json->>'review_only'='true'
 AND scope_json->>'render_authorized'='false')<>2
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PRESTATE_DRIFT'; END IF;
END $prelive$;

-- SALY: Native dual source-bound render wire. CANDIDATE ONLY.
-- Depends on queue_v02 candidate and canonical SALY creative run snapshot in main.
-- No GRANT, no runtime invocation, no writes to orders/RUNs, no provider claims.
-- B1/B2/B6/B11/B12/B13/B25/B27/B30/B32.
BEGIN;

DO $pre$
BEGIN
  IF to_regprocedure('saly.creative_native_render_wire_v1(uuid,bigint,text)') IS NOT NULL
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ALREADY_REGISTERED'; END IF;
  IF to_regclass('saly.creative_queue_claims_v1') IS NULL
     OR to_regprocedure('saly.creative_execution_policy_v1(timestamptz)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema='saly' AND table_name='creative_runs' AND column_name='queue_claim_id'
     )
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_DEPENDENCY_MISSING'; END IF;
END $pre$;

CREATE FUNCTION saly.creative_native_render_wire_v1(
  p_claim_token uuid, p_run_id bigint, p_executor_mode text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog,saly,visual,extensions,pg_temp
AS $fn$
DECLARE
  v_now timestamptz;
  v_row record;
  v_policy jsonb;
  v_snapshot jsonb;
  v_contract jsonb;
  v_manifest jsonb;
  v_sources jsonb;
  v_source jsonb;
  v_attachments jsonb:='[]'::jsonb;
  v_asset record;
  v_name text;
  v_names text[]:=ARRAY[]::text[];
  v_prompt text;
  v_prompt_sha text;
  v_contract_sha text;
  v_snapshot_sha text;
  v_payload jsonb;
  v_wire_bytes bytea;
  v_mode text;
  v_provider text;
  v_ref_count integer:=0;
BEGIN
  -- A queue claim is a fencing token, NOT a provider-identity credential.
  IF p_claim_token IS NULL OR p_run_id IS NULL OR p_run_id<1
     OR p_executor_mode IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ARGUMENT_INVALID'; END IF;
  v_mode:=upper(btrim(p_executor_mode));
  IF v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE')
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_EXECUTOR_MODE_INVALID'; END IF;
  v_provider:=CASE v_mode WHEN 'GPT_NATIVE' THEN 'OPENAI_CHATGPT_NATIVE'
                      ELSE 'ANTHROPIC_CLAUDE_NATIVE' END;

  -- Use same serial lock as the queue. Read one current time AFTER locking.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT c.id AS claim_id,c.claim_token,c.state AS claim_state,
         c.lease_until,c.worker_ref AS claim_worker,
         r.id AS run_id,r.order_id,r.item_id,r.state AS run_state,
         r.worker_ref AS run_worker,r.deadline_at,r.attempt_number,
         r.execution_policy,r.input_snapshot,
         i.status AS item_status,
         o.status AS order_status,o.scope_json
  INTO v_row
  FROM saly.creative_queue_claims_v1 c
  JOIN saly.creative_runs r ON r.queue_claim_id=c.id
      AND r.order_id=c.order_id AND r.item_id=c.item_id
  JOIN saly.creative_orders o ON o.id=r.order_id
  JOIN saly.creative_order_items i ON i.id=r.item_id AND i.order_id=r.order_id
  WHERE c.claim_token=p_claim_token AND r.id=p_run_id
  FOR UPDATE OF c,r,o,i;
  IF NOT FOUND
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_RUN_CLAIM_NOT_BOUND'; END IF;
  v_now:=clock_timestamp();
  IF v_row.claim_state<>'ACTIVE' OR v_row.run_state<>'EJECUTANDO'
     OR v_row.lease_until<=v_now OR v_row.deadline_at<=v_now
     OR nullif(btrim(coalesce(v_row.run_worker,'')),'') IS NULL
     OR v_row.claim_worker IS DISTINCT FROM v_row.run_worker
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_CLAIM_NOT_ACTIVE'; END IF;

  -- An explicit authority at the order is required; REVIEW_ONLY is never promoted.
  IF v_row.order_status NOT IN ('PLANIFICADO','EN_PROCESO')
     OR v_row.item_status NOT IN ('LISTO','PRODUCIENDO')
     OR v_row.scope_json->>'queue_mode' IS DISTINCT FROM 'SERIAL_V1'
     OR v_row.scope_json->'rendering_authority' IS DISTINCT FROM 'true'::jsonb
     OR v_row.scope_json->'render_authorized' IS DISTINCT FROM 'true'::jsonb
     OR v_row.scope_json->'review_only' IS DISTINCT FROM 'false'::jsonb
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ORDER_AUTHORITY_MISSING'; END IF;

  v_policy:=saly.creative_execution_policy_v1(v_now);
  IF v_row.execution_policy IS DISTINCT FROM v_policy
     OR v_row.attempt_number<1
     OR v_row.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_POLICY_DRIFT'; END IF;

  -- The work packet is only valid before RUN admission; after RUN starts it
  -- deliberately returns RUN_ALREADY_ACTIVE. NEVER recompile the prompt here.
  v_snapshot:=v_row.input_snapshot;
  v_contract:=v_snapshot->'visual_contract';
  v_manifest:=v_contract->'production_manifest';
  IF jsonb_typeof(v_snapshot) IS DISTINCT FROM 'object'
     OR v_snapshot->>'schema_version' IS DISTINCT FROM 'SALY_NATIVE_INPUT_SNAPSHOT_L2C_V1'
     OR v_snapshot->>'business_code' IS DISTINCT FROM 'SALY'
     OR v_snapshot->>'order_id' IS DISTINCT FROM v_row.order_id::text
     OR v_snapshot->>'item_id' IS DISTINCT FROM v_row.item_id::text
     OR jsonb_typeof(v_contract) IS DISTINCT FROM 'object'
     OR v_contract->>'schema_version' IS DISTINCT FROM 'SALY_VISUAL_CONTRACT_L3B_V1'
     OR v_contract->>'order_id' IS DISTINCT FROM v_row.order_id::text
     OR v_contract->>'item_id' IS DISTINCT FROM v_row.item_id::text
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_SNAPSHOT_INVALID'; END IF;

  v_snapshot_sha:=encode(extensions.digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex');
  v_contract_sha:=encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex');
  IF v_snapshot->>'visual_contract_sha256' IS DISTINCT FROM v_contract_sha
     OR jsonb_typeof(v_manifest) IS DISTINCT FROM 'object'
     OR v_manifest->>'schema_version' IS DISTINCT FROM 'CREATIVE_UNIT_HANDOFF_V1'
     OR v_manifest->>'order_id' IS DISTINCT FROM v_row.order_id::text
     OR v_manifest->>'item_id' IS DISTINCT FROM v_row.item_id::text
     OR v_manifest->>'dispatch_readiness' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF'
     OR v_manifest->>'mode' IS DISTINCT FROM 'PLAN_ONLY'
     OR v_manifest->'transmitted' IS DISTINCT FROM 'false'::jsonb
     OR v_manifest->>'qa' IS DISTINCT FROM 'NOT_TESTED'
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_FROZEN_CONTRACT_INVALID'; END IF;
  -- The PLAN_ONLY manifest is input provenance, NOT production approval.
  -- Production admission originates only in the explicit order+claim+RUN gates.
  v_prompt:=v_manifest->>'prompt_utf8';
  IF nullif(btrim(coalesce(v_prompt,'')),'') IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PROMPT_NOT_SEALED'; END IF;
  v_prompt_sha:=encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex');
  IF v_manifest->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
     OR v_prompt ~ 'claim_token|queue_claim_token'
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PROMPT_DRIFT'; END IF;

  -- Source descriptors are derived from the frozen RUN snapshot and checked
  -- against authoritative source asset rows, never constructed from model text.
  -- Raw file bytes are NOT in SQL: the Native host MUST download, hash, archive,
  -- and attach exact bytes; this function alone is not a provider receipt.
  v_sources:=v_snapshot->'source_refs';
  IF jsonb_typeof(v_sources) IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_sources)=0
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCES_REQUIRED'; END IF;
  FOR v_source IN SELECT value FROM jsonb_array_elements(v_sources)
  LOOP
    IF jsonb_typeof(v_source) IS DISTINCT FROM 'object'
       OR coalesce(v_source->>'asset_id','') !~ '^[1-9][0-9]*$'
       OR (v_source->>'asset_id')::numeric>9223372036854775807::numeric
    THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCE_INVALID'; END IF;
    SELECT a.*,s.purpose AS source_purpose,s.source_sha256 AS link_sha
    INTO v_asset
    FROM saly.creative_item_sources s
    JOIN visual.source_assets a ON a.id=s.source_asset_id
    WHERE s.order_id=v_row.order_id AND s.item_id=v_row.item_id
      AND a.id=(v_source->>'asset_id')::bigint;
    IF NOT FOUND OR v_asset.source_sha256 IS DISTINCT FROM v_asset.link_sha
       OR v_asset.source_sha256 IS DISTINCT FROM v_source->>'source_sha256'
       OR v_asset.asset_code IS DISTINCT FROM v_source->>'asset_code'
       OR v_asset.file_ref IS DISTINCT FROM v_source->>'file_ref'
       OR v_asset.provider IS DISTINCT FROM v_source->>'provider'
       OR v_asset.source_kind IS DISTINCT FROM v_source->>'source_kind'
       OR v_asset.approval_status IS DISTINCT FROM v_source->>'approval_status'
       OR v_asset.source_purpose IS DISTINCT FROM v_source->>'purpose'
       OR v_asset.brand_code<>'SALY'
       OR v_asset.independent_sha_verified IS DISTINCT FROM true
       OR v_asset.approval_status NOT IN ('CANDIDATE','APPROVED')
       OR v_asset.source_sha256 !~ '^[0-9a-f]{64}$'
       OR nullif(btrim(coalesce(v_asset.file_ref,'')),'') IS NULL
    THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCE_DRIFT'; END IF;
    v_name:=v_asset.metadata->>'source_filename';
    IF v_name IS NULL OR v_name !~ '^[A-Za-z0-9][A-Za-z0-9_. -]{0,127}$'
       OR v_name IN ('.','..') OR v_name=ANY(v_names)
       OR v_asset.metadata->>'mime_type' IS NULL
       OR v_asset.metadata->>'mime_type' NOT IN ('image/png','image/jpeg','image/svg+xml')
    THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ATTACHMENT_INVALID'; END IF;
    v_names:=array_append(v_names,v_name);
    v_attachments:=v_attachments||jsonb_build_array(jsonb_build_object(
       'filename',v_name,'sha256',v_asset.source_sha256,
       'asset_code',v_asset.asset_code,'provider',v_asset.provider,
       'file_ref',v_asset.file_ref,'mime_type',v_asset.metadata->>'mime_type'));
    v_ref_count:=v_ref_count+1;
  END LOOP;
  IF v_ref_count <> jsonb_array_length(v_sources)
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCE_COUNT_DRIFT'; END IF;

  v_payload:=jsonb_build_object('prompt',v_prompt,'attachments',v_attachments);
  v_wire_bytes:=convert_to(v_payload::text,'UTF8');
  RETURN jsonb_build_object(
     'schema_version','SALY_NATIVE_RENDER_WIRE_V1',
     'status','RENDER_WIRE_FROZEN_AUTHORIZED',
     'order_id',v_row.order_id,'item_id',v_row.item_id,
     'run_id',v_row.run_id,'claim_id',v_row.claim_id,
     'executor_mode',v_mode,'executor_provider',v_provider,
     'executor_identity_attested',false,
     'input_snapshot_sha256',v_snapshot_sha,
     'contract_sha256',v_contract_sha,
     'prompt_sha256',v_prompt_sha,
     'wire_sha256',encode(extensions.digest(v_wire_bytes,'sha256'),'hex'),
     'wire_base64',replace(encode(v_wire_bytes,'base64'),chr(10),''),
     'render_authorized',true,'native_transmitted',false,
     'provider_receipt',NULL,
     'host_delivery_verified',false,
     'db_done_allowed',false,
     'next_action','ARCHIVE_EXACT_SOURCE_BYTES_THEN_OWNING_NATIVE_CHAT');
END $fn$;

-- New function is private. Neither a worker token nor a function declaration
-- creates an authenticated Native host caller. No runtime grants in this PR.
REVOKE ALL ON FUNCTION saly.creative_native_render_wire_v1(uuid,bigint,text)
  FROM PUBLIC;
DO $acl$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role','supabase_read_only_user']
  LOOP
    IF to_regrole(v_role) IS NOT NULL THEN
      EXECUTE format(
        'REVOKE ALL ON FUNCTION saly.creative_native_render_wire_v1(uuid,bigint,text) FROM %I',
        v_role);
    END IF;
  END LOOP;
END $acl$;
COMMENT ON FUNCTION saly.creative_native_render_wire_v1(uuid,bigint,text) IS
 'Candidate GPT_NATIVE/CLAUDE_NATIVE render wire derived solely from immutable RUN visual contract; NO GRANT, no model call, no delivery or DONE authority. Requires queue_v02 and a separately authenticated host runtime.';
-- No adapter identity is implicitly trusted. Role privileges are checked
-- by readback and only an authenticated future worker may ever be granted.
DO $post$
DECLARE source text;
BEGIN
 source:=pg_get_functiondef('saly.creative_native_render_wire_v1(uuid,bigint,text)'::regprocedure);
 IF strpos(source,'CREATIVE_RENDER_WIRE_ORDER_AUTHORITY_MISSING')=0
 OR strpos(source,'CREATIVE_RENDER_WIRE_REFERENCE_DRIFT')=0
 OR strpos(source,'executor_identity_attested')=0
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_SOURCE_GUARDS_MISSING'; END IF;
 IF has_function_privilege('service_role',
   'saly.creative_native_render_wire_v1(uuid,bigint,text)','EXECUTE')
 OR has_function_privilege('anon',
   'saly.creative_native_render_wire_v1(uuid,bigint,text)','EXECUTE')
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_RUNTIME_GRANT_LEAK'; END IF;
 IF (SELECT count(*) FROM saly.creative_runs)<>0
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_FAKE_RUN'; END IF;
END $post$;
COMMIT;