-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M2.4 / PAULO-020
-- T-SOURCE extension: consume the existing CAPABILITY_VERSION_COMPATIBILITY asset.
-- Owner: SUPER_ADMIN.
-- Scope: read-only source-version resolution; no parallel registry/store; no runtime activation.
-- EKB: IG-M2-4-PRIVATE-VERSION-PIN-DRIFT-001.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos a
    WHERE a.codigo_activo='CAPABILITY_VERSION_COMPATIBILITY'
      AND a.archived_at IS NULL
      AND a.estado_documental='VIGENTE'
      AND a.estado_operativo='ACTIVO'
      AND coalesce(a.metadata->'transversal_inventory'->>'inventory_status','')='ACTIVE_SHARED_ENFORCEMENT'
  ) THEN
    RAISE EXCEPTION 'BLOCK_M2_4_VERSION_COMPATIBILITY_ASSET_NOT_CURRENT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='CAPABILITY_VERSION_COMPATIBILITY'
  ) THEN
    RAISE EXCEPTION 'BLOCK_M2_4_VERSION_COMPATIBILITY_REGISTRY_PREEXISTING';
  END IF;
END $pre$;

DO $cap$
DECLARE
  v_manifest jsonb;
  v_manifest_sha text;
  v_exec text := 'CHATGPT-IG-CV-M2-4-T-SOURCE-20261003';
BEGIN
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','CAPABILITY_VERSION_COMPATIBILITY',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'input','VERSIONED_SOURCE_IDENTITY_V1',
      'output','LF_VERSION_PIN_RESOLUTION_V1',
      'authority','SOURCE_REGISTRY_DELEGATION_NO_PARALLEL_STORE'
    ),
    'delivery',jsonb_build_object(
      'mode','SUPABASE_SHARED_READ_ONLY',
      'resolver','public.fn_lf_version_compatibility_resolve_source_v1'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','SUPABASE_MIGRATION'
    ),
    'dependencies',jsonb_build_object(
      'capabilities',jsonb_build_array('SOURCE_RESOLUTION_POLICY'),
      'governance',jsonb_build_array('ACT-0001')
    ),
    'compatibility',jsonb_build_object(
      'unknown_state','FAIL_CLOSED',
      'duplicate_engine_forbidden',true,
      'source_authority_preserved',true
    ),
    'migration',jsonb_build_object(
      'mode','REGISTRY_CURRENTNESS_PLUS_SOURCE_PIN_RESOLVER',
      'functional_core_change',true,
      'runtime_activation',false
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','DROP_NEW_RESOLVER_AND_REMOVE_REGISTRY_POINTER_IF_NO_CONSUMER_BOUND'
    ),
    'usage',jsonb_build_object(
      'resolver','public.fn_lf_version_compatibility_resolve_source_v1',
      'scalar_adapter','public.fn_lf_version_compatibility_current_version_id_v1',
      'docs','sandbox/lf_contract_gate_test/transversal_assets/capability_version_compatibility/README.md'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','public.lf_activos:CAPABILITY_VERSION_COMPATIBILITY',
      'source_revision_immutable',false,
      'entry_guard_required',false
    )
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'CAPABILITY_VERSION_COMPATIBILITY','Capability Version Compatibility','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Resolve governed current versions and source pins without consumer hardcodes.',
    v_exec,v_exec,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'CAPABILITY_VERSION_COMPATIBILITY','1.0.0',1,0,0,'RELEASED',null,
    v_manifest,v_manifest_sha,
    'supabase/migrations/20261003013000_ig_m2_4_transversal_version_pin_v1.sql',
    'sandbox/lf_contract_gate_test/transversal_assets/capability_version_compatibility/README.md',
    'M2.4 rollback + deterministic resolver assertions',v_exec
  );

  INSERT INTO public.lf_capability_current(
    capability_code,version,manifest_sha256,previous_version,promoted_by_execution_id,promotion_reason
  ) VALUES (
    'CAPABILITY_VERSION_COMPATIBILITY','1.0.0',v_manifest_sha,null,v_exec,
    'M2.4 consume existing transversal version compatibility; runtime activation unchanged'
  );
END $cap$;

