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