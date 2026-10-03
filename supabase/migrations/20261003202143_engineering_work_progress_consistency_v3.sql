-- SC-M4.3C / RC-002 PLAN_BLOCKER_SIGNAL_DIVERGENCE
-- Generic progress/readiness reconciliation; no historical status mutation.

create or replace view programacion.v_engineering_work_progress
with (security_invoker = true)
as
with checkpoint_agg as (
  select
    work_item_id,
    count(*) as checkpoint_count,
    count(*) filter (where required and status <> 'NOT_APPLICABLE') as required_checkpoint_count,
    count(*) filter (where required and status = 'DONE') as required_done_checkpoint_count,
    count(*) filter (where status = 'DONE') as done_checkpoint_count,
    coalesce(sum(weight) filter (where status <> 'NOT_APPLICABLE'),0) as applicable_weight,
    coalesce(sum(weight) filter (where status = 'DONE'),0) as done_weight
  from programacion.engineering_work_checkpoints
  group by work_item_id
),
blocker_agg as (
  select work_item_id, count(*) filter (where status = 'OPEN') as open_blockers
  from programacion.engineering_work_blockers
  group by work_item_id
),
update_agg as (
  select work_item_id, max(observed_at) as last_update_at
  from programacion.engineering_work_updates
  group by work_item_id
),
base as (
  select
    wi.*,
    ws.stream_code,
    ws.name as workstream_name,
    coalesce(c.checkpoint_count,0) as checkpoint_count,
    coalesce(c.required_checkpoint_count,0) as required_checkpoint_count,
    coalesce(c.required_done_checkpoint_count,0) as required_done_checkpoint_count,
    coalesce(c.done_checkpoint_count,0) as done_checkpoint_count,
    coalesce(c.applicable_weight,0) as applicable_weight,
    coalesce(c.done_weight,0) as done_weight,
    coalesce(b.open_blockers,0) as open_blockers,
    u.last_update_at
  from programacion.engineering_work_items wi
  join programacion.engineering_workstreams ws on ws.id = wi.workstream_id
  left join checkpoint_agg c on c.work_item_id = wi.id
  left join blocker_agg b on b.work_item_id = wi.id
  left join update_agg u on u.work_item_id = wi.id
)
select
  b.id,
  b.work_code,
  b.workstream_id,
  b.stream_code,
  b.workstream_name,
  b.title,
  b.objective,
  b.expected_result,
  b.work_type,
  b.priority,
  b.status,
  b.assignee_type,
  b.assignee_ref,
  b.target_repo,
  b.target_domain,
  b.target_component,
  b.source_ref,
  b.due_date,
  b.started_at,
  b.completed_at,
  b.checkpoint_count,
  b.required_checkpoint_count,
  b.done_checkpoint_count,
  b.applicable_weight,
  b.done_weight,
  case
    when b.applicable_weight = 0 then case when b.status = 'DONE' then 100.00 else 0.00 end
    else round(100.0 * b.done_weight / nullif(b.applicable_weight,0), 2)
  end as progress_pct,
  b.open_blockers,
  b.last_update_at,
  b.updated_at,
  b.required_done_checkpoint_count,
  case
    when b.open_blockers > 0 then 'BLOCKED_OPEN_BLOCKER'
    when b.required_checkpoint_count > b.required_done_checkpoint_count then 'CHECKPOINTS_PENDING'
    when b.required_checkpoint_count = 0 then 'NO_REQUIRED_CHECKPOINT_CONTRACT'
    else 'READY'
  end as closure_state,
  case
    when b.open_blockers > 0 and b.status <> 'BLOCKED' then false
    when b.status = 'DONE' and b.required_checkpoint_count > b.required_done_checkpoint_count then false
    when b.status = 'BLOCKED' and b.open_blockers = 0 and b.required_checkpoint_count = b.required_done_checkpoint_count then false
    else true
  end as status_consistent,
  case
    when b.open_blockers > 0 then 'BLOCKED'
    when b.status = 'DONE' and b.required_checkpoint_count > b.required_done_checkpoint_count then 'BLOCKED'
    else b.status
  end as effective_status
from base b;

comment on view programacion.v_engineering_work_progress is
'Vista operativa de progreso derivado por checkpoint y señales de bloqueo. progress_pct no confía en DONE cuando existe contrato de checkpoints; closure_state/status_consistent/effective_status reconcilian checkpoints, blockers y status sin reescribir historial.';
