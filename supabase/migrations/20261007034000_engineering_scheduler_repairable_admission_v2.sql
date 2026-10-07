-- ENGINEERING_PARALLEL_EXECUTOR_V1
-- Separate scheduler claimability from strict execution permission.
-- CONTRACT_REPAIR units may occupy a lane, but material execution remains fail-closed
-- until canonical execution admission becomes READY.

create or replace function programacion.fn_engineering_unit_scheduler_admission_v2(
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_exec jsonb;
  v_claimable boolean := false;
  v_lane_mode text := 'TRUE_BLOCK';
  v_action_status text;
  v_contract_source text;
  v_terminal text;
begin
  v_exec:=programacion.fn_engineering_unit_execution_admission_v1(
    p_plan_code,p_unit_code
  );

  v_action_status:=coalesce(v_exec->>'action_spec_status','');
  v_contract_source:=coalesce(v_exec->>'contract_source','');
  v_terminal:=coalesce(v_exec->>'terminal_action','');

  if coalesce((v_exec->>'admitted')::boolean,false) then
    v_claimable:=true;
    v_lane_mode:='EXECUTION_READY';
  elsif v_contract_source='EXPLICIT_ACTION_SPEC'
        and v_action_status like 'BLOCK_%'
        and v_terminal in ('STOP_ACTION_SPEC_INCOMPLETE','STOP_EXECUTION_PREFLIGHT') then
    v_claimable:=true;
    v_lane_mode:='CONTRACT_REPAIR';
  end if;

  return v_exec || jsonb_build_object(
    'schema_version','ENGINEERING_UNIT_SCHEDULER_ADMISSION_V2',
    'claimable',v_claimable,
    'lane_mode',v_lane_mode,
    'execution_permission',
      case when v_lane_mode='EXECUTION_READY' then 'ALLOWED'
           else 'DENIED_UNTIL_RECOMPILED_READY'
      end,
    'repair_rule',
      case when v_lane_mode='CONTRACT_REPAIR'
        then 'AUTHOR_OR_IMPLEMENT_MISSING_EXPLICIT_CONTRACT; REBOOTSTRAP; REQUIRE_EXECUTION_ADMISSION_PASS'
        else null
      end
  );
end;
$function$;

comment on function programacion.fn_engineering_unit_scheduler_admission_v2(text,text)
is 'Scheduler claimability is broader than execution admission. Explicit BLOCK_* contracts may be claimed as CONTRACT_REPAIR work, but execution permission stays fail-closed until canonical admission passes.';

create or replace function programacion.fn_engineering_parallel_pilot_pick_unit_v1(
  p_plan_code text,
  p_run_id bigint
)
returns text
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  r record;
  v_admission jsonb;
begin
  update programacion.engineering_parallel_pilot_lane_runs
     set status='ERROR',
         finished_at=coalesce(finished_at,now()),
         result_summary=coalesce(result_summary,'LEASE_EXPIRED')
   where status='RUNNING'
     and lease_expires_at < now();

  for r in
    select pu.unit_code
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
  loop
    v_admission:=programacion.fn_engineering_unit_scheduler_admission_v2(
      p_plan_code,r.unit_code
    );

    if coalesce((v_admission->>'claimable')::boolean,false) then
      return r.unit_code;
    end if;
  end loop;

  return null;
end;
$function$;

comment on function programacion.fn_engineering_parallel_pilot_pick_unit_v1(text,bigint)
is 'ENGINEERING_PARALLEL_EXECUTOR_V1 selector. Claims dependency-clear units when scheduler admission says EXECUTION_READY or CONTRACT_REPAIR. Strict execution permission is evaluated separately and remains fail-closed.';

create or replace function programacion.fn_engineering_parallel_executor_dispatch_bundle_v1(
  p_run_id bigint
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
with r as (
  select id,plan_code,status,max_lanes,max_turns_per_lane
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id
), lanes as materialized (
  select
    lr.lane_no,
    lr.turn_no,
    lr.unit_code,
    lr.status,
    programacion.fn_engineering_unit_scheduler_admission_v2(
      lr.plan_code,lr.unit_code
    ) as scheduler_admission,
    programacion.fn_engineering_unit_bootstrap_v3(
      lr.plan_code,lr.unit_code
    ) as bootstrap
  from programacion.engineering_parallel_pilot_lane_runs lr
  join r on r.id=lr.run_id
  where lr.status='RUNNING'
  order by lr.lane_no,lr.turn_no
)
select jsonb_build_object(
  'schema_version','ENGINEERING_PARALLEL_DISPATCH_BUNDLE_V2',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'run_status',r.status,
  'dispatch_policy','CONCURRENT_ACTIVE_LANES',
  'worker_contract','ONE_WORKER_PER_ACTIVE_LANE',
  'lane_count',(select count(*) from lanes),
  'lanes',coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'lane_no',lane_no,
          'turn_no',turn_no,
          'unit_code',unit_code,
          'status',status,
          'lane_mode',scheduler_admission->>'lane_mode',
          'scheduler_admission',scheduler_admission,
          'worker_next_action',
            case
              when scheduler_admission->>'lane_mode'='CONTRACT_REPAIR'
                then 'REPAIR_EXPLICIT_CONTRACT_THEN_REBOOTSTRAP_SAME_UNIT'
              when scheduler_admission->>'lane_mode'='EXECUTION_READY'
                then 'EXECUTE_CURRENT_PACKET'
              else 'YIELD_CURRENT_UNIT'
            end,
          'bootstrap',bootstrap
        )
        order by lane_no,turn_no
      )
      from lanes
    ),
    '[]'::jsonb
  )
)
from r;
$function$;

