CREATE OR REPLACE FUNCTION saly.creative_k_consume_v2(p_item_id bigint, p_object_kind text, p_object_sha256 text, p_module_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
 SELECT jsonb_build_object('module_code',r.module_code,'decision',r.decision,
  'step',r.step,'reason',r.reason,'output',r.output,'evidence',r.evidence)
 FROM saly.creative_k_results_v2 r
 WHERE r.item_id=p_item_id AND r.object_kind=p_object_kind
 AND r.object_sha256=p_object_sha256 AND r.module_code=p_module_code;
$function$
;

CREATE OR REPLACE FUNCTION saly.creative_k_record_once_v2(p_item_id bigint, p_object_kind text, p_object_sha256 text, p_module_code text, p_decision text, p_step text, p_evidence jsonb, p_output jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE v_selection saly.creative_task_selection_v2%ROWTYPE;
 v_decision jsonb;v_expected text;v_reason text;v_owner text;
BEGIN
 SELECT * INTO STRICT v_selection FROM saly.creative_task_selection_v2
 WHERE item_id=p_item_id;
 SELECT x INTO v_decision FROM jsonb_array_elements(v_selection.selection_json->'decisions') x
 WHERE x->>'module_code'=p_module_code;
 IF v_decision IS NULL OR p_object_sha256 !~ '^[0-9a-f]{64}$'
 OR p_object_kind NOT IN ('PLAN','IMAGE')
 OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
 OR jsonb_typeof(p_output) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'SALY_K_RECORD_INVALID'; END IF;
 v_expected:=v_decision->>'decision';v_reason:=v_decision->>'reason';
 v_owner:=v_decision->>'owner_step';
 IF p_object_kind='IMAGE' THEN
   IF p_module_code<>'K06' OR p_decision<>'EJECUTADO' OR p_step<>'11'
   THEN RAISE EXCEPTION 'SALY_K_WRONG_OBJECT_OWNER'; END IF;
 ELSIF v_expected='OMITIDO' THEN
   IF p_decision<>'OMITIDO' OR p_step<>'2'
   THEN RAISE EXCEPTION 'SALY_K_SKIP_MISMATCH'; END IF;
 ELSE
   IF p_module_code='K06' THEN v_owner:='8'; END IF;
   IF p_decision<>'EJECUTADO'
   OR p_step IS DISTINCT FROM v_owner
   OR p_evidence='{}'::jsonb OR p_output='{}'::jsonb
   THEN RAISE EXCEPTION 'SALY_K_OWNER_OR_EVIDENCE_MISMATCH'; END IF;
 END IF;
 IF p_object_kind='PLAN' AND v_expected='OMITIDO' AND p_decision='OMITIDO'
 THEN
   IF p_output<>'{}'::jsonb THEN RAISE EXCEPTION 'SALY_K_SKIPPED_HAS_OUTPUT'; END IF;
 ELSE
   IF p_evidence='{}'::jsonb OR p_output='{}'::jsonb
   THEN RAISE EXCEPTION 'SALY_K_EXECUTION_EVIDENCE_MISSING'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_k_results_v2 r
     WHERE r.item_id=p_item_id AND r.object_kind=p_object_kind
       AND r.object_sha256=p_object_sha256 AND r.module_code=p_module_code)
 THEN RAISE EXCEPTION 'SALY_K_DUPLICATE_OBJECT_EXECUTION'; END IF;
 INSERT INTO saly.creative_k_results_v2(
 item_id,object_kind,object_sha256,module_code,decision,step,reason,evidence,output,selection_sha256)
 VALUES (p_item_id,p_object_kind,p_object_sha256,p_module_code,p_decision,p_step,
  CASE WHEN p_decision='OMITIDO' THEN v_reason ELSE NULL END,
  p_evidence,p_output,v_selection.selection_sha256);
 RETURN jsonb_build_object('module_code',p_module_code,'decision',p_decision,
     'object_kind',p_object_kind,'step',p_step,'reason',v_reason,
     'output',p_output,'already_executed',false);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'SALY_K_DUPLICATE_OBJECT_EXECUTION';
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_lf_identity_packet_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'lf_design'
AS $function$
 SELECT jsonb_build_object('business_code','LF','design_system',to_jsonb(ds),
 'tokens',jsonb_build_object(
 'colors',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.color_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'typography',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.typography_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'spacing',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.spacing_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'components',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.component_token_code),'[]'::jsonb) FROM lf_design.component_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'themes',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.theme_binding_code),'[]'::jsonb) FROM lf_design.theme_bindings t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE')),
 'assets',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.asset_code),'[]'::jsonb) FROM lf_design.brand_assets a WHERE a.is_current AND a.status='VIGENTE'))
 FROM lf_design.design_systems ds WHERE ds.project_code='LF' AND ds.design_system_code='LF_DS_V1';
$function$
;

