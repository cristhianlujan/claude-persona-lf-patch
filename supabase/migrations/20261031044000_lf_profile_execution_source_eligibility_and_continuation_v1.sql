BEGIN;

-- 1) Materialize the existing Supabase-only UX profile as a governed GitHub execution source.
DO $guard$
DECLARE
  a public.lf_activos%rowtype;
BEGIN
  SELECT * INTO a
  FROM public.lf_activos
  WHERE codigo_activo='PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL;

  IF NOT FOUND
     OR a.metadata->>'profile_slug' IS DISTINCT FROM 'ux_product_experience_architect_lf'
     OR a.ruta_esperada IS DISTINCT FROM 'profiles/ux_product_experience_architect_lf/SKILL.md'
     OR coalesce(a.metadata->>'registry_source','') IS DISTINCT FROM 'SUPABASE_ONLY'
     OR coalesce((a.metadata->>'no_github')::boolean,false) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'BLOCK_UX_PROFILE_SOURCE_MATERIALIZATION_PRECONDITION:%',to_jsonb(a);
  END IF;
END
$guard$;

UPDATE public.lf_activos
SET metadata =
      metadata
      || jsonb_build_object(
           'repo_path','profiles/ux_product_experience_architect_lf',
           'registry_source','SUPABASE',
           'no_github',false
         ),
    raw_payload =
      raw_payload
      || jsonb_build_object('github_created',true),
    accion_migracion='MATERIALIZAR_FUENTE_GITHUB_PARA_EJECUCION_PERFIL',
    updated_at=clock_timestamp()
WHERE codigo_activo='PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
  AND tipo_activo='PERFIL'
  AND archived_at IS NULL;

