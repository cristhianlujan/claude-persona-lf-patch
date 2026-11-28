CREATE OR REPLACE FUNCTION saly.creative_execution_policy_v1(p_asof timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE k text; c record; result jsonb:='{}'; pins jsonb:='{}';
BEGIN
 IF p_asof IS NULL THEN RAISE EXCEPTION 'CREATIVE_CONFIG_ASOF_REQUIRED'; END IF;
 FOREACH k IN ARRAY ARRAY['QUEUE_MAX','MAX_ATTEMPTS','QUEUE_TIMEOUT_SECONDS','LEASE_SECONDS'] LOOP
   SELECT config_value,value_type,value_status,valid_from INTO c FROM saly.config_global
   WHERE scope='CREATIVE_FACTORY' AND config_key=k AND valid_from<=p_asof
   ORDER BY valid_from DESC LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CONFIG_MISSING:%',k; END IF;
   IF c.value_type<>'INTEGER' OR c.value_status<>'REAL' OR c.config_value !~ '^[1-9][0-9]*$'
   THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   IF c.config_value::numeric>2147483647 THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   result:=result||jsonb_build_object(k,c.config_value::integer);
   pins:=pins||jsonb_build_object(k,c.valid_from);
 END LOOP;
 RETURN result||jsonb_build_object('schema_version','CREATIVE_EXECUTION_POLICY_V1','config_scope','CREATIVE_FACTORY','versions',pins);
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_intake_semantic_gate_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.request_kind IS DISTINCT FROM 'APP_SCREEN_SINGLE' THEN RETURN NEW; END IF;
  IF NEW.status='BORRADOR' THEN RETURN NEW; END IF;
  IF nullif(btrim(NEW.scope_json->>'literal_request'),'') IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING'; END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_item_context_l2a(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions'
AS $function$
DECLARE v_item record; v_tokens jsonb; v_refs jsonb; v_expected_snapshot jsonb; v_needed int; v_found int; v_drift int;
BEGIN
 SELECT i.id,i.code,i.context_json,o.id AS order_id,o.context_set_id,o.design_mode,
   o.status AS order_status,o.identity_snapshot AS order_snapshot,
   ctx.state AS context_state,p.codigo AS project_code
 INTO v_item FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 LEFT JOIN saly.creative_context_sets ctx ON ctx.id=o.context_set_id
 WHERE i.id=p_item_id;
 IF NOT FOUND OR v_item.project_code<>'SALY-001' OR v_item.context_set_id IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_CONTEXT_UNAVAILABLE'; END IF;
 IF v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA')
   OR v_item.context_state IS DISTINCT FROM 'SEALED'
   OR v_item.design_mode<>'EXPLORE'
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_CONTEXT_NOT_ADMITTED'; END IF;
 SELECT jsonb_agg(jsonb_build_object('version_id',identity_version_id,
    'sha256',value_sha256,'role',role) ORDER BY identity_version_id)
 INTO v_expected_snapshot
 FROM saly.creative_context_tokens WHERE context_set_id=v_item.context_set_id;
 IF v_expected_snapshot IS NULL OR
    v_item.order_snapshot IS DISTINCT FROM jsonb_build_object(
      'context_set_id',v_item.context_set_id,'selected_versions',v_expected_snapshot)
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_CONTEXT_SNAPSHOT_MISMATCH'; END IF;
 IF v_item.context_json ? 'token_codes'
    AND jsonb_typeof(v_item.context_json->'token_codes')<>'array'
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_TOKEN_SELECTION_INVALID'; END IF;
 -- Candidate tokens are opt-in per screen; official tokens always included.
 WITH requested AS (
  SELECT DISTINCT jsonb_array_elements_text(
    COALESCE(v_item.context_json->'token_codes','[]'::jsonb)) AS code
 )
 SELECT count(*)::int INTO v_needed FROM requested;
 WITH requested AS (
  SELECT DISTINCT jsonb_array_elements_text(
    COALESCE(v_item.context_json->'token_codes','[]'::jsonb)) AS code
 ), available AS (
  SELECT e.code,t.role FROM saly.creative_context_tokens t
  JOIN saly.identity_versions v ON v.id=t.identity_version_id
  JOIN saly.identity_elements e ON e.id=v.element_id
  WHERE t.context_set_id=v_item.context_set_id
 )
 SELECT count(*)::int INTO v_found
 FROM requested r JOIN available a ON a.code=r.code;
 IF v_needed<>v_found THEN RAISE EXCEPTION 'CREATIVE_ITEM_TOKEN_NOT_IN_LOCKED_CONTEXT'; END IF;
 SELECT count(*)::int INTO v_drift FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 WHERE t.context_set_id=v_item.context_set_id
 AND t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex');
 IF v_drift<>0 THEN RAISE EXCEPTION 'CREATIVE_ITEM_TOKEN_VERSION_DRIFT'; END IF;
 WITH requested AS (
  SELECT DISTINCT jsonb_array_elements_text(
    COALESCE(v_item.context_json->'token_codes','[]'::jsonb)) AS code
 )
 SELECT COALESCE(jsonb_agg(jsonb_build_object('code',e.code,'role',t.role,
   'version_id',v.id,'value_json',v.value_json,'value_sha256',t.value_sha256)
   ORDER BY e.code),'[]'::jsonb)
 INTO v_tokens
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id AND
   (t.role='OFFICIAL' OR e.code IN (SELECT code FROM requested)
   OR e.code IN (
       SELECT DISTINCT alias_v.metadata->>'alias_target_code'
       FROM saly.creative_context_tokens alias_link
       JOIN saly.identity_versions alias_v ON alias_v.id=alias_link.identity_version_id
       JOIN saly.identity_elements alias_e ON alias_e.id=alias_v.element_id
       WHERE alias_link.context_set_id=v_item.context_set_id
        AND alias_e.code IN (SELECT code FROM requested)
        AND alias_v.metadata->>'kind'='ALIAS')
   );
 IF EXISTS (SELECT 1 FROM saly.creative_item_sources s
   JOIN visual.source_assets a ON a.id=s.source_asset_id
   WHERE s.item_id=v_item.id AND s.order_id=v_item.order_id
     AND (s.source_sha256 IS DISTINCT FROM a.source_sha256
       OR NOT a.independent_sha_verified OR a.brand_code<>'SALY'
       OR a.approval_status NOT IN ('CANDIDATE','APPROVED')))
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_SOURCE_REFERENCE_DRIFT'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_id',a.id,
  'asset_code',a.asset_code,'source_kind',a.source_kind,
  'provider',a.provider,'file_ref',a.file_ref,
  'source_sha256',s.source_sha256,'approval_status',a.approval_status,
  'purpose',s.purpose) ORDER BY a.asset_code),'[]'::jsonb)
 INTO v_refs
 FROM saly.creative_item_sources s JOIN visual.source_assets a ON a.id=s.source_asset_id
 WHERE s.item_id=v_item.id AND s.order_id=v_item.order_id;
 RETURN jsonb_build_object('schema_version','SALY_CREATIVE_CONTEXT_L2A',
  'business_code','SALY','project_code',v_item.project_code,
  'order_id',v_item.order_id,'item_id',v_item.id,'item_code',v_item.code,
  'design_mode',v_item.design_mode,'context_set_id',v_item.context_set_id,
  'tokens',v_tokens,'source_refs',v_refs,
  'image_generation_allowed',false,'visual_standard_status','NOT_ACTIVATED_BY_THIS_CONTEXT');
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_item_context_medium_v3(p_item_id bigint, p_medium_override text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
 i record; o record; media text;
 selections jsonb; omissions jsonb; v_palette jsonb;
BEGIN
 SELECT id,order_id,context_json INTO i
 FROM saly.creative_order_items WHERE id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_MEDIUM_ITEM_NOT_FOUND'; END IF;
 SELECT id,scope_json,context_set_id INTO o FROM saly.creative_orders WHERE id=i.order_id;
 media:=COALESCE(NULLIF(p_medium_override,''),
    nullif(i.context_json->>'output_medium',''),
    nullif(o.scope_json->>'output_medium',''),
    CASE WHEN nullif(i.context_json#>>'{screen_spec,device}','') IS NOT NULL
         THEN 'PROTOTIPO_APP' ELSE NULL END);
 IF media IS NOT NULL AND media NOT IN ('PROTOTIPO_APP','IMPRESION','PAPEL','REDES_SOCIALES')
 THEN RAISE EXCEPTION 'SALY_MEDIUM_UNKNOWN'; END IF;
 IF o.context_set_id IS NULL THEN RAISE EXCEPTION 'SALY_MEDIUM_CONTEXT_MISSING'; END IF;
 WITH token_rows AS (
  SELECT e.code,v.id AS version_id,v.approval_status,t.role,v.value_json,
   v.metadata->'applies_to' applies_to,
   v.metadata->'applies_to_proposed' applies_to_proposed,
   v.metadata->>'token_role' token_role,
   v.metadata->>'duplicate_of_code' duplicate_of_code,
   v.metadata->>'alias_target_code' alias_target_code,
   v.metadata->>'kind' token_kind,
   COALESCE(v.metadata->>'effective_use_state','')='RETIRADO' AS retired_from_selection,
   v.metadata->>'replaced_by_code' replaced_by_code
  FROM saly.creative_context_tokens t
  JOIN saly.identity_versions v ON v.id=t.identity_version_id
  JOIN saly.identity_elements e ON e.id=v.element_id
  WHERE t.context_set_id=o.context_set_id
    AND v.approval_status IN ('APPROVED','CANDIDATE')
 ), decision AS (
  SELECT *,
    CASE
      WHEN retired_from_selection THEN 'TOKEN_RETIRADO'
      WHEN jsonb_typeof(applies_to) IS DISTINCT FROM 'array'
       OR jsonb_array_length(applies_to)=0 THEN 'SIN_CLASIFICAR'
      WHEN media IS NULL THEN 'MEDIO_SIN_DEFINIR'
      WHEN NOT (applies_to ? media) THEN 'MEDIO_NO_APLICA'
      ELSE NULL END AS reason
  FROM token_rows
 )
 SELECT
  COALESCE(jsonb_agg(jsonb_build_object(
   'code',code,'version_id',version_id,'approval_status',approval_status,
   'role',role,'value_json',value_json,
   'token_role',token_role,'applies_to_proposed',applies_to_proposed,
   'effective_for_palette',token_role IS DISTINCT FROM 'DUPLICADO_DE_CTA' AND COALESCE(token_kind,'')<>'ALIAS',
   'alias_target_code',alias_target_code,'duplicate_of_code',duplicate_of_code) ORDER BY code)
   FILTER(WHERE reason IS NULL),'[]'::jsonb),
  COALESCE(jsonb_agg(jsonb_build_object(
   'code',code,'version_id',version_id,'reason',reason,
   'replaced_by_code',replaced_by_code) ORDER BY code)
   FILTER(WHERE reason IS NOT NULL),'[]'::jsonb)
 INTO selections,omissions FROM decision;
 SELECT COALESCE(jsonb_object_agg(
   CASE WHEN e->>'code'='color.action.primary.bg' THEN 'CTA' ELSE 'MARCA' END,
   jsonb_build_object('code',e->>'code','hex',e#>>'{value_json,value}',
      'version_id',(e->>'version_id')::bigint)
 ),'{}'::jsonb) INTO v_palette
 FROM jsonb_array_elements(selections) e
 WHERE e->>'code' IN ('color.action.primary.bg','color.brand.primary')
 AND e->>'approval_status'='APPROVED';
 RETURN jsonb_build_object(
 'schema_version','SALY_MEDIUM_TOKEN_SELECTION_V3',
 'item_id',p_item_id,'order_id',i.order_id,'output_medium',media,
 'selected',selections,'omitted',omissions,
 'selected_count',jsonb_array_length(selections),
 'omitted_count',jsonb_array_length(omissions),
 'candidates_promoted',false,
 'effective_color_roles',v_palette,
 'effective_palette_exclusions',
   COALESCE((SELECT jsonb_agg(jsonb_build_object(
       'code',e->>'code','version_id',(e->>'version_id')::bigint,
       'reason',e->>'reason','replacement_code',e->>'replaced_by_code')
       ORDER BY (e->>'version_id')::bigint)
      FROM jsonb_array_elements(omissions) e
      WHERE e->>'reason'='TOKEN_RETIRADO'),'[]'::jsonb)
 );
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_item_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_order_status text; v_run record; v_run_id text;
BEGIN
 SELECT status INTO v_order_status FROM saly.creative_orders WHERE id=NEW.order_id FOR UPDATE;
 IF v_order_status IN ('COMPLETADO','CANCELADO')
 THEN RAISE EXCEPTION 'CREATIVE_CLOSED_ORDER_IMMUTABLE_ITEMS'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='APROBADO'
 THEN RAISE EXCEPTION 'CREATIVE_APPROVED_ITEM_IMMUTABLE'; END IF;
 -- Original input and interpretation cannot be silently replaced after capture.
 IF TG_OP='UPDATE' AND OLD.acceptance_json ? 'semantic_qa'
    AND NEW.acceptance_json->'semantic_qa' IS DISTINCT FROM OLD.acceptance_json->'semantic_qa'
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_CONTRACT_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='TERMINADO' AND NEW.status='APROBADO' THEN
   IF NEW.approved_at IS NULL OR NEW.approved_by IS DISTINCT FROM auth.uid()::text
      OR auth.uid() IS NULL
      OR NOT EXISTS (SELECT 1 FROM saly.creative_owner_decisions_v1 d
          WHERE d.item_id=NEW.id AND d.owner_uid=auth.uid() AND d.decision='APROBADO')
      OR NOT EXISTS (SELECT 1 FROM saly.creative_owner_accounts_v1 a
          JOIN saly.creative_orders o ON o.requested_by=a.requested_by
          WHERE o.id=NEW.order_id AND a.owner_uid=auth.uid())
   THEN RAISE EXCEPTION 'SALY_OWNER_APPROVAL_NOT_AUTHORIZED'; END IF;
   RETURN NEW;
 END IF;
 IF NEW.status IN ('TERMINADO','APROBADO')
 AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF TG_OP='INSERT' OR (OLD.status<>'EN_QA' AND NOT (OLD.status='LISTO' AND NEW.status='TERMINADO'))
   THEN RAISE EXCEPTION 'CREATIVE_ITEM_NOT_IN_QA'; END IF;
   IF EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id AND prereq.status NOT IN ('TERMINADO','APROBADO')
   ) THEN RAISE EXCEPTION 'CREATIVE_DEPENDENCY_NOT_APPROVED'; END IF;
   v_run_id:=NEW.qa_receipt->>'run_id';
   IF v_run_id IS NULL OR v_run_id !~ '^[0-9]+$'
      OR (NEW.qa_receipt->>'verdict') IS DISTINCT FROM 'PASS'
      OR jsonb_typeof(NEW.qa_receipt->'reviewer_ref') IS DISTINCT FROM 'string'
      OR nullif(btrim(NEW.qa_receipt->>'reviewer_ref'),'') IS NULL
   THEN RAISE EXCEPTION 'CREATIVE_QA_RECEIPT_MISSING'; END IF;
   SELECT r.id,r.worker_ref,r.input_snapshot,r.output_evidence INTO v_run
   FROM saly.creative_runs r
   WHERE r.id=v_run_id::bigint AND r.item_id=NEW.id AND r.order_id=NEW.order_id
     AND r.state='EXITOSO' AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
       WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number);
   IF NEW.status='TERMINADO' AND NOT EXISTS (
     SELECT 1 FROM saly.creative_run_detection_v1 d
     WHERE d.run_id=v_run_id::bigint AND d.item_id=NEW.id AND d.order_id=NEW.order_id
       AND d.artifact_sha256=v_run.output_evidence->>'sha256'
   ) THEN RAISE EXCEPTION 'SALY_ITEM_TERMINADO_REQUIRES_TIMER_DETECTION'; END IF;
   IF NOT FOUND OR (lower(btrim(NEW.qa_receipt->>'reviewer_ref'))=lower(btrim(v_run.worker_ref)) AND NEW.qa_receipt->>'review_mode' IS DISTINCT FROM 'GPT_SELF_QA')
      OR (NEW.status='TERMINADO' AND (NEW.approved_by IS NOT NULL OR NEW.approved_at IS NOT NULL))
      OR (NEW.status='APROBADO' AND NEW.approved_by IS DISTINCT FROM NEW.qa_receipt->>'reviewer_ref')
   THEN RAISE EXCEPTION 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING'; END IF;
   IF NEW.qa_receipt->>'review_mode'='GPT_SELF_QA' THEN
     IF NEW.status<>'TERMINADO'
       OR lower(btrim(NEW.qa_receipt->>'reviewer_ref')) IS DISTINCT FROM lower(btrim(v_run.worker_ref))
       OR NEW.qa_receipt->'semantic_independence_proven' IS DISTINCT FROM 'false'::jsonb
       OR NEW.qa_receipt->>'artifact_sha256' IS DISTINCT FROM v_run.output_evidence->>'sha256'
       OR jsonb_typeof(NEW.acceptance_json->'qa_checklist') IS DISTINCT FROM 'object'
       OR NEW.acceptance_json->'qa_checklist'='{}'::jsonb
       OR jsonb_typeof(NEW.qa_receipt->'checklist_results') IS DISTINCT FROM 'object'
       OR EXISTS (SELECT 1 FROM jsonb_object_keys(NEW.acceptance_json->'qa_checklist') AS k(code)
          WHERE NEW.qa_receipt#>>ARRAY['checklist_results',k.code,'verdict'] IS DISTINCT FROM 'PASS'
          OR nullif(btrim(NEW.qa_receipt#>>ARRAY['checklist_results',k.code,'evidence']),'') IS NULL)
       OR jsonb_typeof(NEW.qa_receipt->'preflight') IS DISTINCT FROM 'object'
       OR NEW.qa_receipt#>>'{preflight,verdict}' IS DISTINCT FROM 'PASS'
       OR nullif(btrim(NEW.qa_receipt#>>'{preflight,evidence}'),'') IS NULL
     THEN RAISE EXCEPTION 'CREATIVE_SELF_QA_CHECKLIST_INCOMPLETE'; END IF;
   END IF;
   IF NEW.qa_receipt->>'review_mode'='GPT_SELF_QA' THEN
     IF NEW.acceptance_json ? 'design_qa_v1' THEN
       IF jsonb_typeof(NEW.qa_receipt->'design_qa_v1') IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM jsonb_object_keys(NEW.acceptance_json->'design_qa_v1') k(code)
            WHERE coalesce(NEW.qa_receipt#>>ARRAY['design_qa_v1',k.code,'score'],'') NOT IN ('0','1')
             OR nullif(btrim(NEW.qa_receipt#>>ARRAY['design_qa_v1',k.code,'evidence']),'') IS NULL)
          OR (SELECT count(*) FROM jsonb_object_keys(NEW.acceptance_json->'design_qa_v1') k(code)
              WHERE NEW.qa_receipt#>>ARRAY['design_qa_v1',k.code,'score']='1')<5
       THEN RAISE EXCEPTION 'CREATIVE_DESIGN_QA_INCOMPLETE'; END IF;
     END IF;
   END IF;
   IF NEW.acceptance_json ? 'semantic_qa' THEN
     IF v_run.input_snapshot#>'{visual_contract,qa_checks}' IS DISTINCT FROM
        saly.creative_item_visual_contract_l3b(NEW.id)#>'{contract,qa_checks}'
     THEN RAISE EXCEPTION 'CREATIVE_TECHNICAL_CHECK_EXPECTATIONS_MISMATCH'; END IF;
     PERFORM saly.creative_assert_dual_qa_l3c(
        NEW.acceptance_json,NEW.qa_receipt,v_run.input_snapshot,v_run.output_evidence);
   END IF;
 END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_item_source_guard_l2a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'visual'
AS $function$
DECLARE v_row record; v_source record;
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'CREATIVE_SOURCE_LINK_IMMUTABLE'; END IF;
 SELECT o.design_mode,i.status,o.project_id INTO v_row
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i;
 IF NOT FOUND OR v_row.status NOT IN ('PENDIENTE','LISTO')
 THEN RAISE EXCEPTION 'CREATIVE_SOURCE_ITEM_NOT_ELIGIBLE'; END IF;
 SELECT brand_code,approval_status,independent_sha_verified,source_sha256 INTO v_source
 FROM visual.source_assets WHERE id=NEW.source_asset_id;
 IF NOT FOUND OR v_source.brand_code<>'SALY'
 OR NOT v_source.independent_sha_verified OR v_source.source_sha256 IS NULL
 OR v_source.approval_status NOT IN ('CANDIDATE','APPROVED')
 OR v_row.design_mode<>'EXPLORE'
 OR v_row.project_id<>(SELECT id FROM saly.proyecto WHERE codigo='SALY-001')
 THEN RAISE EXCEPTION 'CREATIVE_SOURCE_NOT_VERIFIED_FOR_SALY_EXPLORE'; END IF;
 NEW.source_sha256:=v_source.source_sha256;
 RETURN NEW;
END $function$
;

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
 IF NOT FOUND OR v_white.approval_status NOT IN ('CANDIDATE','APPROVED')
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
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_item_work_packet_l2c(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_item record;
 v_blockers jsonb:='[]'::jsonb;
 v_latest_state text;
 v_attempt integer:=0;
 v_readiness text;
 v_context jsonb;
 v_snapshot jsonb;
 v_review jsonb; v_assets jsonb; v_review_status text;
BEGIN
 SELECT i.id AS item_id,i.order_id,i.code AS item_code,i.ordinal,
   i.status AS item_status,i.kind,i.required,i.context_json,i.acceptance_json,
   o.code AS order_code,o.status AS order_status,o.context_set_id,o.design_mode,o.scope_json,
   p.codigo AS project_code
 INTO v_item
 FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_L2C_ITEM_NOT_FOUND'; END IF;
 IF v_item.project_code<>'SALY-001' THEN
   RAISE EXCEPTION 'SALY_L2C_PROJECT_NOT_ALLOWED'; END IF;

 SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'item_id',prereq.id,'code',prereq.code,'status',prereq.status)
    ORDER BY prereq.ordinal),'[]'::jsonb)
 INTO v_blockers
 FROM saly.creative_item_dependencies d
 JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
 WHERE d.order_id=v_item.order_id AND d.item_id=v_item.item_id
   AND prereq.status<>'APROBADO';

 SELECT COALESCE(max(attempt_number),0) INTO v_attempt
 FROM saly.creative_runs WHERE order_id=v_item.order_id AND item_id=v_item.item_id;
 SELECT state INTO v_latest_state
 FROM saly.creative_runs
 WHERE order_id=v_item.order_id AND item_id=v_item.item_id
 ORDER BY attempt_number DESC LIMIT 1;

 v_readiness:=CASE
   WHEN v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA')
     THEN 'ORDER_NOT_ELIGIBLE'
   WHEN v_item.item_status NOT IN ('PENDIENTE','LISTO')
     THEN 'ITEM_NOT_ELIGIBLE'
   WHEN jsonb_array_length(v_blockers)>0
     THEN 'DEPENDENCIES_NOT_APPROVED'
   WHEN v_latest_state IN ('EN_COLA','EJECUTANDO')
     THEN 'RUN_ALREADY_ACTIVE'
   WHEN v_latest_state='EXITOSO'
     THEN 'AWAITING_INDEPENDENT_QA'
   ELSE 'READY_FOR_NATIVE_HANDOFF'
 END;

 IF v_readiness<>'READY_FOR_NATIVE_HANDOFF' THEN
   RETURN jsonb_build_object(
     'schema_version','SALY_WORK_PACKET_L2C_V1',
     'business_code','SALY',
     'order_id',v_item.order_id,'order_code',v_item.order_code,
     'item_id',v_item.item_id,'item_code',v_item.item_code,
     'readiness_code',v_readiness,'blocking_dependencies',v_blockers,
     'latest_run_state',v_latest_state,'input_snapshot',NULL,
     'native_execution_authorized',false,'image_generation_allowed',false);
 END IF;

 -- Explicit review-only lane; never advertise native dispatch readiness.
 IF v_item.scope_json->'review_only'='true'::jsonb OR v_item.context_json#>>'{screen_spec,mode}'='TEMPLATE_REVIEW' THEN
   IF v_item.scope_json->'review_only' IS DISTINCT FROM 'true'::jsonb
     OR v_item.scope_json->'render_authorized' IS DISTINCT FROM 'false'::jsonb
     OR v_item.context_json#>>'{screen_spec,mode}' IS DISTINCT FROM 'TEMPLATE_REVIEW'
   THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_AUTHORITY_MISMATCH'; END IF;
   v_review_status:='REVIEW_TEMPLATE_INCOMPLETE';
   IF v_item.context_json ? 'preflight_review' THEN
     v_review:=saly.creative_template_preflight_v1(p_item_id);
     IF v_review IS DISTINCT FROM v_item.context_json->'preflight_review'
       OR v_review#>'{contract,handoff}' IS DISTINCT FROM v_item.context_json->'handoff_review'
       OR v_review#>>'{contract,qa_verdict}' IS DISTINCT FROM 'NOT_EVALUATED'
       OR v_review#>'{contract,image_generation_allowed}' IS DISTINCT FROM 'false'::jsonb
       OR v_review#>'{contract,native_execution_authorized}' IS DISTINCT FROM 'false'::jsonb
     THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_CONTRACT_DRIFT'; END IF;
     SELECT jsonb_object_agg(r.key,jsonb_build_object('ref',r.value,'svg_utf8',a.metadata->>'svg')) INTO v_assets
     FROM jsonb_each(v_review#>'{contract,handoff,composition,asset_refs}') r
     JOIN visual.source_assets a ON a.id=(r.value->>'asset_id')::bigint
     AND a.source_sha256=r.value->>'sha256'
     AND a.source_sha256=encode(extensions.digest(convert_to(a.metadata->>'svg','UTF8'),'sha256'),'hex');
     IF v_assets IS NULL OR (SELECT count(*) FROM jsonb_object_keys(v_assets))<>5
     THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_ASSET_BYTES_MISMATCH'; END IF;
     v_review_status:='READY_FOR_REVIEW_ONLY';
   END IF;
   RETURN jsonb_build_object('schema_version','SALY_WORK_PACKET_L2C_V1','business_code','SALY',
     'order_id',v_item.order_id,'order_code',v_item.order_code,'item_id',v_item.item_id,'item_code',v_item.item_code,
     'readiness_code',v_review_status,'blocking_dependencies','[]'::jsonb,'latest_run_state',v_latest_state,
     'input_snapshot',NULL,'review_contract',v_review,'composition_svg_assets',v_assets,
     'native_transport',CASE WHEN v_review_status='READY_FOR_REVIEW_ONLY' THEN
       jsonb_build_object('schema_version','SALY_NATIVE_TRANSPORT_V2','item_id',p_item_id,
         'contract_sha256',v_review->>'contract_sha256',
         'prompt_sha256',v_review#>>'{contract,handoff,prompt_sha256}',
         'payload',jsonb_build_object('prompt',v_review#>>'{contract,handoff,native_prompt}',
          'attachments',v_review#>'{contract,handoff,attachments}'))
       ELSE NULL END,
     'native_execution_authorized',false,'image_generation_allowed',false,
     'next_action',CASE WHEN v_review IS NULL THEN 'COMPLETE_TEMPLATE_REVIEW' ELSE 'REVIEW_EXACT_HANDOFF_NO_RENDER' END);
 END IF;

 -- The L2A compiler rechecks SEALED context, frozen identity/version hashes,
 -- candidate opt-in and source status/SHA on every call. No copy of tokens in code.
 v_context:=saly.creative_item_context_l2a(v_item.item_id);
 IF v_context->>'business_code'<>'SALY'
    OR v_context->>'image_generation_allowed'<>'false'
    OR v_context->>'context_set_id' IS DISTINCT FROM v_item.context_set_id::text
    OR jsonb_typeof(v_context->'tokens')<>'array'
    OR jsonb_array_length(v_context->'tokens')<2
    OR (SELECT count(*) FROM jsonb_array_elements(v_context->'tokens') AS tok(value)
       WHERE tok.value->>'role'='OFFICIAL')<>2
 THEN RAISE EXCEPTION 'SALY_L2C_COMPILED_CONTEXT_INVALID'; END IF;
 IF jsonb_typeof(v_context->'source_refs')<>'array'
    OR jsonb_array_length(v_context->'source_refs')<1
 THEN RAISE EXCEPTION 'SALY_L2C_VERIFIED_SOURCE_REQUIRED'; END IF;
 IF jsonb_typeof(v_item.context_json->'screen_spec')<>'object'
    OR jsonb_typeof(v_item.acceptance_json)<>'object'
    OR v_item.acceptance_json->>'qa_required'<>'true'
 THEN RAISE EXCEPTION 'SALY_L2C_SCREEN_SPEC_OR_QA_MISSING'; END IF;

 -- Matches existing creative_runs input_snapshot fields and success constraints.
 -- This is a proposal for the owning native executor, NOT a run reservation,
 -- rendering receipt, deployment authority or visual approval.
 v_snapshot:=jsonb_build_object(
    'schema_version','SALY_NATIVE_INPUT_SNAPSHOT_L2C_V1',
    'business_code','SALY',
    'order_id',v_item.order_id,
    'item_id',v_item.item_id,
    'item_code',v_item.item_code,
    'design_mode',v_item.design_mode,
    'context_set_id',v_item.context_set_id,
    'identity_versions',v_context->'tokens',
    'source_refs',v_context->'source_refs',
    'screen_spec',v_item.context_json->'screen_spec',
    'acceptance_criteria',v_item.acceptance_json,
    'context_sha256',encode(extensions.digest(
        convert_to(v_context::text,'UTF8'),'sha256'),'hex'),
    'native_execution_authorized',false);

 RETURN jsonb_build_object(
    'schema_version','SALY_WORK_PACKET_L2C_V1',
    'business_code','SALY',
    'order_id',v_item.order_id,'order_code',v_item.order_code,
    'item_id',v_item.item_id,'item_code',v_item.item_code,
    'readiness_code','READY_FOR_NATIVE_HANDOFF',
    'blocking_dependencies','[]'::jsonb,
    'next_attempt_hint',v_attempt+1,
    'idempotency_key_hint','SALY-'||v_item.order_id||'-'||v_item.item_id||
       '-'||(v_attempt+1),
    'latest_run_state',v_latest_state,
    'input_snapshot',v_snapshot,
    'native_execution_authorized',false,
    'image_generation_allowed',false,
    'next_action','GOVERNED_NATIVE_EXECUTOR_AND_WORKER_RECEIPT_REQUIRED');
END $function$
;
