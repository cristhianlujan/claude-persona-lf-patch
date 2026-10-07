create or replace function programacion.fn_guard_engineering_dependency_cycle_v1()
returns trigger
language plpgsql
as $$
declare
  v_cycle boolean := false;
begin
  if new.relation_type <> 'REQUIRES' then
    return new;
  end if;

  if new.work_item_id = new.depends_on_work_item_id then
    raise exception using
      errcode = '23514',
      message = 'ENGINEERING_DEPENDENCY_CYCLE_FORBIDDEN: self dependency';
  end if;

  with recursive reachable(work_item_id) as (
    select new.depends_on_work_item_id
    union
    select d.depends_on_work_item_id
    from programacion.engineering_work_dependencies d
    join reachable r on d.work_item_id = r.work_item_id
    where d.relation_type = 'REQUIRES'
      and d.id <> case when tg_op = 'UPDATE' then old.id else -1 end
  )
  select exists (
    select 1 from reachable where work_item_id = new.work_item_id
  ) into v_cycle;

  if v_cycle then
    raise exception using
      errcode = '23514',
      message = format(
        'ENGINEERING_DEPENDENCY_CYCLE_FORBIDDEN: work_item_id=%s depends_on_work_item_id=%s',
        new.work_item_id,
        new.depends_on_work_item_id
      );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_engineering_dependency_cycle_v1 on programacion.engineering_work_dependencies;
create trigger trg_guard_engineering_dependency_cycle_v1
before insert or update of work_item_id, depends_on_work_item_id, relation_type
on programacion.engineering_work_dependencies
for each row
execute function programacion.fn_guard_engineering_dependency_cycle_v1();
