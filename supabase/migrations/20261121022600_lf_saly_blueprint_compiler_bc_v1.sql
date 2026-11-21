-- Abort if L3B evolved since the implementation was reviewed.
DO $guard$
BEGIN
 IF md5(btrim(pg_get_functiondef('saly.creative_item_visual_contract_l3b(bigint)'::regprocedure),chr(10))) <> '7a58f13ff6331f9367d9093abf620e14'
 THEN RAISE EXCEPTION 'SALY_L3B_SOURCE_CHANGED'; END IF;
END
$guard$;

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
END $function$;

-- Lote B. Enrich the existing screen_spec consumed by L2C and L3B.
-- No new grants, functions, tables or state transitions. Submit via Merge Train.
DO $migration$
DECLARE
 affected integer;
 ready jsonb;
 blocked jsonb;
 v_smoke_item_id bigint;
 contract jsonb;
BEGIN
 PERFORM id FROM saly.creative_orders WHERE id=4 FOR UPDATE;
 PERFORM id FROM saly.creative_order_items WHERE order_id=4 AND id IN (5,6) ORDER BY id FOR UPDATE;
WITH proposed(item_id, item_code, file_ref, original_request_sha, blueprint) AS (
 VALUES
(5, 'HOME', '1YXWAS8McVi0Y91FEtMbCW6M57-6D9em9', '9b1f63d9375a5b9d2af817209f876cd31013c6f2b6ecc342f386cb30c8ad8371', $blueprint${
  "intent": "Corregir las dos pantallas anteriores, no rediseñar la aplicación.",
  "art": "Mockup móvil frontal de una sola pantalla. Mantener el marco, fondo, luz y encuadre del original.",
  "hierarchy": [
    "Logo, saludo y notificación",
    "Disponible para adelanto y CTA Solicitar adelanto",
    "Próximo descuento, adelantos retirados y Mi disponible",
    "Descubre más en Saly: Plus, Rewards y Beneficios",
    "Navegación inferior"
  ],
  "cta": "Solicitar adelanto",
  "bindings": {
    "CTA fondo": "color.action.primary.bg",
    "CTA texto": "candidate.saly_ds_v1.color.surface.white",
    "Identidad": "color.brand.primary",
    "Navegación activa": "candidate.saly_home_v3.semantic.color.navigation.active",
    "Fondo de navegación": "candidate.saly_home_v3.semantic.color.navigation.background"
  },
  "copy_locked": {
    "base": "Conservar los píxeles de todos los textos y cifras de la referencia, salvo las sustituciones explícitas.",
    "overrides": [
      {
        "component": "Descubre más en Saly / Saly Rewards / descripción",
        "value": "Participa en sorteos y gana premios exclusivos",
        "authority": "Pedido actual del dueño"
      }
    ]
  },
  "layout_lock": "Mantener orden, alineación, proporciones, marco y zonas seguras de la referencia.",
  "visual_lock": "Conservar logo y pictogramas originales por composición desde la fuente. Eliminar solo palitos decorativos; conservar iconos funcionales.",
  "guided": [
    "Ajustar saltos de línea al ancho original si cambia el copy."
  ],
  "free": [],
  "restrictions": [
    "Una pantalla por archivo.",
    "Usar solo los datos financieros que ya figuran en esta imagen, como datos ilustrativos del mockup.",
    "Sin adornos ni elementos nuevos."
  ],
  "schema_version": "CREATIVE_VISUAL_BLUEPRINT_V1",
  "brand": "SALY",
  "reference_sha256": "3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e",
  "output": {
    "format": "PNG",
    "dimensions": [
      1086,
      1448
    ],
    "count": 1
  },
  "mode": "PLAN_ONLY"
}$blueprint$::jsonb),
(6, 'ADELANTO', '1n9nNgKow7jcMJuX1tI6JXXAeye5rXJhJ', '9b1f63d9375a5b9d2af817209f876cd31013c6f2b6ecc342f386cb30c8ad8371', $blueprint${
  "intent": "Corregir las dos pantallas anteriores, no rediseñar la aplicación.",
  "art": "Mockup móvil frontal de una sola pantalla. Mantener el marco, fondo, luz y encuadre del original.",
  "hierarchy": [
    "Cabecera con volver, título y ayuda",
    "Disponible y progreso del periodo",
    "Tres montos inteligentes y selección recomendada",
    "Ingreso manual del monto",
    "Mensaje de orientación",
    "Resumen de la solicitud y desglose",
    "CTA Continuar",
    "Navegación inferior"
  ],
  "cta": "Continuar",
  "bindings": {
    "CTA fondo": "color.action.primary.bg",
    "CTA texto": "candidate.saly_ds_v1.color.surface.white",
    "Identidad": "color.brand.primary",
    "Tipografía del monto": "candidate.saly_ds_v1.typography.font.amount.hero",
    "Superficie menta": "candidate.saly_ds_v1.color.surface.mint"
  },
  "copy_locked": {
    "base": "Conservar los píxeles de todos los textos y cifras de la referencia, salvo las sustituciones explícitas.",
    "overrides": []
  },
  "layout_lock": "Mantener orden, alineación, proporciones, marco y zonas seguras de la referencia.",
  "visual_lock": "Conservar logo y pictogramas originales por composición desde la fuente. Eliminar solo palitos decorativos; conservar iconos funcionales.",
  "guided": [
    "Ajustar saltos de línea al ancho original si cambia el copy."
  ],
  "free": [],
  "restrictions": [
    "Una pantalla por archivo.",
    "Usar solo los datos financieros que ya figuran en esta imagen, como datos ilustrativos del mockup.",
    "Sin adornos ni elementos nuevos."
  ],
  "schema_version": "CREATIVE_VISUAL_BLUEPRINT_V1",
  "brand": "SALY",
  "reference_sha256": "65d537d740b9dd19fbf953cbc0574ad55206c00a67f0a10c2035d5e1d21842fc",
  "output": {
    "format": "PNG",
    "dimensions": [
      1024,
      1536
    ],
    "count": 1
  },
  "mode": "PLAN_ONLY"
}$blueprint$::jsonb)
), classified AS (
 SELECT p.*, jsonb_build_object(
    'LOCK',jsonb_build_object('copy_locked',blueprint->'copy_locked','visual_lock',blueprint->'visual_lock',
        'layout_lock',blueprint->'layout_lock','hierarchy',blueprint->'hierarchy','cta',blueprint->'cta',
        'reference_sha256',blueprint->'reference_sha256','output',blueprint->'output',
        'bindings',blueprint->'bindings','restrictions',blueprint->'restrictions'),
    'GUIDED',blueprint->'guided','FREE',blueprint->'free') AS design_lock
 FROM proposed p
), locked AS (
 SELECT item_id,item_code,file_ref,original_request_sha,
    blueprint || jsonb_build_object('design_lock',design_lock,'design_lock_sha256',
       encode(extensions.digest(convert_to(design_lock::text,'UTF8'),'sha256'),'hex')) AS blueprint
 FROM classified
), eligible AS (
 SELECT i.id, p.blueprint
 FROM locked p
 JOIN saly.creative_order_items i ON i.id=p.item_id AND i.code=p.item_code
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.creative_context_sets ctx ON ctx.id=o.context_set_id AND ctx.project_id=o.project_id
 JOIN saly.proyecto project ON project.id=o.project_id
 WHERE o.id=4 AND o.code='SALY_HOME_BATCH_001' AND o.status='PLANIFICADO'
   AND project.codigo='SALY-001' AND ctx.id=1 AND ctx.code='SALY_HOME_FIRST'
   AND ctx.version_label='0.3' AND ctx.state='SEALED' AND i.status='PENDIENTE'
   AND i.acceptance_json#>>'{semantic_qa,original_request_sha256}'=p.original_request_sha
   AND jsonb_typeof(i.context_json->'screen_spec')='object'
   AND i.context_json#>>'{screen_spec,screen}'=i.code
   AND (i.context_json#>'{screen_spec,visual_blueprint}' IS NULL OR
        i.context_json#>'{screen_spec,visual_blueprint}'=p.blueprint)
   AND NOT EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.item_id=i.id)
   AND (SELECT count(*) FROM saly.creative_item_sources s WHERE s.item_id=i.id AND s.order_id=o.id)=1
   AND EXISTS (SELECT 1 FROM saly.creative_item_sources s JOIN visual.source_assets a ON a.id=s.source_asset_id
       WHERE s.item_id=i.id AND s.order_id=o.id AND a.brand_code=p.blueprint->>'brand'
       AND a.file_ref=p.file_ref AND a.independent_sha_verified AND a.source_sha256=s.source_sha256
       AND a.source_sha256=p.blueprint->>'reference_sha256')
   AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(p.blueprint->'bindings') b
       WHERE NOT EXISTS (SELECT 1 FROM saly.creative_context_tokens t
           JOIN saly.identity_versions v ON v.id=t.identity_version_id
           JOIN saly.identity_elements e ON e.id=v.element_id
           WHERE t.context_set_id=ctx.id AND e.code=b.value
           AND t.value_sha256=encode(extensions.digest(v.value_json::text,'sha256'),'hex')))
)

 UPDATE saly.creative_order_items i
 SET context_json=jsonb_set(i.context_json,'{screen_spec,visual_blueprint}',e.blueprint)
 FROM eligible e WHERE i.id=e.id;
 GET DIAGNOSTICS affected=ROW_COUNT;
 IF affected<>2 THEN RAISE EXCEPTION 'SALY_BLUEPRINT_INPUT_DRIFT'; END IF;
 FOREACH v_smoke_item_id IN ARRAY ARRAY[5,6]::bigint[] LOOP
   contract:=saly.creative_item_visual_contract_l3b(v_smoke_item_id)->'contract';
   IF contract#>>'{screen_spec,visual_blueprint,schema_version}' IS DISTINCT FROM 'CREATIVE_VISUAL_BLUEPRINT_V1'
      OR contract#>>'{screen_spec,visual_blueprint,reference_sha256}' IS DISTINCT FROM contract#>>'{source_refs,0,source_sha256}'
      OR contract#>>'{screen_spec,visual_blueprint,design_lock_sha256}' IS DISTINCT FROM
         encode(extensions.digest(convert_to((contract#>'{screen_spec,visual_blueprint,design_lock}')::text,'UTF8'),'sha256'),'hex')
      OR contract#>>'{production_manifest,mode}' IS DISTINCT FROM 'PLAN_ONLY'
      OR contract#>'{production_manifest,transmitted}' IS DISTINCT FROM 'false'::jsonb
      OR nullif(contract#>>'{production_manifest,prompt_utf8}','') IS NULL
      OR contract#>>'{production_manifest,prompt_sha256}' IS DISTINCT FROM
         encode(extensions.digest(convert_to(contract#>>'{production_manifest,prompt_utf8}','UTF8'),'sha256'),'hex')
      OR (v_smoke_item_id=5 AND position('Participa en sorteos y gana premios exclusivos' IN contract#>>'{production_manifest,prompt_utf8}')=0)
      OR (v_smoke_item_id=6 AND position('Participa en sorteos' IN contract#>>'{production_manifest,prompt_utf8}')>0)
      OR contract->'image_generation_allowed' IS DISTINCT FROM 'false'::jsonb
   THEN RAISE EXCEPTION 'SALY_BLUEPRINT_CONTRACT_MISMATCH'; END IF;
 END LOOP;
 ready:=saly.creative_item_work_packet_l2c(5);
 blocked:=saly.creative_item_work_packet_l2c(6);
 IF ready->>'readiness_code' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF'
 OR ready#>'{input_snapshot,screen_spec,visual_blueprint}' IS DISTINCT FROM
    (SELECT context_json#>'{screen_spec,visual_blueprint}' FROM saly.creative_order_items WHERE id=5)
 OR blocked->>'readiness_code' IS DISTINCT FROM 'DEPENDENCIES_NOT_APPROVED'
 OR blocked->'input_snapshot' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'SALY_BLUEPRINT_DISPATCH_MISMATCH'; END IF;
END
$migration$;
