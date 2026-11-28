CREATE OR REPLACE FUNCTION saly.creative_single_screen_item_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE kind_of_order text;
BEGIN
 SELECT request_kind INTO kind_of_order FROM saly.creative_orders
 WHERE id=NEW.order_id FOR UPDATE;
 IF kind_of_order IS DISTINCT FROM 'APP_SCREEN_SINGLE' THEN RETURN NEW; END IF;
 IF NEW.kind IS DISTINCT FROM 'SCREEN' OR NEW.ordinal IS DISTINCT FROM 1
 OR NEW.variant_of_item_id IS NOT NULL
 THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_ITEM_SHAPE'; END IF;
 IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id
  OR NEW.order_id IS DISTINCT FROM OLD.order_id
  OR NEW.code IS DISTINCT FROM OLD.code)
 THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_ITEM_BINDING_IMMUTABLE'; END IF;
 IF TG_OP='INSERT' AND EXISTS (SELECT 1 FROM saly.creative_order_items
   WHERE order_id=NEW.order_id)
 THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_MULTIPLE_ITEMS'; END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_skill_prepare_v1(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE
 base jsonb:=jsonb_build_object('schema_version','CREATIVE_SKILL_PLAN_V1',
    'status','BLOCKED','native_execution_authorized',false,
    'image_generation_allowed',false,'native_transmitted',false,
    'provider_receipt',NULL,'qa_verdict','NOT_EVALUATED',
    'router_invoked',false,'profile_invoked',false,'database_written',false);
 tokens jsonb; logo jsonb;
 k text; item record; n bigint; pkt jsonb; contract jsonb; qa jsonb;
 handoff jsonb; wire jsonb; msg_hash text; contract_hash text; request_hash text;
