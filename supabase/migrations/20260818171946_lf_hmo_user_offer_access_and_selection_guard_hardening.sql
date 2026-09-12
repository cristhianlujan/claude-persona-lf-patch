create table public.lf_user_offer_access (
  user_id uuid not null references auth.users(id) on update restrict on delete cascade,
  offer_id uuid not null references lf_proto.proto_offers(id) on update restrict on delete cascade,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz null,
  source_ref text not null check (btrim(source_ref) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  primary key (user_id, offer_id),
  constraint lf_user_offer_access_revocation_time_chk check (revoked_at is null or revoked_at >= granted_at)
);

create index lf_user_offer_access_offer_id_idx on public.lf_user_offer_access(offer_id);

alter table public.lf_user_offer_access enable row level security;
revoke all on public.lf_user_offer_access from public, anon, authenticated;
grant select on public.lf_user_offer_access to authenticated;

create policy lf_user_offer_access_select_own
on public.lf_user_offer_access
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id and revoked_at is null);

revoke select on lf_proto.v_offer_runtime_identity from authenticated;

drop trigger if exists trg_lf_user_offer_selections_runtime_integrity on public.lf_user_offer_selections;
drop function if exists public.fn_guard_lf_user_offer_selection();

create or replace function lf_proto.fn_guard_lf_user_offer_selection()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, lf_proto, public
as $function$
declare
  v_offer lf_proto.v_offer_runtime_identity%rowtype;
  v_plan_exists boolean := false;
  v_modality_available boolean := false;
begin
  select * into v_offer
  from lf_proto.v_offer_runtime_identity
  where offer_id = new.offer_id;

  if v_offer.offer_id is null then
    raise exception 'OFFER_NOT_FOUND';
  end if;
  if lower(coalesce(v_offer.offer_data->>'status','')) not in ('activa','active') then
    raise exception 'OFFER_NOT_ACTIVE';
  end if;
  if v_offer.expires_at is not null and v_offer.expires_at <= now() then
    raise exception 'OFFER_EXPIRED';
  end if;
  if new.offer_version <> v_offer.offer_version then
    raise exception 'OFFER_VERSION_MISMATCH';
  end if;

  if new.modality = 'pago_unico' then
    v_modality_available := coalesce((v_offer.offer_data #>> '{modalidades,pago_unico,disponible}')::boolean,false);
    if not v_modality_available then raise exception 'OFFER_MODALITY_UNAVAILABLE'; end if;
  elsif new.modality = 'cuotas' then
    v_modality_available := coalesce((v_offer.offer_data #>> '{modalidades,cuotas,disponible}')::boolean,false);
    if not v_modality_available then raise exception 'OFFER_MODALITY_UNAVAILABLE'; end if;
    select exists(
      select 1 from jsonb_array_elements(v_offer.installment_plans) p
      where p->>'plan_id' = new.plan_id
    ) into v_plan_exists;
    if not v_plan_exists then raise exception 'OFFER_PLAN_INVALID'; end if;
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function lf_proto.fn_guard_lf_user_offer_selection() from public, anon, authenticated;

create trigger trg_lf_user_offer_selections_runtime_integrity
before insert or update on public.lf_user_offer_selections
for each row execute function lf_proto.fn_guard_lf_user_offer_selection();

drop policy if exists lf_user_offer_selections_select_own on public.lf_user_offer_selections;
drop policy if exists lf_user_offer_selections_insert_own on public.lf_user_offer_selections;
drop policy if exists lf_user_offer_selections_update_own on public.lf_user_offer_selections;
drop policy if exists lf_user_offer_selections_delete_own on public.lf_user_offer_selections;

create policy lf_user_offer_selections_select_own
on public.lf_user_offer_selections
for select
to authenticated
using (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and exists (
    select 1 from public.lf_user_offer_access a
    where a.user_id = (select auth.uid()) and a.offer_id = lf_user_offer_selections.offer_id and a.revoked_at is null
  )
);

create policy lf_user_offer_selections_insert_own
on public.lf_user_offer_selections
for insert
to authenticated
with check (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and exists (
    select 1 from public.lf_user_offer_access a
    where a.user_id = (select auth.uid()) and a.offer_id = lf_user_offer_selections.offer_id and a.revoked_at is null
  )
);

create policy lf_user_offer_selections_update_own
on public.lf_user_offer_selections
for update
to authenticated
using (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and exists (
    select 1 from public.lf_user_offer_access a
    where a.user_id = (select auth.uid()) and a.offer_id = lf_user_offer_selections.offer_id and a.revoked_at is null
  )
)
with check (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and exists (
    select 1 from public.lf_user_offer_access a
    where a.user_id = (select auth.uid()) and a.offer_id = lf_user_offer_selections.offer_id and a.revoked_at is null
  )
);

create policy lf_user_offer_selections_delete_own
on public.lf_user_offer_selections
for delete
to authenticated
using (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and exists (
    select 1 from public.lf_user_offer_access a
    where a.user_id = (select auth.uid()) and a.offer_id = lf_user_offer_selections.offer_id and a.revoked_at is null
  )
);