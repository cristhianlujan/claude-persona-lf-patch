-- SALY Creative Factory: one NEW, narrowly scoped user refinement request.
-- SOURCE: user message of 2026-11-23; exact unedited excerpt retained as literal.
-- Only HOME summary "Mi disponible": show "Como se calcula" navigation, NOT amount.
-- No modifications to existing #7/#8, image, queue authorization, style or tokens.
-- PR -> PASE -> Merge Train; readback required. B1/B2/B3/B6/B11/B25/B30.
BEGIN;
DO $request$
DECLARE
  v_project bigint;
  v_home_id bigint;
  v_home_item_id bigint;
  v_context_id bigint;
  v_snapshot jsonb;
  v_new_id bigint;
  v_literal text:='un refinanmiento al perido donde se indica que el mi disonible es un ver para que vea como se calcual.';
  v_code text:='SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123';
  v_parent_order_snapshot text;
  v_parent_item_snapshot text;
  v_adelanto_snapshot text;
  v_inserted int;
BEGIN
  SELECT id INTO STRICT v_project
    FROM saly.proyecto WHERE codigo='SALY-001';
  SELECT o.id, o.context_set_id, o.identity_snapshot,
         md5(row_to_json(o)::text)
  INTO STRICT v_home_id,v_context_id,v_snapshot,v_parent_order_snapshot
  FROM saly.creative_orders o
  WHERE o.code='SALY_HOME_V015_SINGLE_20261123'
    AND o.project_id=v_project AND o.request_kind='APP_SCREEN_SINGLE'
    AND o.status='PLANIFICADO'
    AND o.scope_json->>'review_only'='true'
    AND o.scope_json->>'render_authorized'='false'
    AND o.scope_json->>'rendering_authority'='false'
    AND o.scope_json->>'intake_source_status'='MISSING_VERIFIED_USER_VISUAL_REQUEST'
  FOR UPDATE;
  SELECT i.id, md5(row_to_json(i)::text)
   INTO STRICT v_home_item_id,v_parent_item_snapshot
  FROM saly.creative_order_items i
  WHERE i.order_id=v_home_id AND i.code='HOME' AND i.status='PENDIENTE'
  FOR UPDATE;
  SELECT md5(row_to_json(o)::text) INTO STRICT v_adelanto_snapshot
  FROM saly.creative_orders o
  WHERE o.code='SALY_ADELANTO_V015_SINGLE_20261123'
    AND o.project_id=v_project AND o.status='PLANIFICADO'
  FOR UPDATE;

  IF (SELECT count(*) FROM saly.creative_orders
        WHERE code=v_code OR request_key=v_code)<>0
  THEN RAISE EXCEPTION 'SALY_MIDISPONIBLE_DRAFT_ALREADY_REGISTERED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM saly.creative_context_sets c
    WHERE c.id=v_context_id AND c.project_id=v_project
      AND c.state='SEALED' AND c.mode='EXPLORE')
  OR coalesce(v_snapshot->>'context_set_id','')<>v_context_id::text
  THEN RAISE EXCEPTION 'SALY_MIDISPONIBLE_PARENT_IDENTITY_NOT_SEALED'; END IF;
  IF EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.order_id=v_home_id)
  THEN RAISE EXCEPTION 'SALY_MIDISPONIBLE_PARENT_HAS_RUN_UNRECONCILED'; END IF;

  -- Retain the VERBATIM user's excerpt as source, not as a proposed
  -- render prompt. Interpretation is a distinct field and remains QA pending.
  INSERT INTO saly.creative_orders(
    project_id,code,request_key,title,request_kind,design_mode,
    requested_by,scope_json,identity_snapshot,context_set_id,status)
  VALUES (
    v_project,v_code,v_code,
    'Refinamiento HOME · Mi disponible → Cómo se calcula',
    'APP_SCREEN_SINGLE','EXPLORE','CHAT_USER',
    jsonb_build_object(
      'schema_version','SALY_HOME_MIDISPONIBLE_REFINEMENT_DRAFT_V1',
      'queue_mode','SERIAL_V1',
      'screen','HOME',
      'single_change_only',true,
      'refinement_of_order_id',v_home_id,
      'refinement_of_item_id',v_home_item_id,
      'target_component','HOME.SUMMARY.MI_DISPONIBLE',
      'literal_request',v_literal,
      'literal_origin','USER_MESSAGE_VERBATIM_EXCERPT',
      'literal_sha256',encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex'),
      'source_message_ref',null,
      'source_verification_status','USER_EXCERPT_AVAILABLE_MESSAGE_ID_NOT_VERIFIED',
      'interpretation','En HOME, el bloque Mi disponible debe mostrar un acceso navegable a Cómo se calcula (chevron), sin un importe monetario. Mantener todo lo demás igual. El valor S/ 800 del mockup no está autorizado.',
      'change_scope','ONLY_MI_DISPONIBLE_AS_VIEW_CALCULATION_LINK',
      'no_changes_to_other_components',true,
      'preview_artifact_sha256','8854a525b61d5642b3e864d5f35dbd9e3fdaf1bab83754ddeaa884eaf90f52d0',
      'preview_origin','CHAT_GENERATED_IMAGE_NO_VERIFIED_DB_RUN',
      'intake_source_status','VERBATIM_EXCERPT_PENDING_INDEPENDENT_QA',
      'intake_semantic_qa',jsonb_build_object('verdict','PENDING','required',true),
      'rendering_authority',false,
      'render_authorized',false,
      'review_only',true,
      'blocking_reason','NOT_COMPILED_NOT_QA_ATTESTED_NOT_RENDER_AUTHORIZED'
    ),v_snapshot,v_context_id,'BORRADOR')
  RETURNING id INTO v_new_id;
  INSERT INTO saly.creative_order_items(
     order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
  VALUES(
     v_new_id,'HOME_MIDISPONIBLE',1,'SCREEN',
     'HOME · convertir Mi disponible en enlace Cómo se calcula',true,
     jsonb_build_object(
       'qa_required',true,
       'semantic_qa',jsonb_build_object('status','PENDING'),
       'assertions',jsonb_build_array(
          'Mi disponible is a navigation entry to Cómo se calcula',
          'Do not render a standalone monetary value in Mi disponible',
          'All other HOME regions and their copy unchanged')
     ),
     jsonb_build_object(
       'screen_spec',jsonb_build_object('screen','HOME','device','IPHONE16PRO'),
       'parent_order_id',v_home_id,'parent_item_id',v_home_item_id,
       'target_component','HOME.SUMMARY.MI_DISPONIBLE'
     ),'PENDIENTE');
  -- New draft cannot be executed until its original HOME order is truly done.
  INSERT INTO saly.creative_order_sequence_v1(project_id,order_id,depends_on_order_id)
  VALUES (v_project,v_new_id,v_home_id);

  IF (SELECT count(*) FROM saly.creative_order_items i
      WHERE i.order_id=v_new_id AND i.code='HOME_MIDISPONIBLE'
        AND i.kind='SCREEN' AND i.ordinal=1 AND i.status='PENDIENTE')<>1
   OR (SELECT count(*) FROM saly.creative_order_sequence_v1 s
      WHERE s.order_id=v_new_id AND s.depends_on_order_id=v_home_id)<>1
   OR (SELECT scope_json->>'render_authorized' FROM saly.creative_orders
      WHERE id=v_new_id) IS DISTINCT FROM 'false'
   OR (SELECT status FROM saly.creative_orders WHERE id=v_new_id)<>'BORRADOR'
  THEN RAISE EXCEPTION 'SALY_MIDISPONIBLE_DRAFT_POSTSTATE_INVALID'; END IF;

  IF (SELECT md5(row_to_json(o)::text) FROM saly.creative_orders o
         WHERE o.id=v_home_id) IS DISTINCT FROM v_parent_order_snapshot
   OR (SELECT md5(row_to_json(i)::text) FROM saly.creative_order_items i
         WHERE i.id=v_home_item_id) IS DISTINCT FROM v_parent_item_snapshot
   OR (SELECT md5(row_to_json(o)::text) FROM saly.creative_orders o
         WHERE o.code='SALY_ADELANTO_V015_SINGLE_20261123')
      IS DISTINCT FROM v_adelanto_snapshot
  THEN RAISE EXCEPTION 'SALY_MIDISPONIBLE_HISTORICAL_ORDER_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM saly.creative_runs r WHERE r.order_id=v_new_id)
  THEN RAISE EXCEPTION 'SALY_MIDISPONIBLE_PHANTOM_RUN'; END IF;
END $request$;
COMMIT;