CREATE OR REPLACE FUNCTION public.fn_lf_version_compatibility_resolve_source_v1(
  p_source_kind text,
  p_source_code text,
  p_owner_code text DEFAULT null
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, programacion, extensions
AS $fn$
DECLARE
  v_id bigint;
  v_version_id bigint;
  v_schema_version text;
  v_revision text;
  v_estado text;
  v_fail_closed boolean;
  v_owner_version_state text;
  v_payload jsonb;
  v_sha text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos a
    WHERE a.codigo_activo='CAPABILITY_VERSION_COMPATIBILITY'
      AND a.archived_at IS NULL
      AND a.estado_documental='VIGENTE'
      AND a.estado_operativo='ACTIVO'
      AND coalesce(a.metadata->'transversal_inventory'->>'inventory_status','')='ACTIVE_SHARED_ENFORCEMENT'
  ) THEN
    RETURN jsonb_build_object('resolved',false,'code','VERSION_COMPATIBILITY_CAPABILITY_NOT_CURRENT');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current c
    WHERE c.capability_code='CAPABILITY_VERSION_COMPATIBILITY'
  ) THEN
    RETURN jsonb_build_object('resolved',false,'code','VERSION_COMPATIBILITY_REGISTRY_NOT_CURRENT');
  END IF;

  IF p_source_kind IS DISTINCT FROM 'PROGRAMACION_CONTRACT' THEN
    RETURN jsonb_build_object('resolved',false,'code','SOURCE_KIND_UNSUPPORTED','source_kind',p_source_kind);
  END IF;

  SELECT
    c.id,
    c.version_id,
    c.especificacion->>'schema_version',
    c.especificacion->>'contract_revision',
    c.estado,
    c.fail_closed,
    v.estado,
    jsonb_build_object(
      'id',c.id,
      'version_id',c.version_id,
      'contrato_codigo',c.contrato_codigo,
      'fail_closed',c.fail_closed,
      'estado',c.estado,
      'especificacion',c.especificacion
    )
  INTO
    v_id,v_version_id,v_schema_version,v_revision,v_estado,v_fail_closed,v_owner_version_state,v_payload
  FROM programacion.contratos c
  JOIN programacion.versiones_agente v ON v.id=c.version_id
  JOIN programacion.agentes a ON a.id=v.agente_id
  WHERE c.contrato_codigo=p_source_code
    AND c.estado='defined'
    AND c.fail_closed
    AND (p_owner_code IS NULL OR a.agente_codigo=p_owner_code)
  ORDER BY c.version_id DESC,c.id DESC
  LIMIT 1;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'resolved',false,
      'code','SOURCE_VERSION_NOT_RESOLVABLE',
      'identity',jsonb_build_object(
        'source_kind',p_source_kind,'source_code',p_source_code,'owner_code',p_owner_code
      )
    );
  END IF;

  v_sha := encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');

  RETURN jsonb_build_object(
    'resolved',true,
    'identity',jsonb_build_object(
      'source_kind',p_source_kind,
      'source_code',p_source_code,
      'owner_code',p_owner_code,
      'source_id',v_id
    ),
    'version',jsonb_build_object(
      'version_id',v_version_id,
      'revision',v_revision,
      'schema_version',v_schema_version
    ),
    'digest',jsonb_build_object('sha256',v_sha),
    'lifecycle',jsonb_build_object(
      'source_state',v_estado,
      'fail_closed',v_fail_closed,
      'owner_version_state',v_owner_version_state
    )
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_lf_version_compatibility_current_version_id_v1(
  p_source_kind text,
  p_source_code text,
  p_owner_code text DEFAULT null
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
  SELECT CASE
    WHEN coalesce((r->>'resolved')::boolean,false)
      THEN (r->'version'->>'version_id')::bigint
    ELSE null
  END
  FROM (
    SELECT public.fn_lf_version_compatibility_resolve_source_v1(
      p_source_kind,p_source_code,p_owner_code
    ) r
  ) s;
$fn$;

UPDATE public.lf_activos
SET metadata = jsonb_set(
                 jsonb_set(
                   metadata,
                   '{transversal_inventory,physical_assets}',
                   coalesce(metadata->'transversal_inventory'->'physical_assets','[]'::jsonb)
                     || jsonb_build_array(
                          'public.fn_lf_version_compatibility_resolve_source_v1',
                          'public.fn_lf_version_compatibility_current_version_id_v1'
                        ),
                   true
                 ),
                 '{m2_4_version_pin_extension}',
                 jsonb_build_object(
                   'schema_version','LF_VERSION_PIN_RESOLUTION_V1',
                   'source_authority','programacion.contratos',
                   'registry_state','REGISTERED_CURRENT_READ_ONLY_RESOLUTION',
                   'consumer','IG_CURATOR_VALIDATOR_REFACTOR_V2:M2.4'
                 ),
                 true
               ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M2-4-T-SOURCE-20261003'
WHERE codigo_activo='CAPABILITY_VERSION_COMPATIBILITY'
  AND archived_at IS NULL;

DO $post$
DECLARE
  v jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CAPABILITY_VERSION_COMPATIBILITY' AND version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'M2_4_VERSION_COMPATIBILITY_CURRENT_POINTER_MISSING';
  END IF;

  v := public.fn_lf_version_compatibility_resolve_source_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );

  IF coalesce((v->>'resolved')::boolean,false) IS NOT TRUE
     OR coalesce(v->'digest'->>'sha256','') !~ '^[0-9a-f]{64}$'
     OR v->'lifecycle'->>'source_state' <> 'defined'
     OR coalesce((v->'lifecycle'->>'fail_closed')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'M2_4_VERSION_PIN_RESOLVER_POSTCONDITION_FAILED:%',v;
  END IF;
END $post$;
