-- B2B support channels authority
-- Creates an extensible governed source for support contacts without hardcoding UI values.

create table if not exists lf_ops.soporte_canales (
  support_channel_id uuid primary key default gen_random_uuid(),
  channel_code text not null unique,
  purpose_code text not null,
  channel_type text not null,
  label text not null,
  target_value text not null,
  display_value text,
  sort_order integer not null default 100,
  status text not null default 'ACTIVE',
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint soporte_canales_channel_code_ck check (channel_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint soporte_canales_purpose_code_ck check (purpose_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint soporte_canales_channel_type_ck check (channel_type ~ '^[A-Z][A-Z0-9_]*$'),
  constraint soporte_canales_target_value_ck check (btrim(target_value) <> ''),
  constraint soporte_canales_status_ck check (status in ('ACTIVE','INACTIVE')),
  constraint soporte_canales_valid_window_ck check (valid_to is null or valid_to > valid_from),
  constraint soporte_canales_unique_destination_uk unique (purpose_code,channel_type,target_value)
);

comment on table lf_ops.soporte_canales is
'Governed extensible support-channel source for B2B and future LF consumers. Purpose and channel type are data, not UI hardcodes.';

comment on column lf_ops.soporte_canales.purpose_code is
'Extensible purpose token such as USER_SUPPORT, CONTRACTS, IT, MARKETING or OPERATIONS. No fixed enum so new governed purposes do not require shell code changes.';

comment on column lf_ops.soporte_canales.channel_type is
'Extensible channel token such as EMAIL, WHATSAPP or PHONE.';

alter table lf_ops.soporte_canales enable row level security;

revoke all on table lf_ops.soporte_canales from public,anon,authenticated;
grant select on table lf_ops.soporte_canales to authenticated;

drop policy if exists b2b_soporte_canales_select_active on lf_ops.soporte_canales;
create policy b2b_soporte_canales_select_active
on lf_ops.soporte_canales
as permissive
for select
to authenticated
using (
  status='ACTIVE'
  and valid_from <= now()
  and (valid_to is null or valid_to > now())
);

create index if not exists idx_soporte_canales_active_lookup
on lf_ops.soporte_canales(purpose_code,status,sort_order,channel_code);

create or replace function lf_ops.b2b_support_channels(
  p_purpose_code text default 'USER_SUPPORT'
)
returns table(
  channel_code text,
  purpose_code text,
  channel_type text,
  label text,
  target_value text,
  display_value text,
  sort_order integer
)
language sql
stable
security definer
set search_path=''
as $function$
  select
    c.channel_code,
    c.purpose_code,
    c.channel_type,
    c.label,
    c.target_value,
    c.display_value,
    c.sort_order
  from lf_ops.soporte_canales c
  where c.purpose_code = upper(btrim(p_purpose_code))
    and c.status='ACTIVE'
    and c.valid_from <= now()
    and (c.valid_to is null or c.valid_to > now())
  order by c.sort_order,c.channel_code
$function$;

revoke all on function lf_ops.b2b_support_channels(text) from public;
grant execute on function lf_ops.b2b_support_channels(text) to authenticated;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values (
  'PROGRAMMING-B2B-SUPPORT-CHANNEL-AUTHORITY-001',
  'PROGRAMMING_GOVERNANCE',
  'B2B support contacts must come from governed extensible lf_ops authority',
  'B2B support contact values must be stored as data in lf_ops.soporte_canales and read through lf_ops.b2b_support_channels(). The shell must not hardcode email, WhatsApp or phone destinations.',
  'A static topbar contact implementation would couple support destinations and purposes to frontend source code and require redeploy for operational changes.',
  'GOVERNED TABLE -> ACTIVE PURPOSE QUERY -> SERVER RUNTIME BINDING -> UI CHANNEL ACTIONS.',
  'Add or update contact rows through governed data operations. Keep purpose_code and channel_type data-driven. Do not seed or render contact values until approved source rows exist.',
  'Migration creates RLS-enabled lf_ops.soporte_canales, authenticated active-row read policy, lookup index and b2b_support_channels() function. No support contact rows are seeded by this migration.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008005500_b2b_support_channel_authority_v1.sql',
  now()
)
on conflict (codigo) do update
set categoria=excluded.categoria,
    titulo=excluded.titulo,
    descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
