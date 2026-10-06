-- ENGINEERING parallel legacy-alias hardening + canonical EKB read.
-- Goals:
-- 1) ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1 is historical only.
-- 2) Any legacy pilot entrypoint routes to ENGINEERING_PARALLEL_EXECUTOR_V1 (UNIT_TO_TERMINAL).
-- 3) The scheduler storage primitive remains internal/compatibility-only.
-- 4) EKB reads use the canonical codigo column through one stable lookup helper.

create or replace function programacion.fn_engineering_parallel_scheduler_storage_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_run_id bigint;
  v_lane integer;
  v_unit text;
  v_work_item_id bigint;
  v_checkpoint_total integer;
  v_done_before integer;
  v_lanes jsonb := '[]'::jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_EXECUTOR:'||p_plan_code));

  insert into programacion.engineering_parallel_pilot_runs(
    plan_code,status,max_lanes,max_turns_per_lane,actor
  ) values (
    p_plan_code,'RUNNING',2,2,coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
  )
  returning id into v_run_id;

  for v_lane in 1..2 loop
    v_unit:=programacion.fn_engineering_parallel_pilot_pick_unit_v1(p_plan_code,v_run_id);
    if v_unit is null then
      exit;
    end if;

    select pu.work_item_id
      into v_work_item_id
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=v_unit
    limit 1;

    select count(*)::integer,
           count(*) filter (where c.status='DONE')::integer
      into v_checkpoint_total,v_done_before
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id;

    insert into programacion.engineering_parallel_pilot_lane_runs(
      run_id,lane_no,turn_no,plan_code,unit_code,status,
      checkpoint_total,checkpoints_done_before
    ) values (
      v_run_id,v_lane,1,p_plan_code,v_unit,'RUNNING',
      v_checkpoint_total,v_done_before
    );

    v_lanes:=v_lanes || jsonb_build_array(
      jsonb_build_object(
        'lane_no',v_lane,
        'turn_no',1,
        'unit_code',v_unit,
        'status','RUNNING',
        'checkpoint_total',v_checkpoint_total,
        'checkpoints_done_before',v_done_before
      )
    );
  end loop;

  if jsonb_array_length(v_lanes)=0 then
    update programacion.engineering_parallel_pilot_runs
       set status='DONE',finished_at=now(),
           summary=jsonb_build_object(
             'reason','NO_ELIGIBLE_UNITS',
             'checkpoints_completed',0
           )
     where id=v_run_id;
  end if;

  return jsonb_build_object(
    'scheduler_storage_contract','ENGINEERING_PARALLEL_SCHEDULER_STORAGE_V1',
    'run_id',v_run_id,
    'max_lanes',2,
    'max_turns_per_lane',2,
    'max_total_runs',4,
    'lane_count',jsonb_array_length(v_lanes),
    'lanes',v_lanes
  );
end;
$function$;

