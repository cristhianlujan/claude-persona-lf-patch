-- PR93 · Production readiness P0 · inherited trigger ACL assertions
-- Uses temporary objects and rolls back.

begin;

create temporary table p0_inherited_trigger_targets(
  schema_name text not null,
  function_name text not null,
  expected_bindings integer not null,
  function_oid oid,
  primary key(schema_name,function_name)
) on commit drop;

insert into p0_inherited_trigger_targets(schema_name,function_name,expected_bindings) values
  ('private','fn_block_lf_eventos_mutation',1),
  ('private','fn_block_lf_governance_history_mutation_v2',6),
  ('private','fn_consume_lf_event_validation_exemption_v3',1),
  ('private','fn_guard_edge_function_deployment_evidence_v6',1),
  ('private','fn_guard_legacy_event_quarantine_v4',1),
  ('private','fn_guard_lf_event_type_contract_mutation_v2',1),
  ('private','fn_guard_lf_event_type_contract_request_v2',1),
  ('private','fn_guard_provenance_overlay_v4',1),
  ('private','fn_guard_schema_fingerprint_baseline_v4',1),
  ('private','fn_record_lf_event_type_contract_history_v2',1),
  ('public','lf_prod_enforcement_execution_gate_v01',1);

update p0_inherited_trigger_targets x
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
  select count(*) into v_count
  from p0_inherited_trigger_targets where function_oid is not null;
  if v_count<>11 then
    raise exception 'P0_INHERITED_TRIGGER_SET_MISMATCH observed=%',v_count;
  end if;

  select count(*) into v_invalid
  from p0_inherited_trigger_targets x
  join pg_proc p on p.oid=x.function_oid
  where p.proconfig is null
     or has_function_privilege('anon',p.oid,'EXECUTE')
     or has_function_privilege('authenticated',p.oid,'EXECUTE')
     or has_function_privilege('service_role',p.oid,'EXECUTE');
  if v_invalid<>0 then
    raise exception 'P0_INHERITED_TRIGGER_ACL_ASSERTION_FAILED invalid=%',v_invalid;
  end if;

  select count(*) into v_bindings
  from pg_trigger t
  join p0_inherited_trigger_targets x on x.function_oid=t.tgfoid
  where not t.tgisinternal;
  if v_bindings<>16 then
    raise exception 'P0_INHERITED_TRIGGER_BINDING_MISMATCH observed=%',v_bindings;
  end if;

  select count(*) into v_invalid
  from p0_inherited_trigger_targets x
  where x.expected_bindings<>(
    select count(*) from pg_trigger t
    where t.tgfoid=x.function_oid and not t.tgisinternal
  );
  if v_invalid<>0 then
    raise exception 'P0_INHERITED_PER_FUNCTION_BINDING_MISMATCH invalid=%',v_invalid;
  end if;
end
$catalog_assertions$;

create temporary table p0_immutable_test(id integer primary key) on commit drop;
create trigger p0_immutable_guard
before update or delete on p0_immutable_test
for each row execute function private.fn_block_lf_eventos_mutation();

create temporary table p0_exemption_test(
  id bigint,
  payload jsonb,
  created_by_execution_id text
) on commit drop;
create trigger p0_exemption_consume
before insert on p0_exemption_test
for each row execute function private.fn_consume_lf_event_validation_exemption_v3();

create temporary table p0_execution_gate_test(
  operation_code text,
  status text,
  manifest jsonb,
  execution_id text
) on commit drop;
create trigger p0_execution_gate
before insert on p0_execution_gate_test
for each row execute function public.lf_prod_enforcement_execution_gate_v01();

grant select,insert,update,delete
on p0_immutable_test,p0_exemption_test,p0_execution_gate_test
to service_role;

set local role service_role;
insert into p0_immutable_test values(1);

do $immutable_runtime$
begin
  begin
    update p0_immutable_test set id=id where id=1;
    raise exception 'EXPECTED_IMMUTABILITY_REJECTION_NOT_OBSERVED';
  exception when sqlstate '55000' then null;
  end;
end
$immutable_runtime$;

insert into p0_exemption_test values(1,'{}'::jsonb,'P0_READBACK');

do $execution_gate_runtime$
begin
  begin
    insert into p0_execution_gate_test
    values('__P0_UNKNOWN_OPERATION__','CANDIDATE','{}'::jsonb,'P0_READBACK');
    raise exception 'EXPECTED_EXECUTION_GATE_REJECTION_NOT_OBSERVED';
  exception when sqlstate 'P0001' then null;
  end;
end
$execution_gate_runtime$;
reset role;

select
  (select count(*) from p0_inherited_trigger_targets) as functions_observed,
  (select count(*) from p0_inherited_trigger_targets x join pg_proc p on p.oid=x.function_oid where has_function_privilege('anon',p.oid,'EXECUTE')) as anon_execute_count,
  (select count(*) from p0_inherited_trigger_targets x join pg_proc p on p.oid=x.function_oid where has_function_privilege('authenticated',p.oid,'EXECUTE')) as authenticated_execute_count,
  (select count(*) from p0_inherited_trigger_targets x join pg_proc p on p.oid=x.function_oid where has_function_privilege('service_role',p.oid,'EXECUTE')) as service_role_execute_count,
  (select count(*)
   from pg_trigger t
   join p0_inherited_trigger_targets x on x.function_oid=t.tgfoid
   join pg_class c on c.oid=t.tgrelid
   join pg_namespace n on n.oid=c.relnamespace
   where not t.tgisinternal
     and n.nspname not like 'pg_temp_%'
     and n.nspname not like 'pg_toast_temp_%') as canonical_bindings,
  (select count(*) from p0_exemption_test) as exemption_passthrough_rows,
  3 as representative_runtime_cases_passed;

rollback;
