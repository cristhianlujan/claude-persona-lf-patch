create or replace function lf_proto.fn_lf_my_active_offers_internal()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, lf_proto
as $function$
declare
  v_user_id uuid;
  v_result jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'AUTHENTICATED_USER_REQUIRED';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'offer_id',o.offer_id,
        'offer_version',o.offer_version,
        'estado',o.estado,
        'expires_at',o.expires_at,
        'offer_data',o.offer_data,
        'installment_plans',o.installment_plans
      )
      order by o.expires_at nulls last,o.offer_id
    ),
    '[]'::jsonb
  )
  into v_result
  from public.lf_user_offer_access a
  join lf_proto.v_offer_runtime_identity o on o.offer_id=a.offer_id
  where a.user_id=v_user_id
    and a.revoked_at is null
    and lower(coalesce(o.offer_data->>'status','')) in ('activa','active')
    and (o.expires_at is null or o.expires_at>now());

  return v_result;
end;
$function$;

revoke all on function lf_proto.fn_lf_my_active_offers_internal() from public, anon;
grant usage on schema lf_proto to authenticated;
grant execute on function lf_proto.fn_lf_my_active_offers_internal() to authenticated;

create or replace function public.fn_lf_my_active_offers()
returns jsonb
language sql
security invoker
set search_path = pg_catalog, lf_proto
as $function$
  select lf_proto.fn_lf_my_active_offers_internal();
$function$;

revoke all on function public.fn_lf_my_active_offers() from public, anon;
grant execute on function public.fn_lf_my_active_offers() to authenticated;