create or replace function programacion.fn_engineering_parallel_scheduler_storage_complete_and_refill_v1(
  p_run_id bigint,
  p_lane_no integer,
  p_turn_no integer,
  p_outcome text,
  p_bootstrap jsonb,
  p_context_admit boolean,
  p_context_reason text default null
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_plan_code text;
  v_unit text;
  v_work_item_id bigint;
  v_done_before integer;
  v_done_after integer;
  v_checkpoint_total integer;
  v_done_delta integer;
  v_next_unit text;
  v_next_turn integer;
  v_next_work_item_id bigint;
  v_next_checkpoint_total integer;
  v_next_done_before integer;
  v_next jsonb;
  v_active integer;
  v_run_status text;
begin
  if p_outcome not in ('SUCCESS','ERROR') then
    raise exception 'Unsupported scheduler storage outcome: %',p_outcome;
  end if;

  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_EXECUTOR_RUN:'||p_run_id::text));

  select lr.plan_code,lr.unit_code,lr.checkpoints_done_before,lr.checkpoint_total,
         pu.work_item_id
    into v_plan_code,v_unit,v_done_before,v_checkpoint_total,v_work_item_id
  from programacion.engineering_parallel_pilot_lane_runs lr
  join programacion.engineering_plan_units pu
    on pu.plan_code=lr.plan_code
   and pu.unit_code=lr.unit_code
  where lr.run_id=p_run_id
    and lr.lane_no=p_lane_no
    and lr.turn_no=p_turn_no
    and lr.status='RUNNING'
  for update of lr;

  if v_plan_code is null then
    raise exception 'Active lane turn not found: run %, lane %, turn %',
      p_run_id,p_lane_no,p_turn_no;
  end if;

  select count(*) filter (where c.status='DONE')::integer
    into v_done_after
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id;

  v_done_before:=coalesce(v_done_before,v_done_after,0);
  v_done_after:=coalesce(v_done_after,0);
  v_done_delta:=greatest(v_done_after-v_done_before,0);

  update programacion.engineering_parallel_pilot_lane_runs
     set status=p_outcome,
         finished_at=now(),
         bootstrap_terminal_action=p_bootstrap->>'terminal_action',
         bootstrap_engine_variant=p_bootstrap->>'engine_variant',
         bootstrap_execution_allowed=coalesce((p_bootstrap->>'execution_allowed')::boolean,false),
         result_summary=case
           when p_outcome='SUCCESS' then 'BOOTSTRAP_RETURNED'
           else 'BOOTSTRAP_ERROR'
         end,
         context_admit=p_context_admit,
         context_reason=p_context_reason,
         checkpoints_done_after=v_done_after,
         checkpoints_done_delta=v_done_delta
   where run_id=p_run_id
     and lane_no=p_lane_no
     and turn_no=p_turn_no;

  if p_turn_no < 2 and coalesce(p_context_admit,false) then
    v_next_turn:=p_turn_no+1;
    v_next_unit:=programacion.fn_engineering_parallel_pilot_pick_unit_v1(v_plan_code,p_run_id);

    if v_next_unit is not null then
      select pu.work_item_id
        into v_next_work_item_id
      from programacion.engineering_plan_units pu
      where pu.plan_code=v_plan_code
        and pu.unit_code=v_next_unit
      limit 1;

      select count(*)::integer,
             count(*) filter (where c.status='DONE')::integer
        into v_next_checkpoint_total,v_next_done_before
      from programacion.engineering_work_checkpoints c
      where c.work_item_id=v_next_work_item_id;

      insert into programacion.engineering_parallel_pilot_lane_runs(
        run_id,lane_no,turn_no,plan_code,unit_code,status,
        checkpoint_total,checkpoints_done_before
      ) values (
        p_run_id,p_lane_no,v_next_turn,v_plan_code,v_next_unit,'RUNNING',
        v_next_checkpoint_total,v_next_done_before
      );

      v_next:=jsonb_build_object(
        'lane_no',p_lane_no,
        'turn_no',v_next_turn,
        'unit_code',v_next_unit,
        'status','RUNNING',
        'checkpoint_total',v_next_checkpoint_total,
        'checkpoints_done_before',v_next_done_before
      );
    end if;
  end if;

  select count(*) into v_active
  from programacion.engineering_parallel_pilot_lane_runs
  where run_id=p_run_id and status='RUNNING';

  if v_active=0 then
    update programacion.engineering_parallel_pilot_runs
       set status='DONE',
           finished_at=now(),
           summary=jsonb_build_object(
             'completed_lane_runs',
             (select count(*) from programacion.engineering_parallel_pilot_lane_runs
               where run_id=p_run_id and status in ('SUCCESS','ERROR')),
             'contract_max_total_runs',4,
             'checkpoints_completed',
             (select coalesce(sum(checkpoints_done_delta),0)
                from programacion.engineering_parallel_pilot_lane_runs
               where run_id=p_run_id)
           )
     where id=p_run_id;
  end if;

  select status into v_run_status
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id;

  return jsonb_build_object(
    'scheduler_storage_contract','ENGINEERING_PARALLEL_SCHEDULER_STORAGE_V1',
    'run_id',p_run_id,
    'lane_no',p_lane_no,
    'completed_turn',p_turn_no,
    'completed_unit',v_unit,
    'outcome',p_outcome,
    'context_admit',p_context_admit,
    'checkpoint_total',v_checkpoint_total,
    'checkpoints_done_before',v_done_before,
    'checkpoints_done_after',v_done_after,
    'checkpoints_done_delta',v_done_delta,
    'next',v_next,
    'active_lanes',v_active,
    'run_status',v_run_status
  );
end;
$function$;

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
      'unit_loop',jsonb_build_array(
        'BOOTSTRAP_V3',
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

create or replace function programacion.fn_engineering_parallel_executor_complete_and_refill_v1(
  p_run_id bigint,
  p_lane_no integer,
  p_turn_no integer,
  p_outcome text,
  p_bootstrap jsonb,
  p_context_admit boolean,
  p_context_reason text default null
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_plan_code text;
  v_unit_code text;
  v_work_item_id bigint;
  v_work_status text;
  v_required_open integer;
  v_storage_outcome text;
  v_result jsonb;
begin
  if p_outcome not in ('SUCCESS','YIELDED','ERROR') then
    raise exception 'Unsupported executor outcome: %',p_outcome;
  end if;

  select lr.plan_code,lr.unit_code,pu.work_item_id,w.status
    into v_plan_code,v_unit_code,v_work_item_id,v_work_status
  from programacion.engineering_parallel_pilot_lane_runs lr
  join programacion.engineering_plan_units pu
    on pu.plan_code=lr.plan_code and pu.unit_code=lr.unit_code
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where lr.run_id=p_run_id
    and lr.lane_no=p_lane_no
    and lr.turn_no=p_turn_no
    and lr.status='RUNNING';

  if v_unit_code is null then
    raise exception 'Active executor lane turn not found: run %, lane %, turn %',
      p_run_id,p_lane_no,p_turn_no;
  end if;

  select count(*)::integer
    into v_required_open
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE');

  if p_outcome='SUCCESS'
     and (v_work_status <> 'DONE' or v_required_open <> 0) then
    raise exception
      'UNIT_NOT_TERMINAL: %/% status=% required_open=%; SUCCESS forbidden until unit terminal',
      v_plan_code,v_unit_code,coalesce(v_work_status,'NULL'),v_required_open;
  end if;

  v_storage_outcome := case when p_outcome='SUCCESS' then 'SUCCESS' else 'ERROR' end;

  v_result := programacion.fn_engineering_parallel_scheduler_storage_complete_and_refill_v1(
    p_run_id,
    p_lane_no,
    p_turn_no,
    v_storage_outcome,
    p_bootstrap,
    p_context_admit,
    p_context_reason
  );

  if p_outcome='YIELDED' then
    update programacion.engineering_parallel_pilot_lane_runs
       set result_summary='UNIT_YIELDED',
           context_reason=coalesce(nullif(p_context_reason,''),'CURRENT_UNIT_YIELDED')
     where run_id=p_run_id
       and lane_no=p_lane_no
       and turn_no=p_turn_no;
  elsif p_outcome='ERROR' then
    update programacion.engineering_parallel_pilot_lane_runs
       set result_summary='UNIT_EXECUTION_ERROR'
     where run_id=p_run_id
       and lane_no=p_lane_no
       and turn_no=p_turn_no;
  else
    update programacion.engineering_parallel_pilot_lane_runs
       set result_summary='UNIT_TERMINAL_SUCCESS'
     where run_id=p_run_id
       and lane_no=p_lane_no
       and turn_no=p_turn_no;
  end if;

  return v_result || jsonb_build_object(
    'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
    'execution_scope','UNIT_TO_TERMINAL',
    'executor_outcome',p_outcome,
    'unit_status_after',v_work_status,
    'required_checkpoints_open_after',v_required_open
  );
end;
$function$;

-- Historical aliases: never expose BOOTSTRAP_ONLY semantics again.
create or replace function programacion.fn_engineering_parallel_pilot_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_result jsonb;
begin
  v_result := programacion.fn_engineering_parallel_executor_start_v1(
    p_plan_code,
    'ENGINEERING_PARALLEL_EXECUTOR_V1'
  );

  return v_result || jsonb_build_object(
    'requested_contract','ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1',
    'resolved_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
    'legacy_alias',true,
    'legacy_alias_actor',p_actor
  );
end;
$function$;

create or replace function programacion.fn_engineering_parallel_pilot_complete_and_refill_v1(
  p_run_id bigint,
  p_lane_no integer,
  p_turn_no integer,
  p_outcome text,
  p_bootstrap jsonb,
  p_context_admit boolean,
  p_context_reason text default null
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
begin
  if p_outcome not in ('SUCCESS','ERROR') then
    raise exception 'Legacy alias accepts SUCCESS|ERROR only; use executor entrypoint for YIELDED';
  end if;

  return programacion.fn_engineering_parallel_executor_complete_and_refill_v1(
    p_run_id,p_lane_no,p_turn_no,p_outcome,p_bootstrap,p_context_admit,p_context_reason
  ) || jsonb_build_object(
    'requested_contract','ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1',
    'resolved_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
    'legacy_alias',true
  );
end;
$function$;

create or replace function programacion.fn_engineering_parallel_pilot_status_v1(
  p_run_id bigint
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
select programacion.fn_engineering_parallel_executor_status_v2(p_run_id)
       || jsonb_build_object(
            'requested_contract','ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1',
            'resolved_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
            'legacy_alias',true
          );
$function$;

comment on function programacion.fn_engineering_parallel_scheduler_storage_start_v1(text,text)
is 'Internal scheduler storage primitive for ENGINEERING_PARALLEL_EXECUTOR_V1. Not a user-facing execution contract.';

comment on function programacion.fn_engineering_parallel_scheduler_storage_complete_and_refill_v1(bigint,integer,integer,text,jsonb,boolean,text)
is 'Internal scheduler storage completion/refill primitive. Canonical execution semantics belong to fn_engineering_parallel_executor_complete_and_refill_v1.';

comment on function programacion.fn_engineering_parallel_pilot_start_v1(text,text)
is 'SUPERSEDED legacy alias. Always resolves to ENGINEERING_PARALLEL_EXECUTOR_V1 with UNIT_TO_TERMINAL semantics; never BOOTSTRAP_ONLY.';

comment on function programacion.fn_engineering_parallel_pilot_complete_and_refill_v1(bigint,integer,integer,text,jsonb,boolean,text)
is 'SUPERSEDED legacy alias. Delegates to canonical parallel executor completion.';

comment on function programacion.fn_engineering_parallel_pilot_status_v1(bigint)
is 'SUPERSEDED legacy alias. Delegates to ENGINEERING_PARALLEL_EXECUTOR_REPORT_V2.';

create or replace function programacion.fn_engineering_ekb_lookup_v1(
  p_search text default null,
  p_codes text[] default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit,25),1),100);
  v_search text := nullif(btrim(coalesce(p_search,'')),'');
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(q) order by q.ultima_vez desc nulls last,q.codigo),'[]'::jsonb)
    into v_rows
  from (
    select
      e.id,e.codigo,e.categoria,e.titulo,e.descripcion,e.causa_raiz,e.patron,
      e.prevencion,e.validacion,e.severidad,e.frecuencia,e.primera_vez,e.ultima_vez,
      e.lote_origen,e.pr,e.estado,e.evidencia,e.lifecycle_phase,e.consumer_role,
      e.root_cause_family,e.detectability,e.source_context,e.source_ref
    from public.lf_error_knowledge e
    where (p_codes is null or e.codigo=any(p_codes))
      and (
        v_search is null
        or concat_ws(
          ' ',
          e.codigo,e.categoria,e.titulo,e.descripcion,e.causa_raiz,e.patron,
          e.prevencion,e.validacion,e.lote_origen,e.estado,e.source_context,e.source_ref
        ) ilike '%'||v_search||'%'
      )
    order by e.ultima_vez desc nulls last,e.codigo
    limit v_limit
  ) q;

  return jsonb_build_object(
    'schema_version','ENGINEERING_EKB_LOOKUP_V1',
    'authority','public.lf_error_knowledge',
    'canonical_code_column','codigo',
    'deprecated_or_invalid_code_columns',jsonb_build_array('error_code'),
    'search',v_search,
    'codes',to_jsonb(p_codes),
    'limit',v_limit,
    'row_count',jsonb_array_length(v_rows),
    'rows',v_rows
  );
end;
$function$;

comment on function programacion.fn_engineering_ekb_lookup_v1(text,text[],integer)
is 'Canonical engineering EKB read helper. Uses public.lf_error_knowledge.codigo; callers must not assume error_code exists.';

update public.lf_error_knowledge
set estado='SUPERSEDED',
    validacion='SUPERSEDED 2026-10-06: historical bootstrap-only pilot is not an executable contract. The legacy pilot start/status/complete functions now resolve to ENGINEERING_PARALLEL_EXECUTOR_V1 / UNIT_TO_TERMINAL. Canonical start is programacion.fn_engineering_parallel_executor_start_v1.',
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'[SUPERSESSION_20261006] Legacy alias -> ENGINEERING_PARALLEL_EXECUTOR_V1; direct BOOTSTRAP_ONLY semantics removed from alias entrypoints.'),
    source_ref='supabase://programacion.fn_engineering_parallel_executor_start_v1',
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-PARALLEL-BOOTSTRAP-PILOT-001';

