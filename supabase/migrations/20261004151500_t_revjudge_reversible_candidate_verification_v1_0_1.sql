-- T-REVJUDGE / PAULO-191 — REVERSIBLE_CANDIDATE_VERIFICATION v1.0.1
-- Supersedes v1.0.0 by enforcing INDEPENDENT_ASSURANCE receipt validation at call time.
-- Repository-bound provider only. No candidate promotion, runtime activation, or cutover.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION'
      AND version='1.0.0'
      AND manifest_sha256='394518804a92123d410348cdba4af570481f3922bd8fc9d6e2a7916a1b860815'
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_V100_NOT_CURRENT'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.lf_capability_version_registry
    WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION' AND version='1.0.1'
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_V101_ALREADY_PRESENT'; END IF;
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

DO $release$
DECLARE
  v_exec constant text := 'CHATGPT-IG-T-REVJUDGE-PAULO-191-20261004';
  v_source_commit constant text := '761957a35f439136a4f9014cf73ec91d2bd4d236';
  v_source_blob constant text := 'b48e962d07c3a02641143765daa0c43797d8d59d';
  v_test_blob constant text := '1e2b012a45ccd21963bb2bc4f93c0330200b72ef';
  v_ig_adapter_blob constant text := 'feb877298f7064f69cf8312b241daa49b60e5111';
  v_ig_oracle_blob constant text := '964eab08b75868b2fdfe4a035dd40f46e63b6575';
  v_non_ig_adapter_blob constant text := 'e87253f0037a1b80648ea4f0816b6c0435c9f55c';
  v_docs_blob constant text := '444caf45d1ea40b7b04e48551395d37bd7754274';
  v_manifest jsonb;
  v_manifest_sha text;
  v_promote jsonb;
BEGIN
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','REVERSIBLE_CANDIDATE_VERIFICATION',
    'version','1.0.1',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'inputs',jsonb_build_array('candidate_identity','flow_adapter','baseline_oracle','rollback_contract'),
      'baseline_oracle_contract',jsonb_build_object(
        'independent_assurance_receipt_required',true,
        'required_capability_code','INDEPENDENT_ASSURANCE',
        'required_version','1.0.0',
        'required_manifest_sha256','a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8',
        'required_state','INDEPENDENT',
        'required_dimensions',jsonb_build_array('dependency','data','author'),
        'tamper_evident_measurement_digest',true,
        'missing_or_unproven_behavior','BLOCK_BEFORE_CANDIDATE_EXECUTION'
      ),
      'outputs',jsonb_build_array('verdict','findings','oracle_result','adapter_receipt','rollback_exact','material_residue_count','independent_assurance'),
      'verdicts',jsonb_build_array('PASS','BLOCK'),
      'mutation_policy','ROLLBACK_ONLY',
      'baseline_before_candidate',true,
      'candidate_via_adapter_only',true,
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
      'ig_adapter_blob_sha1',v_ig_adapter_blob,
      'ig_oracle_blob_sha1',v_ig_oracle_blob,
      'non_ig_adapter_blob_sha1',v_non_ig_adapter_blob,
      'docs_blob_sha1',v_docs_blob
    ),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'runtime_deploy_required',false),
    'dependencies',jsonb_build_object(
      'migration_source_parity',jsonb_build_object('capability_code','MIGRATION_SOURCE_PARITY','version','1.0.0','manifest_sha256','39bb96aa3668c9e82af061f80be658c093545c918ee8a18cc24c21c423df257e'),
      'runtime_deploy_verification',jsonb_build_object('capability_code','RUNTIME_DEPLOY_VERIFICATION','version','1.0.0','manifest_sha256','ee733461092d956da32ccd27607c0600a8d954a820a05feeae8a0e4fa3b779b9','applicability','READBACK_AUTHORITY_REUSED; RUNTIME_DEPLOY_NOT_REQUIRED_FOR_REPOSITORY_BOUND_PROVIDER'),
      'independent_assurance',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','version','1.0.0','manifest_sha256','a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8','consumption','REQUIRED_RECEIPT_FAIL_CLOSED')
    ),
    'compatibility',jsonb_build_object(
      'domain_agnostic_provider',true,
      'ig_role','CONSUMER_ADAPTER',
      'n9_preserved',true,
      'provider_knows_curator_validator_screens_families',false,
      'second_flow_adapter_required',true,
      'special_domain_branch_in_provider',false,
      'oracle_physically_separate_from_ig_adapter',true,
      'independence_label_without_receipt','BLOCK'
    ),
    'migration',jsonb_build_object('id','T_REVJUDGE_REVERSIBLE_CANDIDATE_VERIFICATION_V1_0_1','mode','CAPABILITY_VERSION_AND_CURRENT_POINTER_ONLY','runtime_cutover',false),
    'rollback',jsonb_build_object('supported',true,'mode','PROMOTE_PREVIOUS_VERSION_1_0_0','runtime_state_untouched',true),
    'usage',jsonb_build_object(
      'call','verify_candidate(candidate_identity, flow_adapter, baseline_oracle, rollback_contract)',
      'promotion_authorized',false,
      'activation_authorized',false,
      'flow_adapter_owns_domain_execution',true,
      'oracle_supplied_separately',true,
      'independent_assurance_receipt_checked_before_adapter',true
    ),
    'currentness',jsonb_build_object('source_event','event://20170','transversalization_event','event://20265','source_commit',v_source_commit,'source_blob_sha1',v_source_blob,'test_blob_sha1',v_test_blob),
    'qualification',jsonb_build_object(
      'observation','PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=8 non_ig=3 ig=2 independence_gate=3 rollback_exact=4 negative_detected=5 domain_branches_in_core=0',
      'n9_contract','lf_eventos#19824',
      'n9_positive','PR1460/job110660596974',
      'n9_negative','PR1459/job110658154758',
      'n9_rollback_residue',0,
      'non_ig_positive',true,
      'non_ig_negative',true,
      'rollback_failure_blocks',true,
      'independent_assurance_missing_blocks',true,
      'not_independent_blocks',true,
      'tampered_assurance_receipt_blocks',true,
      't_indep_negative_shared_dependencies_observed',jsonb_build_array('fn_v09_canonical_jsonb_text','fn_v09_sha256_jsonb')
    ),
    'supersession_reason','v1.0.0 pinned INDEPENDENT_ASSURANCE but did not enforce a receipt at call time; v1.0.1 closes that fail-open gap.'
  );
  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'REVERSIBLE_CANDIDATE_VERIFICATION','1.0.1',1,0,1,'RELEASED','1.0.0',
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/reversible_candidate_verification_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/test_reversible_candidate_verification_v1.py',
    v_exec
  );

  v_promote := public.fn_lf_capability_promote_v1('REVERSIBLE_CANDIDATE_VERIFICATION','1.0.1','394518804a92123d410348cdba4af570481f3922bd8fc9d6e2a7916a1b860815',v_exec,'T-REVJUDGE v1.0.1 enforces INDEPENDENT_ASSURANCE receipt; no candidate/runtime promotion or cutover.');
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_V101_PROMOTION:%',v_promote::text;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION' AND version='1.0.1' AND manifest_sha256=v_manifest_sha
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_V101_CURRENT_READBACK'; END IF;
END
$release$;
