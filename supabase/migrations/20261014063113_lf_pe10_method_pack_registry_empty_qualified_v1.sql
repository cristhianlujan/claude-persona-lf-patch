-- PE10: VERSION DEL CATALOGO COMO INFRAESTRUCTURA SIN METODOS CALIFICADOS.
-- One Train-owned migration; no Profile Updater execution/runtime/production change.
-- Source exact main merge commit: 05b86a49925f4e4d6290bafe7bbf68f24c626a2b; blob: 2eb35f8049c43c23e04536bac55195b4e78cecfe.
-- Do not count 8 declared method CANDIDATES as 8 qualified methods.
DO $registry_version$
DECLARE
  v_exec constant text := 'PE10_C3_V2_METHOD_REGISTRY_VERSION_TRAIN_V1';
  v_source_commit constant text := '05b86a49925f4e4d6290bafe7bbf68f24c626a2b';
  v_source_blob constant text := '2eb35f8049c43c23e04536bac55195b4e78cecfe';
  v_test_blob constant text := '4b02be7bfded90c09b77ee77b78f571a42c1a71b';
  v_catalog_sha constant text := '122f2e85b61f56c059dec229e97062c33545dcb05280d5ff01c5dc1ed8ffde38';
  v_manifest jsonb;
  v_manifest_sha text;
  v_promotion jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='METHOD_PACK_REGISTRY'
      AND status='ACTIVE' AND owner_scope='SUPER_ADMIN'
      AND entry_guard_required IS TRUE
  ) THEN
    RAISE EXCEPTION 'BLOCK_PE10_METHOD_REGISTRY_IDENTITY_MISSING';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='METHOD_PACK_REGISTRY')
    OR EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='METHOD_PACK_REGISTRY') THEN
    RAISE EXCEPTION 'BLOCK_PE10_METHOD_REGISTRY_ALREADY_VERSIONED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c ON c.capability_code=r.capability_code
    JOIN public.lf_capability_version_registry v ON v.capability_code=c.capability_code AND v.version=c.version
    WHERE r.capability_code='CAPABILITY_SELECTOR' AND r.status='ACTIVE'
      AND v.release_state='RELEASED' AND c.manifest_sha256=v.manifest_sha256
  ) THEN
    RAISE EXCEPTION 'BLOCK_PE10_SELECTOR_NOT_CURRENT';
  END IF;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','METHOD_PACK_REGISTRY',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'schema_version','METHOD_PACK_REGISTRY_V1',
      'release_scope','CATALOG_INFRASTRUCTURE_ONLY',
      'catalog_payload_sha256',v_catalog_sha,
      'candidate_method_count',8,
      'qualified_method_portfolio',jsonb_build_array(),
      'method_execution_permission',false,
      'methods_unqualified_until_verified_receipts',true,
      'selection_is_execution_permission',false,
      'candidate_methods_may_execute',false),
    'qualified_method_portfolio',jsonb_build_array(),
    'catalog_payload_sha256',v_catalog_sha,
    'delivery',jsonb_build_object(
      'mode','REPOSITORY_BOUND_READ_ONLY',
      'runtime_deploy_required',false,
      'active_runtime_cutover',false,
      'source_commit',v_source_commit,
      'source_blob_sha1',v_source_blob,
      'validator_blob_sha1',v_test_blob),
    'installation',jsonb_build_object(
      'required',false,'reinstall_required',false,'runtime_deploy_required',false),
    'dependencies',jsonb_build_object(
      'selector','CAPABILITY_SELECTOR@1.0.0',
      'evidence_ledger','LF_SUPABASE_READBACK_V1',
      'profile_assessment_receipt_required',true),
    'compatibility',jsonb_build_object(
      'provider','CAPABILITY_SELECTOR_V1',
      'consumer','CAPABILITY_SELECTOR_COMPOSITION_V2',
      'method_promotion_requires_exact_version_receipt',true),
    'migration',jsonb_build_object(
      'scope','CATALOG_VERSION_POINTER_ONLY',
      'method_qualification',false,
      'profile_runtime_cutover',false),
    'rollback',jsonb_build_object(
      'supported',true,'mode','RESTORE_PREVERSION_IDENTITY_ONLY',
      'runtime_state_untouched',true),
    'usage',jsonb_build_object(
      'read_catalog','READ_ONLY',
      'qualified_methods_available',0,
      'deny_unqualified_by_default',true,
      'allow_runtime_execution',false),
    'currentness',jsonb_build_object(
      'source_commit',v_source_commit,
      'source_blob_sha1',v_source_blob,
      'validator_blob_sha1',v_test_blob,
      'payload_sha256',v_catalog_sha));

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  -- Reversible canary: test the real version insert and pointer promotion
  -- inside a nested exception block, which PostgreSQL rolls back entirely.
  BEGIN
    INSERT INTO public.lf_capability_version_registry (
      capability_code,version,version_major,version_minor,version_patch,release_state,
      supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
    ) VALUES (
      'METHOD_PACK_REGISTRY','1.0.0',1,0,0,'RELEASED',NULL,
      v_manifest,v_manifest_sha,
      'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json',
      'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/skills/profile_creator/evals/profile_method_composition_v1_README.md',
      'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/test_method_pack_registry_v1.py',
      v_exec);
    v_promotion:=public.fn_lf_capability_promote_v1(
      'METHOD_PACK_REGISTRY','1.0.0',NULL,v_exec,
      'Only catalog infrastructure release; zero qualified methods and no runtime activation');
    IF coalesce((v_promotion->>'ready')::boolean,false) IS NOT TRUE THEN
      RAISE EXCEPTION 'BLOCK_PE10_CANARY_PROMOTION:%',v_promotion::text;
    END IF;
    RAISE EXCEPTION 'PE10_VERSION_CANARY_EXPECTED_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'PE10_VERSION_CANARY_EXPECTED_ROLLBACK' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='METHOD_PACK_REGISTRY')
    OR EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='METHOD_PACK_REGISTRY') THEN
    RAISE EXCEPTION 'BLOCK_PE10_VERSION_ROLLBACK_CANARY_RESIDUE';
  END IF;

  INSERT INTO public.lf_capability_version_registry (
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'METHOD_PACK_REGISTRY','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/skills/profile_creator/evals/profile_method_composition_v1_README.md',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/test_method_pack_registry_v1.py',
    v_exec);
  v_promotion:=public.fn_lf_capability_promote_v1(
    'METHOD_PACK_REGISTRY','1.0.0',NULL,v_exec,
    'Catalog infrastructure only; zero qualified methods, subject to separate method evidence qualification');
  IF coalesce((v_promotion->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_PE10_VERSION_PROMOTION:%',v_promotion::text;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry v ON v.capability_code=c.capability_code AND v.version=c.version
    WHERE c.capability_code='METHOD_PACK_REGISTRY' AND c.version='1.0.0'
      AND c.manifest_sha256=v.manifest_sha256
      AND v.manifest->'qualified_method_portfolio'='[]'::jsonb
      AND v.manifest->>'catalog_payload_sha256'=v_catalog_sha
      AND v.manifest->'usage'->>'allow_runtime_execution'='false'
  ) THEN
    RAISE EXCEPTION 'BLOCK_PE10_EMPTY_PORTFOLIO_READBACK';
  END IF;
END $registry_version$;
