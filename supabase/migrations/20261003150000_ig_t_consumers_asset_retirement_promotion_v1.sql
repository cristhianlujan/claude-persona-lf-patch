-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-CONSUMERS / PAULO-026
-- Promote the already-built ASSET_RETIREMENT_GOVERNANCE contract as a governed transversal capability.
-- Reuses PR #1043 source, existing relations and canonical evidence. No runtime deployment, no production activation,
-- no parallel router/judge/runtime, and no mutation of unrelated consumer relations.

DO $promote$
DECLARE
  v_exec text := 'CHATGPT-SUPER-ADMIN-IG-T-CONSUMERS-ASSET-RETIREMENT-PROMOTION-20261003';
  v_manifest jsonb;
  v_manifest_sha text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos
    WHERE codigo_activo='ASSET_RETIREMENT_GOVERNANCE'
      AND archived_at IS NULL
      AND estado_documental='CANDIDATO'
      AND estado_operativo='READ_ONLY'
      AND version='1.0.0-candidate'
      AND ruta_esperada='sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/README.md'
      AND metadata->>'promotion_status'='READY_FOR_PROMOTION'
      AND (metadata->>'source_pr')::int=1043
      AND metadata->>'contract_ref'='sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/asset_retirement_contract_v1.json'
      AND coalesce((metadata#>>'{transversal_inventory,no_duplicate_engine}')::boolean,false)=true
      AND coalesce((metadata#>>'{entry_contract,required}')::boolean,false)=true
      AND metadata#>>'{entry_contract,guard_code}'='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSET_RETIREMENT_NOT_READY';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_capability_registry
    WHERE capability_code='ASSET_RETIREMENT_GOVERNANCE'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSET_RETIREMENT_CAPABILITY_ALREADY_REGISTERED';
  END IF;

  IF (
    SELECT count(*)
    FROM public.lf_activo_relaciones
    WHERE codigo_activo='ASSET_RETIREMENT_GOVERNANCE'
      AND (relacionado_codigo,relacion_tipo) IN (
        ('CURRENTNESS_AUTHORITY','DEPENDE_DE'),
        ('CI_FAST_DEEP_LANE_ROUTER','RELACIONADO_CAPACIDADES'),
        ('GITHUB_CONTRACT_GATE_LF','RELACIONADO_CAPACIDADES'),
        ('FULL_REGRESSION','RELACIONADO_CAPACIDADES')
      )
  ) <> 4 THEN
    RAISE EXCEPTION 'BLOCK_ASSET_RETIREMENT_RELATION_GRAPH_INCOMPLETE';
  END IF;

  UPDATE public.lf_activos
  SET estado_documental='VIGENTE',
      estado_operativo='READ_ONLY',
      version='1.0.0',
      owner_name='SUPER_ADMIN',
      metadata = jsonb_set(
                   jsonb_set(
                     jsonb_set(metadata,'{entry_contract,enforcement_state}','"ENFORCED"'::jsonb,true),
                     '{transversal_inventory,inventory_status}','"ACTIVE_TRANSVERSAL_READ_ONLY"'::jsonb,true),
                   '{transversal_inventory,documentation,status}','"ACTIVE_MAIN"'::jsonb,true)
                 || jsonb_build_object(
                      'promotion_status','PROMOTED_CURRENT',
                      'activation_status','GOVERNED_CURRENT_NO_RUNTIME',
                      'promotion_source_merge_sha','43aa5b2797b309d75acf516340eb8297ad8df413',
                      'runtime_activation',false,
                      'production_activation',false,
                      'promotion_execution_id',v_exec)
                 || jsonb_build_object(
                      'promotion_evidence',coalesce(metadata->'promotion_evidence','{}'::jsonb)
                        || jsonb_build_object(
                             'comprobado',true,
                             'activation_merge_sha','43aa5b2797b309d75acf516340eb8297ad8df413',
                             'active_index_entry','PRESENT_IN_PROMOTION_PR',
                             'comprobado_blocker',null,
                             'post_promotion_readback','GITHUB_SOURCE_PRESENT_AND_DB_POSTCONDITIONS_ENFORCED')),
      updated_at=now(),
      updated_by_execution_id=v_exec
  WHERE codigo_activo='ASSET_RETIREMENT_GOVERNANCE'
    AND archived_at IS NULL;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','ASSET_RETIREMENT_GOVERNANCE',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'schema_version','lf-asset-retirement-governance/v1',
      'lifecycle',jsonb_build_array(
        'DISCOVER','MAP_CONSUMERS','CLASSIFY_RESPONSIBILITIES','DISCONNECT','REHOME','GUARD','PROMOTE','POST_PROMOTION_READBACK','CLOSE'
      ),
      'authority','GITHUB_MAIN_PLUS_SUPABASE_INVENTORY'
    ),
    'delivery',jsonb_build_object(
      'mode','GOVERNANCE_CONTRACT_READ_ONLY',
      'readme','sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/README.md',
      'contract','sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/asset_retirement_contract_v1.json',
      'first_evidence','sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/evidence/lf_bootstrap_reproducibility_retirement_20260923.json'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','REGISTRY_CURRENT_PROJECTION_ONLY'
    ),
    'dependencies',jsonb_build_object(
      'governance',jsonb_build_array(
        'CURRENTNESS_AUTHORITY','CI_FAST_DEEP_LANE_ROUTER','GITHUB_CONTRACT_GATE_LF','FULL_REGRESSION','ORCHESTRATOR_EXECUTION_GUARD_V1'
      )
    ),
    'compatibility',jsonb_build_object(
      'duplicate_engine_forbidden',true,
      'parallel_runtime_forbidden',true,
      'parallel_router_forbidden',true,
      'drive_authority_forbidden',true,
      'runtime_activation',false,
      'production_activation',false
    ),
    'migration',jsonb_build_object(
      'mode','GOVERNED_PROMOTION_AND_REGISTRY_PROJECTION',
      'functional_core_change',false,
      'source_pr',1043,
      'source_merge_sha','43aa5b2797b309d75acf516340eb8297ad8df413',
      'unit_code','T-CONSUMERS',
      'work_code','PAULO-026'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','REMOVE_REGISTRY_PROJECTION_AND_RESTORE_CANDIDATE_METADATA_ONLY_IF_NO_NEW_BINDINGS_DEPEND_ON_IT'
    ),
    'usage',jsonb_build_object(
      'readme','github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/README.md',
      'contract','github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/asset_retirement_contract_v1.json'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','github://cristhianlujan/claude-persona-lf-patch/refs/heads/main',
      'inventory_ref','supabase://public/lf_activos/ASSET_RETIREMENT_GOVERNANCE',
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
    'ASSET_RETIREMENT_GOVERNANCE','Asset Retirement Governance','TRANSVERSAL',
    'SUPER_ADMIN','ACTIVE',
    'Governed reusable lifecycle for asset retirement, replacement and deprecation with zero-residual evidence; no runtime or parallel engine.',
    v_exec,v_exec,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'ASSET_RETIREMENT_GOVERNANCE','1.0.0',1,0,0,'RELEASED',null,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/asset_retirement_contract_v1.json',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/README.md',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/evidence/lf_bootstrap_reproducibility_retirement_20260923.json',
    v_exec
  );

  INSERT INTO public.lf_capability_current(
    capability_code,version,manifest_sha256,previous_version,promoted_by_execution_id,promotion_reason
  ) VALUES (
    'ASSET_RETIREMENT_GOVERNANCE','1.0.0',v_manifest_sha,null,v_exec,
    'Promotion after PR #1043 source merge and governed readback; no runtime deployment.'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE r.capability_code='ASSET_RETIREMENT_GOVERNANCE'
      AND r.status='ACTIVE'
      AND r.owner_scope='SUPER_ADMIN'
      AND r.entry_guard_required=true
      AND r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND c.version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'ASSET_RETIREMENT_CAPABILITY_POSTCHECK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos
    WHERE codigo_activo='ASSET_RETIREMENT_GOVERNANCE'
      AND archived_at IS NULL
      AND estado_documental='VIGENTE'
      AND estado_operativo='READ_ONLY'
      AND owner_name='SUPER_ADMIN'
      AND version='1.0.0'
      AND metadata#>>'{entry_contract,enforcement_state}'='ENFORCED'
      AND metadata->>'promotion_status'='PROMOTED_CURRENT'
  ) THEN
    RAISE EXCEPTION 'ASSET_RETIREMENT_ASSET_POSTCHECK_FAILED';
  END IF;
END $promote$;