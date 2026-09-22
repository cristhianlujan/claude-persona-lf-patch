-- LF_FORENSIC_LEDGER_MIRROR_V1
-- provenance_status=ORIGINAL_SOURCE_NOT_RECOVERABLE
-- materialization_mode=FORENSIC_LEDGER_MIRROR_NOT_ORIGINAL_SOURCE
-- ddl_replayed=false
-- provenance_gap_ekb_code=SRC-001
-- source_search_evidence=sandbox/lf_contract_gate_test/migration_forensic_recovery/engineering_backlog_20260922_source_search.json

drop view if exists programacion.v_engineering_work_progress;

create view programacion.v_engineering_work_progress
with (security_invoker = true)
as
with checkpoint_agg as (
  select
    work_item_id,
    count(*) as checkpoint_count,
    count(*) filter (where required and status <> 'NOT_APPLICABLE') as required_checkpoint_count,
    count(*) filter (where status='DONE') as done_checkpoint_count,
    coalesce(sum(weight) filter (where status <> 'NOT_APPLICABLE'),0) as applicable_weight,
    coalesce(sum(weight) filter (where status='DONE'),0) as done_weight
  from programacion.engineering_work_checkpoints
  group by work_item_id
),
blocker_agg as (
  select work_item_id, count(*) filter (where status='OPEN') as open_blockers
  from programacion.engineering_work_blockers
  group by work_item_id
),
update_agg as (
  select work_item_id, max(observed_at) as last_update_at
  from programacion.engineering_work_updates
  group by work_item_id
)
select
  wi.id,
  wi.work_code,
  wi.workstream_id,
  ws.stream_code,
  ws.name as workstream_name,
  wi.title,
  wi.objective,
  wi.expected_result,
  wi.work_type,
  wi.priority,
  wi.status,
  wi.assignee_type,
  wi.assignee_ref,
  wi.target_repo,
  wi.target_domain,
  wi.target_component,
  wi.source_ref,
  wi.due_date,
  wi.started_at,
  wi.completed_at,
  coalesce(c.checkpoint_count,0) as checkpoint_count,
  coalesce(c.required_checkpoint_count,0) as required_checkpoint_count,
  coalesce(c.done_checkpoint_count,0) as done_checkpoint_count,
  coalesce(c.applicable_weight,0) as applicable_weight,
  coalesce(c.done_weight,0) as done_weight,
  case
    when wi.status='DONE' then 100.00
    when coalesce(c.applicable_weight,0)=0 then 0.00
    else round(100.0 * c.done_weight / nullif(c.applicable_weight,0), 2)
  end as progress_pct,
  coalesce(b.open_blockers,0) as open_blockers,
  u.last_update_at,
  wi.updated_at
from programacion.engineering_work_items wi
join programacion.engineering_workstreams ws on ws.id=wi.workstream_id
left join checkpoint_agg c on c.work_item_id=wi.id
left join blocker_agg b on b.work_item_id=wi.id
left join update_agg u on u.work_item_id=wi.id;

comment on view programacion.v_engineering_work_progress is
'Vista operativa de progreso derivado por checkpoint, bloqueos abiertos y última actualización. No usa porcentaje auto-reportado.';
