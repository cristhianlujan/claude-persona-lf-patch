-- S31 CURRENTNESS_AUTHORITY v1 registry projection.
-- Source-only candidate. Do not apply before canonical source merge/currentness gate.
-- No runtime, production, Golden or scheduler activation is authorized by this migration source.

insert into public.lf_capability_registry(
  capability_code, capability_name, capability_kind, owner_scope, status, description,
  created_by_execution_id, updated_by_execution_id
)
values (
  'CURRENTNESS_AUTHORITY',
  'LF Currentness Authority',
  'TRANSVERSAL',
  'LF_GOVERNANCE_S31',
  'ACTIVE',
  'Material-aware source currentness authority that separates moving refs, immutable evidence revisions, declared dependency graphs and governed compatibility evidence.',
  'EXEC-S31-CURRENTNESS-AUTHORITY-20260914',
  'EXEC-S31-CURRENTNESS-AUTHORITY-20260914'
)
on conflict (capability_code) do nothing;

insert into public.lf_capability_version_registry(
  capability_code, version, version_major, version_minor, version_patch,
  release_state, supersedes_version, manifest, manifest_sha256,
  source_ref, docs_ref, validator_ref, created_by_execution_id
)
values (
  'CURRENTNESS_AUTHORITY','1.0.0',1,0,0,'RELEASED',null,
  $manifest${
    "schema_version":"LF_CAPABILITY_MANIFEST_V1",
    "capability_code":"CURRENTNESS_AUTHORITY",
    "version":"1.0.0",
    "contract":{"input":"LF_MATERIAL_CURRENTNESS_BINDING_V1_PLUS_GOVERNED_COMPATIBILITY","output":"LF_CURRENTNESS_AUTHORITY_RECEIPT_V1"},
    "delivery":{"mode":"VERSIONED_REPOSITORY_CAPABILITY","workflow":".github/workflows/lf-material-currentness.yml"},
    "installation":{"required":false,"reinstall_required":false,"package_update_mode":"REPOSITORY_BOUND"},
    "dependencies":{"packages":["python>=3.11","git"],"capabilities":[],"existing_binder":"public.fn_lf_capability_bind_current_v1"},
    "compatibility":{"mid_execution_rebind":false,"auto_rebind_when_dependency_completeness_complete":true,"compatible_contract_change":"BOUNDED_VALIDATION","breaking_change":"SELECTIVE_AFFECTED_CLOSURE","unknown_dependency":"FAIL_CLOSED"},
    "migration":{"id":"S31_CURRENTNESS_AUTHORITY_V1","zero_step":"SAFE_REBIND_AFTER_CURRENTNESS_AUTHORITY","material_started":"PIN_OR_REVALIDATE_AFFECTED_CLOSURE","execution_row_mutation":false},
    "rollback":{"supported":true,"target":null,"pointer_only":true,"rule":"DO_NOT_REMOVE_LEGACY_SHA_GUARD_UNTIL_MATERIAL_AWARE_REPLACEMENT_IS_PROVEN"},
    "usage":{"evaluate":"sandbox/lf_contract_gate_test/material_currentness/lf_currentness_authority_v1.py","attest":"sandbox/lf_contract_gate_test/material_currentness/lf_source_attestation_v1.py","broker_bridge":"sandbox/lf_contract_gate_test/material_currentness/lf_broker_currentness_bridge_v1.py","bind_after_current_rebound":"public.fn_lf_capability_bind_current_v1"},
    "currentness":{"authority_ref":"refs/heads/main","decision_vocabulary":["CURRENT","CURRENT_REBOUND","STALE_AFFECTED","UNKNOWN_FAIL_CLOSED"],"dependency_completeness_required_for_auto_rebind":"COMPLETE","evidence_revision_immutable":true,"global_main_sha_change_alone_causes_stale":false,"source_attestation_reusable_offline":true,"required_before_material_write":true}
  }$manifest$::jsonb,
  repeat('0',64),
  'github://cristhianlujan/claude-persona-lf-patch@e05f3349fee188166b6bbc278ecf8cf23381f3f6/sandbox/lf_contract_gate_test/material_currentness/CURRENTNESS_AUTHORITY_v1.manifest.json',
  'github://cristhianlujan/claude-persona-lf-patch@e05f3349fee188166b6bbc278ecf8cf23381f3f6/sandbox/lf_contract_gate_test/material_currentness/LF_MATERIAL_CURRENTNESS_CONTRACT_V1.json',
  'github://cristhianlujan/claude-persona-lf-patch@e05f3349fee188166b6bbc278ecf8cf23381f3f6/sandbox/lf_contract_gate_test/material_currentness/lf_currentness_authority_v1.py',
  'EXEC-S31-CURRENTNESS-AUTHORITY-20260914'
)
on conflict (capability_code, version) do nothing;

-- Promotion is intentionally part of the canonical migration, but this file must not be
-- applied from an unmerged branch. The existing binder remains the only binding mutator.
do $$
declare
  v_result jsonb;
begin
  if not exists (
    select 1 from public.lf_capability_current where capability_code='CURRENTNESS_AUTHORITY'
  ) then
    select public.fn_lf_capability_promote_v1(
      'CURRENTNESS_AUTHORITY','1.0.0',null,
      'EXEC-S31-CURRENTNESS-AUTHORITY-20260914',
      'S31 material-aware currentness authority v1 canonical projection'
    ) into v_result;
    if coalesce((v_result->>'ready')::boolean,false) is not true then
      raise exception 'CURRENTNESS_AUTHORITY_PROMOTION_BLOCKED: %', v_result;
    end if;
  end if;
end $$;