-- 2) Central source-eligibility rule for EJECUCION_PERFIL_LF.
-- runtime_estado is intentionally NOT used: GPT_NATIVE/CLAUDE_NATIVE profile execution
-- is governed by the canonical GitHub source binding, not by deployed-runtime status.
CREATE OR REPLACE FUNCTION public.lf_profile_execution_source_eligibility_v1(
  p_profile_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  a public.lf_activos%rowtype;
  r public.lf_profile_selection_registry_v1%rowtype;
  v_repo_path text;
  v_expected text;
  v_entrypoint text;
  v_eligible boolean:=false;
  v_reason text;
BEGIN
  IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'eligible',false,
      'reason','PROFILE_CODE_REQUIRED'
    );
  END IF;

  SELECT * INTO a
  FROM public.lf_activos
  WHERE codigo_activo=p_profile_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'eligible',false,
      'profile_code',p_profile_code,
      'reason','PROFILE_NOT_CURRENT'
    );
  END IF;

  SELECT * INTO r
  FROM public.lf_profile_selection_registry_v1
  WHERE profile_code=p_profile_code
  LIMIT 1;

  v_repo_path:=nullif(btrim(coalesce(a.metadata->>'repo_path','')),'');
  v_expected:=nullif(btrim(coalesce(a.ruta_esperada,'')),'');
  v_entrypoint:=case
    when v_expected is null then null
    when v_expected like '%.md' then v_expected
    when right(v_expected,1)='/' then v_expected||'SKILL.md'
    else v_expected||'/SKILL.md'
  end;

  v_eligible:=
       nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
   AND nullif(a.metadata->>'profile_slug','') IS NOT NULL
   AND r.profile_code IS NOT NULL
   AND r.descriptor_status='CURRENT'
   AND v_repo_path IS NOT NULL
   AND v_repo_path ~ '^profiles/[a-z0-9][a-z0-9_/-]{1,180}$'
   AND v_entrypoint IS NOT NULL
   AND v_entrypoint = v_repo_path||'/SKILL.md';

  v_reason:=case
    when nullif(a.metadata->>'canonical_profile_key','') IS NULL
      or nullif(a.metadata->>'profile_slug','') IS NULL
      then 'PROFILE_IDENTITY_NOT_CANONICAL'
    when r.profile_code IS NULL or r.descriptor_status<>'CURRENT'
      then 'PROFILE_DESCRIPTOR_NOT_CURRENT'
    when v_repo_path IS NULL or v_entrypoint IS NULL
      then 'PROFILE_EXECUTION_SOURCE_UNRESOLVED'
    when v_repo_path !~ '^profiles/[a-z0-9][a-z0-9_/-]{1,180}$'
      or v_entrypoint <> v_repo_path||'/SKILL.md'
      then 'PROFILE_EXECUTION_SOURCE_BINDING_INVALID'
    else 'PROFILE_EXECUTION_SOURCE_READY'
  end;

  RETURN jsonb_build_object(
    'eligible',v_eligible,
    'profile_code',a.codigo_activo,
    'profile_slug',a.metadata->>'profile_slug',
    'repo_path',v_repo_path,
    'entrypoint_path',v_entrypoint,
    'descriptor_status',coalesce(r.descriptor_status,'MISSING'),
    'runtime_status',a.runtime_estado,
    'reason',v_reason
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_source_eligibility_v1(text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_source_eligibility_v1(text)
TO service_role,supabase_read_only_user;

COMMENT ON FUNCTION public.lf_profile_execution_source_eligibility_v1(text) IS
'Central source eligibility for EJECUCION_PERFIL_LF. Requires a canonical current descriptor plus a canonical profiles/<slug>/SKILL.md GitHub binding. Does not use runtime_estado as a GPT_NATIVE/CLAUDE_NATIVE execution gate.';

-- 3) Selector catalog: semantic selection may see only profiles the current
-- EJECUCION_PERFIL_LF bridge can actually resolve to a governed source.
CREATE OR REPLACE FUNCTION public.lf_profile_selector_catalog_v1()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
WITH p AS (
  SELECT
    a.codigo_activo AS profile_code,
    a.nombre_canonico AS profile_name,
    a.subtipo_activo AS profile_subtype,
    a.estado_documental AS document_status,
    a.estado_operativo AS operational_status,
    a.runtime_estado AS runtime_status,
    a.version,
    a.metadata->>'canonical_profile_key' AS canonical_profile_key,
    a.metadata->>'profile_slug' AS profile_slug,
    r.descriptor,
    r.source_kind,
    r.source_ref,
    r.source_revision,
    CASE
      WHEN nullif(a.metadata->>'canonical_profile_key','') IS NULL
        THEN 'NONCANONICAL_PROFILE_RECORD'
      WHEN r.profile_code IS NULL
        THEN 'DESCRIPTOR_MISSING'
      ELSE r.descriptor_status
    END AS descriptor_status,
    coalesce((src.info->>'eligible')::boolean,false) AS execution_source_eligible,
    src.info AS execution_source_eligibility,
    (
      nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
      AND r.profile_code IS NOT NULL
      AND r.descriptor_status='CURRENT'
      AND coalesce((src.info->>'eligible')::boolean,false)
    ) AS selection_eligible
  FROM public.lf_activos a
  LEFT JOIN public.lf_profile_selection_registry_v1 r
    ON r.profile_code=a.codigo_activo
  CROSS JOIN LATERAL (
    SELECT public.lf_profile_execution_source_eligibility_v1(a.codigo_activo) AS info
  ) src
  WHERE a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
),
agg AS (
  SELECT
    count(*)::integer AS total_profile_records,
    count(*) FILTER (WHERE canonical_profile_key IS NOT NULL)::integer AS canonical_profile_count,
    count(*) FILTER (WHERE selection_eligible)::integer AS selectable_profile_count,
    bool_and(
      CASE WHEN canonical_profile_key IS NULL THEN true
           ELSE descriptor_status='CURRENT' AND descriptor IS NOT NULL
      END
    ) AS all_canonical_descriptors_complete,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'profile_code',profile_code,
          'profile_name',profile_name,
          'profile_subtype',profile_subtype,
          'canonical_profile_key',canonical_profile_key,
          'profile_slug',profile_slug,
          'document_status',document_status,
          'operational_status',operational_status,
          'runtime_status',runtime_status,
          'version',version,
          'selection_eligible',selection_eligible,
          'execution_source_eligible',execution_source_eligible,
          'execution_source_eligibility',execution_source_eligibility,
          'descriptor_status',descriptor_status,
          'descriptor',descriptor,
          'descriptor_source_kind',source_kind,
          'descriptor_source_ref',source_ref,
          'descriptor_source_revision',source_revision
        )
        ORDER BY profile_code
      ),
      '[]'::jsonb
    ) AS profiles
  FROM p
)
SELECT jsonb_build_object(
  'schema_version','LF_PROFILE_SELECTOR_CATALOG_V1',
  'selection_mode','DETERMINISTIC_DISCOVERY_ONLY',
  'semantic_selection_performed',false,
  'total_profile_records',total_profile_records,
  'canonical_profile_count',canonical_profile_count,
  'selectable_profile_count',selectable_profile_count,
  'all_canonical_descriptors_complete',all_canonical_descriptors_complete,
  'profiles',profiles
)
FROM agg
$function$;

COMMENT ON FUNCTION public.lf_profile_selector_catalog_v1() IS
'Returns deterministic profile descriptors and filters semantic execution candidates through the central EJECUCION_PERFIL_LF source-eligibility rule. It never performs semantic ranking.';

-- 4) Gate2 is explicitly NON-TERMINAL. Keep the existing canonical runner;
-- do not create a second execution path.
DO $patch$
DECLARE
  v_src text;
  v_before text;
