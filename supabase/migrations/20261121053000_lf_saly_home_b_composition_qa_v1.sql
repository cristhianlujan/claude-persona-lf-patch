BEGIN;
-- Review-only contract for a template with compositor-owned fixed assets.
-- No renderer, run admission, production QA receipt or standard activation.
CREATE FUNCTION saly.creative_template_preflight_v1(p_item bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path TO pg_catalog,saly,visual,extensions
AS $fn$
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
  AND sha256=h#>>'{logo,sha256}' AND approval_status='APPROVED';
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
   jsonb_build_object('code','ASSET_INTEGRITY','severity','BLOCK','expected',refs,'method','COMPARE_RENDER_INPUT_BYTES_AND_SHA256'),
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
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_template_preflight_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

DO $integrate$
DECLARE
 item saly.creative_order_items%ROWTYPE; prev visual.standard_versions%ROWTYPE;
 refs jsonb; spec jsonb; v_id bigint; v_sha text; h jsonb; p jsonb; a_before jsonb;
BEGIN
 SELECT i.* INTO STRICT item FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=9 AND i.code='HOME_B' AND i.status='PENDIENTE' AND o.id=5
 AND o.scope_json->'render_authorized'='false'::jsonb
 AND i.context_json->'handoff_review'->'transmitted'='false'::jsonb FOR UPDATE OF i;
 SELECT * INTO STRICT prev FROM visual.standard_versions
 WHERE id=(item.context_json->>'template_version_id')::bigint AND version='0.3' AND state='CANDIDATE'
 AND manifest_sha256=item.context_json->>'template_sha256';
 IF jsonb_array_length(item.context_json#>'{handoff_review,trace}')<>12 THEN RAISE EXCEPTION 'COMPILER_03_REQUIRED'; END IF;
 SELECT context_json->'handoff_review' INTO STRICT a_before FROM saly.creative_order_items WHERE id=8;
 WITH expected(role,code,sha) AS (VALUES
 ('frame','SALY_IPHONE16PRO_FRAME_VECTOR','1e9fc1061686da752256181b6ad62f086ff20fb4f2fcc62841e07049e4277529'),
 ('Inicio','SALY_NAV_HOME_VECTOR','a25cbdfb38990373017c919cb97b7c44dc2f6e28b39e44329381bc6799a01f88'),
 ('Historial','SALY_NAV_HISTORY_VECTOR','b62158d340d6230ca5c9db956f83c647fb137600dff4d90a461e28c092a95f8e'),
 ('Explorar','SALY_NAV_EXPLORE_VECTOR','9b7de5d834477202f53a6da970e44af3e5887ef6d4c1c05547100c96550489c5'),
 ('Perfil','SALY_NAV_PROFILE_VECTOR','bc8ce2d35903b74e13cfbd2ecb83188c70245a67d0506fbdf5f644ae9fafaeae'))
 SELECT jsonb_object_agg(e.role,jsonb_build_object('asset_id',a.id,'asset_code',a.asset_code,
 'version',a.version_number,'kind',a.source_kind,'sha256',a.source_sha256,'provider',a.provider))
 INTO refs FROM expected e JOIN visual.source_assets a ON a.asset_code=e.code AND a.source_sha256=e.sha
 WHERE a.brand_code='SALY' AND a.version_number=1 AND a.approval_status='CANDIDATE'
 AND a.provider='SUPABASE_INLINE_SVG' AND a.source_sha256=encode(extensions.digest(convert_to(a.metadata->>'svg','UTF8'),'sha256'),'hex');
 IF refs IS NULL OR (SELECT count(*) FROM jsonb_object_keys(refs))<>5 THEN RAISE EXCEPTION 'COMPOSITION_ASSETS_MISSING'; END IF;
 spec:=jsonb_set(prev.manifest_json,'{composition}',(prev.manifest_json->'composition')||
 jsonb_build_object('asset_refs',refs,'pending_assets','[]'::jsonb,'render_ready',false,
 'frame_app_opening','[16,48,400,848]'::jsonb,'frame_outer','[432,928]'::jsonb,
 'navigation_layout',jsonb_build_object('columns',4,'icon_size_px',24,'icon_top_offset_px',16,
 'label_top_offset_px',44,'align','center','color_mode','RESOLVED_TOKEN_CURRENT_COLOR'),
 'asset_state','CANDIDATE_REVIEW_ONLY'));
 spec:=jsonb_set(spec,'{style_bindings,navegacion}',
 '{"inactiva":"candidate.saly_home_v3.semantic.color.navigation.inactive","fuente base":"candidate.saly_ds_v1.typography.font.family.base","tipografía etiqueta":"candidate.saly_ds_v1.typography.font.caption"}'::jsonb,true);
 INSERT INTO visual.standard_versions(standard_id,brand_code,kind,version,parent_version_id,manifest_json,state)
 VALUES(prev.standard_id,prev.brand_code,prev.kind,'0.4',prev.id,spec,'CANDIDATE')
 RETURNING id,manifest_sha256 INTO v_id,v_sha;
 UPDATE saly.creative_order_items SET context_json=context_json||jsonb_build_object(
 'template_version_id',v_id,'template_sha256',v_sha,
 'token_codes',(SELECT jsonb_agg(DISTINCT code ORDER BY code) FROM (
 SELECT jsonb_array_elements_text(item.context_json->'token_codes') code
 UNION ALL SELECT b.value FROM jsonb_each(spec->'style_bindings') c CROSS JOIN LATERAL jsonb_each_text(c.value) b) selected))
 WHERE id=item.id;
 h:=saly.creative_template_review_v1(item.id); p:=saly.creative_template_preflight_v1(item.id);
 IF h->'native_prompt' IS DISTINCT FROM item.context_json#>'{handoff_review,native_prompt}'
 OR h->'attachments' IS DISTINCT FROM '[]'::jsonb
 OR p#>>'{contract,qa_verdict}' IS DISTINCT FROM 'NOT_EVALUATED'
 OR jsonb_array_length(p#>'{contract,qa_checks}')<>5
 OR jsonb_array_length(p#>'{contract,acceptance_criteria,semantic_qa,checks}')<>5
 OR p#>'{contract,handoff}' IS DISTINCT FROM h
 THEN RAISE EXCEPTION 'COMPOSITION_QA_CONTRACT_MISMATCH'; END IF;
 UPDATE saly.creative_order_items SET context_json=context_json||jsonb_build_object('handoff_review',h,'preflight_review',p) WHERE id=item.id;
 IF (SELECT context_json->'handoff_review' FROM saly.creative_order_items WHERE id=8) IS DISTINCT FROM a_before
 OR EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id IN (8,9))
 THEN RAISE EXCEPTION 'REVIEW_SCOPE_DRIFT'; END IF;
END $integrate$;
COMMIT;
