-- LF_S31_CURRENTNESS_AUTHORITY_REGISTRY_V1
-- Source-first registry materialization only. No current-pointer promotion.
-- Canonical S31 source revision: b533f7f4e721d04822359a75f19a82949e799faf

do $lf_s31$
declare
  v_manifest jsonb := $manifest${"schema_version":"LF_CAPABILITY_MANIFEST_V1","capability_code":"CURRENTNESS_AUTHORITY","version":"1.0.0","contract":{"input":"LF_MATERIAL_CURRENTNESS_BINDING_V1_PLUS_GOVERNED_COMPATIBILITY","output":"LF_CURRENTNESS_AUTHORITY_RECEIPT_V1"},"delivery":{"mode":"VERSIONED_REPOSITORY_CAPABILITY","workflow":".github/workflows/lf-material-currentness.yml"},"installation":{"required":false,"reinstall_required":false,"package_update_mode":"REPOSITORY_BOUND"},"dependencies":{"packages":["python>=3.11","git"],"capabilities":[],"existing_binder":"public.fn_lf_capability_bind_current_v1"},"compatibility":{"mid_execution_rebind":false,"auto_rebind_when_dependency_completeness_complete":true,"compatible_contract_change":"BOUNDED_VALIDATION","breaking_change":"SELECTIVE_AFFECTED_CLOSURE","unknown_dependency":"FAIL_CLOSED","missing_compatibility_assessment":"UNKNOWN_FAIL_CLOSED","proof_context_schema":"LF_COMPATIBILITY_PROOF_CONTEXT_V1"},"evidence":{"source_attestation_authority_level":"CANDIDATE_LOCAL_INTEGRITY","expected_repo_and_authority_ref_required":true,"binding_context_required":true,"material_fingerprints_recomputed_offline":true,"durable_evidence_anchor_required_before_authoritative_cutover":true,"durable_evidence_owner":"EVIDENCE_LEDGER","durable_evidence_integration_mode":"SEPARATE_EXCLUSIVE_PR"},"migration":{"id":"S31_CURRENTNESS_AUTHORITY_V1","zero_step":"SAFE_REBIND_AFTER_CURRENTNESS_AUTHORITY","material_started":"PIN_OR_REVALIDATE_AFFECTED_CLOSURE","execution_row_mutation":false},"rollback":{"supported":true,"target":null,"pointer_only":true,"rule":"DO_NOT_REMOVE_LEGACY_SHA_GUARD_UNTIL_MATERIAL_AWARE_REPLACEMENT_IS_PROVEN"},"usage":{"evaluate":"sandbox/lf_contract_gate_test/material_currentness/lf_currentness_authority_v1.py","attest":"sandbox/lf_contract_gate_test/material_currentness/lf_source_attestation_v1.py","broker_bridge":"sandbox/lf_contract_gate_test/material_currentness/lf_broker_currentness_bridge_v1.py","bind_after_current_rebound":"public.fn_lf_capability_bind_current_v1"},"currentness":{"authority_ref":"refs/heads/main","decision_vocabulary":["CURRENT","CURRENT_REBOUND","STALE_AFFECTED","UNKNOWN_FAIL_CLOSED"],"dependency_completeness_required_for_auto_rebind":"COMPLETE","evidence_revision_immutable":true,"global_main_sha_change_alone_causes_stale":false,"source_attestation_reusable_offline":true,"required_before_material_write":true}}$manifest$::jsonb;
  v_expected_manifest_sha text;
  v_actual_manifest_sha text;
  v_count bigint;
