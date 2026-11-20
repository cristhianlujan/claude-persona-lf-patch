-- SALY Fábrica Digital / L2B: plan-only, source-bound three-screen Home pilot.
-- Additive sandbox pilot data, no renderer, no image generation, no approval, no ZIP.
-- Route: ACT-0001 -> ACTUALIZACION_DB_LF reserved by LF Migration Merge Train.
BEGIN;

DO $pilot$
DECLARE
 v_project bigint; v_context_set bigint; v_order bigint;
 v_home bigint; v_advance bigint; v_rewards bigint;
 v_link_count integer; v_json jsonb; v_item record;
BEGIN
 SELECT id INTO STRICT v_project FROM saly.proyecto
  WHERE codigo='SALY-001' AND estado='ACTIVO';
 SELECT id INTO STRICT v_context_set FROM saly.creative_context_sets
  WHERE project_id=v_project AND code='SALY_HOME_FIRST'
   AND version_label='0.3' AND mode='EXPLORE' AND state='SEALED';

 IF (SELECT count(*) FROM saly.creative_context_tokens
     WHERE context_set_id=v_context_set)<>41
    OR (SELECT count(*) FROM saly.creative_context_tokens
        WHERE context_set_id=v_context_set AND role='OFFICIAL')<>2
 THEN RAISE EXCEPTION 'SALY_PILOT_L2A_CONTEXT_INVALID'; END IF;

 IF EXISTS(SELECT 1 FROM saly.creative_orders
   WHERE project_id=v_project AND
   (code='SALY_HOME_BATCH_001' OR request_key='SALY_HOME_BATCH_L2B_001'))
 THEN RAISE EXCEPTION 'SALY_PILOT_ALREADY_EXISTS'; END IF;

 IF (SELECT count(*) FROM visual.source_assets
    WHERE brand_code='SALY'
      AND asset_code IN ('SALY_HOME_IPHONE16PRO','SALY_SOLICITAR_ADELANTO','SALY_REWARDS_HOME_SORTEOS')
      AND approval_status='CANDIDATE' AND independent_sha_verified
      AND source_sha256 IS NOT NULL)<>3
 THEN RAISE EXCEPTION 'SALY_PILOT_SOURCES_NOT_VERIFIED'; END IF;

 INSERT INTO saly.creative_orders
  (project_id,code,request_key,title,request_kind,design_mode,requested_by,
   scope_json,status,context_set_id)
 VALUES
  (v_project,'SALY_HOME_BATCH_001','SALY_HOME_BATCH_L2B_001',
   'SALY Home EXPLORE: tres pantallas referenciadas',
   'APP_SCREEN_BATCH','EXPLORE','SALY_DIGITAL_FACTORY',
   jsonb_build_object('schema_version','SALY_HOME_BATCH_L2B_V1',
     'objective','Prepare an evidence-bound 3-screen exploratory batch; no image is generated',
     'business_code','SALY',
     'qa_state','NOT_STARTED','rendering_authority',false,
     'visual_approval','NONE','pilot_only',true,
     'context_code','SALY_HOME_FIRST','context_version','0.3'),
   'PLANIFICADO',v_context_set)
 RETURNING id INTO v_order;

 IF (SELECT jsonb_array_length(identity_snapshot->'selected_versions')
     FROM saly.creative_orders WHERE id=v_order)<>41
 THEN RAISE EXCEPTION 'SALY_PILOT_IDENTITY_SNAPSHOT_NOT_LOCKED'; END IF;

 INSERT INTO saly.creative_order_items
  (order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
 VALUES
  (v_order,'HOME',1,'SCREEN','Home principal SALY',true,
    jsonb_build_object('visual_standard','NOT_ACTIVATED',
      'expected','Home navigable with accurate brand CTA and source-bound layout',
      'qa_required',true,'no_unapproved_visual_promotion',true),
    jsonb_build_object('token_codes',jsonb_build_array(
      'candidate.saly_home_v3.semantic.color.navigation.active',
      'candidate.saly_home_v3.semantic.color.navigation.background'),
      'screen_spec',jsonb_build_object('screen','HOME','mode','EXPLORE',
        'preserve','Brand tokens and layout semantics, do not fabricate UI details')),
    'PENDIENTE'),
  (v_order,'ADELANTO',2,'SCREEN','Solicitud de adelanto',true,
    jsonb_build_object('visual_standard','NOT_ACTIVATED',
      'expected','Clear salary-advance request entry; no fictional balances or rates',
      'qa_required',true,'no_unapproved_visual_promotion',true),
    jsonb_build_object('token_codes',jsonb_build_array(
      'candidate.saly_ds_v1.typography.font.amount.hero',
      'candidate.saly_ds_v1.color.surface.mint'),
      'screen_spec',jsonb_build_object('screen','ADELANTO','mode','EXPLORE',
        'preserve','Action intent without inventing numerical financial data')),
    'PENDIENTE'),
  (v_order,'REWARDS',3,'SCREEN','SALY Rewards',true,
    jsonb_build_object('visual_standard','NOT_ACTIVATED',
      'approved_copy','Participa en sorteos y gana premios exclusivos.',
      'expected','No points-based rewards claim; retain approved copy',
      'qa_required',true,'no_unapproved_visual_promotion',true),
    jsonb_build_object('token_codes',jsonb_build_array(
      'candidate.saly_ds_v1.color.accent.reward.yellow',
      'candidate.saly_ds_v1.color.surface.reward'),
      'screen_spec',jsonb_build_object('screen','REWARDS','mode','EXPLORE',
        'preserve','Approved prize-draw message; no points mechanics')),
    'PENDIENTE');

 SELECT id INTO STRICT v_home FROM saly.creative_order_items
 WHERE order_id=v_order AND code='HOME';
 SELECT id INTO STRICT v_advance FROM saly.creative_order_items
 WHERE order_id=v_order AND code='ADELANTO';
 SELECT id INTO STRICT v_rewards FROM saly.creative_order_items
 WHERE order_id=v_order AND code='REWARDS';

 INSERT INTO saly.creative_item_dependencies(order_id,item_id,depends_on_item_id)
 VALUES (v_order,v_advance,v_home), (v_order,v_rewards,v_home);

 INSERT INTO saly.creative_item_sources
  (order_id,item_id,source_asset_id,purpose,source_sha256)
 SELECT v_order,i.id,a.id,'VISUAL_REFERENCE',a.source_sha256
 FROM (VALUES
   ('HOME','SALY_HOME_IPHONE16PRO'),
   ('ADELANTO','SALY_SOLICITAR_ADELANTO'),
   ('REWARDS','SALY_REWARDS_HOME_SORTEOS')) src(item_code,asset_code)
 JOIN saly.creative_order_items i
   ON i.order_id=v_order AND i.code=src.item_code
 JOIN visual.source_assets a
   ON a.brand_code='SALY' AND a.asset_code=src.asset_code
   AND a.approval_status='CANDIDATE'
   AND a.independent_sha_verified AND a.source_sha256 IS NOT NULL;
 GET DIAGNOSTICS v_link_count = ROW_COUNT;
 IF v_link_count<>3 THEN RAISE EXCEPTION 'SALY_PILOT_SOURCE_LINKS_INCOMPLETE'; END IF;

 FOR v_item IN SELECT id,code FROM saly.creative_order_items
    WHERE order_id=v_order ORDER BY ordinal LOOP
   v_json:=saly.creative_item_context_l2a(v_item.id);
   IF v_json->>'business_code'<>'SALY'
     OR v_json->>'image_generation_allowed'<>'false'
     OR v_json->>'context_set_id' IS DISTINCT FROM v_context_set::text
     OR jsonb_array_length(v_json->'source_refs')<>1
     OR jsonb_array_length(v_json->'tokens')<3
     OR (SELECT count(*) FROM jsonb_array_elements(v_json->'tokens') AS jt(token)
          WHERE jt.token->>'role'='OFFICIAL')<>2
   THEN RAISE EXCEPTION 'SALY_PILOT_CONTEXT_COMPILATION_FAILED_%',v_item.code; END IF;
 END LOOP;

 IF (SELECT count(*) FROM saly.creative_order_items WHERE order_id=v_order)<>3
    OR (SELECT count(*) FROM saly.creative_item_dependencies WHERE order_id=v_order)<>2
    OR (SELECT count(*) FROM saly.creative_item_sources WHERE order_id=v_order)<>3
    OR (SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order)<>0
    OR (SELECT count(*) FROM saly.creative_order_items
        WHERE order_id=v_order AND (status<>'PENDIENTE' OR qa_receipt<>'{}'::jsonb))<>0
 THEN RAISE EXCEPTION 'SALY_PILOT_UNEXPECTED_STATE'; END IF;
 IF (SELECT count(*) FROM visual.standard_activations)<>0
 THEN RAISE EXCEPTION 'SALY_PILOT_VISUAL_ACTIVATION_FORBIDDEN'; END IF;
END $pilot$;

COMMIT;
