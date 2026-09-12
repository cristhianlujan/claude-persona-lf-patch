update public.lf_activos
set version = 'v0.2-candidate',
    nombre_canonico = case codigo_activo
      when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'ADAPTER_LF_SHELL_PROFILE_v0.2_CANDIDATO'
      when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF_v0.2_CANDIDATO'
      when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'ADAPTER_MARKETPLACE_LF_UX_v0.2_CANDIDATO'
      when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'ADAPTER_MARKETPLACE_LF_CX_TRUST_v0.2_CANDIDATO'
      else nombre_canonico
    end,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'quality_standard', 'ADAPTER_QUALITY_V2',
      'activation', 'ROUTER_ORCHESTRATOR_ONLY',
      'single_model_call', true,
      'runtime_enabled', false,
      'production_enabled', false,
      'current_path', case codigo_activo
        when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'adapters/lf_shell_profile_adapter/ADAPTER.md'
        when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'adapters/project_brand_mockup_render_lf/ADAPTER.md'
        when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'adapters/marketplace_lf_ux/ADAPTER.md'
        when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'adapters/marketplace_lf_cx_trust/ADAPTER.md'
      end,
      'runtime_capsule_path', case codigo_activo
        when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'adapters/lf_shell_profile_adapter/runtime_capsule.md'
        when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'adapters/project_brand_mockup_render_lf/runtime_capsule.md'
        when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'adapters/marketplace_lf_ux/runtime_capsule.md'
        when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'adapters/marketplace_lf_cx_trust/runtime_capsule.md'
      end,
      'canonical_adapter_id', case codigo_activo
        when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'ADAPTER_LF_SHELL_PROFILE'
        when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF'
        when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'ADAPTER_MARKETPLACE_LF_UX'
        when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'ADAPTER_MARKETPLACE_LF_CX_TRUST'
      end,
      'binds_profile', case codigo_activo
        when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
        when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531'
        else metadata->>'binds_profile'
      end
    ),
    raw_payload = coalesce(raw_payload, '{}'::jsonb) || jsonb_build_object(
      'path', case codigo_activo
        when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'adapters/lf_shell_profile_adapter/ADAPTER.md'
        when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'adapters/project_brand_mockup_render_lf/ADAPTER.md'
        when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'adapters/marketplace_lf_ux/ADAPTER.md'
        when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'adapters/marketplace_lf_cx_trust/ADAPTER.md'
      end,
      'github_repo', 'cristhianlujan/claude-persona-lf-patch',
      'quality_standard', 'ADAPTER_QUALITY_V2'
    ),
    updated_at = now()
where codigo_activo in (
  'ADAPTER-LF-SHELL-PROFILE-20260827',
  'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827',
  'ADAPTER-MARKETPLACE-LF-UX-20260531',
  'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531'
);
