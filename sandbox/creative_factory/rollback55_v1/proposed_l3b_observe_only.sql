CREATE OR REPLACE FUNCTION saly.creative_item_visual_contract_l3b(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_bp jsonb; v_lock jsonb; v_binding record; v_token record; v_resolved jsonb := '{}'::jsonb;
 v_code text; v_seen text[]; v_prompt text;
 v_item record; v_context jsonb; v_dispatch jsonb;
 v_cta record; v_brand record; v_white record;
 v_contract jsonb; v_rules jsonb; v_hash text;
BEGIN
 SELECT i.id,i.order_id,i.code AS item_code,i.ordinal,i.status AS item_status,
        i.context_json,i.acceptance_json,
        o.code AS order_code,o.status AS order_status,o.context_set_id,
        p.codigo AS project_code
 INTO v_item
 FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=p_item_id;
 IF NOT FOUND OR v_item.project_code<>'SALY-001'
 THEN RAISE EXCEPTION 'SALY_L3B_ITEM_NOT_ADMITTED'; END IF;
 IF v_item.acceptance_json#>>'{visual_rules,scope}'
    IS DISTINCT FROM v_item.order_code
 OR v_item.acceptance_json#>>'{visual_rules,no_decorative_rays}'
    IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'SALY_L3B_OWNER_VISUAL_POLICY_MISSING'; END IF;

 -- L2A validates SEALED set, version snapshots and SHA, candidate selections,
 -- source identity and hash. Neither prompt nor QA can choose another version.
 v_context:=saly.creative_item_context_l2a(p_item_id);
 v_dispatch:=saly.creative_item_work_packet_l2c(p_item_id);

 SELECT v.id AS version_id,v.value_json->>'value' AS color_value,
        v.value_json->>'usage' AS usage,t.value_sha256,v.approval_status
 INTO v_cta
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
       AND e.code='color.action.primary.bg' AND t.role='OFFICIAL';
 IF NOT FOUND OR v_cta.approval_status<>'APPROVED'
    OR v_cta.usage<>'CTA_BACKGROUND_FOR_WHITE_TEXT'
    OR v_cta.color_value !~ '^#[0-9A-Fa-f]{6}$'
 THEN RAISE EXCEPTION 'SALY_L3B_OFFICIAL_CTA_UNAVAILABLE'; END IF;

 SELECT v.id AS version_id,v.value_json->>'value' AS color_value,
        v.value_json->>'usage' AS usage,t.value_sha256,v.approval_status
 INTO v_brand
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
       AND e.code='color.brand.primary' AND t.role='OFFICIAL';
 IF NOT FOUND OR v_brand.approval_status<>'APPROVED'
    OR v_brand.usage<>'BRAND_ONLY_NOT_WHITE_TEXT_CTA'
 THEN RAISE EXCEPTION 'SALY_L3B_BRAND_COLOR_AUTHORITY_INVALID'; END IF;

 -- Candidate white representation is NOT promoted to an official token:
 -- white typography is separately authorized by the official CTA usage.
 SELECT v.id AS version_id,v.value_json->>'value' AS color_value,
        t.value_sha256,v.approval_status
 INTO v_white
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
       AND e.code='candidate.saly_ds_v1.color.surface.white';
 IF NOT FOUND OR v_white.approval_status<>'CANDIDATE'
    OR upper(v_white.color_value)<>'#FFFFFF'
 THEN RAISE EXCEPTION 'SALY_L3B_WHITE_REFERENCE_UNAVAILABLE'; END IF;

 IF jsonb_array_length(v_context->'source_refs')<1
 THEN RAISE EXCEPTION 'SALY_L3B_SOURCE_REFERENCE_REQUIRED'; END IF;

 v_rules:=jsonb_build_array(
   jsonb_build_object('code','SALY_CTA_BACKGROUND','severity','BLOCK',
     'expected',v_cta.color_value,'source','saly.identity_versions',
     'token_code','color.action.primary.bg','version_id',v_cta.version_id,
     'source_sha256',v_cta.value_sha256,'method','IMAGE_PIXEL_OR_STYLE_VERIFICATION',
     'qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_CTA_TEXT','severity','BLOCK',
     'expected',v_white.color_value,
     'source','OFFICIAL_CTA_USAGE_AND_CANDIDATE_WHITE_REFERENCE',
     'white_reference_status','CANDIDATE_NOT_PROMOTED',
     'version_id',v_white.version_id,'source_sha256',v_white.value_sha256,
     'method','IMAGE_PIXEL_OR_STYLE_VERIFICATION','qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_NO_DECORATIVE_RAYS','severity','BLOCK',
     'expected','ABSENT','source','creative_order_items.acceptance_json.visual_rules',
     'method','INDEPENDENT_IMAGE_VISUAL_INSPECTION','qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_GEOMETRY_SOURCE_MATCH','severity','BLOCK',
     'expected','MATCH_LINKED_SOURCE_GEOMETRY',
     'source','saly.creative_item_sources',
     'reference_sha256',v_context->'source_refs',
     'method','IMAGE_DIMENSIONS_AND_VISUAL_REFERENCE_COMPARE',
     'qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_NO_UNGROUNDED_FINANCIAL_AMOUNTS','severity','BLOCK',
     'expected','ONLY_SOURCE_SUPPORTED_VALUES',
     'source','creative_order_items.acceptance_json.visual_rules',
     'method','IMAGE_COPY_AND_SOURCE_COMPARISON','qa_result','NOT_EVALUATED')
 );


 -- OWNER AUDIT 2026-11-23: report existing candidates and official tokens
 -- in QA without changing approval, execution, or image dispatch gates.
 -- All 23 SPACING / TYPOGRAPHY / LAYOUT / RULE checks are OBSERVE_ONLY.
 SELECT v_rules || COALESCE(jsonb_agg(
   jsonb_build_object(
     'code','SALY_TOKEN_'||upper(e.family)||'_'||v.id::text,
     'severity','OBSERVE',
     'expected',v.value_json->'value',
     'token_code',e.code,'family',e.family,'version_id',v.id,
     'source_sha256',t.value_sha256,
     'unit',CASE WHEN e.family='SPACING' THEN 'PX'
                 WHEN e.family='LAYOUT' AND jsonb_typeof(v.value_json->'value')='number' THEN 'PX'
                 WHEN e.family='TYPOGRAPHY' THEN 'TYPOGRAPHY_JSON'
                 ELSE 'JSON' END,
     'method','INDEPENDENT_IMAGE_STYLE_COMPARE',
     'qa_result','NOT_EVALUATED')
   ORDER BY e.family,e.code), '[]'::jsonb)
 INTO v_rules
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
   AND e.family IN ('SPACING','TYPOGRAPHY','LAYOUT','RULE')
   AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_context->'tokens') tok
               WHERE tok->>'code'=e.code);

 v_contract:=jsonb_build_object(
   'schema_version','SALY_VISUAL_CONTRACT_L3B_V1',
   'business_code','SALY','project_code',v_item.project_code,
   'order_id',v_item.order_id,'order_code',v_item.order_code,
   'item_id',v_item.id,'item_code',v_item.item_code,
   'item_status',v_item.item_status,
   'order_status',v_item.order_status,
   'context_set_id',v_item.context_set_id,
   'source_context_sha256',encode(extensions.digest(convert_to(v_context::text,'UTF8'),'sha256'),'hex'),
   'official_cta',jsonb_build_object(
      'background',v_cta.color_value,'foreground',v_white.color_value,
      'background_version_id',v_cta.version_id,
      'background_version_sha256',v_cta.value_sha256,
      'foreground_reference_version_id',v_white.version_id,
      'foreground_status','DERIVED_FROM_APPROVED_CTA_USAGE'),
   'brand_color',jsonb_build_object('value',v_brand.color_value,
      'version_id',v_brand.version_id,'source_sha256',v_brand.value_sha256,
      'not_valid_for_primary_cta',true),
   'tokens',v_context->'tokens',
   'source_refs',v_context->'source_refs',
   'screen_spec',v_item.context_json->'screen_spec',
   'acceptance_criteria',v_item.acceptance_json,
   'qa_checks',v_rules,
   'qa_verdict','NOT_EVALUATED',
   'visual_generation_state','NOT_EXECUTED',
   'ready_for_handoff',v_dispatch->>'readiness_code',
   'native_execution_authorized',false,
   'image_generation_allowed',false,
   'next_action','INVOKE_REAL_GOVERNED_RENDERER_WITH_THIS_EXACT_CONTRACT');
 -- Opt-in extension of the existing read-only contract. L2C retains dispatch ownership.
 v_bp := v_item.context_json#>'{screen_spec,visual_blueprint}';
 IF v_bp IS NOT NULL THEN
   IF v_bp->>'schema_version' IS DISTINCT FROM 'CREATIVE_VISUAL_BLUEPRINT_V1'
      OR v_bp->>'brand' IS DISTINCT FROM v_contract->>'business_code'
      OR jsonb_array_length(v_context->'source_refs') <> 1
      OR v_bp->>'reference_sha256' IS DISTINCT FROM v_context#>>'{source_refs,0,source_sha256}'
      OR v_bp#>>'{output,count}' IS DISTINCT FROM '1'
      OR v_bp->>'design_lock_sha256' IS DISTINCT FROM
         encode(extensions.digest(convert_to((v_bp->'design_lock')::text,'UTF8'),'sha256'),'hex')
      OR v_bp->>'mode' IS DISTINCT FROM 'PLAN_ONLY'
   THEN RAISE EXCEPTION 'CREATIVE_BLUEPRINT_MISMATCH'; END IF;
   -- Use the locked values in the prompt. Candidate aliases can only resolve
   -- inside the same frozen context and terminate at a selected token or CTA white.
   v_lock := v_bp#>'{design_lock,LOCK}';
   IF NOT (v_lock ?& ARRAY['copy_locked','visual_lock','layout_lock','hierarchy','cta',
      'reference_sha256','output','bindings','restrictions'])
      OR v_lock IS DISTINCT FROM (SELECT jsonb_object_agg(k,v_bp->k)
          FROM jsonb_object_keys(v_lock) AS property(k))
      OR v_bp#>'{design_lock,GUIDED}' IS DISTINCT FROM v_bp->'guided'
      OR v_bp#>'{design_lock,FREE}' IS DISTINCT FROM v_bp->'free'
   THEN RAISE EXCEPTION 'CREATIVE_LOCK_DRIFT'; END IF;
   FOR v_binding IN SELECT key,value FROM jsonb_each_text(v_lock->'bindings') ORDER BY key COLLATE "C" LOOP
     v_code := v_binding.value;
     v_seen := ARRAY[]::text[];
     LOOP
       IF v_code=ANY(v_seen) THEN RAISE EXCEPTION 'CREATIVE_TOKEN_ALIAS_CYCLE'; END IF;
       v_seen := array_append(v_seen,v_code);
       SELECT v.id AS version_id, v.value_json->'value' AS val, v.metadata->>'alias_target_code' AS target
         INTO STRICT v_token
         FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
         JOIN saly.identity_elements e ON e.id=v.element_id
         WHERE t.context_set_id=v_item.context_set_id AND e.code=v_code
           AND (v.id=v_white.version_id OR EXISTS
               (SELECT 1 FROM jsonb_array_elements(v_context->'tokens') tok WHERE tok->>'code'=e.code));
       EXIT WHEN v_token.target IS NULL;
       v_code := v_token.target;
     END LOOP;
     IF v_token.val IS NULL OR jsonb_typeof(v_token.val)='null' OR
        (jsonb_typeof(v_token.val)='string' AND left(v_token.val#>>'{}',1)='{')
     THEN RAISE EXCEPTION 'CREATIVE_UNRESOLVED_TOKEN'; END IF;
     v_resolved := v_resolved || jsonb_build_object(v_binding.key,v_token.val);
   END LOOP;
   IF v_resolved->>'CTA fondo' IS DISTINCT FROM v_cta.color_value
      OR v_resolved->>'CTA texto' IS DISTINCT FROM v_white.color_value
      OR v_resolved->>'Identidad' IS DISTINCT FROM v_brand.color_value
   THEN RAISE EXCEPTION 'CREATIVE_TOKEN_AUTHORITY_CONFLICT'; END IF;
   v_prompt := concat_ws(chr(10),
      format('%s · %s. Una pantalla en PNG de %s × %s.',v_bp->>'brand',v_item.item_code,
          v_lock#>>'{output,dimensions,0}',v_lock#>>'{output,dimensions,1}'),
      v_bp->>'intent', v_bp->>'art', 'Usar la referencia adjunta de esta pieza.',
      'De arriba abajo: '||array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_lock->'hierarchy')),' → '),
      v_lock->>'layout_lock',v_lock->>'visual_lock',v_lock#>>'{copy_locked,base}',
      (SELECT string_agg(format('%s: «%s».',entry->>'component',entry->>'value'),chr(10) ORDER BY ord)
         FROM jsonb_array_elements(v_lock#>'{copy_locked,overrides}') WITH ORDINALITY AS x(entry,ord)),
      format('Conservar CTA «%s».',v_lock->>'cta'),'Tokens aplicables: '||v_resolved::text,
      'Aplicar copy aprobado y CTA oficial. Para lo demás, conservar la referencia. Los candidatos orientan ajustes compatibles.',
      array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_lock->'restrictions')),chr(10)),
      array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_bp->'guided')),chr(10)),
      CASE WHEN jsonb_array_length(v_bp->'free')>0 THEN 'Libertad permitida: '||(v_bp->'free')::text END);
   v_contract := v_contract || jsonb_build_object('production_manifest',jsonb_build_object(
       'schema_version','CREATIVE_UNIT_HANDOFF_V1','order_id',v_item.order_id,'item_id',v_item.id,
       'context_set_id',v_item.context_set_id,'variant','original','mode','PLAN_ONLY',
       'source_refs',v_context->'source_refs','design_lock_sha256',v_bp->>'design_lock_sha256',
       'dispatch_readiness',v_dispatch->>'readiness_code','prompt_utf8',v_prompt,
       'prompt_sha256',encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex'),
       'transmitted',false,'renderer',NULL,'attempt',NULL,'artifact_sha256',NULL,'qa','NOT_TESTED'));
 END IF;
 v_hash:=encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex');
 RETURN jsonb_build_object(
   'contract',v_contract,
   'contract_sha256',v_hash,
   'generator_must_echo_contract_sha256',true,
   'qa_must_compare_same_contract_sha256',true);
END $function$
;
