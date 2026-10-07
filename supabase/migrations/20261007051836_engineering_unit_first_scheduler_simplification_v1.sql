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
  v_work_item_id bigint;
  v_work_status text;
  v_open_blockers integer := 0;
  v_unmet_deps integer := 0;
  v_claimable boolean := false;
begin
  v_exec := programacion.fn_engineering_unit_execution_admission_v1(
    p_plan_code,p_unit_code
  );

  select pu.work_item_id,w.status
    into v_work_item_id,v_work_status
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED'
  limit 1;

  if v_work_item_id is null then
    return coalesce(v_exec,'{}'::jsonb) || jsonb_build_object(
      'schema_version','ENGINEERING_UNIT_SCHEDULER_ADMISSION_V4',
      'claimable',false,
      'lane_mode','TRUE_BLOCK',
      'execution_permission','DENIED_UNIT_NOT_FOUND',
      'restriction_policy','CHECKPOINT_RESTRICTIONS_NEVER_GATE_UNIT_CLAIM'
    );
  end if;

  v_open_blockers :=
    programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id);

  select count(*)::integer
    into v_unmet_deps
  from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
  where d.is_unmet;

  v_claimable :=
    v_work_status in ('BACKLOG','READY','IN_PROGRESS')
    and coalesce(v_open_blockers,0)=0
    and coalesce(v_unmet_deps,0)=0;

  return coalesce(v_exec,'{}'::jsonb) || jsonb_build_object(
    'schema_version','ENGINEERING_UNIT_SCHEDULER_ADMISSION_V4',
    'claimable',v_claimable,
    'lane_mode',case when v_claimable then 'UNIT_READY' else 'TRUE_BLOCK' end,
    'execution_permission',
      case when v_claimable then 'ALLOWED_TO_CLAIM_UNIT'
           else 'DENIED_REAL_BLOCKER_OR_DEPENDENCY'
      end,
    'work_status',v_work_status,
    'open_blockers',coalesce(v_open_blockers,0),
    'unmet_dependencies',coalesce(v_unmet_deps,0),
    'checkpoint_execution_ready',
      coalesce((v_exec->>'admitted')::boolean,false),
    'checkpoint_action_spec_status',v_exec->>'action_spec_status',
    'restriction_policy','CHECKPOINT_RESTRICTIONS_NEVER_GATE_UNIT_CLAIM',
    'checkpoint_policy','VALIDATE_AND_RESOLVE_INSIDE_UNIT_LOOP'
  );
end;
$function$;

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
  update programacion.engineering_parallel_pilot_lane_runs
     set status='ERROR',
         finished_at=coalesce(finished_at,now()),
         result_summary=coalesce(result_summary,'LEASE_EXPIRED')
   where status='RUNNING'
     and lease_expires_at < now();

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
is 'ENGINEERING_PARALLEL_EXECUTOR_V1 selector. Claim eligibility is intentionally simple: assigned unit + BACKLOG/READY/IN_PROGRESS + zero real blockers + zero unmet effective dependencies + no active/same-run duplicate. Checkpoint/action-spec restrictions are handled inside the unit loop and never suppress lane claim.';

create or replace function programacion.fn_engineering_parallel_executor_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_EXECUTOR_V1'::text
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
      'run_definition','ONE_RUN_EQUALS_ONE_UNIT',
      'checkpoint_counting_policy','METRIC_ONLY_NOT_RUN_LIMIT',
      'selection_policy','DEPENDENCIES_CLEAR_AND_NO_REAL_BLOCKER',
      'contract_preflight','NON_BLOCKING_CHECKPOINT_LOCAL',
      'parallel_execution_contract',jsonb_build_object(
        'db_scheduler_role','CLAIM_REFILL_AND_STATE_ONLY',
        'lane_worker_model','ONE_WORKER_PER_UNIT',
        'dispatch_entrypoint','programacion.fn_engineering_parallel_executor_dispatch_bundle_v1',
        'claim_before_worker','DEPENDENCIES_AND_REAL_BLOCKERS_ONLY',
        'checkpoint_contracts','RESOLVE_INSIDE_UNIT_LOOP',
        'same_unit_double_claim','FORBIDDEN',
        'checkpoint_count_as_run','FORBIDDEN',
        'real_parallelism_condition','ACTIVE_LANES_MUST_BE_EXECUTED_CONCURRENTLY_BY_HOST'
      ),
      'unit_loop',jsonb_build_array(
        'BOOTSTRAP_CURRENT_CHECKPOINT',
        'RESOLVE_CURRENT_CHECKPOINT_CONTRACT_IF_NEEDED',
        'EXECUTE_CURRENT_CHECKPOINT',
        'HEARTBEAT_WHEN_REQUIRED',
        'CHECKPOINT_TRANSITION',
        'USE_RETURNED_BOOTSTRAP',
        'REPEAT_WITHOUT_INCREMENTING_UNIT_RUN',
        'STOP_ONLY_AT_UNIT_TERMINAL_OR_REAL_YIELD'
      ),
      'success_guard','WORK_ITEM_DONE_AND_REQUIRED_CHECKPOINTS_TERMINAL',
      'legacy_scheduler_storage',true
    );
