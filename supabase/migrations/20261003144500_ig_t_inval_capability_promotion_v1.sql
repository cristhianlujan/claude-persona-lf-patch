-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-INVAL / PAULO-029
-- Promote the already-applied successor-effective invalidation surface into the canonical capability registry.
-- Functional behavior is unchanged here: the source migration 20261001145000 already established
-- COMPLETED-only predecessor invalidation. No runtime deployment or production activation.

DO $promote$
DECLARE
  v_exec text := 'CHATGPT-SUPER-ADMIN-IG-T-INVAL-PROMOTION-20261003';
  v_batch uuid := gen_random_uuid();
  v_manifest jsonb;
  v_manifest_sha text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='EXECUTION_INVALIDATION_PROPAGATION'
      AND archived_at IS NULL
      AND estado_documental='CANDIDATO'
      AND estado_operativo='READ_ONLY'
      AND coalesce((metadata->>'no_runtime_activation')::boolean,false)=true
      AND coalesce((metadata->>'no_production_activation')::boolean,false)=true
      AND coalesce((metadata#>>'{transversal_inventory,no_duplicate_engine}')::boolean,false)=true
      AND metadata#>>'{entry_contract,guard_code}'='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND coalesce((metadata#>>'{entry_contract,required}')::boolean,false)=true
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INVAL_ASSET_NOT_READY';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='ig_cv_t_inval_completed_successor_only_v1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INVAL_SOURCE_MIGRATION_NOT_APPLIED';
  END IF;

  IF pg_get_functiondef('programacion.fn_input_latch_predecessor_invalidation()'::regprocedure)
       NOT ILIKE '%new.status=''COMPLETED''%'
     OR pg_get_functiondef('programacion.fn_input_latch_predecessor_invalidation()'::regprocedure)
       ILIKE '%new.status in (''COMPLETED'',''BLOCKED'')%'
  THEN
    RAISE EXCEPTION 'BLOCK_T_INVAL_LATCH_SEMANTICS_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='EXECUTION_INVALIDATION_PROPAGATION'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INVAL_CAPABILITY_ALREADY_REGISTERED';
  END IF;

  UPDATE public.lf_activos
  SET estado_documental='VIGENTE',
      estado_operativo='READ_ONLY',
      version='1.0.0',
      owner_name='SUPER_ADMIN',
      metadata=jsonb_set(metadata,'{entry_contract,enforcement_state}','"ENFORCED"'::jsonb,true)
               || jsonb_build_object(
                    'promotion_state','PROMOTED_CURRENT',
                    'promotion_execution_id',v_exec,
                    'runtime_activation',false,
                    'production_activation',false),
      updated_at=now(),
      updated_by_execution_id=v_exec
  WHERE codigo_activo='EXECUTION_INVALIDATION_PROPAGATION'
    AND archived_at IS NULL;

  INSERT INTO public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id,updated_at
  ) VALUES (
    'EXECUTION_INVALIDATION_PROPAGATION','CURRENTNESS_AUTHORITY','DEPENDE_DE',
    'Successor-effective invalidation participates in canonical Input Governance currentness.',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:T-INVAL',v_batch,v_exec,v_exec,now()
  );

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','EXECUTION_INVALIDATION_PROPAGATION',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'authority','SUPABASE_EXISTING_ENFORCEMENT',
      'successor_invalidation_rule','COMPLETED_ONLY',
      'blocked_successor_rule','PRESERVE_PREVIOUS_CURRENT'
    ),
    'delivery',jsonb_build_object(
      'mode','DATABASE_NATIVE_EXISTING_SURFACE',
      'physical_assets',jsonb_build_array(
        'programacion.execution_invalidations',
        'programacion.fn_guard_execution_invalidation',
        'programacion.fn_input_latch_predecessor_invalidation'
      )
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','REGISTRY_CURRENT_PROJECTION_ONLY'
    ),
    'dependencies',jsonb_build_object(
      'governance',jsonb_build_array('CURRENTNESS_AUTHORITY','ORCHESTRATOR_EXECUTION_GUARD_V1')
    ),
    'compatibility',jsonb_build_object(
      'duplicate_engine_forbidden',true,
      'existing_surface_preserved',true,
      'runtime_activation',false,
      'production_activation',false
    ),
    'migration',jsonb_build_object(
      'mode','GOVERNED_PROMOTION_AND_REGISTRY_PROJECTION',
      'functional_core_change',false,
      'source_migration','supabase/migrations/20261001145000_ig_cv_t_inval_completed_successor_only_v1.sql',
      'unit_code','T-INVAL',
      'work_code','PAULO-029'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','REMOVE_REGISTRY_PROJECTION_AND_RESTORE_CANDIDATE_METADATA_ONLY_IF_NO_NEW_BINDINGS_DEPEND_ON_IT'
    ),
    'usage',jsonb_build_object(
      'latch','programacion.fn_input_latch_predecessor_invalidation',
      'guard','programacion.fn_guard_execution_invalidation',
      'ledger','programacion.execution_invalidations',
      'docs','github://cristhianlujan/claude-persona-lf-patch/pull/1381'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','supabase://programacion/fn_input_latch_predecessor_invalidation',
      'source_ref','github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261001145000_ig_cv_t_inval_completed_successor_only_v1.sql',
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
    'EXECUTION_INVALIDATION_PROPAGATION','Execution Invalidation Propagation','ENFORCEMENT',
    'SUPER_ADMIN','ACTIVE',
    'Canonical transversal invalidation propagation: only a COMPLETED successor invalidates its predecessor; BLOCKED preserves prior currentness.',
    v_exec,v_exec,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'EXECUTION_INVALIDATION_PROPAGATION','1.0.0',1,0,0,'RELEASED',null,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261001145000_ig_cv_t_inval_completed_successor_only_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/pull/1381',
    'programacion.fn_input_latch_predecessor_invalidation live semantic readback',
    v_exec
  );

  INSERT INTO public.lf_capability_current(
    capability_code,version,manifest_sha256,previous_version,promoted_by_execution_id,promotion_reason
  ) VALUES (
    'EXECUTION_INVALIDATION_PROPAGATION','1.0.0',v_manifest_sha,null,v_exec,
    'T-INVAL promotion of already-applied successor-effective invalidation surface; no runtime deployment.'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE r.capability_code='EXECUTION_INVALIDATION_PROPAGATION'
      AND r.status='ACTIVE'
      AND r.owner_scope='SUPER_ADMIN'
      AND r.entry_guard_required=true
      AND r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND c.version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'T_INVAL_CAPABILITY_POSTCHECK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo='EXECUTION_INVALIDATION_PROPAGATION'
      AND relacionado_codigo='CURRENTNESS_AUTHORITY'
      AND relacion_tipo='DEPENDE_DE'
  ) THEN
    RAISE EXCEPTION 'T_INVAL_MATERIAL_RELATION_POSTCHECK_FAILED';
  END IF;
END $promote$;