BEGIN;
CREATE OR REPLACE FUNCTION saly.creative_lf_identity_packet_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,lf_design AS $fn$
 SELECT jsonb_build_object('business_code','LF','design_system',to_jsonb(ds),
 'tokens',jsonb_build_object(
 'colors',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.color_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'typography',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.typography_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'spacing',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.spacing_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'components',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.component_token_code),'[]'::jsonb) FROM lf_design.component_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'themes',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.theme_binding_code),'[]'::jsonb) FROM lf_design.theme_bindings t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE')),
 'assets',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.asset_code),'[]'::jsonb) FROM lf_design.brand_assets a WHERE a.is_current AND a.status='VIGENTE'))
 FROM lf_design.design_systems ds WHERE ds.project_code='LF' AND ds.design_system_code='LF_DS_V1';
$fn$;
REVOKE ALL ON FUNCTION saly.creative_lf_identity_packet_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Owner authorization for LF test, current logo candidates only.
UPDATE lf_design.brand_assets SET status='VIGENTE'
WHERE is_current AND status='CANDIDATO_VISUAL' AND asset_code LIKE 'LF_BRAND_LOGO_%';
CREATE OR REPLACE FUNCTION saly.creative_context_token_guard_l2a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'extensions'
AS $function$
DECLARE v_set record; v_version record; v_expected_role text;
BEGIN
 IF TG_OP<>'INSERT' THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_TOKEN_IMMUTABLE';
 END IF;
 SELECT * INTO v_set FROM saly.creative_context_sets WHERE id=NEW.context_set_id FOR UPDATE;
 IF NOT FOUND OR v_set.state<>'DRAFT' THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_NOT_DRAFT';
 END IF;
 SELECT e.project_id,e.code,v.approval_status,v.value_json INTO v_version
 FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE v.id=NEW.identity_version_id;
 IF NOT FOUND OR v_version.project_id<>v_set.project_id THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_WRONG_PROJECT_OR_VERSION';
 END IF;
 IF EXISTS (SELECT 1 FROM saly.proyecto WHERE id=v_set.project_id AND codigo='LF') THEN
   IF v_version.code NOT LIKE 'lf.source.%' OR v_version.approval_status<>'APPROVED' OR NEW.role<>'OFFICIAL' THEN RAISE EXCEPTION 'LF_CONTEXT_SOURCE_NOT_AUTHORIZED'; END IF;
   NEW.value_sha256:=encode(extensions.digest(v_version.value_json::text,'sha256'),'hex');
   RETURN NEW;
 END IF;
 v_expected_role:=CASE
  WHEN v_version.code IN ('color.brand.primary','color.action.primary.bg')
       AND v_version.approval_status='APPROVED' THEN 'OFFICIAL'
  WHEN v_version.code LIKE 'candidate.saly_ds_v1.%'
       AND (v_version.approval_status='CANDIDATE' OR (v_version.approval_status='APPROVED' AND EXISTS (SELECT 1 FROM saly.v_identity_current c WHERE c.version_id=NEW.identity_version_id AND c.project_code='SALY-001'))) THEN 'EXISTING'
  WHEN v_version.code LIKE 'candidate.saly_home_v3.%'
       AND (v_version.approval_status='CANDIDATE' OR (v_version.approval_status='APPROVED' AND EXISTS (SELECT 1 FROM saly.v_identity_current c WHERE c.version_id=NEW.identity_version_id AND c.project_code='SALY-001'))) THEN 'HOME'
  ELSE NULL END;
 IF v_expected_role IS NULL OR NEW.role<>v_expected_role THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_ROLE_NOT_AUTHORIZED';
 END IF;
 NEW.value_sha256:=encode(extensions.digest(v_version.value_json::text,'sha256'),'hex');
 RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_context_set_guard_l2a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'extensions'
