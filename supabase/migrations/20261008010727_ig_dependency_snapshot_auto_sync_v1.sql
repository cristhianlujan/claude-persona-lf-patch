-- IG plan authority: subscribe the existing dependency table to canonical SOURCE_PACK/snapshot read model.
-- Reuses the already-installed cycle guard and cancelled-dependency guard; does not duplicate validation.
-- Scope only IG_CURATOR_VALIDATOR_REFACTOR_V2 ASSIGNED units; no lifecycle/status mutations.
create or replace function programacion.fn_ig_dependency_snapshot_auto_sync_v1()
returns trigger language plpgsql security definer
set search_path='pg_catalog','programacion','public'
as $fn$
declare
  v_ids bigint[];
  v_unit record;
  v_deps jsonb;
begin
  v_ids:=case tg_op
    when 'INSERT' then array[new.work_item_id]
    when 'DELETE' then array[old.work_item_id]
    else array[old.work_item_id,new.work_item_id] end;
  for v_unit in
    select u.plan_code,u.unit_code,u.work_item_id
    from programacion.engineering_plan_units u
    where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and u.disposition='ASSIGNED'
      and u.work_item_id=any(v_ids)
    order by u.unit_code
  loop
    select coalesce(jsonb_agg(to_jsonb(z.dep_code) order by z.dep_code),'[]'::jsonb)
      into v_deps
    from (
      select distinct coalesce(t.unit_code,w.work_code) dep_code
      from programacion.engineering_work_dependencies d
      left join programacion.engineering_plan_units t
        on t.work_item_id=d.depends_on_work_item_id and t.plan_code=v_unit.plan_code
      left join programacion.engineering_work_items w on w.id=d.depends_on_work_item_id
      where d.work_item_id=v_unit.work_item_id and d.relation_type='REQUIRES'
    ) z
    where z.dep_code is not null;
    update programacion.engineering_plan_units u
    set unit_metadata=jsonb_set(
      jsonb_set(u.unit_metadata,'{source_pack_v1,exact_dependencies}',v_deps,true),
      '{dependency_snapshot_v1}',
        coalesce(u.unit_metadata->'dependency_snapshot_v1','{}'::jsonb)
        ||jsonb_build_object(
           'contract','PLAN_DEPENDENCY_SNAPSHOT_V1',
           'authority','programacion.engineering_work_dependencies',
           'rule','SOURCE_PACK_DEPENDENCIES_ARE_DERIVED_FROM_CANONICAL_GRAPH_NOT_MANUALLY_MAINTAINED',
           'refs',v_deps,'count',jsonb_array_length(v_deps),'generated_at',now()
         ),
      true)
    where u.plan_code=v_unit.plan_code
      and u.unit_code=v_unit.unit_code
      and u.work_item_id=v_unit.work_item_id;
  end loop;
  return null;
end $fn$;

revoke all on function programacion.fn_ig_dependency_snapshot_auto_sync_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists trg_ig_dependency_snapshot_auto_sync_v1
 on programacion.engineering_work_dependencies;

create trigger trg_ig_dependency_snapshot_auto_sync_v1
after insert or update of work_item_id,depends_on_work_item_id,relation_type or delete
on programacion.engineering_work_dependencies
for each row execute function programacion.fn_ig_dependency_snapshot_auto_sync_v1();

comment on function programacion.fn_ig_dependency_snapshot_auto_sync_v1() is
'IG plan canonical dependency snapshot derived on each graph edge mutation. Does not alter graph, decisions or statuses. Existing cycle and cancelled guards remain authoritative.';

do $verify$
begin
 if (select count(*) from pg_trigger
     where tgrelid='programacion.engineering_work_dependencies'::regclass
       and tgname='trg_guard_engineering_dependency_cycle_v1' and not tgisinternal)<>1
    or (select count(*) from pg_trigger
     where tgrelid='programacion.engineering_work_dependencies'::regclass
       and tgname='trg_ig_dependency_snapshot_auto_sync_v1' and not tgisinternal)<>1 then
   raise exception 'IG_DEPENDENCY_GUARD_OR_SYNC_HOOK_MISSING';
 end if;
end $verify$;