comment on function programacion.fn_engineering_parallel_executor_dispatch_bundle_v1(bigint)
is 'Dispatch bundle v2. Exposes lane_mode EXECUTION_READY or CONTRACT_REPAIR so host workers can repair missing explicit contracts without granting execution permission prematurely.';

create or replace function programacion.fn_engineering_parallel_executor_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_storage jsonb;
begin
  v_storage := programacion.fn_engineering_parallel_scheduler_storage_start_v1(
    p_plan_code,
    coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
  );

  return v_storage
    || jsonb_build_object(
      'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
      'execution_scope','UNIT_TO_TERMINAL',
      'selection_policy','DEPENDENCIES_CLEAR_AND_SCHEDULER_CLAIMABLE',
      'contract_preflight','EXECUTION_READY_OR_CONTRACT_REPAIR',
      'parallel_execution_contract',jsonb_build_object(
        'db_scheduler_role','CLAIM_REFILL_AND_STATE_ONLY',
        'lane_worker_model','EXTERNAL_CONCURRENT_WORKERS',
        'dispatch_entrypoint','programacion.fn_engineering_parallel_executor_dispatch_bundle_v1',
        'claim_before_worker','SCHEDULER_ADMISSION_REQUIRED',
        'execution_permission','CANONICAL_EXECUTION_ADMISSION_REQUIRED',
        'same_unit_double_claim','FORBIDDEN',
        'real_parallelism_condition','ACTIVE_LANES_MUST_BE_EXECUTED_CONCURRENTLY_BY_HOST'
      ),
      'unit_loop',jsonb_build_array(
        'SCHEDULER_ADMISSION',
        'CONTRACT_REPAIR_WHEN_REQUIRED',
        'REBOOTSTRAP_V3',
        'REQUIRE_EXECUTION_ADMISSION_PASS',
        'EXECUTE_CURRENT_PACKET',
        'HEARTBEAT_WHEN_REQUIRED',
        'CHECKPOINT_TRANSITION',
        'USE_RETURNED_BOOTSTRAP',
        'REPEAT_UNTIL_UNIT_TERMINAL_OR_YIELD'
      ),
      'success_guard','WORK_ITEM_DONE_AND_REQUIRED_CHECKPOINTS_TERMINAL',
      'legacy_scheduler_storage',true
    );
end;
$function$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-SCHEDULER-REPAIRABLE-ADMISSION-001',
  'ENGINEERING_ORCHESTRATION',
  'Scheduler must distinguish repairable contract work from true execution blocks',
  'Strict execution admission was reused as scheduler claim admission. After explicit-contract sanitation, dependency-clear units with BLOCK_* action specs could not obtain a lane, so no worker could repair the contract that was preventing execution.',
  'Scheduler eligibility and material execution permission were collapsed into one boolean gate.',
  'REPAIRABLE_WORK_REJECTED_BEFORE_WORKER_CLAIM',
  'Keep execution admission strict. Add scheduler admission with EXECUTION_READY, CONTRACT_REPAIR and TRUE_BLOCK. CONTRACT_REPAIR may claim a lane but may not execute material work until rebootstrap passes canonical execution admission.',
  'Pending live executor readback after migration.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_unit_scheduler_admission_v2; supabase://programacion.fn_engineering_parallel_pilot_pick_unit_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'ENGINEERING_PARALLEL_EXECUTOR_V1 scheduler admission after explicit contract sanitation',
  'supabase://programacion.fn_engineering_unit_scheduler_admission_v2'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  ultima_vez=now(),
  updated_at=now();
