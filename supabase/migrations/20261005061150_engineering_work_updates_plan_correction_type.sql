alter table programacion.engineering_work_updates
  drop constraint if exists engineering_work_updates_update_type_check;

alter table programacion.engineering_work_updates
  add constraint engineering_work_updates_update_type_check
  check (update_type = any (array[
    'PROGRESS'::text,
    'DECISION'::text,
    'RISK'::text,
    'BLOCKER'::text,
    'NEXT_STEP'::text,
    'DELIVERY'::text,
    'NOTE'::text,
    'PLAN_CORRECTION'::text
  ]));
