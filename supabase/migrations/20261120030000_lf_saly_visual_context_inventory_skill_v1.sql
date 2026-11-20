-- SALY visual context inventory: first read-only visual factory capability.
-- Scope: SALY + PRODUCTO + PERFIL-UI-ARCHITECT only, from Router-admitted RUN.
-- Does not change visual standards, logos, design tokens, profile, existing skills or Router.
-- Migrate ONLY through PR -> PASE -> LF Migration Merge Train.
BEGIN;

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef('public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM '451f8e4deebde034a5271184187c37c8'
  THEN RAISE EXCEPTION 'SALY_INVENTORY_SELECTOR_SOURCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE profile_code='PERFIL-UI-ARCHITECT' AND enabled)<>3
    OR (SELECT count(*) FROM public.lf_profile_selection_registry_v1
      WHERE profile_code='PERFIL-UI-ARCHITECT' AND descriptor_status='CURRENT')<>1
  THEN RAISE EXCEPTION 'SALY_INVENTORY_UI_BASELINE_DRIFT'; END IF;

  IF EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1
            WHERE skill_code='SALY_VISUAL_CONTEXT_INVENTORY')
    OR EXISTS(SELECT 1 FROM public.lf_skill_selection_registry_v1
            WHERE skill_code='SALY_VISUAL_CONTEXT_INVENTORY')
    OR EXISTS(SELECT 1 FROM public.lf_skill_selector_policy_v1
            WHERE skill_code='SALY_VISUAL_CONTEXT_INVENTORY')
    OR to_regprocedure('public.lf_skill_h_saly_visual_context_inventory_v1(jsonb)') IS NOT NULL
  THEN RAISE EXCEPTION 'SALY_INVENTORY_SKILL_ALREADY_REGISTERED'; END IF;

  IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001')<>1
    OR to_regclass('saly.brand_assets') IS NULL
    OR to_regclass('saly.v_identity_current') IS NULL
  THEN RAISE EXCEPTION 'SALY_INVENTORY_CANONICAL_SOURCES_MISSING'; END IF;

  -- Reuse the business-scoped selector introduced with SALY_APP_VISUAL_PROBE.
  IF NOT EXISTS(
     SELECT 1 FROM public.lf_skill_selector_policy_v1
     WHERE skill_code='SALY_APP_VISUAL_PROBE'
       AND profile_code='PERFIL-UI-ARCHITECT'
       AND applicability_contract->>'selection_business'='SALY'
       AND enabled AND selection_mode='SEMANTIC_OPTIONAL'
  ) THEN RAISE EXCEPTION 'SALY_INVENTORY_SCOPE_SELECTOR_NOT_INSTALLED'; END IF;
END $preflight$;

