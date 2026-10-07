-- ENGINEERING plan contract reduction prepass v1.
-- Root change: contract authoring/implementation debt is plan-reduction work,
-- not lane work. ENGINEERING_PARALLEL_EXECUTOR_V1 claims EXECUTION_READY only.

create or replace function programacion.fn_engineering_plan_contract_reduction_v1(
  p_plan_code text
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
with p as materialized (
  select programacion.fn_engineering_plan_execution_preflight_v1(p_plan_code) as x
),
reasons as (
  select
    e.key as reason_code,
    (e.value #>> '{}')::int as item_count
  from p
  cross join lateral jsonb_each(coalesce(p.x->'reason_counts','{}'::jsonb)) e
),
grouped as (
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reason_code',reason_code,
          'item_count',item_count
        )
        order by item_count desc,reason_code
      ) filter (where reason_code<>'COMPILE_NOT_READY'),
      '[]'::jsonb
    ) as blocker_families
  from reasons
)
select jsonb_build_object(
  'schema_version','ENGINEERING_PLAN_CONTRACT_REDUCTION_V1',
  'plan_code',p_plan_code,
  'pending_checkpoints',coalesce((p.x->>'pending_checkpoints')::int,0),
  'execution_ready',coalesce((p.x->>'execution_ready')::int,0),
  'not_ready',coalesce((p.x->>'not_ready')::int,0),
  'compile_not_ready',coalesce((p.x#>>'{reason_counts,COMPILE_NOT_READY}')::int,0),
  'blocker_families',g.blocker_families,
  'lane_policy','EXECUTION_READY_ONLY',
  'reduction_policy','GROUP_AND_REPAIR_BEFORE_LANE_CLAIM',
  'repair_scope','PLAN_WIDE_FAMILY_FIRST',
  'false_ready_policy','FORBIDDEN',
  'unit_lane_contract_repair','FORBIDDEN',
  'source_preflight','programacion.fn_engineering_plan_execution_preflight_v1'
)
from p cross join grouped g;
$function$;

comment on function programacion.fn_engineering_plan_contract_reduction_v1(text)
is 'Plan-wide contract reduction prepass. Groups current execution blockers before scheduling. Contract repair stays outside lane execution; only canonical EXECUTION_READY units may be claimed.';

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
    v_claimable:=false;
    v_lane_mode:='REDUCTION_REQUIRED';
  end if;

  return v_exec || jsonb_build_object(
    'schema_version','ENGINEERING_UNIT_SCHEDULER_ADMISSION_V3',
    'claimable',v_claimable,
    'lane_mode',v_lane_mode,
    'execution_permission',
      case when v_lane_mode='EXECUTION_READY' then 'ALLOWED'
           else 'DENIED_UNTIL_PLAN_REDUCTION_REPAIRS_CONTRACT'
      end,
    'repair_rule',
      case when v_lane_mode='REDUCTION_REQUIRED'
        then 'GROUP_WITH_SAME_BLOCKER_FAMILY_AND_REPAIR_AT_PLAN_REDUCTION; REBOOTSTRAP; REQUIRE_EXECUTION_ADMISSION_PASS'
        else null
      end
  );
end;
$function$;

comment on function programacion.fn_engineering_unit_scheduler_admission_v2(text,text)
is 'Scheduler admission v3 semantics: only canonical EXECUTION_READY units are claimable. Explicit contract debt is REDUCTION_REQUIRED and must be repaired plan-wide before lane claim.';

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

    if coalesce((v_admission->>'claimable')::boolean,false)
       and v_admission->>'lane_mode'='EXECUTION_READY' then
      return r.unit_code;
    end if;
  end loop;

  return null;
end;
$function$;

comment on function programacion.fn_engineering_parallel_pilot_pick_unit_v1(text,bigint)
is 'ENGINEERING_PARALLEL_EXECUTOR_V1 selector. Claims dependency-clear units only when canonical scheduler admission is EXECUTION_READY. REDUCTION_REQUIRED units never consume lanes.';

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
  'schema_version','ENGINEERING_PARALLEL_DISPATCH_BUNDLE_V3',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'run_status',r.status,
  'dispatch_policy','CONCURRENT_EXECUTION_READY_LANES',
  'worker_contract','ONE_WORKER_PER_EXECUTION_READY_LANE',
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
              when scheduler_admission->>'lane_mode'='EXECUTION_READY'
                then 'EXECUTE_CURRENT_PACKET'
              when scheduler_admission->>'lane_mode'='REDUCTION_REQUIRED'
                then 'YIELD_TO_PLAN_REDUCTION'
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
is 'Dispatch bundle v3. Normal execution contains EXECUTION_READY lanes only. Any stale legacy lane that recompiles to REDUCTION_REQUIRED must yield to plan reduction and may not repair contracts in-lane.';

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
  v_reduction jsonb;
begin
  v_reduction:=programacion.fn_engineering_plan_contract_reduction_v1(
    p_plan_code
  );

  v_storage := programacion.fn_engineering_parallel_scheduler_storage_start_v1(
    p_plan_code,
    coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
  );

  return v_storage
    || jsonb_build_object(
      'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
      'execution_scope','UNIT_TO_TERMINAL',
      'selection_policy','DEPENDENCIES_CLEAR_AND_EXECUTION_READY_ONLY',
      'contract_preflight','PLAN_REDUCTION_THEN_CANONICAL_EXECUTION_ADMISSION',
      'contract_reduction',v_reduction,
      'parallel_execution_contract',jsonb_build_object(
        'db_scheduler_role','CLAIM_REFILL_AND_STATE_ONLY',
        'lane_worker_model','EXTERNAL_CONCURRENT_WORKERS',
        'dispatch_entrypoint','programacion.fn_engineering_parallel_executor_dispatch_bundle_v1',
        'claim_before_worker','EXECUTION_READY_ADMISSION_REQUIRED',
        'execution_permission','CANONICAL_EXECUTION_ADMISSION_REQUIRED',
        'contract_repair_in_lane','FORBIDDEN',
        'same_unit_double_claim','FORBIDDEN',
        'real_parallelism_condition','ACTIVE_LANES_MUST_BE_EXECUTED_CONCURRENTLY_BY_HOST'
      ),
      'unit_loop',jsonb_build_array(
        'PLAN_CONTRACT_REDUCTION_PREPASS',
        'SCHEDULER_EXECUTION_READY_ADMISSION',
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

update public.lf_error_knowledge
set estado='SUPERSEDED',
    validacion='SUPERSEDED 2026-10-07: CONTRACT_REPAIR no longer consumes executor lanes. Contract debt is grouped by plan reduction before scheduler claim; canonical lanes require EXECUTION_READY.',
    evidencia=coalesce(evidencia,'') || E'\\n[SUPERSEDED_BY_PLAN_REDUCTION_20261007] programacion.fn_engineering_plan_contract_reduction_v1; scheduler admission REDUCTION_REQUIRED is non-claimable.',
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-SCHEDULER-REPAIRABLE-ADMISSION-001';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-PLAN-REDUCTION-BEFORE-LANE-CLAIM-001',
  'ENGINEERING_ORCHESTRATION',
  'Contract debt must be reduced plan-wide before parallel lane claim',
  'Run 23 consumed five lane turns only to rediscover explicit contract debt. The same debt is deterministic at plan preflight and must be grouped and repaired by blocker family before scheduler claim.',
  'Repairable contract admission moved contract authoring into per-unit lane execution instead of resolving repeated debt during plan reduction.',
  'CONTRACT_REPAIR_LANE_AMPLIFIES_PLAN_DEBT',
  'Run fn_engineering_plan_contract_reduction_v1 before scheduler storage start. Group blockers plan-wide, repair common contract families once, recompile canonical admission, and claim only EXECUTION_READY units. REDUCTION_REQUIRED is never lane-claimable.',
  'PASS when executor start exposes contract_reduction, selector claims only EXECUTION_READY, run 23 blocker units are REDUCTION_REQUIRED/claimable=false, and a new executor run does not consume lanes for contract-only repair.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_plan_contract_reduction_v1; supabase://programacion.fn_engineering_unit_scheduler_admission_v2; supabase://programacion.fn_engineering_parallel_executor_start_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'ENGINEERING_PARALLEL_EXECUTOR_V1 run 23 contract-repair lane waste',
  'supabase://programacion.fn_engineering_plan_contract_reduction_v1'
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
