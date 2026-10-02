-- INV-9.3a - public PostgREST wrappers for external currentness gateway
-- Exact-version identity: 20261002203257
-- Transport: EXACT_VERSION_SOURCE_FIRST
-- Consumer: lf-external-currentness-gateway-v1
--
-- This migration does NOT expose the inventory schema and adds no grants on
-- inventory objects. It creates two minimal SECURITY INVOKER wrappers in public
-- so the gateway can use the default PostgREST schema.

do $preflight$
begin
  if pg_catalog.to_regprocedure('public.lf_external_currentness_read_model_v1()') is not null then
    raise exception 'INV_9_3A_READ_WRAPPER_ALREADY_EXISTS';
  end if;

  if pg_catalog.to_regprocedure(
    'public.lf_external_currentness_apply_observation_v1(jsonb,timestamptz,timestamptz)'
  ) is not null then
    raise exception 'INV_9_3A_WRITE_WRAPPER_ALREADY_EXISTS';
  end if;

  if pg_catalog.to_regprocedure('inventory.fn_external_currentness_read_model_v1()') is null then
    raise exception 'INV_9_3A_TARGET_READ_MODEL_MISSING';
  end if;

  if pg_catalog.to_regprocedure(
    'inventory.fn_apply_external_currentness_observation_v1(jsonb,timestamptz,timestamptz)'
  ) is null then
    raise exception 'INV_9_3A_TARGET_WRITER_MISSING';
  end if;
end
$preflight$;

create function public.lf_external_currentness_read_model_v1()
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, pg_temp
as $function$
  select inventory.fn_external_currentness_read_model_v1();
$function$;

create function public.lf_external_currentness_apply_observation_v1(
  p_report jsonb,
  p_observed_main_committed_at timestamptz,
  p_observed_at timestamptz
)
returns table(
  outcome text,
  snapshot_id bigint,
  snapshot_code text,
  repo_updated integer,
  edge_updated integer,
  repo_inventory_sha256 text,
  edge_inventory_sha256 text,
  observed_main_sha text,
  observed_at timestamptz
)
language sql
volatile
security invoker
set search_path = pg_catalog, pg_temp
as $function$
  select *
  from inventory.fn_apply_external_currentness_observation_v1(
    p_report,
    p_observed_main_committed_at,
    p_observed_at
  );
$function$;

revoke all on function public.lf_external_currentness_read_model_v1()
from public, anon, authenticated;

revoke all on function public.lf_external_currentness_apply_observation_v1(
  jsonb,
  timestamptz,
  timestamptz
)
from public, anon, authenticated;

grant execute on function public.lf_external_currentness_read_model_v1()
to service_role;

grant execute on function public.lf_external_currentness_apply_observation_v1(
  jsonb,
  timestamptz,
  timestamptz
)
to service_role;

comment on function public.lf_external_currentness_read_model_v1() is
'INV-9.3a minimal PostgREST read wrapper for inventory.fn_external_currentness_read_model_v1(), consumed only by lf-external-currentness-gateway-v1.';

comment on function public.lf_external_currentness_apply_observation_v1(
  jsonb,
  timestamptz,
  timestamptz
) is
'INV-9.3a minimal PostgREST write wrapper for inventory.fn_apply_external_currentness_observation_v1(), consumed only by lf-external-currentness-gateway-v1.';
