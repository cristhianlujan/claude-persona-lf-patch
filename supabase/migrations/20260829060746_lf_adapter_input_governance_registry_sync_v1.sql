update public.lf_activos
set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'input_governance_binding_contract', 'gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md',
      'input_governance_authority_contract', 'INPUT_READINESS_CONTRACT',
      'input_governance_contract_resolution', 'LIVE_CURRENT',
      'input_governance_observed_revision', '5.12',
      'input_governance_continuation_policy', 'PASS_ONLY',
      'input_governance_receipt_required', true,
      'input_governance_merge_pr', 314,
      'input_governance_main_sha', '08ff31dba7154a662b35d6784ca7740fb7a44faa',
      'input_governance_synced_at', '2026-08-29T06:05:42Z',
      'last_update_operation_code', 'ACTUALIZACION_ADAPTER_INPUT_GOVERNANCE_REGISTRY_SYNC'
    ),
    raw_payload = coalesce(raw_payload, '{}'::jsonb) || jsonb_build_object(
      'input_governance_binding_contract', 'gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md',
      'input_governance_authority_contract', 'INPUT_READINESS_CONTRACT',
      'input_governance_contract_resolution', 'LIVE_CURRENT',
      'input_governance_continuation_policy', 'PASS_ONLY',
      'input_governance_main_sha', '08ff31dba7154a662b35d6784ca7740fb7a44faa',
      'input_governance_merge_pr', 314
    ),
    updated_at = now()
where codigo_activo in (
  'ADAPTER-LF-SHELL-PROFILE-20260827',
  'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827'
);