begin
  if not exists (
    select 1
    from public.lf_operation_execution
    where execution_id = 'EXEC-S31-CURRENTNESS-AUTHORITY-REGISTRY-20260914-001'
      and operation_code = 'ACTUALIZACION_DB_LF'
      and target_type = 'MIGRATION'
      and target_code = 'S31_CURRENTNESS_AUTHORITY_REGISTRY_V1'
      and target_repo = 'cristhianlujan/claude-persona-lf-patch'
      and target_path = 'supabase/migrations/20260914162000_lf_s31_currentness_authority_registry_v1.sql'
      and status = 'IN_PROGRESS'
  ) then
    raise exception 'BLOCK_S31_REGISTRY_EXECUTION_BINDING';
  end if;

  if to_regprocedure('public.fn_lf_capability_bind_current_v1(text,text,text,text)') is null then
    raise exception 'BLOCK_S31_BINDER_NOT_FOUND';
  end if;

  if exists (
    select 1 from public.lf_capability_current
    where capability_code = 'CURRENTNESS_AUTHORITY'
  ) then
    raise exception 'BLOCK_S31_PREMATURE_CURRENT_POINTER';
  end if;

  insert into public.lf_capability_registry(
    capability_code, capability_name, capability_kind, owner_scope, status,
    description, created_by_execution_id, updated_by_execution_id
  )
  values(
    'CURRENTNESS_AUTHORITY',
    'CURRENTNESS_AUTHORITY',
    'TRANSVERSAL',
    'LF_GOVERNANCE_S31',
    'ACTIVE',
    'Material/dependency-aware currentness authority. Registration does not authorize runtime, production, Golden, Broker cutover or current-pointer promotion.',
    'EXEC-S31-CURRENTNESS-AUTHORITY-REGISTRY-20260914-001',
    'EXEC-S31-CURRENTNESS-AUTHORITY-REGISTRY-20260914-001'
  )
  on conflict (capability_code) do nothing;

  if not exists (
    select 1
    from public.lf_capability_registry
    where capability_code='CURRENTNESS_AUTHORITY'
      and capability_name='CURRENTNESS_AUTHORITY'
      and capability_kind='TRANSVERSAL'
      and owner_scope='LF_GOVERNANCE_S31'
      and status='ACTIVE'
  ) then
    raise exception 'BLOCK_S31_CAPABILITY_REGISTRY_DRIFT';
  end if;

  v_expected_manifest_sha := encode(extensions.digest(v_manifest::text, 'sha256'), 'hex');

  if not exists (
    select 1
    from public.lf_capability_version_registry
    where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0'
  ) then
    insert into public.lf_capability_version_registry(
      capability_code, version, version_major, version_minor, version_patch,
      release_state, supersedes_version, manifest, manifest_sha256,
      source_ref, docs_ref, validator_ref, created_by_execution_id
    )
    values(
      'CURRENTNESS_AUTHORITY','1.0.0',1,0,0,
      'RELEASED',null,v_manifest,v_expected_manifest_sha,
      'github://cristhianlujan/claude-persona-lf-patch@b533f7f4e721d04822359a75f19a82949e799faf/sandbox/lf_contract_gate_test/material_currentness/CURRENTNESS_AUTHORITY_v1.manifest.json',
      'github://cristhianlujan/claude-persona-lf-patch@b533f7f4e721d04822359a75f19a82949e799faf/sandbox/lf_contract_gate_test/material_currentness/README.md',
      'github://cristhianlujan/claude-persona-lf-patch@b533f7f4e721d04822359a75f19a82949e799faf/sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py',
      'EXEC-S31-CURRENTNESS-AUTHORITY-REGISTRY-20260914-001'
    );
  end if;

  select manifest_sha256 into v_actual_manifest_sha
  from public.lf_capability_version_registry
  where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0';

  if v_actual_manifest_sha is distinct from v_expected_manifest_sha then
    raise exception 'BLOCK_S31_MANIFEST_SHA_DRIFT expected=% actual=%',
      v_expected_manifest_sha, v_actual_manifest_sha;
  end if;

  if not exists (
    select 1
    from public.lf_capability_version_registry
    where capability_code='CURRENTNESS_AUTHORITY'
      and version='1.0.0'
      and release_state='RELEASED'
      and manifest=v_manifest
      and source_ref='github://cristhianlujan/claude-persona-lf-patch@b533f7f4e721d04822359a75f19a82949e799faf/sandbox/lf_contract_gate_test/material_currentness/CURRENTNESS_AUTHORITY_v1.manifest.json'
      and docs_ref='github://cristhianlujan/claude-persona-lf-patch@b533f7f4e721d04822359a75f19a82949e799faf/sandbox/lf_contract_gate_test/material_currentness/README.md'
      and validator_ref='github://cristhianlujan/claude-persona-lf-patch@b533f7f4e721d04822359a75f19a82949e799faf/sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py'
      and created_by_execution_id='EXEC-S31-CURRENTNESS-AUTHORITY-REGISTRY-20260914-001'
  ) then
    raise exception 'BLOCK_S31_CAPABILITY_VERSION_DRIFT';
  end if;

  select count(*) into v_count
  from public.lf_capability_current
  where capability_code='CURRENTNESS_AUTHORITY';

  if v_count <> 0 then
    raise exception 'BLOCK_S31_CURRENT_POINTER_CREATED';
  end if;
end
$lf_s31$;
