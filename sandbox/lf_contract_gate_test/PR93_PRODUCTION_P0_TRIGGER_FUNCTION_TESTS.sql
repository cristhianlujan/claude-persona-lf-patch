-- PR93 · Production readiness P0 · trigger hardening assertions
-- Uses only temporary objects and rolls back.

begin;

create temporary table p0_trigger_targets(
  schema_name text not null,
  function_name text not null,
  expected_bindings integer not null,
  function_oid oid,
  primary key(schema_name,function_name)
) on commit drop;

insert into p0_trigger_targets(schema_name,function_name,expected_bindings) values
  ('overall_design','set_updated_at',16),
  ('private','fn_update_lf_skill_artifacts_timestamp',1),
  ('private','fn_update_lf_source_documents_timestamp',1),
  ('public','fn_auto_consumer_ready',1),
  ('public','fn_block_empty_kb_enriched',1),
  ('public','fn_update_lf_activo_relaciones_timestamp',1),
  ('public','fn_update_lf_activos_demo_timestamp',1),
  ('public','fn_update_lf_activos_timestamp',1),
  ('public','fn_update_lf_artifact_destination_registry_timestamp',1),
  ('public','fn_update_lf_artifact_pack_template_registry_timestamp',1),
  ('public','fn_update_lf_audit_backlog_timestamp',1),
  ('public','fn_update_lf_audit_objetivo_timestamp',1),
  ('public','fn_update_lf_b2b_pricing_config_timestamp',1),
  ('public','fn_update_lf_backlog_errores_operativos_timestamp',1),
  ('public','fn_update_lf_bitacora_demo_timestamp',1),
  ('public','fn_update_lf_capture_judge_results_timestamp',1),
  ('public','fn_update_lf_cards_timestamp',1),
  ('public','fn_update_lf_decisiones_gov_timestamp',1),
  ('public','fn_update_lf_deuda_documental_timestamp',1),
  ('public','fn_update_lf_deuda_gov_migrada_timestamp',1),
  ('public','fn_update_lf_eventos_timestamp',0),
  ('public','fn_update_lf_knowledge_base_backup_29g_timestamp',1),
  ('public','fn_update_lf_knowledge_base_timestamp',1),
  ('public','fn_update_lf_lineas_gobernanza_timestamp',1),
  ('public','fn_update_lf_lineas_timestamp',1),
  ('public','fn_update_lf_log_config_timestamp',1),
  ('public','fn_update_lf_log_operativo_timestamp',1),
  ('public','fn_update_lf_operation_contracts_timestamp',1),
  ('public','fn_update_lf_operation_execution_steps_timestamp',1),
  ('public','fn_update_lf_operation_execution_timestamp',1),
  ('public','fn_update_lf_operation_judges_timestamp',1),
  ('public','fn_update_lf_operation_registry_timestamp',1),
  ('public','fn_update_lf_operation_step_contracts_timestamp',1),
  ('public','fn_update_lf_operation_step_judge_bindings_timestamp',1),
  ('public','fn_update_lf_operation_steps_timestamp',1),
  ('public','fn_update_lf_patch_registros_timestamp',1),
  ('public','fn_update_lf_patches_timestamp',1),
  ('public','fn_update_lf_prod_enforcement_observability_log_timestamp',1),
  ('public','fn_update_lf_produccion_checklist_timestamp',1),
  ('public','fn_update_lf_product_rule_sets_timestamp',1),
  ('public','fn_update_lf_product_rules_timestamp',1),
  ('public','fn_update_lf_proyectos_demo_timestamp',1),
  ('public','fn_update_lf_pruebas_timestamp',1),
  ('public','fn_update_lf_runbook_operativo_timestamp',1),
  ('public','fn_update_lf_taxonomia_lf_timestamp',1),
  ('public','fn_update_lf_test_artifacts_timestamp',1),
  ('public','fn_update_lf_test_assertion_results_timestamp',1),
  ('public','fn_update_lf_test_judge_results_timestamp',1),
  ('public','fn_update_lf_test_runs_timestamp',1),
  ('public','fn_update_lf_test_suite_cases_timestamp',1),
  ('public','fn_update_lf_test_suite_runs_timestamp',1),
  ('public','fn_update_lf_test_suites_timestamp',1),
  ('public','fn_update_lf_url_queue_timestamp',1),
  ('public','fn_update_lf_user_stories_timestamp',1),
  ('public','lf_patches_gate_minimo',1),
  ('public','lf_prod_enforcement_step_gate_v01',1),
  ('public','sbx_competitive_set_updated_at',10),
  ('public','sbx_lf_validation_engine_runs_gate_fn',1),
  ('public','sbx_lf_validation_engine_steps_gate_fn',1);

