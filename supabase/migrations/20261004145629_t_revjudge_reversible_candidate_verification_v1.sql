-- T-REVJUDGE / PAULO-191 — REVERSIBLE_CANDIDATE_VERIFICATION v1.0.0
-- Repository-bound verification capability. No promotion/cutover of candidates.

DO $pre$
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_capability_registry WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION')
     OR EXISTS (SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION')
     OR EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION') THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_ALREADY_PRESENT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='MIGRATION_SOURCE_PARITY' AND version='1.0.0' AND manifest_sha256='39bb96aa3668c9e82af061f80be658c093545c918ee8a18cc24c21c423df257e') THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_MIGRATION_SOURCE_PARITY_NOT_CURRENT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='RUNTIME_DEPLOY_VERIFICATION' AND version='1.0.0' AND manifest_sha256='ee733461092d956da32ccd27607c0600a8d954a820a05feeae8a0e4fa3b779b9') THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_RUNTIME_DEPLOY_VERIFICATION_NOT_CURRENT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='INDEPENDENT_ASSURANCE' AND version='1.0.0' AND manifest_sha256='a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8') THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_INDEPENDENT_ASSURANCE_NOT_CURRENT';
  END IF;
END
$pre$;

DO $register$
DECLARE
  v_exec constant text := 'CHATGPT-IG-T-REVJUDGE-PAULO-191-20261004';
  v_source_commit constant text := 'c89058877bca0a50b6d219f7129065e12f18c66b';
  v_source_blob constant text := 'fe9f488029d9f5c96e254b0d5895972e45a8855b';
  v_test_blob constant text := '2b21b63690638ade8e948472e0ca0b6a7367d72f';
  v_ig_adapter_blob constant text := 'bf49ab1b5195b90f50017bf9417b0977994a7a58';
  v_manifest jsonb;
  v_manifest_sha text;
  v_promote jsonb;
BEGIN
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','REVERSIBLE_CANDIDATE_VERIFICATION',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'inputs',jsonb_build_array('candidate_identity','flow_adapter','baseline_oracle','rollback_contract'),
      'outputs',jsonb_build_array('verdict','findings','oracle_result','adapter_receipt','rollback_exact','material_residue_count'),
      'verdicts',jsonb_build_array('PASS','BLOCK'),
      'mutation_policy','ROLLBACK_ONLY',
      'baseline_before_candidate',true,
      'candidate_via_adapter_only',true,
      'independent_oracle_required',true,
      'exact_post_rollback_digest_required',true,
      'zero_material_residue_required',true,
      'rollback_failure','BLOCK',
      'candidate_evidence_grants_activation',false
    ),
    'delivery',jsonb_build_object(
      'mode','REPOSITORY_BOUND_PYTHON_PROVIDER',
      'runtime_deploy_required',false,
      'active_runtime_cutover',false,
      'source_commit',v_source_commit,
      'source_blob_sha1',v_source_blob,
      'test_blob_sha1',v_test_blob,
      'ig_adapter_blob_sha1',v_ig_adapter_blob
    ),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'runtime_deploy_required',false),
    'dependencies',jsonb_build_object(
      'migration_source_parity',jsonb_build_object('capability_code','MIGRATION_SOURCE_PARITY','version','1.0.0','manifest_sha256','39bb96aa3668c9e82af061f80be658c093545c918ee8a18cc24c21c423df257e'),
      'runtime_deploy_verification',jsonb_build_object('capability_code','RUNTIME_DEPLOY_VERIFICATION','version','1.0.0','manifest_sha256','ee733461092d956da32ccd27607c0600a8d954a820a05feeae8a0e4fa3b779b9'),
      'independent_assurance',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','version','1.0.0','manifest_sha256','a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8')
    ),
    'compatibility',jsonb_build_object(
      'domain_agnostic_provider',true,
      'ig_role','CONSUMER_ADAPTER',
      'n9_preserved',true,
      'provider_knows_curator_validator_screens_families',false,
      'second_flow_adapter_required',true,
      'special_domain_branch_in_provider',false
    ),
    'migration',jsonb_build_object('id','T_REVJUDGE_REVERSIBLE_CANDIDATE_VERIFICATION_V1','mode','CAPABILITY_REGISTRY_AND_CURRENT_POINTER_ONLY','runtime_cutover',false),
    'rollback',jsonb_build_object('supported',true,'mode','REMOVE_CURRENT_VERSION_AND_REGISTRY_ROWS','runtime_state_untouched',true),
    'usage',jsonb_build_object(
      'call','verify_candidate(candidate_identity, flow_adapter, baseline_oracle, rollback_contract)',
      'promotion_authorized',false,
      'activation_authorized',false,
      'flow_adapter_owns_domain_execution',true,
      'oracle_supplied_separately',true
    ),
    'currentness',jsonb_build_object('source_event','event://20170','transversalization_event','event://20265','source_commit',v_source_commit,'source_blob_sha1',v_source_blob,'test_blob_sha1',v_test_blob),
    'qualification',jsonb_build_object(
      'observation','PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=5 non_ig=3 ig=2 rollback_exact=4 negative_detected=2 domain_branches_in_core=0',
      'n9_positive','PR1460/job110660596974',
      'n9_negative','PR1459/job110658154758',
      'n9_rollback_residue',0,
      'non_ig_positive',true,
      'non_ig_negative',true,
      'rollback_failure_blocks',true
    )
  );
  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'REVERSIBLE_CANDIDATE_VERIFICATION','Reversible Candidate Verification','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic rollback-only candidate verification with adapter execution, independent oracle, exact post-rollback digest and zero material residue.',
    v_exec,v_exec,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'REVERSIBLE_CANDIDATE_VERIFICATION','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/reversible_candidate_verification_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/test_reversible_candidate_verification_v1.py',
    v_exec
  );

  v_promote := public.fn_lf_capability_promote_v1('REVERSIBLE_CANDIDATE_VERIFICATION','1.0.0',NULL,v_exec,'T-REVJUDGE qualified generic provider with preserved N-9 IG adapter and second non-IG flow adapter; no cutover.');
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_PROMOTION:%',v_promote::text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION' AND version='1.0.0' AND manifest_sha256=v_manifest_sha) THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_CURRENT_READBACK';
  END IF;
END
$register$;
