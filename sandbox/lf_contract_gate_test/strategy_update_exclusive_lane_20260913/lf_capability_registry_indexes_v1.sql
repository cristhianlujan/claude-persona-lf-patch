-- Covering indexes for capability registry foreign keys reported by Supabase performance advisor.
-- Scope: only objects introduced by lf_capability_registry_destination_resolution_v1.

create index if not exists idx_lf_capability_version_supersedes
  on public.lf_capability_version_registry (capability_code, supersedes_version)
  where supersedes_version is not null;

create index if not exists idx_lf_capability_current_version
  on public.lf_capability_current (capability_code, version);

create index if not exists idx_lf_capability_current_previous_version
  on public.lf_capability_current (capability_code, previous_version)
  where previous_version is not null;

create index if not exists idx_lf_capability_binding_capability
  on public.lf_capability_binding (capability_code);

create index if not exists idx_lf_capability_binding_version
  on public.lf_capability_binding (capability_code, bound_version);
