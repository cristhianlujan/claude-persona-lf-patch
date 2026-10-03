-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-SOURCE / PAULO-031
-- Governed Super Admin promotion of the already-closed S30 typed data-access implementation.
-- EKB guard S30-DATA-ACCESS-DEFAULT-OVERFETCH-001 is enforced by making the bounded wrapper
-- the only current public entrypoint. The raw core remains an internal implementation detail.
-- Runtime activation: false. Production runtime deployment: false. No duplicate engine.

DO $promote$
DECLARE
  v_batch uuid := gen_random_uuid();
  v_exec text := 'CHATGPT-SUPER-ADMIN-T-SOURCE-TYPED-DATA-ACCESS-PROMOTION-20261003';
  v_manifest jsonb;
  v_manifest_sha text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos
    WHERE codigo_activo='TYPED_DATA_ACCESS_SCHEMA_SAFETY'
      AND archived_at IS NULL
      AND estado_documental='CANDIDATO'
      AND estado_operativo='READ_ONLY'
      AND version='v2'
      AND metadata->>'terminal_state'='FINAL_CLOSED'
      AND metadata->>'closeout_merge_sha'='ab9f0330a69f7404afc04faa01e93bfcd42fa3f0'
      AND coalesce((metadata->>'no_duplicate_engine')::boolean,false)=true
  ) THEN
    RAISE EXCEPTION 'BLOCK_TYPED_DATA_ACCESS_IMPLEMENTATION_NOT_READY';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='TYPED_DATA_ACCESS'
  ) THEN
    RAISE EXCEPTION 'BLOCK_TYPED_DATA_ACCESS_LOGICAL_ASSET_ALREADY_EXISTS';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='TYPED_DATA_ACCESS'
  ) THEN
    RAISE EXCEPTION 'BLOCK_TYPED_DATA_ACCESS_CAPABILITY_ALREADY_REGISTERED';
  END IF;

  INSERT INTO public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,runtime_estado,impacto_automatico,
    version,ruta_esperada,owner_name,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) VALUES (
    'TYPED_DATA_ACCESS','TRANSVERSAL_TYPED_DATA_ACCESS','CAPABILITY','TRANSVERSAL_CAPABILITY_INFRASTRUCTURE',
    'VIGENTE','READ_ONLY','REPOSITORY_BOUND','BLOQUEADO','2.0.0',
    'sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py',
    'SUPER_ADMIN',
    'Capacidad transversal de acceso tipado y schema-safe con perfiles de campos, limites de filas/bytes, orden determinista y fail-closed; el core no acotado no es entrypoint current.',
    'SUPABASE_DIRECT_INVENTORY','LF_SUPABASE_SANDBOX','public.lf_activos',0,
    v_batch,'{}'::jsonb,
    jsonb_build_object(
      'schema_version','TYPED_DATA_ACCESS_CURRENT_V1',
      'source_repo','cristhianlujan/claude-persona-lf-patch',
      'source_revision','a0f58ad1a1219f0c4dc9a70f167a1908418e5491',
      'implementation_asset','TYPED_DATA_ACCESS_SCHEMA_SAFETY',
      'public_entrypoint','sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py',
      'core_module','sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access.py',
      'registry_contract','LF_DATA_ACCESS_REGISTRY_V2',
      'budget_contract','LF_DATA_ACCESS_BUDGET_V1',
      'ekb_guard','S30-DATA-ACCESS-DEFAULT-OVERFETCH-001',
      'raw_core_entrypoint_policy','INTERNAL_ONLY_NOT_PUBLIC_CURRENT',
      'registered_sources',15,
      'runtime_activation',false,
      'production_activation',false,
      'no_duplicate_engine',true,
      'source_artifacts',jsonb_build_object(
        'core_blob','0fc3792e2f75fd5befc6fb22eb6d8e53ccd16965',
        'registry_blob','f9376af67530a4d7d1753d98f3ecfe9aec2f0ca0',
        'budgeted_blob','466751dc09990414c0e0aa6b5d1aaecf99c54ff3',
        'budget_profiles_blob','8bc7d3f3b8198f5f157441c20beacc83af7ebc80',
        'budget_test_blob','58ee9d851f723a644a42db31cb11b4a1e20f0802',
        'final_receipt_blob','30cb872a08f926a285f1d27ef752659de49974d8'
      ),
      'entry_contract',jsonb_build_object(
        'required',true,
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1',
        'enforcement_state','ENFORCED',
        'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'direct_new_binding_policy','BLOCK'
      )
    ),
    v_exec,v_exec
  );

  UPDATE public.lf_activos
  SET estado_documental='VIGENTE',
      estado_operativo='READ_ONLY',
      ruta_esperada='sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py',
      metadata=metadata || jsonb_build_object(
        'promotion_state','PROMOTED_AS_TYPED_DATA_ACCESS_IMPLEMENTATION',
        'logical_capability','TYPED_DATA_ACCESS',
        'budget_contract','LF_DATA_ACCESS_BUDGET_V1',
        'public_entrypoint','sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py',
        'raw_core_entrypoint_policy','INTERNAL_ONLY_NOT_PUBLIC_CURRENT',
        'ekb_guard','S30-DATA-ACCESS-DEFAULT-OVERFETCH-001',
        'promotion_execution_id',v_exec
      ),
      updated_by_execution_id=v_exec
  WHERE codigo_activo='TYPED_DATA_ACCESS_SCHEMA_SAFETY'
    AND archived_at IS NULL;

  INSERT INTO public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id,updated_at
  ) VALUES (
    'TYPED_DATA_ACCESS','TYPED_DATA_ACCESS_SCHEMA_SAFETY','IMPLEMENTADO_POR_ACTIVO',
    'TYPED_DATA_ACCESS_SCHEMA_SAFETY','IG_CURATOR_VALIDATOR_REFACTOR_V2:T-SOURCE',
    v_batch,v_exec,v_exec,now()
  );

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','TYPED_DATA_ACCESS',
    'version','2.0.0',
    'contract',jsonb_build_object(
      'registry','LF_DATA_ACCESS_REGISTRY_V2',
      'budget','LF_DATA_ACCESS_BUDGET_V1',
      'interface','PREEXECUTION_DATA_ACCESS_RESULT',
      'statuses',jsonb_build_array('PASS','BLOCKED'),
      'ekb_guard','S30-DATA-ACCESS-DEFAULT-OVERFETCH-001'
    ),
    'delivery',jsonb_build_object(
      'mode','REPOSITORY_BOUND_READ_ONLY',
      'implementation_asset','TYPED_DATA_ACCESS_SCHEMA_SAFETY',
      'public_entrypoint','sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py',
      'core_module','sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access.py'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','REGISTRY_CURRENT_PROJECTION_ONLY'
    ),
    'dependencies',jsonb_build_object(
      'governance',jsonb_build_array('ACT-0001'),
      'source_artifacts',jsonb_build_array('LF_DATA_ACCESS_REGISTRY_V2','LF_DATA_ACCESS_BUDGET_V1')
    ),
    'compatibility',jsonb_build_object(
      'unknown_source','SCHEMA_CONTRACT_RESOLVER_FIRST',
      'stale_binding','BLOCK_AND_RERESOLVE',
      'free_sql_registered_source','FORBIDDEN',
      'default_overfetch','BLOCKED_BY_BUDGET_PROFILE',
      'raw_core_public_entrypoint',false,
      'duplicate_engine_forbidden',true
    ),
    'migration',jsonb_build_object(
      'mode','GOVERNED_PROMOTION_AND_REGISTRY_PROJECTION',
      'functional_core_change',false,
      'runtime_activation',false
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','REMOVE_LOGICAL_CURRENT_AND_RESTORE_IMPLEMENTATION_CANDIDATE_ONLY_IF_NO_NEW_BINDINGS_DEPEND_ON_IT'
    ),
    'usage',jsonb_build_object(
      'fields','FIELD_PROFILE_OR_EXPLICIT_WITHIN_PROFILE',
      'row_bound','REQUIRED',
      'byte_budget','REQUIRED',
      'deterministic_order','REQUIRED',
      'detail_filter','REQUIRED_WHEN_PROFILE_REQUIRES'
    ),
    'currentness',jsonb_build_object(
      'source_revision','a0f58ad1a1219f0c4dc9a70f167a1908418e5491',
      'budgeted_blob','466751dc09990414c0e0aa6b5d1aaecf99c54ff3',
      'budget_profiles_blob','8bc7d3f3b8198f5f157441c20beacc83af7ebc80',
      'final_receipt_blob','30cb872a08f926a285f1d27ef752659de49974d8',
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
    'TYPED_DATA_ACCESS','Typed Data Access','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Bounded typed data access with schema safety and deterministic read budgets; raw unbounded core is not the current public entrypoint.',
    v_exec,v_exec,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'TYPED_DATA_ACCESS','2.0.0',2,0,0,'RELEASED',null,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@a0f58ad1a1219f0c4dc9a70f167a1908418e5491/sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py#blob=466751dc09990414c0e0aa6b5d1aaecf99c54ff3',
    'sandbox/lf_contract_gate_test/s30_data_access_candidate/s30_b_final_receipt_v1.json',
    'sandbox/lf_contract_gate_test/s30_data_access_candidate/test_s30_data_access_budget_v1.py#blob=58ee9d851f723a644a42db31cb11b4a1e20f0802',
    v_exec
  );

  INSERT INTO public.lf_capability_current(
    capability_code,version,manifest_sha256,previous_version,promoted_by_execution_id,promotion_reason
  ) VALUES (
    'TYPED_DATA_ACCESS','2.0.0',v_manifest_sha,null,v_exec,
    'Super Admin approved promotion for T-SOURCE; exact closed S30 implementation reused with mandatory bounded access wrapper and no runtime activation.'
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='TYPED_DATA_ACCESS'
      AND estado_documental='VIGENTE'
      AND estado_operativo='READ_ONLY'
      AND ruta_esperada='sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py'
  ) THEN
    RAISE EXCEPTION 'TYPED_DATA_ACCESS_LOGICAL_ASSET_POSTCHECK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='TYPED_DATA_ACCESS_SCHEMA_SAFETY'
      AND estado_documental='VIGENTE'
      AND estado_operativo='READ_ONLY'
      AND ruta_esperada='sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py'
  ) THEN
    RAISE EXCEPTION 'TYPED_DATA_ACCESS_IMPLEMENTATION_POSTCHECK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo='TYPED_DATA_ACCESS'
      AND relacionado_codigo='TYPED_DATA_ACCESS_SCHEMA_SAFETY'
      AND relacion_tipo='IMPLEMENTADO_POR_ACTIVO'
  ) THEN
    RAISE EXCEPTION 'TYPED_DATA_ACCESS_RELATION_POSTCHECK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_current c
    JOIN public.lf_capability_registry r USING(capability_code)
    WHERE c.capability_code='TYPED_DATA_ACCESS'
      AND c.version='2.0.0'
      AND r.status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'TYPED_DATA_ACCESS_CURRENT_POSTCHECK_FAILED';
  END IF;
END $promote$;
