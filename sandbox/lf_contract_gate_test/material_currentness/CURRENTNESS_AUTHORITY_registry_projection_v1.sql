-- S31 CURRENTNESS_AUTHORITY registry projection candidate.
-- NON-MIGRATION SOURCE CANDIDATE. Do not apply before canonical source merge and MIGRATION_LIFECYCLE_LF.
-- No live DB mutation, runtime, production, Golden or scheduler activation is authorized here.
-- __CANONICAL_SOURCE_REVISION__ must be materialized by the governed migration lifecycle after merge.

do $$
begin
  if '__CANONICAL_SOURCE_REVISION__' like '__%__' then
    raise exception 'BLOCK_CURRENTNESS_AUTHORITY_NONCANONICAL_PROJECTION';
  end if;
end $$;

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
  jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','CURRENTNESS_AUTHORITY',
    'version','1.0.0',
    'source_manifest','sandbox/lf_contract_gate_test/material_currentness/CURRENTNESS_AUTHORITY_v1.manifest.json',
    'currentness_contract','sandbox/lf_contract_gate_test/material_currentness/LF_MATERIAL_CURRENTNESS_CONTRACT_V1.json',
    'binder','public.fn_lf_capability_bind_current_v1',
    'global_main_sha_change_alone_causes_stale',false,
    'dependency_completeness_required_for_auto_rebind','COMPLETE'
  ),
  repeat('0',64),
  'github://cristhianlujan/claude-persona-lf-patch@__CANONICAL_SOURCE_REVISION__/sandbox/lf_contract_gate_test/material_currentness/CURRENTNESS_AUTHORITY_v1.manifest.json',
  'github://cristhianlujan/claude-persona-lf-patch@__CANONICAL_SOURCE_REVISION__/sandbox/lf_contract_gate_test/material_currentness/LF_MATERIAL_CURRENTNESS_CONTRACT_V1.json',
  'github://cristhianlujan/claude-persona-lf-patch@__CANONICAL_SOURCE_REVISION__/sandbox/lf_contract_gate_test/material_currentness/lf_currentness_authority_v1.py',
  'EXEC-S31-CURRENTNESS-AUTHORITY-20260914'
)
on conflict (capability_code, version) do nothing;

-- The canonical migration lifecycle must replace the placeholder, derive the real
-- manifest SHA256, verify execution provenance, then use the existing promotion/binding APIs.
