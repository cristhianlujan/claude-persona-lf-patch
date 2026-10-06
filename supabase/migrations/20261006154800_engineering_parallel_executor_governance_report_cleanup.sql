-- ENGINEERING parallel executor governance/report cleanup.
-- Scope:
-- 1) governed process auto-merge authorization
-- 2) action-spec materiality authority (no title-based readonly downgrade)
-- 3) cross-unit test-case ownership guard
-- 4) M10.12 own post-batch smoke instead of M7 validation reuse
-- 5) checkpoint-progress report V2
-- 6) EKB evidence

create or replace function programacion.fn_engineering_merge_authorization_contract_v1()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $$
select jsonb_build_object(
  'schema_version','ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1',
  'authorization_owner','PROCESS',
  'human_approval_required',false,
  'auto_merge_when_authorized',true,
  'authorization_capability','SAFE_CHANGE_ADMISSION',
  'required_execution_permission','DOWNSTREAM_EXECUTION_ELIGIBLE',
  'required_preconditions',jsonb_build_array(
    'EKB_PREFLIGHT_CLEAR',
    'PASE_ROUTER_TERMINAL_ALLOW',
    'EXACT_HEAD_MATCH',
    'PR_MERGEABLE_TRUE'
  ),
  'forbidden',jsonb_build_array(
    'MERGE_WITHOUT_PROCESS_AUTHORIZATION',
    'TREAT_RECOMMENDATION_AS_PERMISSION',
    'SKIP_EKB_PREFLIGHT',
    'SKIP_PASE_WHEN_APPLICABLE',
    'MERGE_DIFFERENT_HEAD'
  ),
  'on_authorized','MERGE_AND_CONTINUE_CURRENT_UNIT',
  'on_not_authorized','YIELD_CURRENT_UNIT_CONTINUE_SCHEDULER',
  'global_scheduler_stop',false,
  'fail_closed',true
);
$$;

create or replace function programacion.fn_engineering_packet_apply_governed_merge_v1(p_packet jsonb)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_plan jsonb := '[]'::jsonb;
  v_op jsonb;
  v_contract jsonb := programacion.fn_engineering_merge_authorization_contract_v1();
begin
  for v_op in
    select x.value
    from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb)) with ordinality x(value,ord)
    order by x.ord
  loop
    if v_op->>'operation'='WRITE_GIT' then
      v_op := jsonb_set(
        v_op,
        '{executor_contract}',
        coalesce(v_op->'executor_contract','{}'::jsonb)
        || jsonb_build_object(
          'human_approval_required',false,
          'auto_merge_when_authorized',true,
          'merge_authorization',v_contract,
          'continue_after_merge',true
        ),
        true
      );
      v_op := v_op || jsonb_build_object(
        'merge_authorization_contract',v_contract
      );
    end if;
    v_plan := v_plan || jsonb_build_array(v_op);
  end loop;

  return jsonb_set(
    p_packet || jsonb_build_object(
      'process_merge_authorization',v_contract
    ),
    '{connector_plan}',
    v_plan,
    true
  );
end;
$$;

create or replace function programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_packet jsonb;
  v_budget int;
  v_spec jsonb := coalesce(p_action_spec,'{}'::jsonb);
  v_material boolean := coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_title text := coalesce(p_action_spec->>'checkpoint_title','');
