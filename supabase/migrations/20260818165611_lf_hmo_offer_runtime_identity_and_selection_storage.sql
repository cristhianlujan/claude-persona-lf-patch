create or replace view lf_proto.v_offer_runtime_identity
with (security_invoker = true)
as
select
  o.id as offer_id,
  encode(
    digest(
      jsonb_build_object(
        'offer_id', o.id,
        'estado', o.estado,
        'expires_at', o.expires_at,
        'offer_data', o.offer_data
      )::text,
      'sha256'
    ),
    'hex'
  ) as offer_version,
  o.estado,
  o.expires_at,
  o.offer_data,
  case
    when jsonb_typeof(o.offer_data #> '{modalidades,cuotas,opciones}') = 'array' then (
      select coalesce(
        jsonb_agg(
          p.opt || jsonb_build_object(
            'plan_id', encode(
              digest(
                o.id::text || '|' ||
                encode(
                  digest(
                    jsonb_build_object(
                      'offer_id', o.id,
                      'estado', o.estado,
                      'expires_at', o.expires_at,
                      'offer_data', o.offer_data
                    )::text,
                    'sha256'
                  ),
                  'hex'
                ) || '|' || p.opt::text,
                'sha256'
              ),
              'hex'
            )
          )
          order by p.ord
        ),
        '[]'::jsonb
      )
      from jsonb_array_elements(o.offer_data #> '{modalidades,cuotas,opciones}') with ordinality as p(opt, ord)
    )
    else '[]'::jsonb
  end as installment_plans
from lf_proto.proto_offers o;

revoke all on lf_proto.v_offer_runtime_identity from public;

grant select on lf_proto.v_offer_runtime_identity to authenticated;

create table public.lf_user_offer_selections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on update restrict on delete cascade,
  offer_id uuid not null references lf_proto.proto_offers(id) on update restrict on delete restrict,
  offer_version text not null check (offer_version ~ '^[0-9a-f]{64}$'),
  modality text not null check (modality in ('pago_unico','cuotas')),
  plan_id text null,
  selected_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint lf_user_offer_selections_plan_shape_chk check (
    (modality = 'pago_unico' and plan_id is null)
    or
    (modality = 'cuotas' and plan_id is not null and btrim(plan_id) <> '')
  ),
  constraint lf_user_offer_selections_user_offer_uq unique (user_id, offer_id)
);

create index lf_user_offer_selections_offer_id_idx
  on public.lf_user_offer_selections(offer_id);

alter table public.lf_user_offer_selections enable row level security;

revoke all on public.lf_user_offer_selections from public, anon;
grant select, insert, update, delete on public.lf_user_offer_selections to authenticated;

create policy lf_user_offer_selections_select_own
on public.lf_user_offer_selections
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy lf_user_offer_selections_insert_own
on public.lf_user_offer_selections
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy lf_user_offer_selections_update_own
on public.lf_user_offer_selections
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy lf_user_offer_selections_delete_own
on public.lf_user_offer_selections
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);