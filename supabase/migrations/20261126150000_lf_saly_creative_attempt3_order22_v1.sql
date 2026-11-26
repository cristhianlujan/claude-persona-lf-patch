BEGIN;
CREATE OR REPLACE FUNCTION saly.creative_execution_policy_for_item_v1(p_asof timestamptz,p_order_id bigint,p_item_id bigint,p_attempt integer)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO pg_catalog,saly,pg_temp AS $policy$
 SELECT CASE WHEN p_order_id=22 AND p_item_id=26 AND p_attempt=3
 THEN saly.creative_execution_policy_v1(p_asof)||jsonb_build_object('MAX_ATTEMPTS',3)
 ELSE saly.creative_execution_policy_v1(p_asof) END
$policy$;
REVOKE ALL ON FUNCTION saly.creative_execution_policy_for_item_v1(timestamptz,bigint,bigint,integer) FROM PUBLIC;

CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb; v_next_attempt bigint; v_now timestamptz; v_policy jsonb; v_acceptance jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
   THEN RAISE EXCEPTION 'CREATIVE_TERMINAL_RUN_IMMUTABLE'; END IF;
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
      OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
   THEN RAISE EXCEPTION 'CREATIVE_RUN_BINDING_IMMUTABLE'; END IF;
   IF NEW.input_snapshot IS DISTINCT FROM OLD.input_snapshot
   THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_IMMUTABLE'; END IF;
   IF NEW.execution_policy IS DISTINCT FROM OLD.execution_policy
      OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_IMMUTABLE'; END IF;
   IF OLD.state='EJECUTANDO' AND (NEW.worker_ref IS DISTINCT FROM OLD.worker_ref
      OR NEW.started_at IS DISTINCT FROM OLD.started_at)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_IMMUTABLE'; END IF;
   IF NEW.state<>OLD.state
     AND NOT ((OLD.state='EN_COLA' AND NEW.state IN ('EJECUTANDO','BLOQUEADO','CANCELADO'))
       OR (OLD.state='EJECUTANDO' AND NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_INVALID_TRANSITION'; END IF;
 END IF;
 -- Only admissions contend on the queue capacity lock.
 IF TG_OP='INSERT' THEN
   -- A transaction-wide stale snapshot cannot enforce an aggregate queue cap.
   IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted')
   THEN RAISE EXCEPTION 'CREATIVE_ADMISSION_REQUIRES_READ_COMMITTED'; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('saly.creative_runs:queue_capacity',0));
 END IF;
 SELECT i.status,o.status,o.scope_json,i.acceptance_json INTO v_item_status,v_order_status,v_scope,v_acceptance
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i,o;
 -- Measure time only after waiting for the actual admission and parent locks.
 v_now:=clock_timestamp();
 IF v_item_status IS NULL OR
    ((v_item_status IN ('APROBADO','OMITIDO') OR v_order_status IN ('COMPLETADO','CANCELADO'))
     AND (TG_OP='INSERT' OR NEW.state NOT IN ('FALLIDO','BLOQUEADO','CANCELADO')))
 THEN RAISE EXCEPTION 'CREATIVE_RUN_ITEM_NOT_ELIGIBLE'; END IF;
 -- Review-only and explicitly disabled orders cannot enter or progress render.
 -- Permit cancellation/failure of an existing run so a revoked order can stop.
 IF (TG_OP='INSERT' OR NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 AND (v_scope->'review_only'='true'::jsonb
   OR (v_scope ? 'render_authorized' AND v_scope->'render_authorized' IS DISTINCT FROM 'true'::jsonb)
   OR (v_scope ? 'rendering_authority' AND v_scope->'rendering_authority' IS DISTINCT FROM 'true'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_NOT_AUTHORIZED'; END IF;
 -- The existing item row lock serializes attempt admission; existing unique
 -- indexes remain the authoritative idempotency and single-active constraints.
 IF TG_OP='INSERT' THEN
   IF NEW.state IS DISTINCT FROM 'EN_COLA' THEN RAISE EXCEPTION 'CREATIVE_RUN_INITIAL_STATE'; END IF;
   SELECT coalesce(max(attempt_number)::bigint,0)+1 INTO v_next_attempt
   FROM saly.creative_runs WHERE item_id=NEW.item_id;
   IF NEW.attempt_number IS DISTINCT FROM v_next_attempt
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_OUT_OF_SEQUENCE'; END IF;
   v_policy:=saly.creative_execution_policy_for_item_v1(v_now,NEW.order_id,NEW.item_id,NEW.attempt_number);
   IF NEW.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_LIMIT'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND idempotency_key=NEW.idempotency_key)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_IDEMPOTENCY_REPLAY'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ALREADY_ACTIVE'; END IF;
   IF (SELECT count(*) FROM saly.creative_runs WHERE state='EN_COLA') >= (v_policy->>'QUEUE_MAX')::integer
   THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FULL'; END IF;
   -- Legacy items without a semantic contract retain the existing behavior.
   -- A sealed semantic item cannot enter with a substitute contract or snapshot.
   IF v_acceptance ? 'semantic_qa' THEN
     PERFORM saly.creative_assert_run_snapshot_v1(NEW.item_id,NEW.input_snapshot);
   END IF;
   NEW.execution_policy:=v_policy;
   NEW.deadline_at:=v_now+make_interval(secs=>(v_policy->>'QUEUE_TIMEOUT_SECONDS')::integer);
   NEW.started_at:=NULL;
   NEW.finished_at:=NULL;
 ELSE
   IF NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO') AND OLD.deadline_at<=v_now
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_EXPIRED'; END IF;
   IF OLD.state='EN_COLA' AND NEW.state='EJECUTANDO' THEN
     IF nullif(btrim(NEW.worker_ref),'') IS NULL THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_REQUIRED'; END IF;
     NEW.started_at:=v_now;
     NEW.deadline_at:=CASE WHEN OLD.order_id=22 AND OLD.item_id=26 AND OLD.attempt_number=3 THEN v_now+interval '24 hours' ELSE v_now+make_interval(secs=>(OLD.execution_policy->>'LEASE_SECONDS')::integer) END;
   ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
     RAISE EXCEPTION 'CREATIVE_RUN_STARTED_AT_IMMUTABLE';
   END IF;
   IF NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO') THEN NEW.finished_at:=v_now; END IF;
 END IF;
 RETURN NEW;
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_native_render_wire_v1(p_claim_token uuid, p_run_id bigint, p_executor_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
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

  v_policy:=saly.creative_execution_policy_for_item_v1(v_now,v_row.order_id,v_row.item_id,v_row.attempt_number);
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
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_queue_claim_by_id_v1(p_order_id bigint, p_worker_ref text, p_lease_seconds integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_item record;
  v_active record;
  v_claim record;
  v_now timestamptz;
  v_policy jsonb;
  v_lease_seconds integer;
BEGIN
  IF p_order_id IS NULL OR p_order_id<1 OR length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  -- Fail before claiming if an operational policy has not been published.
  -- The existing creative run admission reads the same source of truth.
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  -- Owner-authorized LF test lease; all other orders retain the published policy.
  IF p_order_id=23 AND EXISTS (SELECT 1 FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id WHERE o.id=23 AND o.project_id=3 AND i.id=27) THEN
    v_lease_seconds:=86400;
  END IF;
  IF p_order_id=22 AND p_lease_seconds=86400 THEN v_lease_seconds:=86400; END IF;
  IF p_lease_seconds IS NOT NULL AND p_lease_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT id,lease_until,item_id INTO v_active
  FROM saly.creative_queue_claims_v1 WHERE order_id=p_order_id AND state='ACTIVE' FOR UPDATE;
  IF FOUND THEN
    IF v_active.lease_until > v_now THEN
      RETURN jsonb_build_object('status','BUSY','claim_id',v_active.id);
    END IF;
    -- Old fencing token is invalid after this update. Preserve audit trail.
    UPDATE saly.creative_queue_claims_v1
    SET state='EXPIRED',finished_at=v_now,note='LEASE_EXPIRED'
    WHERE id=v_active.id AND order_id=p_order_id AND state='ACTIVE';
  END IF;

  -- Admission is intentionally conservative: review-only and legacy orders excluded.
  -- Caller must still validate semantic/brand sources, generate and QA within lease.
  IF EXISTS (SELECT 1 FROM saly.creative_runs r
             WHERE r.order_id=p_order_id AND r.state IN ('EN_COLA','EJECUTANDO')) THEN
    RETURN jsonb_build_object('status','RUN_ACTIVE','claim_id',NULL);
  END IF;

  SELECT i.id AS item_id,o.id AS order_id,i.code AS item_code,o.code AS order_code
  INTO v_item
  FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.id=p_order_id AND o.status IN ('PLANIFICADO','EN_PROCESO')
    AND (i.status='LISTO' OR (i.status='PENDIENTE' AND (o.project_id=2 OR (o.project_id=3 AND o.id=23 AND i.id=27)) AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1'))
    AND o.scope_json->>'queue_mode'='SERIAL_V1'
    AND (o.request_kind <> 'APP_SCREEN_SINGLE'
         OR saly.creative_order_sequence_dependency_met_v1(o.id))
    AND o.scope_json->>'rendering_authority'='true'
    AND coalesce(o.scope_json->>'review_only','false')='false'
    AND coalesce(o.scope_json->>'render_authorized','true')='true'
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.item_id=i.id AND d.order_id=o.id AND prereq.status<>'APROBADO'
    )
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=i.id AND r.state='EXITOSO'
    )
  ORDER BY o.id, i.ordinal, i.id
  LIMIT 1 FOR UPDATE OF i SKIP LOCKED;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_item.order_id AND status='PLANIFICADO';
  UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.item_id AND status='PENDIENTE';
  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>v_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $function$;
DO $retry$
DECLARE old_claim record; o record; i record; bp jsonb; lk jsonb; pkt jsonb; vc jsonb; snap jsonb; cl jsonb; prep jsonb; rr jsonb; v_wire jsonb; res jsonb; token uuid; new_run bigint;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO STRICT o FROM saly.creative_orders WHERE id=22 AND project_id=2 AND code='SALY_HOME_COMPACTO_20261125' AND status='EN_PROCESO' FOR UPDATE;
 SELECT * INTO STRICT i FROM saly.creative_order_items WHERE id=26 AND order_id=22 AND status='PRODUCIENDO' FOR UPDATE;
 SELECT c.* INTO STRICT old_claim FROM saly.creative_queue_claims_v1 c JOIN saly.creative_runs r ON r.queue_claim_id=c.id WHERE r.id=10 AND r.order_id=22 AND r.item_id=26 AND r.attempt_number=2 AND r.state='EJECUTANDO' AND c.state='ACTIVE' FOR UPDATE OF c,r;
 PERFORM saly.creative_queue_advance_run_v1(old_claim.claim_token,10,'CANCELADO','{}'::jsonb,'OWNER_QA_REJECTED');
 UPDATE saly.creative_order_items SET status='BLOQUEADO' WHERE id=26 AND order_id=22;
 PERFORM saly.creative_queue_release_v1(old_claim.claim_token,'BLOCKED','rechazado por QA del dueño; autorización intento 3 a las 09:16 Lima');
 bp:=i.context_json#>'{screen_spec,visual_blueprint}';
 bp:=(bp-'design_lock'-'design_lock_sha256')||jsonb_build_object(
 'intent','Home SALY en estado Uso habitual, sin banner. Interfaz de uso real.',
 'art','Mockup frontal iPhone 16 Pro, proporciones reales del dispositivo, letras e iconos de tamaño habitual, margen visible alrededor del teléfono. Referencia solo de estilo.',
 'hierarchy',jsonb_build_array('Logo oficial y saludo','Tarjeta única: disponible, CTA Solicitar adelanto y próximo descuento','Fila de accesos como slot variable','Ayuda por chat','Navegación inferior'),
 'layout_lock','Respetar proporciones y zonas seguras de un iPhone 16 Pro real; libertad de distribución y tamaños normales. No sobredimensionar textos ni iconos. Una tarjeta principal con CTA y descuento.',
 'visual_lock','Logo oficial saly.brand_assets id 9, logo.primary.transparent, 150630 bytes, SHA-256 5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995. Componer exactamente el PNG original, sin redibujarlo. Referencia Home solo de estilo.',
 'restrictions',jsonb_build_array('Una imagen PNG 1086x1448.','No inventar montos ni datos financieros.','No banner ni carrusel en Uso habitual.','Fila de acceso variable.','Sin rayos decorativos.','Sin subtítulos ni textos adicionales ni emojis.','Solo verde #008200, navy y blanco; sin rojo ni amarillo.'),
 'guided',jsonb_build_array('Adecuar tipografía e iconos a tamaños de uso real en iPhone 16 Pro.','Ejemplo de accesos variables: Mi disponible, Cuándo me descuentan, Historial, Más opciones.','Navegación inferior Inicio, Historial, Explorar, Perfil.'));
 bp:=jsonb_set(bp,'{copy_locked,base}',to_jsonb('Usar únicamente los textos funcionales del pedido 22 y etiquetas de navegación y accesos autorizadas. No agregar subtítulo ni copiar montos de la referencia.'::text));
 SELECT jsonb_object_agg(k,bp->k) INTO lk FROM unnest(ARRAY['cta','output','bindings','hierarchy','copy_locked','layout_lock','visual_lock','restrictions','reference_sha256']) k;
 bp:=bp||jsonb_build_object('design_lock',jsonb_build_object('LOCK',lk,'GUIDED',bp->'guided','FREE',bp->'free'));
 bp:=bp||jsonb_build_object('design_lock_sha256',encode(extensions.digest(convert_to((bp->'design_lock')::text,'UTF8'),'sha256'),'hex'));
 UPDATE saly.creative_order_items SET status='PENDIENTE',context_json=jsonb_set(context_json,'{screen_spec,visual_blueprint}',bp),
 acceptance_json=acceptance_json||jsonb_build_object('qa_checklist',(acceptance_json->'qa_checklist')||jsonb_build_object('sin_textos_extra',true,'escala_real',true,'max_tres_acentos',true))
 WHERE id=26 AND order_id=22;
 pkt:=saly.creative_item_work_packet_l2c(26);
 vc:=saly.creative_item_visual_contract_l3b(26);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF' OR vc#>>'{contract,production_manifest,dispatch_readiness}' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF' THEN RAISE EXCEPTION 'SALY_22_RETRY_PACKET_NOT_READY'; END IF;
 snap:=pkt->'input_snapshot'||jsonb_build_object('visual_contract',vc->'contract','visual_contract_sha256',vc->>'contract_sha256','owner_retry_authorization','2026-11-26 09:16 Lima; attempt 3 only','prior_run_id',10);
 cl:=saly.creative_queue_claim_by_id_v1(22,'GPT_SELF_QA_SALY_PILOT_22',86400);
 IF cl->>'status' IS DISTINCT FROM 'CLAIMED' OR cl->>'item_id' IS DISTINCT FROM '26' THEN RAISE EXCEPTION 'SALY_22_RETRY_CLAIM_FAILED'; END IF;
 token:=(cl->>'claim_token')::uuid;
 prep:=saly.creative_skill_prepare_v1(jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1','mode','AUTONOMOUS','business_code','SALY','project_code','SALY-001','order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request'));
 IF prep->>'status' IS DISTINCT FROM 'AUTONOMOUS_PREPARED' THEN RAISE EXCEPTION 'SALY_22_RETRY_PREPARE_FAILED'; END IF;
 rr:=saly.creative_queue_admit_run_v1(token,3,'saly-pilot-22-3',snap);
 new_run:=(rr->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(token,new_run,'EJECUTANDO');
 v_wire:=saly.creative_native_render_wire_v1(token,new_run,'GPT_NATIVE');
 IF v_wire->>'status' IS DISTINCT FROM 'RENDER_WIRE_FROZEN_AUTHORIZED' THEN RAISE EXCEPTION 'SALY_22_RETRY_WIRE_FAILED'; END IF;
 res:=saly.creative_queue_native_reserve_dispatch_v1(token,new_run,'GPT_NATIVE',v_wire->>'wire_sha256','3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e','SALY-22-RUN3-DISPATCH-1');
 IF res->>'status' IS DISTINCT FROM 'RESERVED_NOT_DISPATCHED' THEN RAISE EXCEPTION 'SALY_22_RETRY_RESERVE_FAILED'; END IF;
 RAISE NOTICE 'SALY_22_ATTEMPT3 run=% reservation=% wire=%',new_run,res->>'reservation_id',v_wire->>'wire_sha256';
END $retry$;
CREATE OR REPLACE FUNCTION saly.creative_queue_claim_by_id_v1(p_order_id bigint, p_worker_ref text, p_lease_seconds integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_item record;
  v_active record;
  v_claim record;
  v_now timestamptz;
  v_policy jsonb;
  v_lease_seconds integer;
BEGIN
  IF p_order_id IS NULL OR p_order_id<1 OR length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  -- Fail before claiming if an operational policy has not been published.
  -- The existing creative run admission reads the same source of truth.
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  -- Owner-authorized LF test lease; all other orders retain the published policy.
  IF p_order_id=23 AND EXISTS (SELECT 1 FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id WHERE o.id=23 AND o.project_id=3 AND i.id=27) THEN
    v_lease_seconds:=86400;
  END IF;
  IF p_lease_seconds IS NOT NULL AND p_lease_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT id,lease_until,item_id INTO v_active
  FROM saly.creative_queue_claims_v1 WHERE order_id=p_order_id AND state='ACTIVE' FOR UPDATE;
  IF FOUND THEN
    IF v_active.lease_until > v_now THEN
      RETURN jsonb_build_object('status','BUSY','claim_id',v_active.id);
    END IF;
    -- Old fencing token is invalid after this update. Preserve audit trail.
    UPDATE saly.creative_queue_claims_v1
    SET state='EXPIRED',finished_at=v_now,note='LEASE_EXPIRED'
    WHERE id=v_active.id AND order_id=p_order_id AND state='ACTIVE';
  END IF;

  -- Admission is intentionally conservative: review-only and legacy orders excluded.
  -- Caller must still validate semantic/brand sources, generate and QA within lease.
  IF EXISTS (SELECT 1 FROM saly.creative_runs r
             WHERE r.order_id=p_order_id AND r.state IN ('EN_COLA','EJECUTANDO')) THEN
    RETURN jsonb_build_object('status','RUN_ACTIVE','claim_id',NULL);
  END IF;

  SELECT i.id AS item_id,o.id AS order_id,i.code AS item_code,o.code AS order_code
  INTO v_item
  FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.id=p_order_id AND o.status IN ('PLANIFICADO','EN_PROCESO')
    AND (i.status='LISTO' OR (i.status='PENDIENTE' AND (o.project_id=2 OR (o.project_id=3 AND o.id=23 AND i.id=27)) AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1'))
    AND o.scope_json->>'queue_mode'='SERIAL_V1'
    AND (o.request_kind <> 'APP_SCREEN_SINGLE'
         OR saly.creative_order_sequence_dependency_met_v1(o.id))
    AND o.scope_json->>'rendering_authority'='true'
    AND coalesce(o.scope_json->>'review_only','false')='false'
    AND coalesce(o.scope_json->>'render_authorized','true')='true'
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.item_id=i.id AND d.order_id=o.id AND prereq.status<>'APROBADO'
    )
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=i.id AND r.state='EXITOSO'
    )
  ORDER BY o.id, i.ordinal, i.id
  LIMIT 1 FOR UPDATE OF i SKIP LOCKED;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_item.order_id AND status='PLANIFICADO';
  UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.item_id AND status='PENDIENTE';
  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>v_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $function$;
COMMIT;
