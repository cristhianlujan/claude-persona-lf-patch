-- SALY L3B | Shared source-bound generation instructions + QA contract + order preview.
-- No renderer invocation, no fake output, no ZIP, no QA autoapproval.
-- Must be deployed only by LF Migration Merge Train.
BEGIN;

-- Owner-requested composition rule is stored on the existing PILOT order.
-- No global brand promotion: scope is these three pending screens only.
DO $policy$
DECLARE v_count integer;
BEGIN
 UPDATE saly.creative_order_items i
 SET acceptance_json=jsonb_set(
      i.acceptance_json,
      '{visual_rules}',
      jsonb_build_object(
        'no_decorative_rays',true,
        'no_unsupported_financial_amounts',true,
        'require_original_source_comparison',true,
        'qa_visual_review_required',true,
        'provenance','OWNER_DIRECT_INSTRUCTION_2026_11_20',
        'scope','SALY_HOME_BATCH_001'),
      true)
 FROM saly.creative_orders o
 WHERE o.id=i.order_id AND o.code='SALY_HOME_BATCH_001'
   AND o.status='PLANIFICADO' AND i.code IN ('HOME','ADELANTO','REWARDS')
   AND i.status='PENDIENTE'
   AND NOT i.acceptance_json ? 'visual_rules';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>3 THEN RAISE EXCEPTION 'SALY_L3B_PILOT_POLICY_PRECONDITION_FAILED'; END IF;
END $policy$;

CREATE FUNCTION saly.creative_item_visual_contract_l3b(p_item_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,saly,visual,extensions,pg_temp AS $fn$
DECLARE
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
 v_hash:=encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex');
 RETURN jsonb_build_object(
   'contract',v_contract,
   'contract_sha256',v_hash,
   'generator_must_echo_contract_sha256',true,
   'qa_must_compare_same_contract_sha256',true);
END $fn$;

CREATE FUNCTION saly.creative_order_live_summary_l3b(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,saly,visual,extensions,pg_temp AS $fn$
DECLARE v_order record; v_items jsonb; v_all integer; v_ready integer; v_blocked integer;
BEGIN
 SELECT o.id,o.code,o.status,p.codigo AS project_code INTO v_order
 FROM saly.creative_orders o JOIN saly.proyecto p ON p.id=o.project_id
 WHERE o.id=p_order_id;
 IF NOT FOUND OR v_order.project_code<>'SALY-001'
 THEN RAISE EXCEPTION 'SALY_L3B_ORDER_NOT_ADMITTED'; END IF;

 WITH entries AS (
 SELECT i.ordinal,i.id,i.code,i.status,
    pkt.result->>'readiness_code' AS readiness,
    COALESCE(jsonb_array_length(pkt.result->'blocking_dependencies'),0) AS deps,
    vc.info->>'contract_sha256' AS contract_sha256,
    (SELECT count(*) FROM saly.creative_runs r WHERE r.item_id=i.id) AS runs,
    (SELECT count(*) FROM saly.creative_item_sources s WHERE s.item_id=i.id) AS sources
 FROM saly.creative_order_items i
 CROSS JOIN LATERAL (SELECT saly.creative_item_work_packet_l2c(i.id) AS result) pkt
 CROSS JOIN LATERAL (SELECT saly.creative_item_visual_contract_l3b(i.id) AS info) vc
 WHERE i.order_id=v_order.id)
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'ordinal',ordinal,'item_id',id,'screen',code,'status',status,
    'readiness',readiness,'blocked_dependencies',deps,
    'sources',sources,'runs',runs,
    'visual_contract_sha256',contract_sha256,'qa_status','NOT_EVALUATED')
    ORDER BY ordinal),'[]'::jsonb),
 count(*)::integer,
 count(*) FILTER(WHERE readiness='READY_FOR_NATIVE_HANDOFF')::integer,
 count(*) FILTER(WHERE readiness<>'READY_FOR_NATIVE_HANDOFF')::integer
 INTO v_items,v_all,v_ready,v_blocked FROM entries;
 RETURN jsonb_build_object(
 'schema_version','SALY_ORDER_LIVE_SUMMARY_L3B_V1',
 'order_id',v_order.id,'order_code',v_order.code,'order_status',v_order.status,
 'total_screens',v_all,'ready_for_handoff',v_ready,'blocked',v_blocked,
 'items',v_items,
 'actual_generation_count',(SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order.id),
 'qa_pass_count',(SELECT count(*) FROM saly.creative_order_items WHERE order_id=v_order.id AND status='APROBADO'),
 'visual_generation_enabled',false,
 'batch_status','PREPARED_NOT_RENDERED');
