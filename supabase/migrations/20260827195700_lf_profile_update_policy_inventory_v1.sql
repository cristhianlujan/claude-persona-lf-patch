create table if not exists public.lf_policy_versions (
  policy_code text not null references public.lf_activos(codigo_activo) on update cascade on delete restrict,
  policy_version text not null,
  policy_payload jsonb not null,
  policy_sha text not null,
  status text not null check (status in ('ACTIVE','SUPERSEDED','CANDIDATE','RETIRED')),
  effective_at timestamptz not null default now(),
  superseded_at timestamptz,
  source_ref text,
  created_by_execution_id text not null,
  updated_by_execution_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (policy_code, policy_version),
  unique (policy_code, policy_sha),
  check (policy_sha ~ '^[0-9a-f]{64}$')
);

create unique index if not exists ux_lf_policy_versions_one_active
  on public.lf_policy_versions(policy_code)
  where status = 'ACTIVE';

create table if not exists public.lf_operation_policy_bindings (
  operation_code text not null references public.lf_operation_registry(operation_code) on update cascade on delete restrict,
  policy_code text not null references public.lf_activos(codigo_activo) on update cascade on delete restrict,
  policy_role text not null default 'PASS_POLICY',
  required boolean not null default true,
  distribution_modes text[] not null default array['ROUTER','DIRECT']::text[],
  binding_status text not null check (binding_status in ('ACTIVE','INACTIVE')),
  created_by_execution_id text not null,
  updated_by_execution_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (operation_code, policy_code, policy_role)
);

create unique index if not exists ux_lf_operation_policy_one_active_role
  on public.lf_operation_policy_bindings(operation_code, policy_role)
  where binding_status = 'ACTIVE';

create or replace function public.lf_policy_version_sha_guard()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
declare
  expected_sha text;
begin
  expected_sha := encode(extensions.digest(convert_to(new.policy_payload::text, 'UTF8'), 'sha256'), 'hex');
  if new.policy_sha is null or new.policy_sha <> expected_sha then
    raise exception 'POLICY_SHA_MISMATCH expected=% got=%', expected_sha, coalesce(new.policy_sha,'NULL');
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_lf_policy_version_sha_guard on public.lf_policy_versions;
create trigger trg_lf_policy_version_sha_guard
before insert or update of policy_payload, policy_sha on public.lf_policy_versions
for each row execute function public.lf_policy_version_sha_guard();

create or replace view public.v_lf_operation_policy_snapshot
with (security_invoker = true)
as
select
  b.operation_code,
  b.policy_role,
  b.required,
  b.distribution_modes,
  b.policy_code,
  a.nombre_canonico as policy_name,
  a.tipo_activo,
  a.subtipo_activo,
  v.policy_version,
  v.policy_sha,
  v.policy_payload,
  v.effective_at,
  v.source_ref,
  b.updated_at as binding_updated_at,
  v.updated_at as policy_updated_at
from public.lf_operation_policy_bindings b
join public.lf_activos a on a.codigo_activo = b.policy_code
join public.lf_policy_versions v on v.policy_code = b.policy_code and v.status = 'ACTIVE'
where b.binding_status = 'ACTIVE';

alter table public.lf_policy_versions enable row level security;
alter table public.lf_operation_policy_bindings enable row level security;
revoke all on table public.lf_policy_versions from anon, authenticated;
revoke all on table public.lf_operation_policy_bindings from anon, authenticated;
revoke all on table public.v_lf_operation_policy_snapshot from anon, authenticated;
revoke execute on function public.lf_policy_version_sha_guard() from public, anon, authenticated;
