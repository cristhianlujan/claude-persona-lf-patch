-- PROFILE_EVOLUTION_CAPABILITIES_V1
-- Registers transversal building blocks. No ACTUALIZACION_PERFIL_LF cutover.
-- Source qualification must pass before this migration is applied.

do $m$
declare
  v_exec constant text := 'EXEC-PROFILE-EVOLUTION-CAPABILITIES-V1-20261007';
  v_manifest jsonb;
  v_sha text;
  v_promote jsonb;
begin
  if not exists (
    select 1 from public.lf_capability_current
    where capability_code='TYPED_EVIDENCE_REGISTRY' and version='3.0.0'
  ) then raise exception 'BLOCK_PROFILE_EVOLUTION_TYPED_EVIDENCE_NOT_CURRENT'; end if;
  if not exists (
    select 1 from public.lf_capability_current
    where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0'
  ) then raise exception 'BLOCK_PROFILE_EVOLUTION_CURRENTNESS_NOT_CURRENT'; end if;
  if not exists (
    select 1 from public.lf_capability_current
    where capability_code='CAPABILITY_SELECTOR' and version='1.0.0'
  ) then raise exception 'BLOCK_PROFILE_EVOLUTION_SELECTOR_BASE_NOT_CURRENT'; end if;

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'PROFILE_ASSESSMENT','Profile Assessment','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Evidence-bound profile maturity/gap assessment separated from structural compatibility. Selection support only; no write authority.',
    v_exec,v_exec,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) on conflict (capability_code) do nothing;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','PROFILE_ASSESSMENT','version','1.0.0',
    'contract',jsonb_build_object(
      'inputs',jsonb_build_array('evidence','signals'),
      'outputs',jsonb_build_array('maturity','structural_compatibility','profile_gaps','evolution_mode','typed_signals','uncertainty','risk'),
      'maturity_states',jsonb_build_array('GENERIC','SPECIALIZED','ADAPTIVE','EXPERT','EVIDENCE_OPTIMIZED'),
      'evolution_modes',jsonb_build_array('NO_CHANGE','PATCH','SPECIALIZE','ADAPT','REARCHITECT','OPTIMIZE'),
      'evidence_bound',true,'write_authority',false
    ),
    'delivery',jsonb_build_object('mode','REPOSITORY_BOUND_PURE_PYTHON','runtime_deploy_required',false,'active_runtime_cutover',false),
    'installation',jsonb_build_object('required',false,'runtime_deploy_required',false),
    'dependencies',jsonb_build_object('typed_evidence_registry','3.0.0','currentness_authority','1.0.0'),
    'compatibility',jsonb_build_object('structural_baseline_separate',true,'selection_admission_separated',true),
    'migration',jsonb_build_object('id','PROFILE_EVOLUTION_CAPABILITIES_V1','runtime_cutover',false),
    'rollback',jsonb_build_object('supported',true,'runtime_state_untouched',true),
    'usage',jsonb_build_object('call','assess_profile(payload)','execution_permission',false),
    'currentness',jsonb_build_object(
      'source_ref','github://cristhianlujan/claude-persona-lf-patch@a21eb7c3416425be071272fe1dafea7bc44878d8/sandbox/lf_contract_gate_test/transversal_assets/profile_assessment/profile_assessment_v1.py',
      'validator_ref','github://cristhianlujan/claude-persona-lf-patch@fef7e31a73ccdab7dbb8e12c4108eaebffebcc46/sandbox/lf_contract_gate_test/transversal_assets/profile_assessment/test_profile_assessment_v1.py'
    )
  );
  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'PROFILE_ASSESSMENT','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_sha,
    v_manifest#>>'{currentness,source_ref}',
    'github://cristhianlujan/claude-persona-lf-patch/skills/profile_creator/contracts/profile_evolution_orchestrator_v1.json',
    v_manifest#>>'{currentness,validator_ref}',v_exec
  ) on conflict (capability_code,version) do nothing;
  v_promote:=public.fn_lf_capability_promote_v1('PROFILE_ASSESSMENT','1.0.0',null,v_exec,'Profile Evolution E1 qualified transversal assessment.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_PROFILE_ASSESSMENT_PROMOTION:%',v_promote::text;
  end if;

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'METHOD_PACK_REGISTRY','Method Pack Registry','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Governed registry of selectable reasoning/search/optimization methods with typed signals, preconditions, cost, risk, stops and validation.',
    v_exec,v_exec,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) on conflict (capability_code) do nothing;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','METHOD_PACK_REGISTRY','version','1.0.0',
    'contract',jsonb_build_object(
      'inputs',jsonb_build_array('typed_signals','method_catalog'),
      'outputs',jsonb_build_array('eligible_methods','preconditions','cost','risk','stop_conditions','validation_method'),
      'execution_permission',false,'auto_promote_learning',false
    ),
    'delivery',jsonb_build_object('mode','REPOSITORY_BOUND_REGISTRY','runtime_deploy_required',false,'active_runtime_cutover',false),
    'installation',jsonb_build_object('required',false,'runtime_deploy_required',false),
    'dependencies',jsonb_build_object('capability_selector','1.0.0'),
    'compatibility',jsonb_build_object('srcr_consumer_not_owner',true,'domain_names_are_not_selectors',true),
    'migration',jsonb_build_object('id','PROFILE_EVOLUTION_CAPABILITIES_V1','runtime_cutover',false),
    'rollback',jsonb_build_object('supported',true,'runtime_state_untouched',true),
    'usage',jsonb_build_object('registry_path','sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json','selection_is_admission',false),
    'currentness',jsonb_build_object(
      'source_ref','github://cristhianlujan/claude-persona-lf-patch@2165f3428eef1267186e7e06e1989502e3c93c31/sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json',
      'validator_ref','github://cristhianlujan/claude-persona-lf-patch@2165f3428eef1267186e7e06e1989502e3c93c31/sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/test_method_pack_registry_v1.py'
    )
  );
  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'METHOD_PACK_REGISTRY','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_sha,
    v_manifest#>>'{currentness,source_ref}',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/README.md',
    v_manifest#>>'{currentness,validator_ref}',v_exec
  ) on conflict (capability_code,version) do nothing;
  v_promote:=public.fn_lf_capability_promote_v1('METHOD_PACK_REGISTRY','1.0.0',null,v_exec,'Profile Evolution E2 qualified governed method registry.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_METHOD_PACK_REGISTRY_PROMOTION:%',v_promote::text;
  end if;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','CAPABILITY_SELECTOR','version','1.1.0',
    'contract',jsonb_build_object(
      'v1_select_capabilities_unchanged',true,
      'composition_call','compose_capabilities(context,catalog,policy,method_registry)',
      'context_fields',jsonb_build_array('profile_gaps','task_family','complexity','novelty','uncertainty','causal_requirement','risk','repeated_pattern','evidence_sufficiency','budget'),
      'outputs',jsonb_build_array('selected_capabilities','method_requirements','composition_order','reason','estimated_cost','escalation_conditions','fallback_state'),
      'execution_permission',false,'admission_required',true
    ),
    'delivery',jsonb_build_object('mode','REPOSITORY_BOUND_PURE_PYTHON','runtime_deploy_required',false,'active_runtime_cutover',false),
    'installation',jsonb_build_object('required',false,'runtime_deploy_required',false),
    'dependencies',jsonb_build_object('typed_evidence_registry','3.0.0','currentness_authority','1.0.0','method_pack_registry','1.0.0'),
    'compatibility',jsonb_build_object('provider_contract_v1_preserved',true,'selection_admission_separated',true),
    'migration',jsonb_build_object('id','PROFILE_EVOLUTION_CAPABILITIES_V1','runtime_cutover',false),
    'rollback',jsonb_build_object('supported',true,'previous_version','1.0.0','runtime_state_untouched',true),
    'usage',jsonb_build_object('legacy_call','select_capabilities(signals,catalog,policy)','composition_call','compose_capabilities(context,catalog,policy,method_registry)'),
    'currentness',jsonb_build_object(
      'source_ref','github://cristhianlujan/claude-persona-lf-patch@b9a453c2053bef5a0d421dc8a247052bc5885bb0/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v2.py',
      'validator_ref','github://cristhianlujan/claude-persona-lf-patch@b9a453c2053bef5a0d421dc8a247052bc5885bb0/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/test_capability_selector_v2.py'
    )
  );
  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'CAPABILITY_SELECTOR','1.1.0',1,1,0,'RELEASED','1.0.0',v_manifest,v_sha,
    v_manifest#>>'{currentness,source_ref}',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/README.md',
    v_manifest#>>'{currentness,validator_ref}',v_exec
  ) on conflict (capability_code,version) do nothing;
  v_promote:=public.fn_lf_capability_promote_v1('CAPABILITY_SELECTOR','1.1.0','fd4d6b41303dad446873c9d9d9ad1e3a87461f880f458b68debfcacacb4c1ff3',v_exec,'Profile Evolution E3 composition extension; v1 API preserved.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_CAPABILITY_SELECTOR_1_1_PROMOTION:%',v_promote::text;
  end if;
end
$m$;