CREATE OR REPLACE FUNCTION saly.creative_native_canonical_wire_v1(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE pkt jsonb; v jsonb; raw_bytes bytea; wire_sha text;
BEGIN
 pkt:=saly.creative_item_work_packet_l2c(p_item_id);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_REVIEW_ONLY'
 OR pkt->'native_execution_authorized' IS DISTINCT FROM 'false'::jsonb
 OR pkt->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_NOT_REVIEW'; END IF;
 v:=saly.creative_assert_native_transport_v2(pkt->'native_transport');
 IF v->>'status' IS DISTINCT FROM 'PAYLOAD_MATCH_REVIEW_ONLY'
 OR v->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR v->'transmitted' IS DISTINCT FROM 'false'::jsonb
 OR v->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_NOT_REVIEW'; END IF;
 raw_bytes:=convert_to((pkt#>'{native_transport,payload}')::text,'UTF8');
 wire_sha:=encode(extensions.digest(raw_bytes,'sha256'),'hex');
 IF wire_sha IS DISTINCT FROM v->>'payload_sha256'
 THEN RAISE EXCEPTION 'CREATIVE_CANONICAL_WIRE_HASH_DRIFT'; END IF;
 RETURN jsonb_build_object(
  'schema_version','SALY_CANONICAL_NATIVE_WIRE_V1',
  'status','CANONICAL_WIRE_REVIEW_ONLY',
  'item_id',p_item_id,'contract_sha256',v->>'contract_sha256',
  'prompt_sha256',v->>'prompt_sha256','payload_sha256',v->>'payload_sha256',
  'wire_base64',replace(encode(raw_bytes,'base64'),chr(10),''),
  'wire_sha256',wire_sha,'render_authorized',false,
  'native_transmitted',false,'provider_receipt',NULL,'qa_verdict','NOT_EVALUATED');
END $function$
;

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
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_order_close_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
 IF NEW.status='COMPLETADO' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF EXISTS(SELECT 1 FROM saly.creative_runs r WHERE r.order_id=NEW.id
      AND r.state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_ORDER_CLOSURE_WITH_ACTIVE_RUNS'; END IF;
   IF NOT EXISTS (SELECT 1 FROM saly.creative_order_items i
                  WHERE i.order_id=NEW.id AND i.required)
      OR EXISTS (SELECT 1 FROM saly.creative_order_items i WHERE i.order_id=NEW.id
                 AND (i.status NOT IN ('TERMINADO','APROBADO','OMITIDO')
                  OR (i.required AND i.status NOT IN ('TERMINADO','APROBADO'))))
   THEN RAISE EXCEPTION 'CREATIVE_ORDER_CLOSURE_WITH_INCOMPLETE_DETAILS'; END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status='COMPLETADO'
 THEN RAISE EXCEPTION 'CREATIVE_COMPLETED_ORDER_IMMUTABLE'; END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_order_context_guard_l2a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_context record; v_tokens jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.status<>'BORRADOR'
      AND (NEW.context_set_id IS DISTINCT FROM OLD.context_set_id
       OR NEW.identity_snapshot IS DISTINCT FROM OLD.identity_snapshot)
   THEN RAISE EXCEPTION 'CREATIVE_ORDER_CONTEXT_FROZEN'; END IF;
 END IF;
 IF NEW.status<>'BORRADOR' THEN
  SELECT project_id,mode,state INTO v_context FROM saly.creative_context_sets
  WHERE id=NEW.context_set_id;
  IF NOT FOUND OR v_context.project_id<>NEW.project_id
   OR v_context.mode<>NEW.design_mode OR v_context.state<>'SEALED'
  THEN RAISE EXCEPTION 'CREATIVE_ORDER_CONTEXT_NOT_SEALED'; END IF;
  IF TG_OP='INSERT' THEN
    SELECT jsonb_agg(jsonb_build_object('version_id',identity_version_id,
      'sha256',value_sha256,'role',role) ORDER BY identity_version_id)
    INTO v_tokens
    FROM saly.creative_context_tokens WHERE context_set_id=NEW.context_set_id;
    NEW.identity_snapshot:=jsonb_build_object('context_set_id',NEW.context_set_id,
      'selected_versions',v_tokens);
  ELSIF OLD.status='BORRADOR' THEN
    SELECT jsonb_agg(jsonb_build_object('version_id',identity_version_id,
      'sha256',value_sha256,'role',role) ORDER BY identity_version_id)
    INTO v_tokens
    FROM saly.creative_context_tokens WHERE context_set_id=NEW.context_set_id;
    NEW.identity_snapshot:=jsonb_build_object('context_set_id',NEW.context_set_id,
      'selected_versions',v_tokens);
  END IF;
 END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_order_create_v1(p_project_id bigint, p_context_set_id bigint, p_code text, p_request_key text, p_title text, p_requested_by text, p_scope_json jsonb, p_item_code text, p_item_title text, p_acceptance_json jsonb, p_context_json jsonb)
 RETURNS TABLE(order_id bigint, item_id bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_order bigint; v_item bigint;
BEGIN
 INSERT INTO saly.creative_orders(project_id,context_set_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status)
 VALUES(p_project_id,p_context_set_id,p_code,p_request_key,p_title,'APP_SCREEN_SINGLE','EXPLORE',p_requested_by,p_scope_json,'{}'::jsonb,'PLANIFICADO')
 RETURNING id INTO v_order;
 INSERT INTO saly.creative_order_items(order_id,code,ordinal,kind,title,acceptance_json,context_json,status)
 VALUES(v_order,p_item_code,1,'SCREEN',p_item_title,p_acceptance_json,p_context_json,'PENDIENTE')
 RETURNING id INTO v_item;
 RETURN QUERY SELECT v_order,v_item;
END $function$
;