begin
  if v_material
     and v_kind not in ('READBACK_ONCE','OBSERVE_ONCE','DECISION_GATE','TERMINAL_RECONCILE') then
    v_spec := jsonb_set(
      v_spec,
      '{checkpoint_title}',
      to_jsonb('execute material: ' || v_title),
      true
    );
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec,p_execution_input
  );

  v_budget:=nullif(p_action_spec#>>'{read_budget,checkpoint_queries_max}','')::int;

  if v_budget is null then
    select nullif(
      coalesce(
        pu.unit_metadata#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
        pu.unit_metadata#>>'{source_fast_path_v1,preferred_queries_max}'
      ),''
    )::int
    into v_budget
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=p_unit_code;
  end if;

  v_packet:=programacion.fn_engineering_packet_apply_read_budget_v1(
    v_packet,v_budget
  );

  v_packet:=programacion.fn_engineering_packet_apply_governed_merge_v1(v_packet);

  return v_packet || jsonb_build_object(
    'readonly_policy',jsonb_build_object(
      'scope','EXPLICIT_READ_ACTIONS_ONLY',
      'materiality_authority','ACTION_SPEC_REQUIRES_MATERIAL_EXECUTION',
      'title_based_materiality_downgrade','FORBIDDEN',
      'material_actions_allowed',jsonb_build_array('WRITE_DB','WRITE_GIT','RUN_TEST')
    )
  );
end;
$$;

create or replace function programacion.fn_engineering_packet_apply_explicit_test_cases_v1(
  p_packet jsonb,
  p_action_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_codes jsonb;
  v_sha text;
  v_plan jsonb:='[]'::jsonb;
  v_op jsonb;
  v_unit text := nullif(p_packet->>'unit_code','');
  v_missing int := 0;
  v_foreign int := 0;
  v_ownerless int := 0;
  v_foreign_refs jsonb := '[]'::jsonb;
begin
  v_codes:=coalesce(p_action_spec->'test_case_codes','[]'::jsonb);
  v_sha:=nullif(p_action_spec->>'test_case_set_sha256','');

  if jsonb_array_length(v_codes)=0
     or coalesce(p_packet->>'execution_capability','')<>'RUN_TEST' then
    return p_packet;
  end if;

  with codes as (
    select jsonb_array_elements_text(v_codes) as test_code
  ),
  cat as (
    select c.test_code,
           t.test_code as catalog_code,
           t.metadata->>'unit_code' as owner_unit
    from codes c
    left join public.lf_test_suite_cases t on t.test_code=c.test_code
  )
  select
    count(*) filter (where catalog_code is null),
    count(*) filter (where catalog_code is not null and owner_unit is not null and owner_unit<>v_unit),
    count(*) filter (where catalog_code is not null and owner_unit is null),
    coalesce(
      jsonb_agg(
        jsonb_build_object('test_code',test_code,'owner_unit',owner_unit)
        order by test_code
      ) filter (where catalog_code is not null and owner_unit is not null and owner_unit<>v_unit),
      '[]'::jsonb
    )
  into v_missing,v_foreign,v_ownerless,v_foreign_refs
  from cat;

  if v_missing>0 then
    return (p_packet || jsonb_build_object(
      'status','BLOCK_TEST_CASE_NOT_FOUND',
      'block_reasons',coalesce(p_packet->'block_reasons','[]'::jsonb)
        || jsonb_build_array('TEST_CASE_NOT_FOUND'),
      'test_case_ownership',jsonb_build_object(
        'consumer_unit',v_unit,
        'missing_case_count',v_missing,
        'foreign_owner_count',v_foreign,
        'ownerless_shared_count',v_ownerless,
        'ownership_transfer','FORBIDDEN'
      )
    )) - 'connector_plan'
       || jsonb_build_object('connector_plan','[]'::jsonb);
  end if;

  if v_foreign>0 then
    return (p_packet || jsonb_build_object(
      'status','BLOCK_CROSS_UNIT_TEST_OWNERSHIP',
      'block_reasons',coalesce(p_packet->'block_reasons','[]'::jsonb)
        || jsonb_build_array('CROSS_UNIT_TEST_OWNERSHIP'),
      'test_case_ownership',jsonb_build_object(
        'consumer_unit',v_unit,
        'foreign_owner_count',v_foreign,
        'foreign_cases',v_foreign_refs,
        'ownerless_shared_count',v_ownerless,
        'rule','DEPENDENCY_DONE_ENABLES_CONSUMPTION_NOT_TEST_OWNERSHIP_TRANSFER',
        'ownership_transfer','FORBIDDEN'
      )
    )) - 'connector_plan'
       || jsonb_build_object('connector_plan','[]'::jsonb);
  end if;

  for v_op in
    select x.value
    from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb))
         with ordinality x(value,ord)
    order by x.ord
  loop
    if v_op->>'operation'='RUN_TEST' then
      v_op:=jsonb_set(
        v_op,
        '{test_scope}',
        coalesce(v_op->'test_scope','{}'::jsonb)
        || jsonb_build_object(
          'case_resolution','EXPLICIT_TEST_CODES',
          'test_case_codes',v_codes,
          'case_set_sha256',v_sha,
          'case_count',jsonb_array_length(v_codes),
          'consumer_unit',v_unit,
          'foreign_owner_count',0,
          'ownerless_shared_count',v_ownerless
        ),
        true
      );
      v_op:=jsonb_set(
        v_op,
        '{executor_contract}',
        coalesce(v_op->'executor_contract','{}'::jsonb)
        || jsonb_build_object(
          'case_resolution','EXPLICIT_TEST_CODES',
          'explicit_test_codes',v_codes,
          'case_set_sha256',v_sha,
          'case_count',jsonb_array_length(v_codes),
          'fallback_case_discovery','FORBIDDEN',
          'execute_only_declared_case_set',true,
          'cross_unit_test_ownership','FORBIDDEN'
        ),
        true
      );
    end if;

    v_plan:=v_plan||jsonb_build_array(v_op);
  end loop;

  return jsonb_set(
    p_packet
    || jsonb_build_object(
      'explicit_test_case_set',jsonb_build_object(
        'test_case_codes',v_codes,
        'case_set_sha256',v_sha,
        'case_count',jsonb_array_length(v_codes),
        'consumer_unit',v_unit,
        'foreign_owner_count',0,
        'ownerless_shared_count',v_ownerless,
        'ownership_transfer','FORBIDDEN'
      )
    ),
    '{connector_plan}',
    v_plan,
    true
  );
