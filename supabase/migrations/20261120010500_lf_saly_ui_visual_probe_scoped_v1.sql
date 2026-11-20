-- SALY / UI Architect: Hello world probe, scope-bound to a real parent RUN.
-- One existing RUN owns the skill; Router never starts a skill RUN.
-- Owner-approved: SALY+PRODUCTO only; no visual output, no LF impact.
-- One migration through LF Migration Merge Train; no direct apply.
BEGIN;

DO $preflight$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)'::regprocedure))
      IS DISTINCT FROM '353a555c6c3a1666d36293dd6792ea9a'
 THEN RAISE EXCEPTION 'SALY_PROBE_SELECTOR_PREIMAGE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1 WHERE skill_code='SALY_APP_VISUAL_PROBE')
    OR EXISTS(SELECT 1 FROM public.lf_skill_selection_registry_v1 WHERE skill_code='SALY_APP_VISUAL_PROBE')
    OR EXISTS(SELECT 1 FROM public.lf_skill_selector_policy_v1 WHERE skill_code='SALY_APP_VISUAL_PROBE')
    OR to_regprocedure('public.lf_skill_h_saly_app_visual_probe_v1(jsonb)') IS NOT NULL
 THEN RAISE EXCEPTION 'SALY_PROBE_ALREADY_REGISTERED_OR_HANDLER_EXISTS'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE profile_code='PERFIL-UI-ARCHITECT' AND enabled)<>2
    OR (SELECT count(*) FROM public.lf_profile_selection_registry_v1
      WHERE profile_code='PERFIL-UI-ARCHITECT' AND descriptor_status='CURRENT')<>1
 THEN RAISE EXCEPTION 'SALY_PROBE_UI_BASELINE_DRIFT'; END IF;
END $preflight$;

-- Generic, opt-in policy predicate. No special-case profile or skill code.
-- If applicability_contract has selection_business, the selector must verify
-- against the authenticated source of truth: manifest of the *active parent RUN*.
DO $scope_selector$
DECLARE
 v_def text;
 v_old text:=$old$
   WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   ORDER BY p.skill_code
$old$;
 v_new text:=$new$
   WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
     AND (
       NOT (p.applicability_contract ? 'selection_business')
       OR EXISTS (
         SELECT 1
         FROM public.lf_operation_execution parent
         WHERE parent.execution_id=v_ctx#>>'{input,execution_id}'
           AND parent.operation_code='EJECUCION_PERFIL_LF'
           AND parent.status='IN_PROGRESS'
           AND parent.target_code=p_profile_code
           AND parent.manifest#>>'{router_profile_handoff,channel}'=p_channel
           AND parent.manifest#>>'{router_profile_handoff,business}'=
               p.applicability_contract->>'selection_business'
           AND parent.manifest#>>'{router_profile_handoff,literal_request}'=
               v_ctx->>'request_text'
       )
     )
   ORDER BY p.skill_code