-- Only an authenticated parent profile RUN may trigger this through the existing
-- selected-skill invoker. Never trust a business_code/project_code supplied in input.
CREATE FUNCTION public.lf_skill_h_saly_visual_context_inventory_v1(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions','saly'
AS $handler$
DECLARE
  e public.lf_operation_execution%ROWTYPE;
  h jsonb;
  bound_skills jsonb;
  v_inventory jsonb;
  v_output_type text;
BEGIN
  IF jsonb_typeof(p_input)<>'object'
     OR nullif(btrim(coalesce(p_input->>'execution_id','')),'') IS NULL
  THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','SALY_INVENTORY_PARENT_EXECUTION_REQUIRED'); END IF;
  IF (p_input ? 'business_code') OR (p_input ? 'project_code') OR
     (p_input ? 'source_override') THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','SALY_INVENTORY_CALLER_AUTHORITY_FORBIDDEN');
  END IF;
  v_output_type:=p_input->>'output_type';
  IF v_output_type IS NOT NULL AND v_output_type NOT IN ('APP_SCREEN','APP_MOCKUP') THEN
    RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','SALY_INVENTORY_OUTPUT_TYPE_INVALID');
  END IF;

  SELECT * INTO e FROM public.lf_operation_execution
  WHERE execution_id=p_input->>'execution_id'
    AND operation_code='EJECUCION_PERFIL_LF'
    AND target_type='PERFIL'
    AND target_code='PERFIL-UI-ARCHITECT'
    AND status='IN_PROGRESS';
  IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','SALY_INVENTORY_PARENT_RUN_NOT_ACTIVE_OR_WRONG_PROFILE'); END IF;

  h:=e.manifest->'router_profile_handoff';
  bound_skills:=e.manifest#>'{skill_selection_readback,selected_skill_codes}';
  IF jsonb_typeof(h)<>'object'
     OR h->>'business' IS DISTINCT FROM 'SALY'
     OR h->>'channel' IS DISTINCT FROM 'PRODUCTO'
     OR h->>'profile_code' IS DISTINCT FROM 'PERFIL-UI-ARCHITECT'
     OR h->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR coalesce((h->>'effect_authority')::boolean,true) IS NOT FALSE
     OR nullif(h->>'literal_request','') IS NULL
     OR e.request_sha256 IS DISTINCT FROM
        encode(extensions.digest(convert_to(h->>'literal_request','UTF8'),'sha256'),'hex')
  THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','SALY_INVENTORY_HANDOFF_SOURCE_INVALID'); END IF;

  -- Prevent unselected skills from being invoked even if a caller knows the
  -- parent RUN ID. Actual semantic decision is bound by the profile lane.
  IF jsonb_typeof(bound_skills)<>'array'
     OR NOT (bound_skills @> '["SALY_VISUAL_CONTEXT_INVENTORY"]'::jsonb)
     OR e.manifest#>>'{skill_selection_readback,source}' IS DISTINCT FROM
        'OFFICIAL_SKILL_POLICY_CURRENT_RUN'
  THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','SALY_INVENTORY_SKILL_NOT_SELECTED_BY_PARENT'); END IF;

  -- Exact-SALY canonical sources only. Same fields as checked-in readback SQL.
  WITH project AS (
    SELECT p.id,p.codigo FROM saly.proyecto p WHERE p.codigo='SALY-001'
  ),
  tokens AS (
    SELECT v.element_code,v.version_id,v.version_number,v.channel_code,
           v.audience_code,v.value_json,v.valid_from,v.valid_to
    FROM saly.v_identity_current v JOIN project p ON p.codigo=v.project_code
  ),
  logos AS (
    SELECT a.id,a.code,a.version_number,a.file_provider,a.external_file_id,
           a.sha256,a.approval_status,a.approval_reference,a.metadata,
           a.valid_from,a.valid_to
    FROM saly.brand_assets a JOIN project p ON p.id=a.project_id
    WHERE a.approval_status='APPROVED'
      AND now()>=a.valid_from AND (a.valid_to IS NULL OR now()<a.valid_to)
  )
  SELECT jsonb_build_object(
     'schema_version','SALY_VISUAL_CONTEXT_INVENTORY_V0_1',
     'status','SOURCE_INVENTORY_ONLY',
     'business_code','SALY',
     'project_code',(SELECT codigo FROM project LIMIT 1),
     'as_of',now(),
     'effective_token_count',(SELECT count(*) FROM tokens),
     'effective_tokens',(
       SELECT coalesce(jsonb_agg(jsonb_build_object(
         'element_code',t.element_code,'version_id',t.version_id,
         'version_number',t.version_number,'channel',t.channel_code,
         'audience',t.audience_code,'value_json',t.value_json,
         'valid_from',t.valid_from,'valid_to',t.valid_to)
         ORDER BY t.element_code),'[]'::jsonb) FROM tokens t),
     'approved_asset_count',(SELECT count(*) FROM logos),
     'approved_assets',(
       SELECT coalesce(jsonb_agg(jsonb_build_object(
         'code',a.code,'asset_id',a.id,'version_number',a.version_number,
         'provider',a.file_provider,'file_ref',a.external_file_id,
         'registered_sha256',a.sha256,
         'independent_sha_verified',
         coalesce((a.metadata->>'sha256_independent_byte_check')::boolean,false),
         'approval_reference',a.approval_reference)
         ORDER BY a.code),'[]'::jsonb) FROM logos a),
     'standard_catalog_exists',(to_regclass('visual.standard_activations') IS NOT NULL),
     'active_standard_version_id',NULL,
     'blocking_codes',jsonb_build_array(
       CASE WHEN to_regclass('visual.standard_activations') IS NULL
         THEN 'STANDARD_CATALOG_NOT_IMPLEMENTED'
         ELSE 'STANDARD_CATALOG_EXISTS_BUT_NOT_RESOLVED' END,
       'ACTIVE_STANDARD_NOT_RESOLVED',
       'APP_SCREEN_AND_MOCKUP_SOURCES_NOT_VERIFIED'),
     'image_generation_allowed',false
  ) INTO v_inventory;

  IF v_inventory->>'project_code' IS DISTINCT FROM 'SALY-001' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code',
      'SALY_INVENTORY_PROJECT_SOURCE_INVALID');
  END IF;

  -- status=SOURCE_INVENTORY_ONLY is a valid read result, not authorization
  -- for image generation. The parent invoker logs the receipt.
  RETURN v_inventory||jsonb_build_object(
    'runtime_invoked',true,
    'simulated',false,
    'effect_authority',false,
    'write_performed',false,
    'handler_version','v0.1',
    'transport_receipt',jsonb_build_object(
      'source','VERIFIED_PARENT_RUN_MANIFEST',
      'execution_id',e.execution_id,
      'request_sha256',e.request_sha256,
      'business',h->>'business',
      'channel',h->>'channel',
      'profile_code',h->>'profile_code',
      'selected_skill_codes',bound_skills,
      'handoff_fingerprint_sha256',h->>'fingerprint_sha256',
      'output_type',coalesce(v_output_type,'BOTH_READ_ONLY')
    )
  );