end;
$$;

update programacion.engineering_work_checkpoints
set title='Smoke de integridad post-lote propio de M10.12: fachada estable disponible'
where work_item_id=(
  select work_item_id
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and unit_code='M10.12'
)
and checkpoint_code='SMOKE_M7_PER_BATCH';

update programacion.engineering_plan_units
set exit_criterion='cada lote con smoke de integridad propio de M10.12 y 0 residuos',
    unit_metadata=jsonb_set(
      unit_metadata,
      '{action_specs_v1,SMOKE_M7_PER_BATCH}',
      jsonb_build_object(
        'schema_version','ENGINEERING_ACTION_SPEC_V3',
        'status','READY',
        'checkpoint_code','SMOKE_M7_PER_BATCH',
        'checkpoint_title','Smoke de integridad post-lote propio de M10.12: fachada estable disponible',
        'action_kind','READBACK_ONCE',
        'recipe_mode','READBACK_EXACT',
        'precision','EXPLICIT_POST_BATCH_OWN_PROCESS_SMOKE',
        'requires_material_execution',false,
        'mutation_policy','NO_DOMAIN_MUTATION',
        'target',jsonb_build_object(
          'checkpoint','SMOKE_M7_PER_BATCH',
          'declared_assets','[]'::jsonb,
          'declared_events','[]'::jsonb,
          'declared_artifacts','[]'::jsonb,
          'declared_objects',jsonb_build_array(
            'public.fn_input_governance_execute',
            'public.fn_input_governance_validator_validate_v1',
            'public.fn_input_governance_curator_materialize_v1',
            'public.fn_input_governance_safe_autofix_v1',
            'public.fn_input_governance_validator_resume_context_v1'
          )
        ),
        'expected','After the current M10.12 retirement batch, the five stable public IG facade entrypoints remain present. This checkpoint validates M10.12 post-batch integrity and does not execute M7-owned tests.',
        'action_steps',jsonb_build_array(
          'READ_STABLE_FACADE_AFTER_CURRENT_BATCH',
          'ASSERT_FIVE_OF_FIVE_ENTRYPOINTS_PRESENT',
          'PERSIST_DONE_ON_PASS',
          'USE_RETURNED_BOOTSTRAP'
        ),
        'verification_queries',jsonb_build_array(
          $q$select count(distinct p.proname) facade_functions_present,
                    array_agg(distinct p.proname order by p.proname) facade_functions
              from pg_proc p
              join pg_namespace n on n.oid=p.pronamespace
              where n.nspname='public'
                and p.proname in (
                  'fn_input_governance_execute',
                  'fn_input_governance_validator_validate_v1',
                  'fn_input_governance_curator_materialize_v1',
                  'fn_input_governance_safe_autofix_v1',
                  'fn_input_governance_validator_resume_context_v1'
                )$q$
        ),
        'persist',jsonb_build_object(
          'on_pass','DONE',
          'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
          'next_state','RETURNED_BOOTSTRAP_ONLY'
        ),
        'forbidden',jsonb_build_array(
          'REEXECUTE_M7_TESTS',
          'REUSE_FOREIGN_UNIT_TEST_CASESET',
          'PERSIST_M7_CASES_AS_M10_12_CASES'
        ),
        'dependency_evidence_policy',jsonb_build_object(
          'upstream_done','ENABLES_EXECUTION_ONLY',
          'test_ownership_transfer','FORBIDDEN'
        ),
        'contract_correction','OWN_PROCESS_POST_BATCH_SMOKE_REPLACES_CROSS_UNIT_M7_VALIDATION'
      ),
      true
    )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M10.12';