end;
$function$;

create or replace function programacion.fn_engineering_parallel_executor_dispatch_bundle_v1(
  p_run_id bigint
)
returns jsonb
language sql
set search_path to 'programacion','public','pg_catalog'
as $function$
with r as (
  select id,plan_code,status,max_lanes,max_turns_per_lane
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id
),
lanes as materialized (
  select
    lr.lane_no,
    lr.turn_no,
    lr.unit_code,
    lr.status,
    programacion.fn_engineering_unit_scheduler_admission_v2(
      lr.plan_code,lr.unit_code
    ) as scheduler_admission,
    programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
      lr.plan_code,lr.unit_code
    ) as bootstrap
  from programacion.engineering_parallel_pilot_lane_runs lr
  join r on r.id=lr.run_id
  where lr.status='RUNNING'
  order by lr.lane_no,lr.turn_no
)
select jsonb_build_object(
  'schema_version','ENGINEERING_PARALLEL_DISPATCH_BUNDLE_V5',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'run_status',r.status,
  'run_definition','ONE_RUN_EQUALS_ONE_UNIT',
  'checkpoint_counting_policy','METRIC_ONLY_NOT_RUN_LIMIT',
  'dispatch_policy','CONCURRENT_UNIT_LANES',
  'worker_contract','ONE_WORKER_PER_UNIT_LOOP_CHECKPOINTS_UNTIL_TERMINAL_OR_REAL_YIELD',
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
          'worker_next_action','EXECUTE_UNIT_LOOP',
          'checkpoint_run_policy','DO_NOT_INCREMENT_UNIT_RUN',
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

update public.lf_error_knowledge
   set estado='SUPERSEDED',
       ultima_vez=now(),
       updated_at=now(),
       descripcion=descripcion || ' Superseded: checkpoint execution-readiness/reduction status no longer gates scheduler lane claim; only real blockers and effective dependencies do.'
 where codigo='ENGINEERING-PLAN-REDUCTION-BEFORE-LANE-CLAIM-001';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-UNIT-FIRST-SCHEDULER-SIMPLIFICATION-001',
  'ENGINEERING_ORCHESTRATION',
  'Scheduler claim is unit-first; checkpoint restrictions stay inside the unit loop',
  'The executor now claims units using only effective dependencies, real blockers, assignment and active-lane duplication. Action-spec/readiness/reduction states are checkpoint-local and cannot suppress lane claim. One executor run means one unit; all checkpoints are processed inside that unit run and checkpoint count is telemetry only.',
  'Checkpoint readiness was incorrectly promoted to a scheduler admission restriction, causing dependency-clear units to disappear from parallel lanes.',
  'CHECKPOINT_RESTRICTION_PROMOTED_TO_UNIT_CLAIM_BLOCK',
  'Keep scheduler selection simple. Claim the unit when dependencies are clear and real blockers are zero. Resolve checkpoint contracts inside the unit loop. Never count checkpoint transitions as unit runs.',
  'PASS when previously dependency-clear REDUCTION_REQUIRED units become claimable, picker candidate count is not reduced by action-spec status, and executor start contract reports ONE_RUN_EQUALS_ONE_UNIT plus checkpoint_counting_policy=METRIC_ONLY_NOT_RUN_LIMIT.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_unit_scheduler_admission_v2; supabase://programacion.fn_engineering_parallel_pilot_pick_unit_v1; supabase://programacion.fn_engineering_parallel_executor_start_v1; supabase://programacion.fn_engineering_parallel_executor_dispatch_bundle_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Unit-first executor simplification',
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
