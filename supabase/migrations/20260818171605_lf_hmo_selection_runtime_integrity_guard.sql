create or replace function public.fn_guard_lf_user_offer_selection()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, lf_proto
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
    if not v_modality_available then
      raise exception 'OFFER_MODALITY_UNAVAILABLE';
    end if;
  elsif new.modality = 'cuotas' then
    v_modality_available := coalesce((v_offer.offer_data #>> '{modalidades,cuotas,disponible}')::boolean,false);
    if not v_modality_available then
      raise exception 'OFFER_MODALITY_UNAVAILABLE';
    end if;

    select exists(
      select 1
      from jsonb_array_elements(v_offer.installment_plans) p
      where p->>'plan_id' = new.plan_id
    ) into v_plan_exists;

    if not v_plan_exists then
      raise exception 'OFFER_PLAN_INVALID';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function public.fn_guard_lf_user_offer_selection() from public, anon, authenticated;

create trigger trg_lf_user_offer_selections_runtime_integrity
before insert or update on public.lf_user_offer_selections
for each row execute function public.fn_guard_lf_user_offer_selection();