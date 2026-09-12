-- PR93 · Production readiness P0
-- Remove direct EXECUTE from the exact inherited trigger-function ACL set.
-- Preserve function bodies, OIDs, trigger definitions and enablement.

begin;

create temporary table p0_inherited_trigger_targets(
  schema_name text not null,
  function_name text not null,
  expected_bindings integer not null,
  before_oid oid,
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
set before_oid=p.oid
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname=x.schema_name
  and p.proname=x.function_name
  and pg_get_function_identity_arguments(p.oid)=''
  and p.prorettype='trigger'::regtype;

do $preflight$
declare
  v_missing integer;
  v_bindings integer;
  v_mismatch integer;
begin
  select count(*) filter(where before_oid is null)
    into v_missing from p0_inherited_trigger_targets;
  if v_missing<>0 or (select count(*) from p0_inherited_trigger_targets)<>11 then
    raise exception 'P0_INHERITED_TRIGGER_SET_INVALID missing=%',v_missing;
  end if;

  select count(*) into v_bindings
  from pg_trigger t
  join p0_inherited_trigger_targets x on x.before_oid=t.tgfoid
  where not t.tgisinternal;
  if v_bindings<>16 then
    raise exception 'P0_INHERITED_BINDING_COUNT_INVALID observed=%',v_bindings;
  end if;

  select count(*) into v_mismatch
  from p0_inherited_trigger_targets x
  where x.expected_bindings<>(
    select count(*) from pg_trigger t
    where t.tgfoid=x.before_oid and not t.tgisinternal
  );
  if v_mismatch<>0 then
    raise exception 'P0_INHERITED_PER_FUNCTION_BINDING_INVALID count=%',v_mismatch;
  end if;
end
$preflight$;

create temporary table p0_inherited_bindings_before on commit drop as
select t.oid as trigger_oid,t.tgfoid,t.tgrelid,t.tgname,t.tgenabled
from pg_trigger t
join p0_inherited_trigger_targets x on x.before_oid=t.tgfoid
where not t.tgisinternal;

-- Remove explicit pg_temp resolution from the production execution gate.
alter function public.lf_prod_enforcement_execution_gate_v01()
  set search_path = pg_catalog, public;

do $revoke$
declare r record;
begin
  for r in select * from p0_inherited_trigger_targets order by schema_name,function_name loop
    execute format(
      'revoke execute on function %I.%I() from public, anon, authenticated, service_role',
      r.schema_name,r.function_name
    );
  end loop;
end
$revoke$;

do $post$
declare v_invalid integer;
begin
  select count(*) into v_invalid
  from p0_inherited_trigger_targets x
  join pg_proc p on p.oid=x.before_oid
  where has_function_privilege('anon',p.oid,'EXECUTE')
     or has_function_privilege('authenticated',p.oid,'EXECUTE')
     or has_function_privilege('service_role',p.oid,'EXECUTE')
     or p.proconfig is null;
  if v_invalid<>0 then
    raise exception 'P0_INHERITED_TRIGGER_ACL_INVALID count=%',v_invalid;
  end if;

  select count(*) into v_invalid
  from p0_inherited_bindings_before b
  full join (
    select t.oid as trigger_oid,t.tgfoid,t.tgrelid,t.tgname,t.tgenabled
    from pg_trigger t
    join p0_inherited_trigger_targets x on x.before_oid=t.tgfoid
    where not t.tgisinternal
  ) c
    on c.trigger_oid=b.trigger_oid
   and c.tgfoid=b.tgfoid
   and c.tgrelid=b.tgrelid
   and c.tgname=b.tgname
   and c.tgenabled=b.tgenabled
  where b.trigger_oid is null or c.trigger_oid is null;
  if v_invalid<>0 then
    raise exception 'P0_INHERITED_BINDING_CHANGED count=%',v_invalid;
  end if;
end
$post$;

commit;
