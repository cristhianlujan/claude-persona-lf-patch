-- PR93 · Production readiness P0
-- Harden the exact current trigger-function set without recreating functions
-- or changing trigger bindings.

begin;

create temporary table p0_trigger_targets(
  schema_name text not null,
  function_name text not null,
  expected_bindings integer not null,
  before_oid oid,
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
set before_oid=p.oid
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname=x.schema_name
  and p.proname=x.function_name
  and pg_get_function_identity_arguments(p.oid)=''
  and p.prorettype='trigger'::regtype;

do $preflight$
declare
  v_targets integer;
  v_missing integer;
  v_catalog integer;
  v_bindings integer;
  v_mismatch integer;
begin
  select count(*), count(*) filter(where before_oid is null)
    into v_targets,v_missing from p0_trigger_targets;
  if v_targets<>59 or v_missing<>0 then
    raise exception 'P0_TRIGGER_TARGET_SET_INVALID targets=% missing=%',v_targets,v_missing;
  end if;

  select count(*) into v_catalog
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','overall_design')
    and p.prorettype='trigger'::regtype
    and p.proconfig is null;
  if v_catalog<>59 then
    raise exception 'P0_TRIGGER_CATALOG_DRIFT expected=59 observed=%',v_catalog;
  end if;

  select count(*) into v_mismatch
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  left join p0_trigger_targets x
    on x.schema_name=n.nspname and x.function_name=p.proname
  where n.nspname in ('public','private','overall_design')
    and p.prorettype='trigger'::regtype
    and p.proconfig is null
    and x.before_oid is null;
  if v_mismatch<>0 then
    raise exception 'P0_TRIGGER_UNLISTED_TARGETS observed=%',v_mismatch;
  end if;

  select count(*) into v_bindings
  from pg_trigger t
  join p0_trigger_targets x on x.before_oid=t.tgfoid
  where not t.tgisinternal;
  if v_bindings<>82 then
    raise exception 'P0_TRIGGER_BINDING_COUNT_DRIFT expected=82 observed=%',v_bindings;
  end if;

  select count(*) into v_mismatch
  from p0_trigger_targets x
  where x.expected_bindings <> (
    select count(*) from pg_trigger t
    where t.tgfoid=x.before_oid and not t.tgisinternal
  );
  if v_mismatch<>0 then
    raise exception 'P0_TRIGGER_PER_FUNCTION_BINDING_DRIFT mismatches=%',v_mismatch;
  end if;
end
$preflight$;

create temporary table p0_trigger_bindings_before on commit drop as
select t.oid as trigger_oid,t.tgfoid,t.tgrelid,t.tgname,t.tgenabled
from pg_trigger t
join p0_trigger_targets x on x.before_oid=t.tgfoid
where not t.tgisinternal;

do $apply$
declare
  r record;
  v_path text;
begin
  for r in select * from p0_trigger_targets order by schema_name,function_name loop
    v_path := case r.schema_name
      when 'public' then 'pg_catalog, public'
      when 'private' then 'pg_catalog, private, public'
      when 'overall_design' then 'pg_catalog, overall_design'
      else null end;
    if v_path is null then
      raise exception 'P0_TRIGGER_SCHEMA_NOT_ALLOWED %',r.schema_name;
    end if;
    execute format(
      'alter function %I.%I() set search_path = %s',
      r.schema_name,r.function_name,v_path
    );
    execute format(
      'revoke execute on function %I.%I() from public, anon, authenticated, service_role',
      r.schema_name,r.function_name
    );
  end loop;
end
$apply$;

do $post$
declare
  v_invalid integer;
  v_bindings integer;
begin
  select count(*) into v_invalid
  from p0_trigger_targets x
  join pg_proc p on p.oid=x.before_oid
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname<>x.schema_name
     or p.proname<>x.function_name
     or p.proconfig is null
     or has_function_privilege('anon',p.oid,'EXECUTE')
     or has_function_privilege('authenticated',p.oid,'EXECUTE')
     or has_function_privilege('service_role',p.oid,'EXECUTE');
  if v_invalid<>0 then
    raise exception 'P0_TRIGGGER_POST_STATE_INVALID count=%',v_invalid;
  end if;

  select count(*) into v_invalid
  from p0_trigger_bindings_before b
  full join (
    select t.oid as trigger_oid,t.tgfoid,t.tgrelid,t.tgname,t.tgenabled
    from pg_trigger t
    join p0_trigger_targets x on x.before_oid=t.tgfoid
    where not t.tgisinternal
  ) c
    on c.trigger_oid=b.trigger_oid
   and c.tgfoid=b.tgfoid
   and c.tgrelid=b.tgrelid
   and c.tgname=b.tgname
   and c.tgenabled=b.tgenabled
  where b.trigger_oid is null or c.trigger_oid is null;
  if v_invalid<>0 then
    raise exception 'P0_TRIGGER_BINDING_IDENTITY_CHANGED count=%',v_invalid;
  end if;

  select count(*) into v_bindings
  from pg_trigger t
  join p0_trigger_targets x on x.before_oid=t.tgfoid
  where not t.tgisinternal;
  if v_bindings<>82 then
    raise exception 'P0_TRIGGER_BINDING_COUNT_CHANGED observed=%',v_bindings;
  end if;
end
$post$;

commit;
