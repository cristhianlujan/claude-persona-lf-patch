create or replace view programacion.v_agent_task_backlog_v1
with (security_invoker = true)
as
with current_tasks as (
  select
    r.task_id,
    r.task_code,
    r.task_version,
    r.functional_version_id,
    r.readiness,
    t.objective as task_objective,
    t.definition_status as task_definition_status,
    f.artifact_code,
    f.story_code,
    f.objective as functional_objective,
    f.status as functional_status
  from programacion.v_agent_task_readiness r
  join programacion.agent_tasks t on t.id = r.task_id
  join public.lf_functional_versions f on f.id = r.functional_version_id
), latest_execution as (
  select
    c.task_id,
    x.execution_id,
    x.execution_state,
    x.execution_branch_name,
    x.execution_head_sha,
    x.execution_created_at,
    x.execution_started_at,
    x.execution_completed_at,
    x.derived_status,
    x.effective_verdict,
    x.block_reason,
    x.invalidation_reason_code,
    x.invalidation_reason,
    x.invalidation_source_ref
  from current_tasks c
  left join lateral (
    select
      e.id as execution_id,
      e.estado as execution_state,
      e.branch_name as execution_branch_name,
      e.head_sha as execution_head_sha,
      e.created_at as execution_created_at,
      e.started_at as execution_started_at,
      e.completed_at as execution_completed_at,
      a.derived_status,
      a.effective_verdict,
      a.bloqueo_razon as block_reason,
      a.invalidation_reason_code,
      a.invalidation_reason,
      a.invalidation_source_ref
    from programacion.ejecuciones e
    join programacion.v_ejecucion_autoridad a on a.execution_id = e.id
    where e.request_ref = ('agent-task://' || c.task_id::text)
    order by e.created_at desc, e.id desc
    limit 1
  ) x on true
)
select
  c.task_id,
  c.task_code,
  c.task_version,
  c.functional_version_id,
  c.artifact_code,
  c.story_code,
  c.functional_objective,
  c.task_objective,
  c.functional_status,
  c.task_definition_status,
  coalesce((c.readiness ->> 'ready_for_development')::boolean, false) as ready_for_development,
  coalesce((c.readiness ->> 'executable_now')::boolean, false) as executable_now,
  c.readiness ->> 'sizing' as sizing,
  c.readiness ->> 'sizing_policy_status' as sizing_policy_status,
  c.readiness ->> 'sizing_profile_code' as sizing_profile_code,
  c.readiness -> 'sizing_metrics' as sizing_metrics,
  c.readiness -> 'blockers' as blockers,
  c.readiness -> 'waiting_on_task_ids' as waiting_on_task_ids,
  c.readiness -> 'dag' as dag,
  c.readiness -> 'source_rule_authority' as source_rule_authority,
  x.execution_id,
  x.execution_state,
  x.execution_branch_name,
  x.execution_head_sha,
  x.execution_created_at,
  x.execution_started_at,
  x.execution_completed_at,
  x.derived_status as execution_derived_status,
  x.effective_verdict as execution_effective_verdict,
  x.block_reason as execution_block_reason,
  x.invalidation_reason_code,
  x.invalidation_reason,
  x.invalidation_source_ref,
  case
    when x.effective_verdict in ('FAIL', 'INVALIDATED')
      or x.derived_status in ('FAIL', 'INVALIDATED') then 'NEEDS_REWORK'::text
    when not coalesce((c.readiness ->> 'ready_for_development')::boolean, false) then 'BLOCKED'::text
    when not coalesce((c.readiness ->> 'executable_now')::boolean, false) then 'WAITING_DEPENDENCY'::text
    when x.effective_verdict = 'PASS' then 'DONE_VERIFIED'::text
    when x.execution_state = 'RUNNING' then 'IN_PROGRESS'::text
    when x.effective_verdict = 'BLOCKED'
      or x.derived_status like 'BLOCKED%' then 'BLOCKED'::text
    when coalesce((c.readiness ->> 'ready_for_development')::boolean, false)
      and coalesce((c.readiness ->> 'executable_now')::boolean, false) then 'READY'::text
    else 'BLOCKED'::text
  end as backlog_state,
  'DERIVED_FROM_CANONICAL_SUPABASE'::text as authority_model,
  case
    when x.effective_verdict = 'PASS'
      and not coalesce((c.readiness ->> 'ready_for_development')::boolean, false)
      then 'PASS_CONFLICTS_WITH_CURRENT_BLOCKER'::text
    when x.effective_verdict = 'PASS'
      and not coalesce((c.readiness ->> 'executable_now')::boolean, false)
      then 'PASS_CONFLICTS_WITH_CURRENT_DEPENDENCY'::text
    else null::text
  end as state_conflict_code
from current_tasks c
left join latest_execution x on x.task_id = c.task_id;

revoke all on programacion.v_agent_task_backlog_v1 from public;
grant select on programacion.v_agent_task_backlog_v1 to programacion_builder;
grant select on programacion.v_agent_task_backlog_v1 to programacion_auditor;
grant select on programacion.v_agent_task_backlog_v1 to programacion_human_authority;