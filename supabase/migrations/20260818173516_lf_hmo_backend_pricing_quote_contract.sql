create table lf_proto.checkout_pricing_quotes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on update restrict on delete cascade,
  selection_sha256 text not null check (selection_sha256 ~ '^[0-9a-f]{64}$'),
  selection_snapshot jsonb not null check (jsonb_typeof(selection_snapshot)='array' and jsonb_array_length(selection_snapshot)>0),
  pricing_config_code text not null references public.lf_b2b_pricing_config(pricing_config_code) on update restrict on delete restrict,
  pricing_config_version text not null check (btrim(pricing_config_version)<>''),
  offers_subtotal_today numeric not null check (offers_subtotal_today>=0),
  management_fee_customer numeric not null check (management_fee_customer>=0),
  management_fee_igv_customer numeric not null check (management_fee_igv_customer>=0),
  niubiz_fee_customer numeric not null check (niubiz_fee_customer>=0),
  niubiz_fee_igv_customer numeric not null check (niubiz_fee_igv_customer>=0),
  final_customer_price numeric not null check (final_customer_price>=0),
  total_savings numeric null check (total_savings is null or total_savings>=0),
  savings_verified boolean not null default false,
  quote_status text not null default 'VALID' check (quote_status in ('VALID','INVALIDATED')),
  source_ref text not null check (btrim(source_ref)<>''),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint lf_checkout_pricing_quote_expiry_chk check (expires_at>created_at),
  constraint lf_checkout_pricing_quote_total_chk check (
    final_customer_price = offers_subtotal_today + management_fee_customer + management_fee_igv_customer + niubiz_fee_customer + niubiz_fee_igv_customer
  )
);

create index lf_checkout_pricing_quotes_user_selection_idx
  on lf_proto.checkout_pricing_quotes(user_id,selection_sha256,created_at desc);

revoke all on lf_proto.checkout_pricing_quotes from public, anon, authenticated;

create or replace function lf_proto.fn_lf_my_checkout_pricing_quote_internal(p_selection_sha256 text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, lf_proto, public
as $function$
declare
  v_user_id uuid;
  v_quote lf_proto.checkout_pricing_quotes%rowtype;
  v_cfg public.lf_b2b_pricing_config%rowtype;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'AUTHENTICATED_USER_REQUIRED';
  end if;
  if coalesce(p_selection_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_SELECTION_SHA256';
  end if;

  select * into v_quote
  from lf_proto.checkout_pricing_quotes
  where user_id=v_user_id
    and selection_sha256=p_selection_sha256
    and quote_status='VALID'
    and expires_at>now()
  order by created_at desc,id desc
  limit 1;

  if v_quote.id is null then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocker_code','BACKEND_PRICING_QUOTE_UNAVAILABLE',
      'selection_sha256',p_selection_sha256
    );
  end if;

  select * into v_cfg
  from public.lf_b2b_pricing_config
  where pricing_config_code=v_quote.pricing_config_code;

  if v_cfg.pricing_config_code is null
     or v_cfg.status not in ('APROBADO','VIGENTE')
     or v_cfg.version<>v_quote.pricing_config_version then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocker_code','PRICING_CONFIG_NOT_AUTHORIZED_OR_VERSION_MISMATCH',
      'selection_sha256',p_selection_sha256,
      'pricing_config_code',v_quote.pricing_config_code,
      'pricing_config_version',v_quote.pricing_config_version
    );
  end if;

  return jsonb_build_object(
    'status','READY',
    'selection_sha256',v_quote.selection_sha256,
    'selection_snapshot',v_quote.selection_snapshot,
    'pricing_config_code',v_quote.pricing_config_code,
    'pricing_config_version',v_quote.pricing_config_version,
    'offers_subtotal_today',v_quote.offers_subtotal_today,
    'management_fee_customer',v_quote.management_fee_customer,
    'management_fee_igv_customer',v_quote.management_fee_igv_customer,
    'niubiz_fee_customer',v_quote.niubiz_fee_customer,
    'niubiz_fee_igv_customer',v_quote.niubiz_fee_igv_customer,
    'final_customer_price',v_quote.final_customer_price,
    'total_savings',v_quote.total_savings,
    'savings_verified',v_quote.savings_verified,
    'visibility',jsonb_build_object(
      'show_final_price',v_cfg.show_final_price,
      'show_customer_breakdown',v_cfg.show_customer_breakdown,
      'show_offers_subtotal',v_cfg.show_offers_subtotal,
      'show_management_fee',v_cfg.show_management_fee,
      'show_management_fee_igv',v_cfg.show_management_fee_igv,
      'show_niubiz_fee',v_cfg.show_niubiz_fee,
      'show_niubiz_fee_igv',v_cfg.show_niubiz_fee_igv,
      'hide_zero_value_components',v_cfg.hide_zero_value_components,
      'display_order',v_cfg.display_order
    ),
    'created_at',v_quote.created_at,
    'expires_at',v_quote.expires_at
  );
end;
$function$;

revoke all on function lf_proto.fn_lf_my_checkout_pricing_quote_internal(text) from public, anon;
grant execute on function lf_proto.fn_lf_my_checkout_pricing_quote_internal(text) to authenticated;

create or replace function public.fn_lf_my_checkout_pricing_quote(p_selection_sha256 text)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, lf_proto
as $function$
  select lf_proto.fn_lf_my_checkout_pricing_quote_internal(p_selection_sha256);
$function$;

revoke all on function public.fn_lf_my_checkout_pricing_quote(text) from public, anon;
grant execute on function public.fn_lf_my_checkout_pricing_quote(text) to authenticated;