update p0_trigger_targets x
set function_oid=p.oid
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname=x.schema_name
  and p.proname=x.function_name
  and pg_get_function_identity_arguments(p.oid)=''
  and p.prorettype='trigger'::regtype;

do $catalog_assertions$
declare
  v_count integer;
  v_invalid integer;
  v_bindings integer;
begin
  select count(*) into v_count from p0_trigger_targets where function_oid is not null;
  if v_count<>59 then
    raise exception 'P0_TRIGGER_SET_MISMATCH observed=%',v_count;
  end if;

  select count(*) into v_invalid
  from p0_trigger_targets x
  join pg_proc p on p.oid=x.function_oid
  where p.proconfig is null
     or has_function_privilege('anon',p.oid,'EXECUTE')
     or has_function_privilege('authenticated',p.oid,'EXECUTE')
     or has_function_privilege('service_role',p.oid,'EXECUTE');
  if v_invalid<>0 then
    raise exception 'P0_TRIGGGER_HARDENING_ASSERTION_FAILED invalid=%',v_invalid;
  end if;

  select count(*) into v_bindings
  from pg_trigger t
  join p0_trigger_targets x on x.function_oid=t.tgfoid
  where not t.tgisinternal;
  if v_bindings<>82 then
    raise exception 'P0_TRIGGGER_BINDING_COUNT_MISMATCH observed=%',v_bindings;
  end if;

  select count(*) into v_invalid
  from p0_trigger_targets x
  where x.expected_bindings <> (
    select count(*) from pg_trigger t
    where t.tgfoid=x.function_oid and not t.tgisinternal
  );
  if v_invalid<>0 then
    raise exception 'P0_TRIGGER_PER_FUNCTION_BINDING_MISMATCH invalid=%',v_invalid;
  end if;
end
$catalog_assertions$;

create temporary table p0_overall_trigger_test(
  id integer primary key,
  updated_at timestamptz
) on commit drop;
create trigger p0_overall_updated
before update on p0_overall_trigger_test
for each row execute function overall_design.set_updated_at();

create temporary table p0_private_trigger_test(
  id integer primary key,
  updated_at timestamptz
) on commit drop;
create trigger p0_private_updated
before update on p0_private_trigger_test
for each row execute function private.fn_update_lf_skill_artifacts_timestamp();

create temporary table p0_public_trigger_test(
  id integer primary key,
  updated_at timestamptz
) on commit drop;
create trigger p0_public_updated
before update on p0_public_trigger_test
for each row execute function public.fn_update_lf_activos_timestamp();

grant select,insert,update
on p0_overall_trigger_test,p0_private_trigger_test,p0_public_trigger_test
to service_role;

set local role service_role;
insert into p0_overall_trigger_test values(1,'2000-01-01');
insert into p0_private_trigger_test values(1,'2000-01-01');
insert into p0_public_trigger_test values(1,'2000-01-01');
update p0_overall_trigger_test set id=id where id=1;
update p0_private_trigger_test set id=id where id=1;
update p0_public_trigger_test set id=id where id=1;
reset role;

do $runtime_assertions$
declare
  v_fail integer;
begin
  select count(*) into v_fail from (
    select updated_at from p0_overall_trigger_test
    union all select updated_at from p0_private_trigger_test
    union all select updated_at from p0_public_trigger_test
  ) s where updated_at <= '2000-01-02'::timestamptz;
  if v_fail<>0 then
    raise exception 'P0_TRIGGGER_RUNTIME_FAILED count=%',v_fail;
  end if;
end
$runtime_assertions$;

select
  (select count(*) from p0_trigger_targets) as functions_observed,
  (select count(*) from p0_trigger_targets x join pg_proc p on p.oid=x.function_oid where p.proconfig is not null) as fixed_search_path_count,
  (select count(*) from p0_trigger_targets x join pg_proc p on p.oid=x.function_oid where has_function_privilege('anon',p.oid,'EXECUTE')) as anon_execute_count,
  (select count(*) from p0_trigger_targets x join pg_proc p on p.oid=x.function_oid where has_function_privilege('authenticated',p.oid,'EXECUTE')) as authenticated_execute_count,
  (select count(*) from p0_trigger_targets x join pg_proc p on p.oid=x.function_oid where has_function_privilege('service_role',p.oid,'EXECUTE')) as service_role_execute_count,
  (select count(*) from pg_trigger t join p0_trigger_targets x on x.function_oid=t.tgfoid join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname not like 'pg_temp_%' and n.nspname not like 'pg_toast_temp_%') as canonical_trigger_bindings,
  3 as representative_runtime_triggers_passed;

rollback;