BEGIN
 IF jsonb_typeof(p_request) IS DISTINCT FROM 'object'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_REQUEST_INVALID'); END IF;
 IF NOT(p_request ?& ARRAY['schema_version','mode','business_code','project_code',
       'order_code','item_code','literal_request'])
 OR (SELECT count(*) FROM jsonb_object_keys(p_request))<>7
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_REQUEST_FIELDS_INVALID'); END IF;
 FOREACH k IN ARRAY ARRAY['schema_version','mode','business_code','project_code',
       'order_code','item_code','literal_request'] LOOP
   IF jsonb_typeof(p_request->k) IS DISTINCT FROM 'string'
   OR nullif(btrim(p_request->>k),'') IS NULL
   THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_REQUEST_FIELDS_INVALID'); END IF;
 END LOOP;
 IF p_request->>'schema_version'<>'CREATIVE_SKILL_PREPARE_REQUEST_V1'
 OR p_request->>'mode' NOT IN ('PLAN_ONLY','AUTONOMOUS')
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_MODE_INVALID'); END IF;
 IF p_request->>'business_code'='LF' THEN
   IF p_request->>'project_code'<>'LF' OR p_request->>'mode'<>'AUTONOMOUS' THEN RETURN base||jsonb_build_object('blocking_code','LF_MODE_OR_PROJECT_INVALID'); END IF;
   SELECT i.id,i.order_id,o.scope_json,o.context_set_id,o.status AS order_status,c.state AS context_state,c.provenance
   INTO item FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id JOIN saly.proyecto p ON p.id=o.project_id JOIN saly.creative_context_sets c ON c.id=o.context_set_id AND c.project_id=p.id
   WHERE p.codigo='LF' AND o.code=p_request->>'order_code' AND i.code=p_request->>'item_code';
   IF NOT FOUND THEN RETURN base||jsonb_build_object('blocking_code','SKILL_TARGET_NOT_FOUND'); END IF;
   IF item.scope_json->>'literal_request' IS DISTINCT FROM p_request->>'literal_request' OR item.context_state<>'SEALED' OR item.order_status NOT IN ('PLANIFICADO','EN_PROCESO') THEN RETURN base||jsonb_build_object('blocking_code','LF_TARGET_NOT_READY'); END IF;
   SELECT jsonb_agg(jsonb_build_object('code',e.code,'version_id',v.id,'value',v.value_json,'role',t.role,'sha256',t.value_sha256) ORDER BY e.code) INTO tokens FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=item.context_set_id;
   RETURN base||jsonb_build_object('status','LF_DISCOVERY_PREPARED','business_code','LF','order_id',item.order_id,'item_id',item.id,'context_set_id',item.context_set_id,'literal_request',item.scope_json->>'literal_request','tokens',tokens,'assets',item.provenance::jsonb->'assets','next_action','ART_DIRECTION_PREFLIGHT_HANDOFF');
 END IF;
 IF p_request->>'business_code'<>'SALY'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE'); END IF;
 IF p_request->>'project_code'<>'SALY-001'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PROJECT_NOT_ADMITTED'); END IF;

 -- Exact target binding, not a similarity guess across projects.
 SELECT count(*) INTO n
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE p.codigo=p_request->>'project_code' AND o.code=p_request->>'order_code'
   AND i.code=p_request->>'item_code';
 IF n<>1 THEN RETURN base||jsonb_build_object('blocking_code',
       CASE WHEN n=0 THEN 'SKILL_TARGET_NOT_FOUND' ELSE 'SKILL_TARGET_AMBIGUOUS' END); END IF;
 SELECT i.id,i.order_id,i.code AS item_code,o.code AS order_code,o.scope_json,o.status AS order_status,o.context_set_id,o.project_id,
 (SELECT state FROM saly.creative_context_sets WHERE id=o.context_set_id) AS context_state
 INTO STRICT item
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE p.codigo=p_request->>'project_code' AND o.code=p_request->>'order_code'
   AND i.code=p_request->>'item_code';

 -- A different literal is a new intent, not authority to reuse the old strategy.
 IF convert_to(p_request->>'literal_request','UTF8') IS DISTINCT FROM
    convert_to(item.scope_json->>'literal_request','UTF8')
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_NEW_INTENT_REQUIRES_INTERPRETATION'); END IF;

 IF p_request->>'mode'='AUTONOMOUS' THEN
   IF item.order_status NOT IN ('PLANIFICADO','EN_PROCESO') OR item.context_state IS DISTINCT FROM 'SEALED'
   THEN RETURN base||jsonb_build_object('blocking_code','SKILL_AUTONOMOUS_TARGET_NOT_READY'); END IF;
   IF item.scope_json->>'queue_mode'='SERIAL_V1' AND NOT EXISTS (SELECT 1 FROM saly.creative_queue_claims_v1 c WHERE c.order_id=item.order_id AND c.item_id=item.id AND c.state='ACTIVE' AND c.lease_until>clock_timestamp()) THEN RETURN base||jsonb_build_object('blocking_code','SKILL_AUTONOMOUS_CLAIM_REQUIRED'); END IF;
   SELECT jsonb_agg(jsonb_build_object('code',e.code,'version_id',v.id,'value',v.value_json,'role',t.role,'sha256',t.value_sha256) ORDER BY e.code) INTO tokens
   FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=item.context_set_id;
   SELECT jsonb_build_object('asset_id',id,'code',code,'version',version_number,'sha256',sha256,'file_provider',file_provider,'external_file_id',external_file_id,'filename',metadata->>'filename') INTO logo
   FROM saly.brand_assets WHERE id=9 AND project_id=item.project_id AND approval_status='APPROVED';
   RETURN base||jsonb_build_object('status','AUTONOMOUS_PREPARED','blocking_code',NULL,'image_generation_allowed',true,
    'item_id',item.id,'order_id',item.order_id,'context_set_id',item.context_set_id,
    'literal_request',item.scope_json->>'literal_request','compiled_prompt',coalesce(item.scope_json->>'compiled_prompt',item.scope_json->>'content_prompt',item.scope_json->>'literal_request'),
    'tokens',tokens,'logo_ref',logo,'next_action','GPT_GENERATE_AND_QA');
 END IF;

 IF item.scope_json->'review_only' IS DISTINCT FROM 'true'::jsonb
 OR item.scope_json->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_TARGET_NOT_REVIEW_ONLY'); END IF;

 pkt:=saly.creative_item_work_packet_l2c(item.id);
 IF pkt->>'readiness_code' IS DISTINCT FROM 'READY_FOR_REVIEW_ONLY'
 THEN RETURN base||jsonb_build_object('blocking_code','SKILL_PLAN_SOURCE_NOT_READY',
               'source_readiness',pkt->>'readiness_code','item_id',item.id); END IF;
 IF pkt->>'business_code' IS DISTINCT FROM 'SALY'
 OR pkt->>'item_id' IS DISTINCT FROM item.id::text
 OR pkt->>'order_id' IS DISTINCT FROM item.order_id::text
 OR pkt->>'item_code' IS DISTINCT FROM item.item_code
 OR pkt->>'order_code' IS DISTINCT FROM item.order_code
 OR pkt->'native_execution_authorized' IS DISTINCT FROM 'false'::jsonb
 OR pkt->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'SKILL_PLAN_CANONICAL_PACKET_DRIFT'; END IF;

 contract:=pkt#>'{review_contract,contract}';
 handoff:=contract->'handoff';
 qa:=contract#>'{acceptance_criteria,semantic_qa}';
 msg_hash:=encode(extensions.digest(convert_to((qa->'original_messages')::text,'UTF8'),'sha256'),'hex');
 contract_hash:=encode(extensions.digest(convert_to(contract::text,'UTF8'),'sha256'),'hex');
 request_hash:=encode(extensions.digest(convert_to(p_request->>'literal_request','UTF8'),'sha256'),'hex');
 IF pkt#>>'{review_contract,state}' IS DISTINCT FROM 'REVIEW_CONTRACT_PREPARED'
 OR contract_hash IS NULL
 OR contract_hash IS DISTINCT FROM pkt#>>'{review_contract,contract_sha256}'
 OR qa->>'source_type' IS DISTINCT FROM 'PERSISTED_ORDER_LITERAL_REQUEST'
 OR qa#>>'{original_messages,0,speaker}' IS DISTINCT FROM 'USER'
 OR qa#>>'{original_messages,0,text}' IS DISTINCT FROM p_request->>'literal_request'
 OR msg_hash IS NULL OR msg_hash IS DISTINCT FROM qa->>'original_request_sha256'
 OR qa#>>'{interpretation,origin}' IS DISTINCT FROM 'ASSISTANT_INTERPRETATION_SEPARATE_FROM_USER_LITERAL'
 OR qa#>'{interpretation,strategy}' IS DISTINCT FROM item.scope_json->'strategy'
 OR qa#>>'{interpretation,mode}' IS DISTINCT FROM 'REVIEW_ONLY'
 OR jsonb_typeof(qa->'checks') IS DISTINCT FROM 'array'
 OR jsonb_array_length(qa->'checks')=0
 OR jsonb_typeof(contract->'qa_checks') IS DISTINCT FROM 'array'
 OR jsonb_array_length(contract->'qa_checks')=0
 OR handoff->>'mode' IS DISTINCT FROM 'REVIEW_ONLY'
 OR handoff->'transmitted' IS DISTINCT FROM 'false'::jsonb
 OR jsonb_typeof(handoff->'trace') IS DISTINCT FROM 'array'
 OR jsonb_array_length(handoff->'trace')=0
 OR jsonb_typeof(handoff#>'{composition,asset_refs}') IS DISTINCT FROM 'object'
 OR jsonb_typeof(handoff#>'{composition,logo_ref}') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'SKILL_PLAN_INTERPRETATION_OR_CONTRACT_DRIFT'; END IF;

 -- Existing DB wire resolver owns serialization and checks exact prompt/attachments.
 wire:=saly.creative_native_canonical_wire_v1(item.id);
 IF wire->>'status' IS DISTINCT FROM 'CANONICAL_WIRE_REVIEW_ONLY'
 OR wire->>'contract_sha256' IS DISTINCT FROM contract_hash
 OR wire->>'prompt_sha256' IS DISTINCT FROM handoff->>'prompt_sha256'
 OR wire->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
 OR wire->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR wire->'provider_receipt' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'SKILL_PLAN_WIRE_DRIFT'; END IF;

 -- One canonical packet; stages only summarize it and point to exact source paths.
 RETURN base||jsonb_build_object(
   'status','PLAN_PREPARED_REVIEW_ONLY','blocking_code',NULL,
   'source','saly.creative_item_work_packet_l2c+saly.creative_native_canonical_wire_v1',
   'business_code','SALY','project_code',p_request->>'project_code',
   'order_code',item.order_code,'item_code',item.item_code,'item_id',item.id,
   'request_sha256',request_hash,'original_messages_sha256',msg_hash,
   'interpretation_status','PERSISTED_INTERPRETATION_VERIFIED',
   'discovery_status','CANONICAL_PACKET_SOURCE_REVALIDATED',
   'blueprint_status','EXACT_HANDOFF_PREPARED_NOT_SENT',
   'contract_sha256',contract_hash,
   'prompt_sha256',handoff->>'prompt_sha256',
   'template',handoff->>'template','template_version',handoff->>'template_version',
   'token_trace_count',jsonb_array_length(handoff->'trace'),
   'svg_asset_count',(SELECT count(*) FROM jsonb_object_keys(pkt->'composition_svg_assets')),
   'logo_ref',handoff#>'{composition,logo_ref}',
   'technical_check_count',jsonb_array_length(contract->'qa_checks'),
   'semantic_check_count',jsonb_array_length(qa->'checks'),
   'work_packet',pkt,'canonical_wire',wire,
   'next_action','REVIEW_PLAN_NO_RENDER');
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_task_select_once_v2(p_item_id bigint, p_task text, p_spatial_change boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE v_row saly.creative_task_selection_v2%ROWTYPE;v_j jsonb;
BEGIN
 IF p_item_id IS NULL OR p_item_id<1 OR
 NOT EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=p_item_id)
 THEN RAISE EXCEPTION 'SALY_K_ITEM_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:k:select:'||p_item_id::text,0));
 SELECT * INTO v_row FROM saly.creative_task_selection_v2 WHERE item_id=p_item_id;
 IF FOUND THEN
   IF v_row.task IS DISTINCT FROM p_task
     OR v_row.spatial_change IS DISTINCT FROM p_spatial_change
   THEN RAISE EXCEPTION 'SALY_K_SELECTION_ALREADY_FIXED'; END IF;
   RETURN v_row.selection_json;
 END IF;
 v_j:=visual.knowledge_select_task_v2('SALY',p_task,p_spatial_change);
 INSERT INTO saly.creative_task_selection_v2(
    item_id,task,spatial_change,selection_json,selection_sha256)
 VALUES(p_item_id,p_task,p_spatial_change,v_j,
    encode(extensions.digest(v_j::text,'sha256'),'hex'));
 RETURN v_j;
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_template_preflight_v1(p_item bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions'
AS $function$
DECLARE
 h jsonb; g jsonb; t jsonb; a jsonb; asset visual.source_assets%ROWTYPE;
 logo saly.brand_assets%ROWTYPE; item record; refs jsonb; n integer;
 semantic jsonb; checks jsonb; contract jsonb; messages jsonb;
BEGIN
 SELECT i.status,i.context_json,i.qa_receipt,o.scope_json,v.manifest_json
 INTO STRICT item FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN visual.standard_versions v ON v.id=(i.context_json->>'template_version_id')::bigint
 WHERE i.id=p_item AND v.state='CANDIDATE';
 IF item.status<>'PENDIENTE' OR item.scope_json->'render_authorized' IS DISTINCT FROM 'false'::jsonb
 OR item.qa_receipt IS DISTINCT FROM '{}'::jsonb THEN RAISE EXCEPTION 'TEMPLATE_PREFLIGHT_REVIEW_ONLY'; END IF;
 h:=saly.creative_template_review_v1(p_item); t:=item.manifest_json; g:=h#>'{composition,geometry}';
 refs:=h#>'{composition,asset_refs}';
 IF h->'transmitted' IS DISTINCT FROM 'false'::jsonb OR h->>'mode' IS DISTINCT FROM 'REVIEW_ONLY'
 OR jsonb_typeof(refs) IS DISTINCT FROM 'object'
 OR NOT (refs ?& ARRAY['frame','Inicio','Historial','Explorar','Perfil'])
 OR (SELECT count(*) FROM jsonb_object_keys(refs))<>5
 OR g->'viewport' IS DISTINCT FROM '[400,848]'::jsonb
 OR h#>'{composition,render_ready}' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'TEMPLATE_PREFLIGHT_SHAPE'; END IF;
 FOR a IN SELECT value FROM jsonb_each(refs) LOOP
  SELECT * INTO STRICT asset FROM visual.source_assets WHERE id=(a->>'asset_id')::bigint
   AND brand_code='SALY' AND asset_code=a->>'asset_code'
   AND version_number=(a->>'version')::integer AND approval_status='CANDIDATE'
   AND provider='SUPABASE_INLINE_SVG' AND source_sha256=a->>'sha256'
   AND source_sha256=encode(extensions.digest(convert_to(metadata->>'svg','UTF8'),'sha256'),'hex')
   AND xml_is_well_formed_document(metadata->>'svg');
  IF asset.source_kind IS DISTINCT FROM a->>'kind' THEN RAISE EXCEPTION 'COMPOSITION_ASSET_KIND'; END IF;
 END LOOP;
 IF (SELECT count(DISTINCT x->>'asset_id') FROM jsonb_each(refs) z(k,x))<>5
 OR refs#>>'{frame,kind}' IS DISTINCT FROM 'FRAME'
 OR EXISTS(SELECT 1 FROM jsonb_each(refs) z(k,x) WHERE k<>'frame' AND x->>'kind'<>'ICON')
 THEN RAISE EXCEPTION 'COMPOSITION_ASSET_ROLE'; END IF;
 SELECT * INTO STRICT asset FROM visual.source_assets WHERE id=(refs#>>'{frame,asset_id}')::bigint;
 IF asset.metadata#>'{geometry,app_opening}' IS DISTINCT FROM '[16,48,400,848]'::jsonb THEN
  RAISE EXCEPTION 'COMPOSITION_FRAME_GEOMETRY';
 END IF;
 SELECT * INTO STRICT logo FROM saly.brand_assets WHERE id=(h#>>'{logo,id}')::bigint
  AND code=h#>>'{logo,code}' AND version_number=(h#>>'{logo,version}')::integer
  AND sha256=h#>>'{logo,sha256}' AND approval_status='APPROVED' AND valid_to IS NULL;
 IF h#>'{composition,logo_ref}' IS DISTINCT FROM jsonb_build_object('asset_id',logo.id,'provider',logo.file_provider,'file_id',logo.external_file_id,'sha256',logo.sha256,'version',logo.version_number,'mime_type','image/png') THEN RAISE EXCEPTION 'COMPOSITION_LOGO_LOCATOR'; END IF;
 SELECT count(*) INTO n FROM jsonb_array_elements(h->'trace') x
 WHERE x->>'consumer'='composition' AND x->>'component'='navegacion'
 AND x->>'property' IN ('activa','fondo','inactiva','fuente base','tipografía etiqueta');
 IF n<>5 OR jsonb_array_length(h->'trace')<>15
 OR h->>'prompt_sha256' IS DISTINCT FROM encode(extensions.digest(convert_to(h->>'native_prompt','UTF8'),'sha256'),'hex')
 THEN RAISE EXCEPTION 'TEMPLATE_PREFLIGHT_TRACE'; END IF;
 IF nullif(btrim(item.scope_json->>'literal_request'),'') IS NULL THEN RAISE EXCEPTION 'MISSING_LITERAL_REQUEST'; END IF;
 messages:=jsonb_build_array(jsonb_build_object('speaker','USER','text',item.scope_json->>'literal_request'));
 semantic:=jsonb_build_object('schema_version','SALY_SEMANTIC_QA_L3C_V1',
  'source_type','PERSISTED_ORDER_LITERAL_REQUEST','original_messages',messages,
  'original_request_sha256',encode(extensions.digest(convert_to(messages::text,'UTF8'),'sha256'),'hex'),
  'interpretation',jsonb_build_object('origin','ASSISTANT_INTERPRETATION_SEPARATE_FROM_USER_LITERAL',
   'strategy',item.scope_json->'strategy','template',h->'template','mode','REVIEW_ONLY'),
  'require_independent_interpretation',true,'require_artifact_evidence',true,
  'checks',jsonb_build_array(
   jsonb_build_object('code','INTENT_MATCH','severity','BLOCK','expected','Home muestra disponible y solicitud de adelanto'),
   jsonb_build_object('code','SCOPE_MATCH','severity','BLOCK','expected','Variante B; creatividad limitada al cuerpo'),
   jsonb_build_object('code','FIXED_COMPONENTS_PRESERVED','severity','BLOCK','expected','Marco, logo, CTA y navegación pertenecen al compositor'),
   jsonb_build_object('code','NO_UNREQUESTED_CHANGES','severity','BLOCK','expected','Sin funciones, cifras, fechas ni adornos añadidos'),
   jsonb_build_object('code','FUNCTIONAL_PURPOSE_PRESERVED','severity','BLOCK','expected','Copy, monto, servicios y navegación de la estrategia guardada')));
 checks:=jsonb_build_array(
   jsonb_build_object('code','ASSET_INTEGRITY','severity','BLOCK','expected',jsonb_build_object('svg_assets',refs,'logo',h#>'{composition,logo_ref}'),'method','COMPARE_RENDER_INPUT_BYTES_AND_SHA256'),
   jsonb_build_object('code','GEOMETRY','severity','BLOCK','expected',g,'method','COMPARE_RENDER_BOXES_WITH_MANIFEST'),
   jsonb_build_object('code','STYLE_TOKENS','severity','BLOCK','expected',h->'trace','method','VERIFY_RENDER_MEASUREMENTS_AND_COLOR'),
   jsonb_build_object('code','COPY_AND_NUMBERS','severity','BLOCK','expected',item.scope_json->'strategy','method','INDEPENDENT_OCR_AND_VISUAL_REVIEW'),
   jsonb_build_object('code','COMPOSITION_BOUNDARIES','severity','BLOCK','expected',h->'composition','method','CHECK_NO_DUPLICATE_FIXED_ELEMENTS'));
 contract:=jsonb_build_object('schema_version','SALY_TEMPLATE_PREFLIGHT_V1','item_id',p_item,
  'handoff',h,'acceptance_criteria',jsonb_build_object('semantic_qa',semantic,'review_only',true),
  'qa_checks',checks,'qa_verdict','NOT_EVALUATED','native_execution_authorized',false,
  'image_generation_allowed',false,'render_state','NOT_EXECUTED');
 RETURN jsonb_build_object('contract',contract,
 'contract_sha256',encode(extensions.digest(convert_to(contract::text,'UTF8'),'sha256'),'hex'),
 'state','REVIEW_CONTRACT_PREPARED');
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_template_review_v1(p_item bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions'
AS $function$
DECLARE u record; t jsonb; c jsonb; b record; tok record; target text; seen text[];
 rec text; trace jsonb:='[]'; lines text[]; ctx jsonb; brief text; style_bindings jsonb; rendered text;
BEGIN
 SELECT o.id oid,o.context_set_id,o.scope_json->'strategy' plan,i.code,
  v.manifest_json tpl,v.id vid,v.version,v.manifest_sha256,s.standard_code INTO STRICT u
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id JOIN visual.standard_versions v ON v.id=(i.context_json->>'template_version_id')::bigint
 JOIN visual.standards s ON s.id=v.standard_id
 WHERE i.id=p_item AND p.codigo='SALY-001' AND v.brand_code='SALY' AND v.state='CANDIDATE'
 AND o.design_mode='EXPLORE' AND v.manifest_sha256=i.context_json->>'template_sha256'
 AND v.manifest_json->>'type'='MOBILE_TEMPLATE_REVIEW_V1';
 ctx:=saly.creative_item_context_l2a(p_item); t:=u.tpl;
 lines:=ARRAY[u.plan->>'objective',u.plan->>'body',t->>'native_layout'];
 style_bindings:=coalesce(t->'style_bindings','{}'::jsonb);
 IF jsonb_typeof(style_bindings) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'BAD_TEMPLATE_STYLE_BINDINGS'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(style_bindings) d
   WHERE jsonb_typeof(d.value) IS DISTINCT FROM 'object'
     OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(u.plan->'components') x WHERE x->>'code'=d.key))
 THEN RAISE EXCEPTION 'BAD_TEMPLATE_STYLE_COMPONENT'; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(u.plan->'components') LOOP
   rec:=coalesce(t->'owners'->>(c->>'code'),'native');
   IF rec NOT IN ('native','composition') THEN RAISE EXCEPTION 'BAD_COMPONENT_OWNER'; END IF;
   IF rec='native' THEN lines:=array_append(lines,c->>'instruction'); END IF;
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(coalesce(style_bindings->(c->>'code'),'{}'::jsonb)) k
      WHERE c->'bindings' ? k) THEN RAISE EXCEPTION 'TEMPLATE_STYLE_BINDING_COLLISION'; END IF;
   FOR b IN SELECT key,value FROM jsonb_each_text(c->'bindings'||coalesce(style_bindings->(c->>'code'),'{}'::jsonb)) ORDER BY key COLLATE "C" LOOP
     target:=b.value; seen:=ARRAY[]::text[];
     LOOP
       IF target=ANY(seen) THEN RAISE EXCEPTION 'ALIAS_CYCLE'; END IF;
       seen:=array_append(seen,target);
       SELECT v.id,v.value_json->'value' val,v.metadata->>'alias_target_code' alias,v.approval_status,e.family
       INTO STRICT tok FROM saly.creative_context_tokens ct JOIN saly.identity_versions v ON v.id=ct.identity_version_id
       JOIN saly.identity_elements e ON e.id=v.element_id WHERE ct.context_set_id=u.context_set_id AND e.code=target
       AND EXISTS(SELECT 1 FROM jsonb_array_elements(ctx->'tokens') x WHERE x->>'code'=target)
       AND ct.value_sha256=encode(extensions.digest(v.value_json::text,'sha256'),'hex');
       EXIT WHEN tok.alias IS NULL; target:=tok.alias;
     END LOOP;
     IF tok.val IS NULL OR jsonb_typeof(tok.val)='null' THEN RAISE EXCEPTION 'EMPTY_OR_UNRESOLVED_TOKEN'; END IF;
     IF jsonb_typeof(tok.val)='object' THEN
       IF tok.family IS DISTINCT FROM 'TYPOGRAPHY'
          OR NOT (tok.val ?& ARRAY['size_px','weight','line_height_px'])
          OR (tok.val - ARRAY['size_px','weight','line_height_px']) <> '{}'::jsonb
          OR jsonb_typeof(tok.val->'size_px') IS DISTINCT FROM 'number'
          OR jsonb_typeof(tok.val->'weight') IS DISTINCT FROM 'number'
          OR jsonb_typeof(tok.val->'line_height_px') IS DISTINCT FROM 'number'
       THEN RAISE EXCEPTION 'UNSUPPORTED_STRUCTURED_TOKEN'; END IF;
       IF (tok.val->>'size_px')::numeric<=0
          OR (tok.val->>'line_height_px')::numeric<=0
          OR (tok.val->>'weight')::numeric NOT BETWEEN 1 AND 1000
       THEN RAISE EXCEPTION 'INVALID_TYPOGRAPHY_TOKEN'; END IF;
       rendered:=format('%s px, peso %s, interlineado %s px',tok.val->>'size_px',tok.val->>'weight',tok.val->>'line_height_px');
     ELSIF jsonb_typeof(tok.val) IN ('number','string','boolean') THEN
       rendered:=tok.val#>>'{}';
       IF nullif(btrim(rendered),'') IS NULL THEN RAISE EXCEPTION 'EMPTY_OR_UNRESOLVED_TOKEN'; END IF;
     ELSE RAISE EXCEPTION 'UNSUPPORTED_STRUCTURED_TOKEN';
     END IF;
     trace:=trace||jsonb_build_array(jsonb_build_object('component',c->>'code','property',b.key,'consumer',rec,
      'chain',seen,'value',tok.val,'version_id',tok.id,'status',tok.approval_status));
     IF rec='native' THEN lines:=array_append(lines,format('%s · %s: %s.',c->>'code',b.key,rendered)); END IF;
   END LOOP;
 END LOOP;
 brief:=array_to_string(lines,chr(10));
 RETURN jsonb_build_object('order_id',u.oid,'item_id',p_item,'template',u.standard_code,'template_version_id',u.vid,
 'template_version',u.version,'template_sha256',u.manifest_sha256,'native_prompt',brief,'trace',trace,
 'prompt_sha256',encode(extensions.digest(convert_to(brief,'UTF8'),'sha256'),'hex'),'attachments','[]'::jsonb,
 'composition',t->'composition','navigation_active',u.plan->'navigation_active','cta_copy',(SELECT x->>'instruction' FROM jsonb_array_elements(u.plan->'components') x WHERE x->>'code'='cta'),'logo',t->'logo','mode','REVIEW_ONLY','transmitted',false);
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_token_confirm_medium_v1(p_version_id bigint, p_medium text, p_comment text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'auth', 'extensions', 'pg_temp'
AS $function$
DECLARE uid uuid; v saly.identity_versions%ROWTYPE;
 v_role text; v_old_sha text; v_next jsonb;
BEGIN
 uid:=auth.uid();
 IF uid IS NULL OR p_version_id IS NULL OR p_version_id<1
 OR p_medium NOT IN ('REDES_SOCIALES','IMPRESION','PAPEL')
 OR nullif(btrim(coalesce(p_comment,'')),'') IS NULL
 THEN RAISE EXCEPTION 'SALY_TOKEN_CONFIRM_INPUT_INVALID'; END IF;
 IF NOT EXISTS (SELECT 1 FROM saly.creative_owner_accounts_v1
  WHERE requested_by='CHAT_USER' AND owner_uid=uid)
 THEN RAISE EXCEPTION 'SALY_TOKEN_CONFIRM_OWNER_REQUIRED'; END IF;
 SELECT * INTO STRICT v FROM saly.identity_versions WHERE id=p_version_id FOR UPDATE;
 v_role:=v.metadata->>'token_role';
 IF v_role IN ('CTA','DUPLICADO_DE_CTA','GEOMETRIA_UI','NAVEGACION_ESTADO_UI')
 THEN RAISE EXCEPTION 'SALY_TOKEN_ROLE_APP_ONLY'; END IF;
 IF jsonb_typeof(v.metadata->'applies_to_proposed') IS DISTINCT FROM 'array'
 OR NOT (v.metadata->'applies_to_proposed' ? p_medium)
 THEN RAISE EXCEPTION 'SALY_TOKEN_MEDIUM_NOT_PROPOSED'; END IF;
 IF v.metadata->'applies_to' ? p_medium
 THEN RAISE EXCEPTION 'SALY_TOKEN_MEDIUM_ALREADY_CONFIRMED'; END IF;
 v_old_sha:=encode(extensions.digest(v.metadata::text,'sha256'),'hex');
 v_next:=jsonb_set(v.metadata,'{applies_to}',
    (v.metadata->'applies_to')||jsonb_build_array(p_medium),true);
 INSERT INTO saly.creative_token_medium_confirmations_v1(
 version_id,medium,confirmed_by,comment,metadata_previous_sha256)
 VALUES(p_version_id,p_medium,uid,p_comment,v_old_sha);
 UPDATE saly.identity_versions SET metadata=v_next WHERE id=p_version_id;
 RETURN jsonb_build_object('version_id',p_version_id,
  'medium',p_medium,'confirmed_by',uid,'confirmed_at',
  (SELECT confirmed_at FROM saly.creative_token_medium_confirmations_v1
  WHERE version_id=p_version_id AND medium=p_medium),
  'metadata_previous_sha256',v_old_sha,
  'approval_status',v.approval_status,
  'role',v_role,'status','CONFIRMADO');
END; $function$
;