$new$;
BEGIN
 v_def:=pg_get_functiondef('public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)'::regprocedure);
 IF (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1
 THEN RAISE EXCEPTION 'SALY_PROBE_SELECTOR_EXACT_ANCHOR_DRIFT'; END IF;
 EXECUTE replace(v_def,v_old,v_new);
END $scope_selector$;

CREATE FUNCTION public.lf_skill_h_saly_app_visual_probe_v1(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $handler$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 h jsonb;
 bound_skills jsonb;
BEGIN
 IF jsonb_typeof(p_input)<>'object'
    OR nullif(btrim(coalesce(p_input->>'execution_id','')),'') IS NULL
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SALY_PROBE_PARENT_EXECUTION_REQUIRED');
 END IF;

 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_input->>'execution_id'
   AND operation_code='EJECUCION_PERFIL_LF' AND status='IN_PROGRESS'
   AND target_code='PERFIL-UI-ARCHITECT';
 IF NOT FOUND THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SALY_PROBE_PARENT_RUN_NOT_ACTIVE_OR_WRONG_PROFILE');
 END IF;

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
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SALY_PROBE_HANDOFF_SOURCE_INVALID');
 END IF;

 -- Selection is committed by the profile-owned OIDC/Edge continuation.
 -- A caller cannot self-authorize by putting SALY or a skill code in input.
 IF jsonb_typeof(bound_skills)<>'array'
    OR NOT (bound_skills @> '["SALY_APP_VISUAL_PROBE"]'::jsonb)
    OR e.manifest#>>'{skill_selection_readback,source}' IS DISTINCT FROM
       'OFFICIAL_SKILL_POLICY_CURRENT_RUN'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SALY_PROBE_SKILL_NOT_SELECTED_BY_PARENT');
 END IF;

 RETURN jsonb_build_object(
   'status','COMPLETED',
   'mensaje','Hola mundo, ya llegué.',
   'skill_code','SALY_APP_VISUAL_PROBE',
   'handler_version','v0.1',
   'runtime_invoked',true,'simulated',false,
   'effect_authority',false,'write_performed',false,
   'transporte_recibido',jsonb_build_object(
      'execution_id',e.execution_id,
      'business',h->>'business','channel',h->>'channel',
      'profile_code',h->>'profile_code',
      'operation_code',h->>'operation_code',
      'literal_request',h->>'literal_request',
      'scope',h->'scope',
      'request_sha256',e.request_sha256,
      'router_profile_handoff_fingerprint_sha256',h->>'fingerprint_sha256',
      'skill_selection_readback',e.manifest->'skill_selection_readback',
      'transport_source','VERIFIED_PARENT_RUN_MANIFEST')
 );
END;
$handler$;

REVOKE ALL ON FUNCTION public.lf_skill_h_saly_app_visual_probe_v1(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_skill_h_saly_app_visual_probe_v1(jsonb) TO service_role;

INSERT INTO public.lf_skill_catalog_v1
(skill_code,description,required_operation,handler_fn,effect,input_required,status)
VALUES (
  'SALY_APP_VISUAL_PROBE',
  'Hola mundo read-only con transporte auténtico del RUN UI SALY/PRODUCTO',
  'EJECUCION_PERFIL_LF',
  'lf_skill_h_saly_app_visual_probe_v1',
  'READ_ONLY',
  ARRAY['execution_id']::text[],
  'READY'
);

INSERT INTO public.lf_skill_selection_registry_v1
(skill_code,descriptor,source_kind,source_ref,source_revision,descriptor_status)
VALUES (
 'SALY_APP_VISUAL_PROBE',
 jsonb_build_object(
   'schema_version','LF_SKILL_SELECTION_DESCRIPTOR_V1',
   'description','Probe READ_ONLY: Hola mundo y transporte auténtico de UI para SALY/PRODUCTO. Sin diseño ni generación visual.',
   'selection_evidence',jsonb_build_array(
     jsonb_build_object('kind','PURPOSE',
         'value','Demostrar que UI recibió el handoff SALY y seleccionó el skill dentro del mismo RUN; devolver Hola mundo y el transporte real.',
         'source_section','Propósito'),
     jsonb_build_object('kind','ACTIVATION',
         'value','Solo para el piloto explícito de UI Architect en SALY PRODUCTO, con RUN gobernado y readback de selección.',
         'source_section','Activación'),
     jsonb_build_object('kind','BOUNDARY',
         'value','No disponible para LF ni otros canales; sin generación de imágenes, escritura, aprobación visual o segundo RUN.',
         'source_section','Control de seguridad')
   )
 ),
 'GITHUB_SKILL',
 'github://cristhianlujan/claude-persona-lf-patch/skills/saly_app_visual_probe/SKILL.md',
 'gitblob:1736f40ed9fc9668703d7581f561cb54fe1ee11e',
 'CURRENT'
);

INSERT INTO public.lf_skill_selector_policy_v1
(profile_code,skill_code,channels,required_operation,allowed_effects,selection_mode,enabled,
 applicability_contract,policy_evidence_ref,owner_decision_required)
VALUES (
 'PERFIL-UI-ARCHITECT',
 'SALY_APP_VISUAL_PROBE',
 ARRAY['PRODUCTO']::text[],
 'EJECUCION_PERFIL_LF',
 ARRAY['READ_ONLY']::text[],
 'SEMANTIC_OPTIONAL',
 true,
 jsonb_build_object(
    'evaluation','PARENT_RUN_BUSINESS_EXACT',
    'selection_business','SALY',
    'only_if_applicable',false,
    'scope_evidence','RUN_MANIFEST_ROUTER_PROFILE_HANDOFF',
    'effect_authority',false
 ),
 'owner://saly/2026-11-20/ui-visual-probe-hello-world-approved',
 false
);

DO $postflight$
DECLARE
 r jsonb;
 v_test_run text;
BEGIN
 IF (SELECT count(*) FROM public.lf_skill_catalog_v1 WHERE skill_code='SALY_APP_VISUAL_PROBE' AND status='READY' AND effect='READ_ONLY')<>1
    OR (SELECT count(*) FROM public.lf_skill_selection_registry_v1 WHERE skill_code='SALY_APP_VISUAL_PROBE' AND descriptor_status='CURRENT')<>1
    OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1 WHERE skill_code='SALY_APP_VISUAL_PROBE'
          AND profile_code='PERFIL-UI-ARCHITECT' AND channels=ARRAY['PRODUCTO']::text[]
          AND enabled=true AND selection_mode='SEMANTIC_OPTIONAL'
          AND applicability_contract->>'selection_business'='SALY')<>1
 THEN RAISE EXCEPTION 'SALY_PROBE_REGISTRY_POSTFLIGHT_INVALID'; END IF;

 -- No RUN context means not selectable. Prevent polluting LF/global UI selectors.
 r:=public.lf_profile_skill_selection_prepare_v1('PERFIL-UI-ARCHITECT','PRODUCTO',NULL);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(r->'skill_candidates','[]'::jsonb)) x WHERE x->>'skill_code'='SALY_APP_VISUAL_PROBE')
 THEN RAISE EXCEPTION 'SALY_PROBE_LEAKED_TO_GENERIC_PRODUCTO'; END IF;

 -- Wrong synthetic RUN is insufficient. This is a selector read-only negative.
 r:=public.lf_profile_skill_selection_prepare_context_v1(
    'PERFIL-UI-ARCHITECT','PRODUCTO',NULL,
    jsonb_build_object('profile_code','PERFIL-UI-ARCHITECT','channel','PRODUCTO',
      'step','40','request_text','fake LF request',
      'input',jsonb_build_object('execution_id','DOES-NOT-EXIST')));
 IF r->>'status'<>'READY' OR EXISTS(
    SELECT 1 FROM jsonb_array_elements(coalesce(r->'skill_candidates','[]'::jsonb)) x WHERE x->>'skill_code'='SALY_APP_VISUAL_PROBE'
 ) THEN RAISE EXCEPTION 'SALY_PROBE_UNAUTHENTIC_CONTEXT_ALLOWED'; END IF;

 -- Handler cannot greet without a source-bound parent RUN/selection.
 r:=public.lf_skill_h_saly_app_visual_probe_v1(jsonb_build_object('execution_id','DOES-NOT-EXIST'));
 IF r->>'status'<>'BLOCKED'
    OR r->>'blocking_code'<>'SALY_PROBE_PARENT_RUN_NOT_ACTIVE_OR_WRONG_PROFILE'
 THEN RAISE EXCEPTION 'SALY_PROBE_HANDLER_NEGATIVE_FAILED'; END IF;

 -- If a currently active SALY UI run exists, test its deterministic discovery.
 SELECT e.execution_id INTO v_test_run
 FROM public.lf_operation_execution e
 WHERE e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_code='PERFIL-UI-ARCHITECT' AND e.status='IN_PROGRESS'
   AND e.manifest#>>'{router_profile_handoff,business}'='SALY'
   AND e.manifest#>>'{router_profile_handoff,channel}'='PRODUCTO'
 ORDER BY e.started_at DESC LIMIT 1;
 IF v_test_run IS NOT NULL THEN
   r:=public.lf_profile_execution_plan_for_run_v1(v_test_run,NULL::jsonb);
   IF r->>'status'<>'READY'
      OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(r->'skill_candidates','[]'::jsonb)) x
           WHERE x->>'skill_code'='SALY_APP_VISUAL_PROBE')
   THEN RAISE EXCEPTION 'SALY_PROBE_LIVE_RUN_DISCOVERY_FAILED'; END IF;
 END IF;

 -- No modification to existing skills or other profile policies.
 IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE profile_code='PERFIL-UI-ARCHITECT' AND skill_code<>'SALY_APP_VISUAL_PROBE' AND enabled)<>2
 THEN RAISE EXCEPTION 'SALY_PROBE_EXISTING_UI_SKILL_POLICY_REGRESSION'; END IF;
END $postflight$;

COMMIT;
