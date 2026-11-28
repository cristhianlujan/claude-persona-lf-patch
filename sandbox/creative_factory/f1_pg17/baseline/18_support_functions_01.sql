\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$function$
;
CREATE OR REPLACE FUNCTION visual.knowledge_select_task_v2(p_business text, p_task text, p_spatial_change boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'visual', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_legacy_task text;
 v_dense boolean:=false;
 v_related jsonb:='[]'::jsonb;
 v_required text[];
 v_pins jsonb;
 v_review jsonb;
 v_decisions jsonb;
 v_module text;
BEGIN
 IF p_business IS DISTINCT FROM 'SALY' OR p_task IS NULL
   OR p_spatial_change IS NULL THEN RAISE EXCEPTION 'SALY_K_TASK_INVALID'; END IF;
 CASE p_task
 WHEN 'NEW_SCREEN','EXPLORE_CREATIVE' THEN
   v_legacy_task:='NEW_DESIGN';v_dense:=true;
   v_required:=ARRAY['K01','K02','K03','K04','K05','K06'];
 WHEN 'LOCAL_CORRECTION' THEN
   IF p_spatial_change THEN
     v_legacy_task:='AUDIT';v_related:='["K04","K05"]'::jsonb;
     v_required:=ARRAY['K04','K05','K06'];
   ELSE
     v_legacy_task:='LOCAL_CORRECTION';
     v_required:=ARRAY['K05','K06'];
   END IF;
 WHEN 'LOCAL_CHAT','NUMERIC_ADJUST' THEN
   IF p_spatial_change THEN RAISE EXCEPTION 'SALY_K_SPATIAL_SCOPE_INVALID'; END IF;
   v_legacy_task:='LOCAL_CORRECTION';
   v_required:=ARRAY['K05','K06'];
 ELSE RAISE EXCEPTION 'SALY_K_TASK_UNSUPPORTED: %',p_task;
 END CASE;
 SELECT jsonb_agg(jsonb_build_object('module_code',v.module_code,
   'version',v.version,'sha256',v.document_sha256) ORDER BY v.module_code)
 INTO v_pins
 FROM visual.knowledge_module_versions v
 WHERE v.business_code='SALY' AND v.state='CANDIDATE'
 AND v.module_code=ANY(v_required);
 IF jsonb_array_length(COALESCE(v_pins,'[]'::jsonb))<>cardinality(v_required)
 THEN RAISE EXCEPTION 'SALY_K_MODULE_SOURCE_INCOMPLETE'; END IF;
 -- Existing selector verifies document bytes, hashes and evidence pins.
 v_review:=visual.knowledge_select_review_v1('SALY','REVIEW_ONLY',
   jsonb_build_object('task',v_legacy_task,'dense',v_dense,'related_modules',v_related),
   v_pins);
 IF v_review->>'status' IS DISTINCT FROM 'CANDIDATE_REVIEW_ONLY'
 OR jsonb_array_length(v_review->'modules')<>cardinality(v_required)
 THEN RAISE EXCEPTION 'SALY_K_LEGACY_SELECTION_DRIFT'; END IF;
 SELECT jsonb_agg(jsonb_build_object(
   'module_code',k,
   'decision',CASE WHEN k=ANY(v_required) THEN 'EJECUTAR' ELSE 'OMITIDO' END,
   'reason',CASE WHEN k=ANY(v_required) THEN NULL
     ELSE CASE WHEN k IN ('K01','K02') THEN 'TAREA_LOCAL_SIN_REDISENO'
               WHEN k IN ('K03','K04') THEN 'TAREA_NO_REQUIERE_RECOMPOSICION'
               ELSE 'NO_APLICA_AL_TIPO_DE_TAREA' END END,
   'owner_step',CASE WHEN k IN ('K01','K02') THEN '5'
                     WHEN k IN ('K03','K04') THEN '6'
                     WHEN k='K05' THEN '7' ELSE '8_PLAN_11_IMAGE' END)
   ORDER BY k) INTO v_decisions
 FROM unnest(ARRAY['K01','K02','K03','K04','K05','K06']) AS m(k);
 RETURN jsonb_build_object(
   'schema_version','SALY_K_TASK_SELECTION_V2',
   'source','visual.knowledge_select_review_v1',
   'task',p_task,'spatial_change',p_spatial_change,
   'decisions',v_decisions,'modules',v_review->'modules',
   'pins',v_pins,'mode','CANDIDATE_REVIEW_ONLY',
   'render_authorized',false);
END; $function$
;
CREATE OR REPLACE FUNCTION lf_design.guard_component_token_bindings_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'lf_design'
AS $function$
DECLARE
  v_checked_bindings jsonb;
  v_key text;
  v_value jsonb;
  v_sval text;
  v_color_status text;
  v_color_keys constant text[] := ARRAY[
    'background','border','text','body_text','title_text',
    'error_text','success_text','error_background',
    'border_focus','border_default','fill','stroke',
    'hero_title_color','hero_subtitle_color','icon_color'
  ];
BEGIN
  IF NEW.token_bindings IS NULL OR jsonb_typeof(NEW.token_bindings)<>'object' THEN
    RAISE EXCEPTION
      USING ERRCODE='23514',
            MESSAGE='DESIGN_TOKEN_BINDINGS_INVALID_SHAPE',
            DETAIL='component_tokens.token_bindings must be a JSON object.';
  END IF;


  -- Only unchanged legacy evidence may retain literal visual observations.
  -- New values or modifications to either evidence field are still rejected.
  v_checked_bindings := NEW.token_bindings;
  IF TG_OP='UPDATE' THEN
    IF OLD.token_bindings ? 'measured_fill'
       AND NEW.token_bindings->'measured_fill' IS NOT DISTINCT FROM OLD.token_bindings->'measured_fill' THEN
      v_checked_bindings := v_checked_bindings - 'measured_fill';
    END IF;
    IF OLD.token_bindings ? 'expected_visible_color_range'
       AND NEW.token_bindings->'expected_visible_color_range' IS NOT DISTINCT FROM OLD.token_bindings->'expected_visible_color_range' THEN
      v_checked_bindings := v_checked_bindings - 'expected_visible_color_range';
    END IF;
  END IF;

  IF v_checked_bindings::text ~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()' THEN
    RAISE EXCEPTION
      USING ERRCODE='23514',
            MESSAGE='DESIGN_TOKEN_LITERAL_COLOR_FORBIDDEN',
            DETAIL='Use registered token names in token_bindings; literal HEX/RGB/HSL colors are forbidden.';
  END IF;

  FOR v_key,v_value IN
    SELECT key,value
    FROM jsonb_each(NEW.token_bindings)
  LOOP
    IF v_key = ANY(v_color_keys)
       AND jsonb_typeof(v_value)='string'
    THEN
      v_sval:=trim(both '"' from v_value::text);

      SELECT status
        INTO v_color_status
      FROM lf_design.color_tokens
      WHERE token_name=v_sval
      LIMIT 1;

      IF v_color_status IS NULL THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_COLOR_TOKEN_REFERENCE_NOT_FOUND',
                DETAIL=format(
                  'component=%s key=%s value=%s is not a registered lf_design.color_tokens.token_name',
                  NEW.component_token_code,v_key,v_sval
                );
      END IF;

      IF v_color_status='DEPRECADO' THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_COLOR_TOKEN_REFERENCE_DEPRECATED',
                DETAIL=format(
                  'component=%s key=%s token=%s is DEPRECADO',
                  NEW.component_token_code,v_key,v_sval
                );
      END IF;

      IF NEW.status='VIGENTE' AND v_color_status<>'VIGENTE' THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_VIGENTE_COMPONENT_REQUIRES_VIGENTE_COLOR_TOKEN',
                DETAIL=format(
                  'component=%s key=%s token=%s status=%s',
                  NEW.component_token_code,v_key,v_sval,v_color_status
                );
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION public.fn_update_lf_decisiones_gov_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $function$
;
CREATE OR REPLACE FUNCTION visual.guard_append_only_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'visual'
AS $function$
BEGIN
  RAISE EXCEPTION 'VISUAL_APPEND_ONLY_%',TG_TABLE_NAME;
END
$function$
;
CREATE OR REPLACE FUNCTION visual.guard_standard_version_history_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'visual'
AS $function$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_DELETE_FORBIDDEN';
  END IF;
  IF NEW.standard_id IS DISTINCT FROM OLD.standard_id
    OR NEW.brand_code IS DISTINCT FROM OLD.brand_code
    OR NEW.kind IS DISTINCT FROM OLD.kind
    OR NEW.version IS DISTINCT FROM OLD.version
    OR NEW.parent_version_id IS DISTINCT FROM OLD.parent_version_id
    OR NEW.manifest_json IS DISTINCT FROM OLD.manifest_json
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_MANIFEST_IMMUTABLE'; END IF;
  IF NEW.state IS DISTINCT FROM OLD.state
    AND NOT (
      (OLD.state='DRAFT' AND NEW.state IN ('CANDIDATE','REVOKED'))
      OR (OLD.state='CANDIDATE' AND NEW.state IN ('APPROVED','REVOKED'))
      OR (OLD.state='APPROVED' AND NEW.state='REVOKED')
    )
  THEN RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_INVALID_TRANSITION'; END IF;
  IF OLD.state IN ('APPROVED','REVOKED')
     AND NEW.approval_ref IS DISTINCT FROM OLD.approval_ref
  THEN RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_APPROVAL_REF_IMMUTABLE'; END IF;
  RETURN NEW;
END
$function$
;
