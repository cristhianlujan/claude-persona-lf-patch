-- Reconcile stale dependency-derived engineering blockers against the canonical dependency graph.
-- Scope is intentionally narrow: only blockers sourced from the canonical work-items + dependencies readback
-- are auto-resolved, and only when the owning work item has zero unmet REQUIRES dependencies.

create or replace function programacion.fn_engineering_reconcile_dependency_blockers_v1(
  p_work_item_id bigint default null,
  p_actor text default 'ENGINEERING_DEPENDENCY_BLOCKER_RECONCILER_V1'
)
returns integer
language plpgsql
security invoker
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_resolved integer := 0;
begin
  with candidates as materialized (
    select b.id
    from programacion.engineering_work_blockers b
    where b.status = 'OPEN'
      and (p_work_item_id is null or b.work_item_id = p_work_item_id)
      and b.source_ref like 'supabase://programacion.engineering_work_items+programacion.engineering_work_dependencies%'
      and not exists (
        select 1
        from programacion.engineering_work_dependencies d
        join programacion.engineering_work_items dw on dw.id = d.depends_on_work_item_id
        where d.work_item_id = b.work_item_id
          and d.relation_type = 'REQUIRES'
          and coalesce(dw.status,'BACKLOG') <> 'DONE'
      )
  ), updated as (
    update programacion.engineering_work_blockers b
       set status = 'RESOLVED',
           resolved_at = now(),
           resolution_ref = 'supabase://programacion.fn_engineering_reconcile_dependency_blockers_v1?reason=NO_UNMET_REQUIRES',
           updated_by_execution_id = coalesce(nullif(p_actor,''),'ENGINEERING_DEPENDENCY_BLOCKER_RECONCILER_V1')
      from candidates c
     where b.id = c.id
     returning b.id
  )
  select count(*)::integer into v_resolved from updated;

  return v_resolved;
end;
$function$;

revoke all on function programacion.fn_engineering_reconcile_dependency_blockers_v1(bigint,text) from public;
grant execute on function programacion.fn_engineering_reconcile_dependency_blockers_v1(bigint,text) to postgres;

create or replace function programacion.fn_engineering_reconcile_dependency_blocker_insert_v1()
returns trigger
language plpgsql
security invoker
set search_path to 'programacion','public','pg_catalog'
as $function$
begin
  if new.status = 'OPEN'
     and new.source_ref like 'supabase://programacion.engineering_work_items+programacion.engineering_work_dependencies%'
  then
    perform programacion.fn_engineering_reconcile_dependency_blockers_v1(
      new.work_item_id,
      'ENGINEERING_DEPENDENCY_BLOCKER_INSERT_TRIGGER_V1'
    );
  end if;
  return new;
end;
$function$;

create or replace function programacion.fn_engineering_reconcile_dependency_work_status_v1()
returns trigger
language plpgsql
security invoker
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
begin
  if new.status is distinct from old.status then
    for v_work_item_id in
      select distinct d.work_item_id
      from programacion.engineering_work_dependencies d
      where d.depends_on_work_item_id = new.id
        and d.relation_type = 'REQUIRES'
    loop
      perform programacion.fn_engineering_reconcile_dependency_blockers_v1(
        v_work_item_id,
        'ENGINEERING_DEPENDENCY_STATUS_TRIGGER_V1'
      );
    end loop;
  end if;
  return new;
end;
$function$;

create or replace function programacion.fn_engineering_reconcile_dependency_edge_v1()
returns trigger
language plpgsql
security invoker
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
begin
  v_work_item_id := case when tg_op = 'DELETE' then old.work_item_id else new.work_item_id end;

  perform programacion.fn_engineering_reconcile_dependency_blockers_v1(
    v_work_item_id,
    'ENGINEERING_DEPENDENCY_EDGE_TRIGGER_V1'
  );

  if tg_op = 'UPDATE' and old.work_item_id is distinct from new.work_item_id then
    perform programacion.fn_engineering_reconcile_dependency_blockers_v1(
      old.work_item_id,
      'ENGINEERING_DEPENDENCY_EDGE_TRIGGER_V1'
    );
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

drop trigger if exists trg_engineering_reconcile_dependency_blocker_insert_v1 on programacion.engineering_work_blockers;
create trigger trg_engineering_reconcile_dependency_blocker_insert_v1
after insert on programacion.engineering_work_blockers
for each row execute function programacion.fn_engineering_reconcile_dependency_blocker_insert_v1();

drop trigger if exists trg_engineering_reconcile_dependency_work_status_v1 on programacion.engineering_work_items;
create trigger trg_engineering_reconcile_dependency_work_status_v1
after update of status on programacion.engineering_work_items
for each row execute function programacion.fn_engineering_reconcile_dependency_work_status_v1();

drop trigger if exists trg_engineering_reconcile_dependency_edge_v1 on programacion.engineering_work_dependencies;
create trigger trg_engineering_reconcile_dependency_edge_v1
after insert or update or delete on programacion.engineering_work_dependencies
for each row execute function programacion.fn_engineering_reconcile_dependency_edge_v1();

-- Backfill currently stale dependency-derived blockers, including M3.9 if its canonical REQUIRES set is satisfied.
select programacion.fn_engineering_reconcile_dependency_blockers_v1(
  null,
  'MIGRATION_20261005180500_DEPENDENCY_BLOCKER_RECONCILIATION_V1'
);
