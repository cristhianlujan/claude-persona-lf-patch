-- Intelligence Method Portfolio V1
-- Physical registry for current, qualified methods and champion/challenger bindings.
-- This does NOT select methods and does NOT authorize execution.
-- CAPABILITY_SELECTOR remains the only transversal selector.
-- Owner: SUPER_ADMIN.

create table if not exists public.lf_intelligence_method_registry (
  method_code text primary key,
  method_name text not null,
  method_kind text not null default 'SEMANTIC',
  owner_scope text not null default 'SUPER_ADMIN',
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','RETIRED')),
  description text not null,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text
);

create table if not exists public.lf_intelligence_method_version_registry (
  method_code text not null references public.lf_intelligence_method_registry(method_code) on delete restrict,
  version text not null,
  release_state text not null check (release_state in ('DRAFT','RELEASED','SUPERSEDED','RETIRED')),
  qualification_state text not null check (qualification_state in ('UNQUALIFIED','QUALIFIED','FAILED')),
  source_ref text not null,
  validator_ref text not null,
  output_contract_ref text not null,
  qualification_ref text,
  benchmark_ref text,
  holdout_ref text,
  holdout_na_reason text,
  qualification_digest text,
  benchmark_digest text,
  accepted_signals jsonb not null default '[]'::jsonb,
  model_compatibility jsonb not null default '{}'::jsonb,
  cost_profile jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  primary key (method_code, version),
  check (jsonb_typeof(accepted_signals) = 'array'),
  check (jsonb_typeof(model_compatibility) = 'object'),
  check (jsonb_typeof(cost_profile) = 'object'),
  check (jsonb_typeof(metadata) = 'object'),
  check (
    qualification_state <> 'QUALIFIED'
    or (
      release_state = 'RELEASED'
      and qualification_ref is not null
      and benchmark_ref is not null
      and qualification_digest is not null
      and benchmark_digest is not null
      and (holdout_ref is not null or holdout_na_reason is not null)
    )
  )
);

create table if not exists public.lf_intelligence_method_current (
  method_code text primary key,
  version text not null,
  qualification_digest text not null,
  benchmark_digest text not null,
  promoted_at timestamptz not null default now(),
  promoted_by_execution_id text not null,
  promotion_reason text not null,
  foreign key (method_code, version)
    references public.lf_intelligence_method_version_registry(method_code, version)
    on delete restrict
);

create table if not exists public.lf_intelligence_method_family_binding (
  decision_family text not null,
  method_code text not null,
  version text not null,
  role text not null check (role in ('ELIGIBLE','CHAMPION','CHALLENGER','ROBUST_DEFAULT')),
  mix_group text,
  mix_mode text not null default 'SINGLE' check (
    mix_mode in (
      'SINGLE',
      'UNION_COMPLEMENTARY',
      'CONSENSUS_REQUIRED',
      'AUTHORITY_PRIORITY',
      'HARD_INVARIANT_VETO',
      'BOUNDED_ALTERNATIVES'
    )
  ),
  priority_order integer not null default 100 check (priority_order >= 0),
  applicability_signals jsonb not null default '[]'::jsonb,
  evidence_ref text not null,
  calibration_ref text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text,
  primary key (decision_family, method_code, version, role),
  foreign key (method_code, version)
    references public.lf_intelligence_method_version_registry(method_code, version)
    on delete restrict,
  check (jsonb_typeof(applicability_signals) = 'array')
);

create index if not exists lf_intelligence_method_family_binding_active_idx
  on public.lf_intelligence_method_family_binding(decision_family, role, priority_order)
  where active;

create or replace function public.fn_lf_intelligence_method_current_guard_v1()
returns trigger
language plpgsql
as $$
declare
  v_version public.lf_intelligence_method_version_registry%rowtype;
begin
  select * into v_version
  from public.lf_intelligence_method_version_registry
  where method_code = new.method_code
    and version = new.version;

  if not found then
    raise exception 'METHOD_VERSION_NOT_FOUND:%@%', new.method_code, new.version;
  end if;

  if v_version.release_state <> 'RELEASED' then
    raise exception 'METHOD_VERSION_NOT_RELEASED:%@%', new.method_code, new.version;
  end if;

  if v_version.qualification_state <> 'QUALIFIED' then
    raise exception 'METHOD_VERSION_NOT_QUALIFIED:%@%', new.method_code, new.version;
  end if;

  if v_version.qualification_ref is null
     or v_version.benchmark_ref is null
     or v_version.qualification_digest is null
     or v_version.benchmark_digest is null
     or (v_version.holdout_ref is null and v_version.holdout_na_reason is null) then
    raise exception 'METHOD_VERSION_EVIDENCE_INCOMPLETE:%@%', new.method_code, new.version;
  end if;

  if new.qualification_digest <> v_version.qualification_digest
     or new.benchmark_digest <> v_version.benchmark_digest then
    raise exception 'METHOD_VERSION_DIGEST_MISMATCH:%@%', new.method_code, new.version;
  end if;

  return new;