AS $function$
DECLARE v_all int; v_official int; v_drift int; v_distinct_codes int;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_SET_DELETE_FORBIDDEN'; END IF;
 IF TG_OP='UPDATE' THEN
  IF OLD.state='SEALED' THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_SET_IMMUTABLE'; END IF;
  IF NEW.project_id IS DISTINCT FROM OLD.project_id
   OR NEW.code IS DISTINCT FROM OLD.code
   OR NEW.version_label IS DISTINCT FROM OLD.version_label
   OR NEW.mode IS DISTINCT FROM OLD.mode
   OR NEW.provenance IS DISTINCT FROM OLD.provenance
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_IDENTITY_IMMUTABLE'; END IF;
 END IF;
 IF NEW.state='SEALED' THEN
  IF EXISTS (SELECT 1 FROM saly.proyecto WHERE id=NEW.project_id AND codigo='LF') THEN
    SELECT count(*),count(DISTINCT e.code),count(*) FILTER(WHERE e.project_id<>NEW.project_id OR e.code NOT LIKE 'lf.source.%' OR v.approval_status<>'APPROVED' OR t.role<>'OFFICIAL' OR t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex'))
    INTO v_all,v_distinct_codes,v_drift FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=NEW.id;
    IF v_all<1 OR v_all<>v_distinct_codes OR v_drift<>0 THEN RAISE EXCEPTION 'LF_CONTEXT_SEAL_INCOMPLETE'; END IF;
    NEW.sealed_at:=now(); RETURN NEW;
  END IF;
  -- OLD is read only in the UPDATE-only guard above.
  -- Universal seal rule: two effective SALY official colors, no duplicate codes,
  -- verified immutable values; no 41-token hardcode for future EXPLORE sets.
  SELECT count(*)::int,
    count(*) FILTER(WHERE t.role='OFFICIAL')::int,
    count(DISTINCT e.code)::int,
    count(*) FILTER(WHERE t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex'))::int
  INTO v_all,v_official,v_distinct_codes,v_drift
  FROM saly.creative_context_tokens t
  JOIN saly.identity_versions v ON v.id=t.identity_version_id
  JOIN saly.identity_elements e ON e.id=v.element_id
  WHERE t.context_set_id=NEW.id;
  IF v_all<2 OR v_official<>2 OR v_all<>v_distinct_codes OR v_drift<>0
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_SEAL_INCOMPLETE_DUPLICATE_OR_DRIFT'; END IF;
  IF EXISTS (
    SELECT 1 FROM saly.creative_context_tokens t
    WHERE t.context_set_id=NEW.id AND t.role='OFFICIAL'
    AND NOT EXISTS (SELECT 1 FROM saly.v_identity_current effective
       WHERE effective.project_code='SALY-001'
       AND effective.version_id=t.identity_version_id))
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_OFFICIAL_NOT_EFFECTIVE'; END IF;
  IF EXISTS (
   SELECT 1 FROM saly.creative_context_tokens alias_link
   JOIN saly.identity_versions alias_v ON alias_v.id=alias_link.identity_version_id
   WHERE alias_link.context_set_id=NEW.id
    AND alias_v.metadata->>'kind'='ALIAS'
    AND NOT EXISTS (
       SELECT 1 FROM saly.creative_context_tokens target_link
       JOIN saly.identity_versions target_v ON target_v.id=target_link.identity_version_id
       JOIN saly.identity_elements target_e ON target_e.id=target_v.element_id
       WHERE target_link.context_set_id=NEW.id
        AND target_e.code=alias_v.metadata->>'alias_target_code'))
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_ALIAS_TARGET_MISSING'; END IF;
  NEW.sealed_at:=now();
 END IF;
 RETURN NEW;
END $function$
;

DO $seed$
DECLARE pid bigint; cid bigint; eid bigint; vid bigint; packet jsonb; grp record; tok jsonb; code text; fam text;
BEGIN
 SELECT id INTO STRICT pid FROM saly.proyecto WHERE codigo='LF';
 packet:=saly.creative_lf_identity_packet_v1();
 IF packet IS NULL OR jsonb_array_length(packet->'assets')=0 THEN RAISE EXCEPTION 'LF_IDENTITY_MISSING'; END IF;
 INSERT INTO saly.creative_context_sets(project_id,code,version_label,provenance) VALUES(pid,'LF_DS_V1_TEST','v1.3',jsonb_build_object('source','lf_design','assets',packet->'assets','design_system',packet->'design_system')::text) RETURNING id INTO cid;
 FOR grp IN SELECT * FROM jsonb_each(packet->'tokens') LOOP
   FOR tok IN SELECT * FROM jsonb_array_elements(grp.value) LOOP
     code:='lf.source.'||grp.key||'.'||lower(coalesce(tok->>'token_name',tok->>'component_token_code',tok->>'theme_binding_code'));
     fam:=CASE grp.key WHEN 'colors' THEN 'COLOR' WHEN 'typography' THEN 'TYPOGRAPHY' WHEN 'spacing' THEN 'SPACING' ELSE 'RULE' END;
     INSERT INTO saly.identity_elements(project_id,code,family,value_type,name,status,metadata) VALUES(pid,code,fam,'JSON',code,'ACTIVE',jsonb_build_object('source','lf_design','source_status','VIGENTE')) RETURNING id INTO eid;
     INSERT INTO saly.identity_versions(element_id,version_number,value_json,approval_status,valid_from,approval_reference) VALUES(eid,1,jsonb_build_object('value',tok),'APPROVED',now(),'LF source VIGENTE; owner authorized factory test') RETURNING id INTO vid;
     INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256) VALUES(cid,vid,'OFFICIAL',repeat('0',64));
   END LOOP;
 END LOOP;
 UPDATE saly.creative_context_sets SET state='SEALED' WHERE id=cid;
END $seed$;
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
COMMIT;