END;
$handler$;

REVOKE ALL ON FUNCTION public.lf_skill_h_saly_visual_context_inventory_v1(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_skill_h_saly_visual_context_inventory_v1(jsonb) TO service_role;

INSERT INTO public.lf_skill_catalog_v1
(skill_code,description,required_operation,handler_fn,effect,input_required,status)
VALUES (
  'SALY_VISUAL_CONTEXT_INVENTORY',
  'Consulta read-only del estado de tokens, logos y estándar visual SALY con fuente gobernada',
  'EJECUCION_PERFIL_LF',
  'lf_skill_h_saly_visual_context_inventory_v1',
  'READ_ONLY',ARRAY['execution_id']::text[],'READY'
);

INSERT INTO public.lf_skill_selection_registry_v1
(skill_code,descriptor,source_kind,source_ref,source_revision,descriptor_status)
VALUES (
 'SALY_VISUAL_CONTEXT_INVENTORY',
 jsonb_build_object(
   'schema_version','LF_SKILL_SELECTION_DESCRIPTOR_V1',
   'description','Lee el inventario aprobado de tokens y logos SALY para un futuro estándar APP_SCREEN o APP_MOCKUP; devuelve fuentes/versiones y bloqueos sin generar imágenes.',
   'selection_evidence',jsonb_build_array(
     jsonb_build_object('kind','PURPOSE',
       'value','Inventariar fuentes oficiales SALY de identidad visual para UI: tokens efectivos, logos aprobados y límites del estándar.',
       'source_section','Qué hace'),
     jsonb_build_object('kind','ACTIVATION',
       'value','Elegir solo con RUN UI Architect SALY PRODUCTO auténtico cuando el pedido requiere fuentes visuales o readiness de pantallas/mockups.',
       'source_section','Entrada requerida'),
     jsonb_build_object('kind','BOUNDARY',
       'value','No cambia tokens, no genera imágenes, no permite LF, no promueve candidatos, retorna SOURCE_INVENTORY_ONLY sin estándar vigente.',
       'source_section','Límites y aceptación')
   )
 ),
 'GITHUB_SKILL',
 'github://cristhianlujan/claude-persona-lf-patch/skills/saly_visual_context_inventory/SKILL.md',
 'gitblob:3aa981f4b05c40abafb78917937429c6e5202a53',
 'CURRENT'
);

INSERT INTO public.lf_skill_selector_policy_v1
(profile_code,skill_code,channels,required_operation,allowed_effects,
 selection_mode,enabled,applicability_contract,policy_evidence_ref,owner_decision_required)
VALUES (
 'PERFIL-UI-ARCHITECT','SALY_VISUAL_CONTEXT_INVENTORY',
 ARRAY['PRODUCTO']::text[],'EJECUCION_PERFIL_LF',
 ARRAY['READ_ONLY']::text[],'SEMANTIC_OPTIONAL',true,
 jsonb_build_object(
   'evaluation','PARENT_RUN_BUSINESS_EXACT',
   'selection_business','SALY',
   'only_if_applicable',false,
   'scope_evidence','RUN_MANIFEST_ROUTER_PROFILE_HANDOFF',
   'effect_authority',false
 ),
 'owner://saly/2026-11-20/visual-inventory-ui-integration-approved',
 false
);

DO $postflight$
DECLARE
  r jsonb;
  v_live_run text;
  v_profile_cnt integer;
BEGIN
  IF (SELECT count(*) FROM public.lf_skill_catalog_v1
      WHERE skill_code='SALY_VISUAL_CONTEXT_INVENTORY' AND status='READY'
       AND effect='READ_ONLY' AND input_required=ARRAY['execution_id']::text[])<>1
     OR (SELECT count(*) FROM public.lf_skill_selection_registry_v1
      WHERE skill_code='SALY_VISUAL_CONTEXT_INVENTORY' AND descriptor_status='CURRENT'
        AND source_revision='gitblob:3aa981f4b05c40abafb78917937429c6e5202a53')<>1
     OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='SALY_VISUAL_CONTEXT_INVENTORY'
        AND profile_code='PERFIL-UI-ARCHITECT' AND enabled
        AND channels=ARRAY['PRODUCTO']::text[]
        AND applicability_contract->>'selection_business'='SALY')<>1
  THEN RAISE EXCEPTION 'SALY_INVENTORY_REGISTRY_READBACK_INVALID'; END IF;

  -- Existing skills have not been edited. Only one new optional policy is added.
  IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE profile_code='PERFIL-UI-ARCHITECT' AND enabled)<>4
  THEN RAISE EXCEPTION 'SALY_INVENTORY_EXISTING_UI_SKILLS_CHANGED'; END IF;

  -- No global UI/PRODUCTO leakage: no authenticated RUN in generic context.
  r:=public.lf_profile_skill_selection_prepare_v1('PERFIL-UI-ARCHITECT','PRODUCTO',NULL);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(r->'skill_candidates','[]'::jsonb)) x
    WHERE x->>'skill_code'='SALY_VISUAL_CONTEXT_INVENTORY')
  THEN RAISE EXCEPTION 'SALY_INVENTORY_SKILL_LEAKED_TO_UNSCOPED_PRODUCTO'; END IF;

  -- No run/no selection cannot trigger the handler.
  r:=public.lf_skill_h_saly_visual_context_inventory_v1(
      '{"execution_id":"DOES-NOT-EXIST"}'::jsonb);
  IF r->>'status'<>'BLOCKED' OR r->>'blocking_code'<>'SALY_INVENTORY_PARENT_RUN_NOT_ACTIVE_OR_WRONG_PROFILE'
  THEN RAISE EXCEPTION 'SALY_INVENTORY_BAD_RUN_NOT_BLOCKED'; END IF;

  r:=public.lf_skill_h_saly_visual_context_inventory_v1(
      jsonb_build_object('execution_id','DOES-NOT-EXIST',
                         'business_code','SALY'));
  IF r->>'blocking_code'<>'SALY_INVENTORY_CALLER_AUTHORITY_FORBIDDEN'
  THEN RAISE EXCEPTION 'SALY_INVENTORY_SELF_ASSERTED_BUSINESS_NOT_BLOCKED'; END IF;

  r:=public.lf_skill_h_saly_visual_context_inventory_v1(
      jsonb_build_object('execution_id','DOES-NOT-EXIST',
                         'output_type','UNKNOWN'));
  IF r->>'blocking_code'<>'SALY_INVENTORY_OUTPUT_TYPE_INVALID'
  THEN RAISE EXCEPTION 'SALY_INVENTORY_UNKNOWN_OUTPUT_TYPE_NOT_BLOCKED'; END IF;

  SELECT e.execution_id INTO v_live_run FROM public.lf_operation_execution e
  WHERE e.operation_code='EJECUCION_PERFIL_LF'
    AND e.target_code='PERFIL-UI-ARCHITECT'
    AND e.status='IN_PROGRESS'
    AND e.manifest#>>'{router_profile_handoff,business}'='SALY'
    AND e.manifest#>>'{router_profile_handoff,channel}'='PRODUCTO'
  ORDER BY e.started_at DESC LIMIT 1;
  IF v_live_run IS NOT NULL THEN
    r:=public.lf_profile_execution_plan_for_run_v1(v_live_run,NULL::jsonb);
    IF r->>'status'<>'READY'
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(r->'skill_candidates','[]'::jsonb)) x
         WHERE x->>'skill_code'='SALY_VISUAL_CONTEXT_INVENTORY')
    THEN RAISE EXCEPTION 'SALY_INVENTORY_LIVE_RUN_DISCOVERY_FAILED'; END IF;

    -- The old pilot RUN selected a different skill; it cannot read this new one.
    r:=public.lf_skill_h_saly_visual_context_inventory_v1(
          jsonb_build_object('execution_id',v_live_run));
    IF r->>'status'<>'BLOCKED'
       OR r->>'blocking_code'<>'SALY_INVENTORY_SKILL_NOT_SELECTED_BY_PARENT'
    THEN RAISE EXCEPTION 'SALY_INVENTORY_UNSELECTED_HANDLER_NOT_BLOCKED'; END IF;
  END IF;
END $postflight$;

COMMIT;