update public.lf_error_knowledge
set validacion='PASS 2026-10-06: canonical ENGINEERING_PARALLEL_EXECUTOR_V1 executes UNIT_TO_TERMINAL. Legacy ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1 entrypoints are compatibility aliases that resolve to the executor; calling the old start returns executor_contract=ENGINEERING_PARALLEL_EXECUTOR_V1 and execution_scope=UNIT_TO_TERMINAL.',
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'[LEGACY_ALIAS_HARDENING_20261006] pilot entrypoints delegate to executor; internal storage primitive separated.'),
    source_ref='supabase://programacion.fn_engineering_parallel_executor_start_v1',
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-PARALLEL-EXECUTOR-V1-001';

update public.lf_error_knowledge
set validacion='PASS 2026-10-06: engineering EKB read must use programacion.fn_engineering_ekb_lookup_v1 or the live schema. Canonical code column is codigo; error_code does not exist on public.lf_error_knowledge. A raw query that assumes error_code is a caller regression and must not be treated as an EKB defect.',
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'[CANONICAL_EKB_READ_20261006] fn_engineering_ekb_lookup_v1 publishes canonical_code_column=codigo and invalid alias error_code.'),
    source_ref='supabase://programacion.fn_engineering_ekb_lookup_v1',
    ultima_vez=now(),
    updated_at=now()
where codigo='OPS-EKB-SCHEMA-CONSTRAINT-ASSUMPTION-001';

do $verify$
declare
  v_alias jsonb;
  v_lookup jsonb;
begin
  v_alias := programacion.fn_engineering_parallel_pilot_start_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1'
  );

  if v_alias->>'executor_contract' <> 'ENGINEERING_PARALLEL_EXECUTOR_V1'
     or v_alias->>'execution_scope' <> 'UNIT_TO_TERMINAL'
     or coalesce((v_alias->>'legacy_alias')::boolean,false) is not true
     or v_alias ? 'pilot_contract' then
    raise exception 'BLOCK_LEGACY_ALIAS_NOT_RESOLVED_TO_EXECUTOR:%',v_alias::text;
  end if;

  v_lookup := programacion.fn_engineering_ekb_lookup_v1('parallel',null,5);

  if v_lookup->>'canonical_code_column' <> 'codigo'
     or coalesce((v_lookup->>'row_count')::integer,0) < 1 then
    raise exception 'BLOCK_CANONICAL_EKB_LOOKUP_INVALID:%',v_lookup::text;
  end if;
end;
$verify$;
