-- PR93 · Production readiness P0 · public read RPC assertions
-- Read-only verification after the corresponding migration.

begin;
set local transaction read only;

set local role anon;
select count(*) >= 0 as anon_search_ok
from public.lf_buscar_activos(null, null, null, null, 1);
select count(*) = 1 as anon_health_ok
from public.lf_healthcheck();
reset role;

set local role authenticated;
select count(*) >= 0 as authenticated_search_ok
from public.lf_buscar_activos(null, null, null, null, 1);
select count(*) = 1 as authenticated_health_ok
from public.lf_healthcheck();
reset role;

set local role service_role;
select count(*) >= 0 as service_search_ok
from public.lf_buscar_activos(null, null, null, null, 1);
select count(*) = 1 as service_health_ok
from public.lf_healthcheck();
reset role;

do $assertions$
declare
  v_count integer;
  v_invalid integer;
begin
  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and (
      (p.proname='lf_buscar_activos' and pg_get_function_identity_arguments(p.oid)='p_texto text, p_linea text, p_estado_documental text, p_tipo_activo text, p_limit integer')
      or (p.proname='lf_healthcheck' and pg_get_function_identity_arguments(p.oid)='')
    );

  if v_count <> 2 then
    raise exception 'P0_READ_RPC_SET_MISMATCH observed=%', v_count;
  end if;

  select count(*) into v_invalid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in ('lf_buscar_activos','lf_healthcheck')
    and (
      p.prosecdef is true
      or p.proconfig is null
      or not has_function_privilege('anon',p.oid,'EXECUTE')
      or not has_function_privilege('authenticated',p.oid,'EXECUTE')
      or not has_function_privilege('service_role',p.oid,'EXECUTE')
    );

  if v_invalid <> 0 then
    raise exception 'P0_READ_RPC_ASSERTION_FAILED invalid=%', v_invalid;
  end if;
end
$assertions$;

select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  p.prosecdef as security_definer,
  p.proconfig,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
  has_function_privilege('service_role',p.oid,'EXECUTE') as service_role_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('lf_buscar_activos','lf_healthcheck')
order by p.proname;

rollback;
