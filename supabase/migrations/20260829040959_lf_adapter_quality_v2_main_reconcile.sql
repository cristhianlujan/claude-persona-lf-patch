alter table private.lf_profile_runtime_queue_v1
  drop constraint if exists lf_profile_runtime_queue_adapter_resolution_ck;

alter table private.lf_profile_runtime_queue_v1
  drop column if exists lf_adapter_resolution;

update public.lf_activos
set version = 'v0.1',
    nombre_canonico = case codigo_activo
      when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'ADAPTER_LF_SHELL_PROFILE_v0.1_CANDIDATO'
      when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF_v0.1_CANDIDATO'
      when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'ADAPTER_MARKETPLACE_LF_UX_v0.1_CANDIDATO'
      when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'ADAPTER_MARKETPLACE_LF_CX_TRUST_v0.1_CANDIDATO'
      else nombre_canonico
    end,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'quality_standard', 'ADAPTER_ASSURANCE_V2',
      'assurance_revision', 'v2',
      'activation', 'ROUTER_BOUND_ONLY',
      'router_discoverable', true,
      'runtime_enabled', false,
      'production_enabled', false,
      'current_path', case codigo_activo
        when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'adapters/lf_shell_profile_adapter/ADAPTER.md'
        when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'adapters/project_brand_mockup_render_lf/ADAPTER.md'
        when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'adapters/marketplace_lf_ux/ADAPTER.md'
        when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'adapters/marketplace_lf_cx_trust/ADAPTER.md'
      end,
      'runtime_capsule_path', case codigo_activo
        when 'ADAPTER-LF-SHELL-PROFILE-20260827' then 'adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml'
        when 'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827' then 'adapters/project_brand_mockup_render_lf/runtime/runtime_capsule.yaml'
        when 'ADAPTER-MARKETPLACE-LF-UX-20260531' then 'adapters/marketplace_lf_ux/runtime/runtime_capsule.yaml'
        when 'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531' then 'adapters/marketplace_lf_cx_trust/runtime/runtime_capsule.yaml'
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
      'assurance_revision', 'v2'
    ),
    updated_at = now()
where codigo_activo in (
  'ADAPTER-LF-SHELL-PROFILE-20260827',
  'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827',
  'ADAPTER-MARKETPLACE-LF-UX-20260531',
  'ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531'
);

insert into public.lf_activo_relaciones (
  codigo_activo, relacionado_codigo, relacion_tipo, valor_original, fuente, migration_batch_id
)
select v.codigo_activo, v.relacionado_codigo, v.relacion_tipo, v.valor_original, v.fuente,
       '55555555-5555-4555-8555-202608290001'::uuid
from (values
  ('ADAPTER-MARKETPLACE-LF-UX-20260531', 'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531', 'ADAPTER_APLICA_A', 'Canonical adapter binding for Marketplace UX profile assurance v2', 'SUPABASE_CANONICAL_ROUTER_BINDING'),
  ('ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531', 'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531', 'ADAPTER_APLICA_A', 'Canonical adapter binding for Marketplace CX/Trust profile assurance v2', 'SUPABASE_CANONICAL_ROUTER_BINDING')
) as v(codigo_activo, relacionado_codigo, relacion_tipo, valor_original, fuente)
where not exists (
  select 1 from public.lf_activo_relaciones r
  where r.codigo_activo = v.codigo_activo
    and r.relacionado_codigo = v.relacionado_codigo
    and r.relacion_tipo = v.relacion_tipo
);
