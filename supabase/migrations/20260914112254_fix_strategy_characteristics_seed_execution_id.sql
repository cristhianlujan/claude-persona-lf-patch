create or replace function public.lf_strategy_characteristics_seed_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  insert into public.lf_strategy_test_characteristics(
    snapshot_id,
    characteristic_code,
    enabled,
    created_by_execution_id
  )
  select
    new.id,
    c.characteristic_code,
    null,
    coalesce(new.updated_by_execution_id, 'UNKNOWN')
  from public.lf_strategy_test_characteristic_catalog c
  where c.status = 'ACTIVE'
  on conflict (snapshot_id, characteristic_code) do nothing;

  return new;
end
$function$;