BEGIN
  SELECT pg_get_functiondef(
    'public.lf_router_pipeline_context_profile_semantic_submit_v2(text,text)'::regprocedure
  ) INTO v_src;

  IF md5(v_src)<>'de08b8dc63dba3755723ca21252ea750' THEN
    RAISE EXCEPTION 'BLOCK_PROFILE_GATE2_CONTINUATION_SOURCE_DRIFT:semantic_submit:%',md5(v_src);
  END IF;

  v_before:=v_src;
  v_src:=replace(
    v_src,
    $needle$
         'next_step','GOVERNED_PROFILE_EXECUTION_REQUIRED',
         'stage1_payload',$needle$,
    $replacement$
         'next_step','GOVERNED_PROFILE_EXECUTION_REQUIRED',
         'next_action','DISPATCH_GOVERNED_PROFILE_RUNNER',
         'terminal',false,
         'continuation_required',true,
         'stop_allowed',false,
         'continuation_runner','scripts/lf_profile_router_admit.py',
         'continuation_trigger','lf-profile-admit-governed',
         'continuation_stage06_action','router_profile_admit_context_v2',
         'continuation_stage07_action','profile_execution_begin_from_router_context_v1',
         'stage1_payload',$replacement$
  );

  IF v_src=v_before THEN
    RAISE EXCEPTION 'BLOCK_PROFILE_GATE2_CONTINUATION_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE v_src;

  SELECT pg_get_functiondef(
    'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)'::regprocedure
  ) INTO v_src;

  IF md5(v_src)<>'94038416c351c3809b53161926fbca8f' THEN
    RAISE EXCEPTION 'BLOCK_PROFILE_GATE2_CONTINUATION_SOURCE_DRIFT:profile_admit:%',md5(v_src);
  END IF;

  v_before:=v_src;
  v_src:=replace(
    v_src,
    $needle$
   'next_action','EJECUCION_PERFIL_LF_BEGIN_REQUIRED',
   'router_reentry_required',false$needle$,
    $replacement$
   'next_action','EJECUCION_PERFIL_LF_BEGIN_REQUIRED',
   'terminal',false,
   'continuation_required',true,
   'stop_allowed',false,
   'continuation_runner','scripts/lf_profile_router_admit.py',
   'continuation_stage07_action','profile_execution_begin_from_router_context_v1',
   'router_reentry_required',false$replacement$
  );

  IF v_src=v_before THEN
    RAISE EXCEPTION 'BLOCK_PROFILE_ADMISSION_CONTINUATION_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE v_src;
END
$patch$;

-- 5) Production guards / readback.
DO $verify$
DECLARE
  ux jsonb;
  cx jsonb;
  pd jsonb;
  cat jsonb;
  req jsonb;
  sem_src text;
  admit_src text;
BEGIN
  ux:=public.lf_profile_execution_source_eligibility_v1(
    'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
  );
  cx:=public.lf_profile_execution_source_eligibility_v1(
    'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531'
  );
  pd:=public.lf_profile_execution_source_eligibility_v1(
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF coalesce((ux->>'eligible')::boolean,false) IS NOT TRUE
     OR ux->>'entrypoint_path'<>'profiles/ux_product_experience_architect_lf/SKILL.md'
  THEN
    RAISE EXCEPTION 'UX_PROFILE_EXECUTION_SOURCE_NOT_ENABLED:%',ux;
  END IF;

  IF coalesce((cx->>'eligible')::boolean,true) IS NOT FALSE
     OR cx->>'reason'<>'PROFILE_EXECUTION_SOURCE_UNRESOLVED'
  THEN
    RAISE EXCEPTION 'SUPABASE_ONLY_PROFILE_NOT_FAIL_CLOSED:%',cx;
  END IF;

  IF coalesce((pd->>'eligible')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'PRODUCT_DIRECTOR_REGRESSION:%',pd;
  END IF;

  cat:=public.lf_profile_selector_catalog_v1();
  IF (cat->>'canonical_profile_count')::integer<>10
     OR (cat->>'selectable_profile_count')::integer<>9
     OR coalesce((cat->>'all_canonical_descriptors_complete')::boolean,false) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_EXECUTABLE_CARDINALITY_INVALID:%',left(cat::text,2000);
  END IF;

  req:=public.lf_profile_selector_semantic_prepare_v1(
    'Revisar login B2B de LF'
  );

  IF NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(req->'candidate_profiles') p
       WHERE p->>'profile_code'='PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
     )
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(req->'candidate_profiles') p
       WHERE p->>'profile_code'='PERFIL-PRODUCT-DIRECTOR-LF'
     )
     OR EXISTS(
       SELECT 1 FROM jsonb_array_elements(req->'candidate_profiles') p
       WHERE p->>'profile_code'='PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531'
     )
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_EXECUTABLE_CANDIDATE_SET_INVALID:%',left(req::text,2400);
  END IF;

  SELECT pg_get_functiondef(
    'public.lf_router_pipeline_context_profile_semantic_submit_v2(text,text)'::regprocedure
  ) INTO sem_src;
  SELECT pg_get_functiondef(
    'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)'::regprocedure
  ) INTO admit_src;

  IF position('continuation_required' in sem_src)=0
     OR position('DISPATCH_GOVERNED_PROFILE_RUNNER' in sem_src)=0
     OR position('scripts/lf_profile_router_admit.py' in sem_src)=0
     OR position('continuation_required' in admit_src)=0
     OR position('profile_execution_begin_from_router_context_v1' in admit_src)=0
  THEN
    RAISE EXCEPTION 'PROFILE_GATE2_NON_TERMINAL_CONTINUATION_NOT_ENFORCED';
  END IF;
END
$verify$;

COMMIT;