end
$$;

drop trigger if exists trg_lf_intelligence_method_current_guard_v1
  on public.lf_intelligence_method_current;
create trigger trg_lf_intelligence_method_current_guard_v1
before insert or update on public.lf_intelligence_method_current
for each row execute function public.fn_lf_intelligence_method_current_guard_v1();

create or replace function public.fn_lf_intelligence_method_binding_guard_v1()
returns trigger
language plpgsql
as $$
declare
  v_current public.lf_intelligence_method_current%rowtype;
begin
  if new.active is not true then
    return new;
  end if;

  select * into v_current
  from public.lf_intelligence_method_current
  where method_code = new.method_code;

  if not found or v_current.version <> new.version then
    raise exception 'METHOD_BINDING_REQUIRES_CURRENT_VERSION:%@%', new.method_code, new.version;
  end if;

  if new.mix_mode = 'SINGLE' and new.mix_group is not null then
    raise exception 'SINGLE_METHOD_CANNOT_DECLARE_MIX_GROUP:%', new.decision_family;
  end if;

  if new.mix_mode <> 'SINGLE' and new.mix_group is null then
    raise exception 'MIX_MODE_REQUIRES_MIX_GROUP:%:%', new.decision_family, new.mix_mode;
  end if;

  return new;
end
$$;

drop trigger if exists trg_lf_intelligence_method_binding_guard_v1
  on public.lf_intelligence_method_family_binding;
create trigger trg_lf_intelligence_method_binding_guard_v1
before insert or update on public.lf_intelligence_method_family_binding
for each row execute function public.fn_lf_intelligence_method_binding_guard_v1();

create or replace function public.fn_lf_intelligence_method_catalog_v1(p_decision_family text)
returns jsonb
language sql
stable
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'decision_family', b.decision_family,
        'method_code', b.method_code,
        'version', b.version,
        'role', b.role,
        'mix_group', b.mix_group,
        'mix_mode', b.mix_mode,
        'priority_order', b.priority_order,
        'applicability_signals', b.applicability_signals,
        'evidence_ref', b.evidence_ref,
        'source_ref', v.source_ref,
        'validator_ref', v.validator_ref,
        'output_contract_ref', v.output_contract_ref,
        'qualification_ref', v.qualification_ref,
        'benchmark_ref', v.benchmark_ref,
        'holdout_ref', v.holdout_ref,
        'holdout_na_reason', v.holdout_na_reason,
        'qualification_digest', v.qualification_digest,
        'benchmark_digest', v.benchmark_digest,
        'accepted_signals', v.accepted_signals,
        'model_compatibility', v.model_compatibility,
        'cost_profile', v.cost_profile
      ) order by b.priority_order, b.method_code, b.version, b.role
    ),
    '[]'::jsonb
  )
  from public.lf_intelligence_method_family_binding b
  join public.lf_intelligence_method_current c
    on c.method_code = b.method_code
   and c.version = b.version
  join public.lf_intelligence_method_version_registry v
    on v.method_code = b.method_code
   and v.version = b.version
  where b.decision_family = p_decision_family
    and b.active is true
    and v.release_state = 'RELEASED'
    and v.qualification_state = 'QUALIFIED';
$$;

comment on function public.fn_lf_intelligence_method_catalog_v1(text) is
  'Read-only eligible-method catalog for CAPABILITY_SELECTOR. It does not select a method and does not grant execution permission.';

create or replace function public.fn_lf_intelligence_method_portfolio_readback_v1(p_decision_family text)
returns jsonb
language sql
stable
as $$
with catalog as (
  select public.fn_lf_intelligence_method_catalog_v1(p_decision_family) as items
), stats as (
  select
    count(*) filter (where active) as active_bindings,
    count(*) filter (where active and role='CHAMPION') as champions,
    count(*) filter (where active and role='CHALLENGER') as challengers,
    count(*) filter (where active and role='ROBUST_DEFAULT') as robust_defaults
  from public.lf_intelligence_method_family_binding
  where decision_family = p_decision_family
)
select jsonb_build_object(
  'schema_version','INTELLIGENCE_METHOD_PORTFOLIO_READBACK_V1',
  'decision_family',p_decision_family,
  'selection_engine','CAPABILITY_SELECTOR@CURRENT',
  'selection_is_execution_permission',false,
  'active_bindings',stats.active_bindings,
  'champions',stats.champions,
  'challengers',stats.challengers,
  'robust_defaults',stats.robust_defaults,
  'catalog',catalog.items
)
from catalog cross join stats;
$$;

comment on function public.fn_lf_intelligence_method_portfolio_readback_v1(text) is
  'Deterministic readback of exact current qualified method bindings for one decision family; no selection and no runtime activation.';
