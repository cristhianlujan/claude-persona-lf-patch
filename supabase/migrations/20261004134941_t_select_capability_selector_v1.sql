-- T-SELECT / PAULO-184 — CAPABILITY_SELECTOR v1.0.0
-- Repository-bound transversal selector. No active IG runtime cutover.
-- Owner: SUPER_ADMIN.

DO $pre$
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_capability_registry WHERE capability_code='CAPABILITY_SELECTOR') THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_REGISTRY_ALREADY_PRESENT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='CAPABILITY_SELECTOR') THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_VERSION_ALREADY_PRESENT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='CAPABILITY_SELECTOR') THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_CURRENT_ALREADY_PRESENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='TYPED_EVIDENCE_REGISTRY'
      AND version='3.0.0'
      AND manifest_sha256='0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_TYPED_EVIDENCE_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CURRENTNESS_AUTHORITY'
      AND version='1.0.0'
      AND manifest_sha256='9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_CURRENTNESS_AUTHORITY_NOT_CURRENT';
  END IF;
END
$pre$;

DO $register$
DECLARE
  v_execution_id constant text := 'CHATGPT-IG-T-SELECT-PAULO-184-20261004';
  v_source_commit constant text := '3d2e347b6309f55654e9d34ded18dc99d00d262c';
  v_source_blob constant text := 'd0624beacb1ee68b349bfa23a274b52c92d1c9aa';
  v_test_blob constant text := '949ca8f7972fd6dec9885cc0bd6a3a112b2b3eb9';
  v_manifest jsonb;
  v_manifest_sha text;
  v_promote jsonb;
BEGIN
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','CAPABILITY_SELECTOR',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'inputs',jsonb_build_array('signals','catalog','policy'),
      'outputs',jsonb_build_array('selected_capabilities','reasons','fallback_state'),
      'states',jsonb_build_array('CLEAR','MULTI','NO_SIGNAL','CONTRADICTORY','CAPABILITY_FAILURE'),
      'multi_label',true,
      'typed_signal_selection',true,
      'consumer_fallback_required',true,
      'ranking_effect','ORDER_ONLY',
      'confidence_authorizes_execution',false,
      'selection_is_admission',false
    ),
    'delivery',jsonb_build_object(
      'mode','REPOSITORY_BOUND_PURE_PYTHON',
      'runtime_deploy_required',false,
      'active_runtime_cutover',false,
      'source_commit',v_source_commit,
      'source_blob_sha1',v_source_blob,
      'test_blob_sha1',v_test_blob
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'runtime_deploy_required',false
    ),
    'dependencies',jsonb_build_object(
      'typed_evidence_registry',jsonb_build_object(
        'capability_code','TYPED_EVIDENCE_REGISTRY',
        'version','3.0.0',
        'manifest_sha256','0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da'
      ),
      'currentness_authority',jsonb_build_object(
        'capability_code','CURRENTNESS_AUTHORITY',
        'version','1.0.0',
        'manifest_sha256','9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09'
      )
    ),
    'compatibility',jsonb_build_object(
      'provider_contract','CAPABILITY_SELECTOR_V1',
      'consumer_policy_external',true,
      'selection_admission_separated',true,
      'active_runtime_cutover',false
    ),
    'migration',jsonb_build_object(
      'id','T_SELECT_CAPABILITY_SELECTOR_V1',
      'mode','CAPABILITY_REGISTRY_AND_CURRENT_POINTER_ONLY',
      'runtime_cutover',false
    ),
    'consumer_proofs',jsonb_build_object(
      'non_domain_fixture','sandbox/lf_contract_gate_test/transversal_assets/capability_selector/non_ig_consumer_fixture_v1.json',
      'ig_binding_policy','sandbox/lf_contract_gate_test/transversal_assets/capability_selector/ig_consumer_binding_v1.json',
      'shared_provider','sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v1.py',
      'special_domain_branch',false
    ),
    'safety_boundary',jsonb_build_object(
      'safe_change_admission_duplicated',false,
      'authority_decision_owned',false,
      'materiality_decision_owned',false,
      'reversibility_decision_owned',false,
      'execution_permission_owned',false
    ),
    'qualification',jsonb_build_object(
      'observation','PASS_CAPABILITY_SELECTOR_V1 checks=17 states=5 consumers=2 domain_branches=0',
      'provider_domain_branches',0,
      'states_covered',5,
      'consumers_covered',2
    ),
    'usage',jsonb_build_object(
      'call','select_capabilities(signals,catalog,policy)',
      'consumer_supplies_catalog',true,
      'consumer_supplies_fallback',true,
      'selected_capabilities_are_execution_permission',false
    ),
    'currentness',jsonb_build_object(
      'source_event','event://20170',
      'transversalization_event','event://20265',
      'source_commit',v_source_commit,
      'source_blob_sha1',v_source_blob,
      'validator_blob_sha1',v_test_blob
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'mode','REMOVE_CURRENT_VERSION_AND_REGISTRY_ROWS',
      'runtime_state_untouched',true
    )
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'CAPABILITY_SELECTOR','Capability Selector','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic typed-signal capability selector. Selection is separate from execution permission and safe-change admission.',
    v_execution_id,v_execution_id,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'CAPABILITY_SELECTOR','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/test_capability_selector_v1.py',
    v_execution_id
  );

  v_promote := public.fn_lf_capability_promote_v1(
    'CAPABILITY_SELECTOR','1.0.0',NULL,v_execution_id,
    'T-SELECT generic selector qualified with non-IG and IG consumer policies; repository-bound, no runtime cutover.'
  );

  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_PROMOTION:%',v_promote::text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='CAPABILITY_SELECTOR'
      AND capability_kind='TRANSVERSAL'
      AND owner_scope='SUPER_ADMIN'
      AND status='ACTIVE'
      AND entry_guard_required IS FALSE
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_REGISTRY_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CAPABILITY_SELECTOR'
      AND version='1.0.0'
      AND manifest_sha256=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_CURRENT_READBACK';
  END IF;
END
$register$;