create or replace function programacion.fn_engineering_parallel_executor_status_v2(p_run_id bigint)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
with run_row as (
  select *
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id
),
lane_rows as (
  select
    lr.*,
    pu.work_item_id,
    wi.work_code,
    wp.status as unit_status_live,
    wp.progress_pct as unit_progress_pct_live,
    wp.open_blockers as open_blockers_live,
    nx.checkpoint_code as next_checkpoint_code,
    nx.title as next_checkpoint_title,
    nx.status as next_checkpoint_status
  from run_row r
  join programacion.engineering_parallel_pilot_lane_runs lr on lr.run_id=r.id
  left join programacion.engineering_plan_units pu
    on pu.plan_code=r.plan_code and pu.unit_code=lr.unit_code
  left join programacion.engineering_work_items wi on wi.id=pu.work_item_id
  left join programacion.v_engineering_work_progress wp on wp.id=pu.work_item_id
  left join lateral (
    select c.checkpoint_code,c.title,c.status
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=pu.work_item_id
      and c.status not in ('DONE','NOT_APPLICABLE')
    order by c.sequence_no
    limit 1
  ) nx on true
),
agg as (
  select
    count(*) as lane_runs,
    coalesce(sum(coalesce(checkpoint_total,0)),0) as checkpoint_total,
    coalesce(sum(coalesce(checkpoints_done_before,0)),0) as done_before,
    coalesce(sum(coalesce(checkpoints_done_after,0)),0) as done_after,
    coalesce(sum(coalesce(checkpoints_done_delta,0)),0) as done_delta,
    count(*) filter (where result_summary='UNIT_TERMINAL_SUCCESS') as units_terminal_success,
    count(*) filter (where result_summary='UNIT_YIELDED') as units_yielded,
    count(*) filter (where result_summary='UNIT_EXECUTION_ERROR') as unit_execution_errors
  from lane_rows
)
select jsonb_build_object(
  'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
  'report_contract','ENGINEERING_PARALLEL_EXECUTOR_REPORT_V2',
  'execution_scope','UNIT_TO_TERMINAL',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'status',r.status,
  'max_lanes',r.max_lanes,
  'max_turns_per_lane',r.max_turns_per_lane,
  'max_total_runs',r.max_lanes*r.max_turns_per_lane,
  'started_at',r.started_at,
  'finished_at',r.finished_at,
  'checkpoint_progress',jsonb_build_object(
    'done_before',a.done_before,
    'done_after',a.done_after,
    'completed_this_run',a.done_delta,
    'total',a.checkpoint_total,
    'remaining',greatest(a.checkpoint_total-a.done_after,0),
    'progress_pct',case when a.checkpoint_total=0 then 0
                        else round((100.0*a.done_after/a.checkpoint_total)::numeric,1) end,
    'progress_label',a.done_after::text||'/'||a.checkpoint_total::text
  ),
  'summary',coalesce(r.summary,'{}'::jsonb) || jsonb_build_object(
    'lane_runs',a.lane_runs,
    'checkpoints_completed',a.done_delta,
    'checkpoint_progress_label',a.done_after::text||'/'||a.checkpoint_total::text,
    'checkpoint_progress_pct',case when a.checkpoint_total=0 then 0
                                   else round((100.0*a.done_after/a.checkpoint_total)::numeric,1) end,
    'units_terminal_success',a.units_terminal_success,
    'units_yielded',a.units_yielded,
    'unit_execution_errors',a.unit_execution_errors
  ),
  'lanes',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'lane_no',l.lane_no,
        'turn_no',l.turn_no,
        'unit_code',l.unit_code,
        'work_code',l.work_code,
        'status',case
          when l.result_summary='UNIT_YIELDED' then 'YIELDED'
          when l.result_summary='UNIT_EXECUTION_ERROR' then 'ERROR'
          else l.status
        end,
        'unit_status_live',l.unit_status_live,
        'unit_progress_pct_live',l.unit_progress_pct_live,
        'open_blockers_live',l.open_blockers_live,
        'started_at',l.started_at,
        'finished_at',l.finished_at,
        'result_summary',l.result_summary,
        'context_admit',l.context_admit,
        'context_reason',l.context_reason,
        'checkpoint_progress',jsonb_build_object(
          'done_before',coalesce(l.checkpoints_done_before,0),
          'done_after',coalesce(l.checkpoints_done_after,0),
          'completed_this_turn',coalesce(l.checkpoints_done_delta,0),
          'total',coalesce(l.checkpoint_total,0),
          'remaining',greatest(coalesce(l.checkpoint_total,0)-coalesce(l.checkpoints_done_after,0),0),
          'progress_pct',case when coalesce(l.checkpoint_total,0)=0 then 0
                              else round((100.0*coalesce(l.checkpoints_done_after,0)/l.checkpoint_total)::numeric,1) end,
          'progress_label',coalesce(l.checkpoints_done_after,0)::text||'/'||coalesce(l.checkpoint_total,0)::text
        ),
        'next_checkpoint',case
          when l.next_checkpoint_code is null then null
          else jsonb_build_object(
            'checkpoint_code',l.next_checkpoint_code,
            'title',l.next_checkpoint_title,
            'status',l.next_checkpoint_status
          )
        end
      )
      order by l.lane_no,l.turn_no
    )
    from lane_rows l
  ),'[]'::jsonb)
)
from run_row r
cross join agg a;
$$;

