-- PR93 · Production readiness P0 · security-invoker view assertions
-- Read-only verification after the corresponding migration.

begin;
set local transaction read only;

create temporary table expected_views(view_name text primary key) on commit drop;
insert into expected_views(view_name) values
  ('v_lf_artifact_destination_registry'),
  ('v_lf_artifact_pack_template_registry'),
  ('v_lf_fuente_operativa_busqueda'),
  ('v_lf_operation_contract'),
  ('v_lf_operation_execution_checklist'),
  ('v_lf_operation_execution_judge'),
  ('v_lf_operation_judge_definition'),
  ('v_lf_operation_step_contract_judge_coverage'),
  ('v_lf_operation_step_contracts'),
  ('v_lf_operation_steps'),
  ('v_lf_operation_steps_with_contracts'),
  ('v_lf_product_rules_current'),
  ('v_lf_profile_runtime_protocol'),
  ('v_lf_reporte_salida'),
  ('v_lf_strategy_events'),
  ('v_lf_strategy_latest'),
  ('v_lf_test_run_observability'),
  ('v_lf_test_suite_observability'),
  ('v_sbx_competitive_observation_summary'),
  ('v_sbx_mod_8_13_1_dashboard'),
  ('v_sbx_mod_8_13_1_matriz');

do $assert_options$
declare
  v_expected integer;
  v_observed integer;
  v_invalid integer;
begin
  select count(*) into v_expected from expected_views;

  select count(*) into v_observed
  from expected_views e
  join pg_class c on c.relname=e.view_name and c.relkind='v'
  join pg_namespace n on n.oid=c.relnamespace and n.nspname='public';

  if v_expected <> 21 or v_observed <> v_expected then
    raise exception 'P0_VIEW_SET_MISMATCH expected=% observed=%', v_expected, v_observed;
  end if;

  select count(*) into v_invalid
  from expected_views e
  join pg_class c on c.relname=e.view_name and c.relkind='v'
  join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
  where coalesce(
    (select option_value::boolean
     from pg_options_to_table(c.reloptions)
     where option_name='security_invoker'),
    false
  ) is not true;

  if v_invalid <> 0 then
    raise exception 'P0_SECURITY_INVOKER_ASSERTION_FAILED invalid=%', v_invalid;
  end if;
end
$assert_options$;

set local role service_role;

do $assert_reads$
declare
  v_name text;
begin
  for v_name in select view_name from pg_temp.expected_views order by view_name
  loop
    execute format('select 1 from public.%I limit 1', v_name);
  end loop;
end
$assert_reads$;

reset role;

select
  c.relname as view_name,
  (select option_value::boolean
   from pg_options_to_table(c.reloptions)
   where option_name='security_invoker') as security_invoker,
  has_table_privilege('service_role', c.oid, 'SELECT') as service_role_select,
  has_table_privilege('anon', c.oid, 'SELECT') as anon_select,
  has_table_privilege('authenticated', c.oid, 'SELECT') as authenticated_select
from expected_views e
join pg_class c on c.relname=e.view_name and c.relkind='v'
join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
order by c.relname;

rollback;
