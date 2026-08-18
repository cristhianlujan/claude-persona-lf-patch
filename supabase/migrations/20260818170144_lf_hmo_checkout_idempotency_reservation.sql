create table public.lf_checkout_idempotency_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on update restrict on delete cascade,
  idempotency_key text not null check (btrim(idempotency_key) <> '' and length(idempotency_key) <= 200),
  request_sha256 text not null check (request_sha256 ~ '^[0-9a-f]{64}$'),
  operation_number uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  constraint lf_checkout_idempotency_user_key_uq unique (user_id, idempotency_key),
  constraint lf_checkout_idempotency_operation_number_uq unique (operation_number)
);

alter table public.lf_checkout_idempotency_reservations enable row level security;

revoke all on public.lf_checkout_idempotency_reservations from public, anon, authenticated;
grant select, insert on public.lf_checkout_idempotency_reservations to authenticated;

create policy lf_checkout_idempotency_select_own
on public.lf_checkout_idempotency_reservations
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy lf_checkout_idempotency_insert_own
on public.lf_checkout_idempotency_reservations
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create or replace function public.fn_lf_checkout_reserve_operation(
  p_idempotency_key text,
  p_request_sha256 text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid;
  v_row public.lf_checkout_idempotency_reservations%rowtype;
  v_inserted boolean := false;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'AUTHENTICATED_USER_REQUIRED';
  end if;
  if btrim(coalesce(p_idempotency_key,'')) = '' or length(p_idempotency_key) > 200 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;
  if coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_REQUEST_SHA256';
  end if;

  insert into public.lf_checkout_idempotency_reservations(user_id,idempotency_key,request_sha256)
  values(v_user_id,p_idempotency_key,p_request_sha256)
  on conflict (user_id,idempotency_key) do nothing
  returning * into v_row;

  if v_row.id is not null then
    v_inserted := true;
  else
    select * into v_row
    from public.lf_checkout_idempotency_reservations
    where user_id=v_user_id and idempotency_key=p_idempotency_key;
  end if;

  if v_row.id is null then
    raise exception 'IDEMPOTENCY_RESERVATION_UNAVAILABLE';
  end if;
  if v_row.request_sha256 <> p_request_sha256 then
    raise exception 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST';
  end if;

  return jsonb_build_object(
    'reservation_id',v_row.id,
    'operation_number',v_row.operation_number,
    'idempotency_key',v_row.idempotency_key,
    'request_sha256',v_row.request_sha256,
    'result',case when v_inserted then 'RESERVED' else 'REPLAY' end,
    'created_at',v_row.created_at
  );
end;
$function$;

revoke all on function public.fn_lf_checkout_reserve_operation(text,text) from public, anon;
grant execute on function public.fn_lf_checkout_reserve_operation(text,text) to authenticated;
