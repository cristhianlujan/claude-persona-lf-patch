-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-SOURCE / PAULO-031
-- Super Admin owner change-set for SOURCE_RESOLUTION_POLICY registry/current projection.
-- Reuses the already-active Supabase policy and implementation asset; creates no new resolver/engine.
-- Runtime activation: false. Production policy activation: false (policy is already ACTIVE before this migration).

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos
    WHERE codigo_activo='SOURCE_RESOLUTION_POLICY'
      AND archived_at IS NULL
      AND estado_documental='VIGENTE'
      AND estado_operativo='ACTIVO'
  ) THEN
    RAISE EXCEPTION 'BLOCK_SOURCE_RESOLUTION_ASSET_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activo_relaciones
    WHERE codigo_activo='SOURCE_RESOLUTION_POLICY'
      AND relacionado_codigo='POL-LF-SOURCE-RESOLUTION'
      AND relacion_tipo='IMPLEMENTADO_POR_ACTIVO'
  ) THEN
    RAISE EXCEPTION 'BLOCK_SOURCE_RESOLUTION_IMPLEMENTATION_RELATION_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_policy_versions
    WHERE policy_code='POL-LF-SOURCE-RESOLUTION'
      AND policy_version='v1.4-transversal-supabase-authority-visual-support'
      AND status='ACTIVE'
      AND superseded_at IS NULL
      AND policy_sha='5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46'
  ) THEN
    RAISE EXCEPTION 'BLOCK_SOURCE_RESOLUTION_POLICY_VERSION_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='SOURCE_RESOLUTION_POLICY'
  ) THEN
    RAISE EXCEPTION 'BLOCK_SOURCE_RESOLUTION_CAPABILITY_ALREADY_REGISTERED';
  END IF;
END $pre$;

DO $cap$
DECLARE
  v_manifest jsonb;
  v_manifest_sha text;
  v_exec text := 'CHATGPT-SUPER-ADMIN-T-SOURCE-CAPABILITY-PROJECTION-20261003';
BEGIN
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','SOURCE_RESOLUTION_POLICY',
    'version','1.4.0',
    'contract',jsonb_build_object(
      'authority','SUPABASE_POLICY_AUTHORITY',
      'policy_code','POL-LF-SOURCE-RESOLUTION',
      'policy_version','v1.4-transversal-supabase-authority-visual-support',
      'policy_sha256','5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46'
    ),
    'delivery',jsonb_build_object(
      'mode','SUPABASE_SHARED_POLICY',
      'implementation_asset','POL-LF-SOURCE-RESOLUTION',
      'operational_source','public.v_lf_fuente_operativa'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','REGISTRY_PROJECTION_ONLY'
    ),
    'dependencies',jsonb_build_object(
      'governance',jsonb_build_array('ACT-0001')
    ),
    'compatibility',jsonb_build_object(
      'unknown_state','FAIL_CLOSED',
      'duplicate_engine_forbidden',true,
      'source_authority_preserved',true
    ),
    'migration',jsonb_build_object(
      'mode','REGISTRY_PROJECTION_ONLY',
      'functional_core_change',false,
      'runtime_activation',false
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','REMOVE_REGISTRY_PROJECTION_ONLY_IF_NO_NEW_BINDINGS_DEPEND_ON_IT'
    ),
    'usage',jsonb_build_object(
      'docs','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','supabase://public/lf_policy_versions/POL-LF-SOURCE-RESOLUTION/v1.4-transversal-supabase-authority-visual-support',
      'entry_guard_required',true
    )
  );

  v_manifest_sha := encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'SOURCE_RESOLUTION_POLICY','Source Resolution Policy','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Canonical transversal source-resolution authority projected from the already-active Supabase policy; no duplicate engine.',
    v_exec,v_exec,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'SOURCE_RESOLUTION_POLICY','1.4.0',1,4,0,'RELEASED',null,
    v_manifest,v_manifest_sha,
    'supabase://public/lf_policy_versions/POL-LF-SOURCE-RESOLUTION/v1.4-transversal-supabase-authority-visual-support',
    'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md',
    'T-SOURCE SOURCE_RESOLUTION_POLICY currentness/readback',v_exec
  );

  INSERT INTO public.lf_capability_current(
    capability_code,version,manifest_sha256,previous_version,promoted_by_execution_id,promotion_reason
  ) VALUES (
    'SOURCE_RESOLUTION_POLICY','1.4.0',v_manifest_sha,null,v_exec,
    'Registry projection of already-active SOURCE_RESOLUTION_POLICY; no runtime or policy activation'
  );
END $cap$;

DO $post$
DECLARE
  v_manifest_sha text;
  v_current_sha text;
BEGIN
  SELECT manifest_sha256
  INTO STRICT v_manifest_sha
  FROM public.lf_capability_version_registry
  WHERE capability_code='SOURCE_RESOLUTION_POLICY'
    AND version='1.4.0';

  SELECT manifest_sha256
  INTO STRICT v_current_sha
  FROM public.lf_capability_current
  WHERE capability_code='SOURCE_RESOLUTION_POLICY'
    AND version='1.4.0';

  IF v_manifest_sha IS DISTINCT FROM v_current_sha THEN
    RAISE EXCEPTION 'SOURCE_RESOLUTION_CURRENT_MANIFEST_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_policy_versions
    WHERE policy_code='POL-LF-SOURCE-RESOLUTION'
      AND policy_sha='5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46'
      AND status='ACTIVE'
      AND superseded_at IS NULL
  ) THEN
    RAISE EXCEPTION 'SOURCE_RESOLUTION_POLICY_CHANGED_DURING_PROJECTION';
  END IF;
END $post$;