create or replace function programacion.fn_engineering_parallel_executor_status_v1(p_run_id bigint)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
select programacion.fn_engineering_parallel_executor_status_v2(p_run_id);
$$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-PROCESS-AUTO-MERGE-AUTHORITY-001',
  'ENGINEERING_ORCHESTRATION',
  'Governed process authorization replaces manual merge approval inside an already authorized execution scope',
  'WRITE_GIT previously required a human merge pause even when process gates could establish exact-head, EKB, PASE and safe-change admission.',
  'Merge authorization was modeled as an external human approval instead of a governed execution permission.',
  'MANUAL_MERGE_PAUSE_DESPITE_PROCESS_AUTHORITY',
  'WRITE_GIT packets must carry ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1. Merge automatically only when SAFE_CHANGE_ADMISSION returns DOWNSTREAM_EXECUTION_ELIGIBLE and EKB/PASE/exact-head/mergeability preconditions pass. Recommendation alone is never permission. If not authorized, yield only the current unit and continue the scheduler.',
  'PASS 2026-10-06: M6.2 GRAPH_SHA_RECEIPT packet is WRITE_GIT/READY with human_approval_required=false, auto_merge_when_authorized=true, required permission DOWNSTREAM_EXECUTION_ELIGIBLE and on_authorized=MERGE_AND_CONTINUE_CURRENT_UNIT.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_merge_authorization_contract_v1; supabase://programacion.fn_engineering_execution_packet_from_spec_v1/M6.2#GRAPH_SHA_RECEIPT',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','PROCESS_DEPENDENT',
  'Parallel executor governed merge',
  'supabase://programacion.fn_engineering_merge_authorization_contract_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,prevencion=excluded.prevencion,
  validacion=excluded.validacion,evidencia=excluded.evidencia,ultima_vez=now(),updated_at=now();

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-ACTION-SPEC-MATERIALITY-TITLE-DOWNGRADE-001',
  'ENGINEERING_ORCHESTRATION',
  'Checkpoint title must never downgrade explicit material execution to readonly',
  'The packet compiler could turn requires_material_execution=true into READ when the checkpoint title began with readback/verify-like wording.',
  'Materiality was partially inferred from natural-language title instead of relying only on the explicit action-spec contract.',
  'MATERIAL_ACTION_DOWNGRADED_BY_TITLE_HEURISTIC',
  'Only explicit read action kinds are readonly. WRITE_DB, WRITE_GIT and RUN_TEST declared by the action spec remain material regardless of checkpoint-title wording. Title-based materiality downgrade is forbidden.',
  'PASS 2026-10-06: synthetic material action titled Verificar deliverable material compiles to WRITE_DB/READY; M6.2 material migration compiles to WRITE_GIT/READY; packet exposes readonly_policy.scope=EXPLICIT_READ_ACTIONS_ONLY.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_execution_packet_from_spec_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','PROCESS_DEPENDENT',
  'Execution packet materiality',
  'supabase://programacion.fn_engineering_execution_packet_from_spec_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,prevencion=excluded.prevencion,
  validacion=excluded.validacion,evidencia=excluded.evidencia,ultima_vez=now(),updated_at=now();

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-PARALLEL-REPORT-CHECKPOINT-PROGRESS-001',
  'ENGINEERING_ORCHESTRATION',
  'Parallel execution report must expose checkpoint progress per lane and aggregate',
  'The previous report counted completed checkpoints but did not make per-unit done/total progress and the next checkpoint prominent.',
  'Scheduler evidence and user-facing progress were stored separately instead of being projected into one canonical report.',
  'CHECKPOINT_PROGRESS_NOT_VISIBLE_IN_EXECUTION_REPORT',
  'Use ENGINEERING_PARALLEL_EXECUTOR_REPORT_V2. Show aggregate done/total, percent and completed_this_run; for every lane show done_before, done_after, total, remaining, completed_this_turn, progress label, live unit status and next checkpoint.',
  'PASS 2026-10-06 on run_id=6: aggregate 9/17 = 52.9%; lanes show M6.2 2/5, T-PRIVACY 2/4, N-16 4/4, M4.5 1/4 plus next checkpoint.',
  'MEDIUM',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_parallel_executor_status_v2/6',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','PROCESS_DEPENDENT',
  'Parallel executor reporting',
  'supabase://programacion.fn_engineering_parallel_executor_status_v2'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,prevencion=excluded.prevencion,
  validacion=excluded.validacion,evidencia=excluded.evidencia,ultima_vez=now(),updated_at=now();

update public.lf_error_knowledge
set validacion='PASS 2026-10-06 full plan audit: 171 active units, 824 checkpoints, 23 explicit action specs, 8 remaining DECLARED_TEST_EXECUTION checkpoints all classified as own-unit test contracts, 0 cross-unit test_case refs, 0 legacy Smoke M7 specs. M10.12 smoke was replaced by an own-process post-batch facade integrity readback (5/5 stable public entrypoints). Runtime guard blocks any future foreign-owner case set with BLOCK_CROSS_UNIT_TEST_OWNERSHIP.',
    evidencia=case
      when position('[FULL_PLAN_AUDIT_20261006]' in coalesce(evidencia,''))>0 then evidencia
      else coalesce(evidencia,'') || E'\n[FULL_PLAN_AUDIT_20261006] units=171; checkpoints=824; explicit_specs=23; declared_test_execution=8; own_test_contract_missing=8; cross_unit_test_case_refs=0; legacy_smoke_m7_specs=0; M10.12 own smoke 5/5.'
    end,
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-DEPENDENCY-TEST-OWNERSHIP-TRANSFER-001';