END $fn$;

REVOKE ALL ON FUNCTION saly.creative_item_visual_contract_l3b(bigint),
 saly.creative_order_live_summary_l3b(bigint)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION saly.creative_item_visual_contract_l3b(bigint),
 saly.creative_order_live_summary_l3b(bigint)
 TO service_role;

DO $smoke$
DECLARE v_order bigint; v_home bigint; v_advance bigint;
 v_contract jsonb; v_summary jsonb; v_actual_cta text; v_expected_sha text;
BEGIN
 SELECT id INTO STRICT v_order FROM saly.creative_orders WHERE code='SALY_HOME_BATCH_001';
 SELECT id INTO STRICT v_home FROM saly.creative_order_items WHERE order_id=v_order AND code='HOME';
 SELECT id INTO STRICT v_advance FROM saly.creative_order_items WHERE order_id=v_order AND code='ADELANTO';
 SELECT v.value_json->>'value',t.value_sha256 INTO STRICT v_actual_cta,v_expected_sha
 FROM saly.creative_context_tokens t
 JOIN saly.creative_context_sets s ON s.id=t.context_set_id
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE s.code='SALY_HOME_FIRST' AND s.version_label='0.3'
 AND e.code='color.action.primary.bg' AND t.role='OFFICIAL';

 v_contract:=saly.creative_item_visual_contract_l3b(v_home);
 v_summary:=saly.creative_order_live_summary_l3b(v_order);
 IF v_contract#>>'{contract,official_cta,background}' IS DISTINCT FROM v_actual_cta
 OR v_contract#>>'{contract,official_cta,background_version_sha256}' IS DISTINCT FROM v_expected_sha
 OR v_contract#>>'{contract,qa_verdict}'<>'NOT_EVALUATED'
 OR jsonb_array_length(v_contract#>'{contract,qa_checks}')<>5
 OR v_contract#>>'{contract,acceptance_criteria,visual_rules,no_decorative_rays}'<>'true'
 OR (v_summary->>'total_screens')::integer<>3
 OR (v_summary->>'ready_for_handoff')::integer<>1
 OR (v_summary->>'blocked')::integer<>2
 OR (v_summary->>'actual_generation_count')::integer<>0
 OR (v_summary->>'qa_pass_count')::integer<>0
 THEN RAISE EXCEPTION 'SALY_L3B_GENERATOR_QA_SOURCE_PARITY_FAILED'; END IF;

 v_contract:=saly.creative_item_visual_contract_l3b(v_advance);
 IF v_contract#>>'{contract,ready_for_handoff}'<>'DEPENDENCIES_NOT_APPROVED'
 OR v_contract#>>'{contract,official_cta,background}' IS DISTINCT FROM v_actual_cta
 OR v_contract#>>'{contract,qa_verdict}'<>'NOT_EVALUATED'
 THEN RAISE EXCEPTION 'SALY_L3B_BLOCKED_SCREEN_QA_PARITY_FAILED'; END IF;

 IF NOT has_function_privilege('service_role',
 'saly.creative_item_visual_contract_l3b(bigint)','EXECUTE')
 OR NOT has_function_privilege('service_role',
 'saly.creative_order_live_summary_l3b(bigint)','EXECUTE')
 OR has_function_privilege('anon',
 'saly.creative_item_visual_contract_l3b(bigint)','EXECUTE')
 OR has_function_privilege('authenticated',
 'saly.creative_order_live_summary_l3b(bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'SALY_L3B_FUNCTION_PRIVILEGES_FAILED'; END IF;
 IF (SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order)<>0
 OR (SELECT count(*) FROM visual.generation_receipts)<>0
 OR (SELECT count(*) FROM visual.standard_activations)<>0
 THEN RAISE EXCEPTION 'SALY_L3B_UNAUTHORIZED_PRODUCTION_SIDE_EFFECT'; END IF;
END $smoke$;

COMMIT;
