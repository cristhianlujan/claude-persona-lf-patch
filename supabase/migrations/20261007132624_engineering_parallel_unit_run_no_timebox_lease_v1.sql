
create or replace function programacion.fn_engineering_parallel_pilot_pick_unit_v1(
  p_plan_code text,
  p_run_id bigint
)
returns text
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_unit text;
begin
  select pu.unit_code
    into v_unit
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w
    on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and w.status in ('BACKLOG','READY','IN_PROGRESS')
    and programacion.fn_engineering_effective_open_blocker_count_v1(w.id)=0
    and not exists (
      select 1
      from programacion.fn_engineering_effective_dependencies_v1(w.id) d
      where d.is_unmet
    )
    and not exists (
      select 1
      from programacion.engineering_parallel_pilot_lane_runs lr
      where lr.plan_code=p_plan_code
        and lr.unit_code=pu.unit_code
        and lr.status='RUNNING'
    )
    and not exists (
      select 1
      from programacion.engineering_parallel_pilot_lane_runs lr
      where lr.run_id=p_run_id
        and lr.unit_code=pu.unit_code
    )
  order by
    case w.priority
      when 'P0' then 0
      when 'P1' then 1
      when 'P2' then 2
      when 'P3' then 3
      else 9
    end,
    pu.id
  limit 1;

  return v_unit;
end;
$function$;

comment on function programacion.fn_engineering_parallel_pilot_pick_unit_v1(text,bigint)
is 'ENGINEERING_PARALLEL_EXECUTOR_V1 selector. A claimed unit is not auto-failed by wall-clock lease expiry. One run owns the unit until explicit terminal success, real yield, or execution error. Claim eligibility remains assigned + active work state + zero real blockers + zero unmet dependencies + no active/same-run duplicate.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-UNIT-RUN-LEASE-NOT-TIMEBOX-001',
  'ENGINEERING_ORCHESTRATION',
  'Unit runs must not expire while declared material execution is still in progress',
  'The parallel selector no longer marks RUNNING unit lanes ERROR merely because the fixed 15-minute lease timestamp elapsed. One executor run equals one unit and ends only by explicit success, yield or execution error.',
  'A fixed 15-minute scheduler lease was shorter than valid material checkpoints, so long-running RUN_TEST work was converted to LEASE_EXPIRED while still executing.',
  'LONG_UNIT_EXECUTION -> FIXED_15M_LEASE -> FALSE_ERROR',
  'Do not use wall-clock lease expiry as an implicit unit terminal transition. Recover stale lanes explicitly; active unit lifecycle is closed by executor completion.',
  'PASS when a unit can execute beyond the legacy 15-minute lease without pick_unit mutating its lane to ERROR/LEASE_EXPIRED.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_parallel_pilot_pick_unit_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Parallel unit run lease semantics',
  'supabase://programacion.fn_engineering_parallel_pilot_pick_unit_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
