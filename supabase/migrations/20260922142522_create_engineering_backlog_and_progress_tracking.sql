-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260922142522-20260922-001
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- source_version=20260922142522
-- source_name=create_engineering_backlog_and_progress_tracking

create sequence if not exists programacion.engineering_workstreams_id_seq;
create table if not exists programacion.engineering_workstreams (
  id bigint primary key default nextval('programacion.engineering_workstreams_id_seq'),
  stream_code text not null unique,
  name text not null,
  objective text not null,
  owner_ref text not null,
  status text not null default 'ACTIVE'
    check (status in ('PLANNED','ACTIVE','PAUSED','CLOSED','CANCELLED')),
  source_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_execution_id text not null default 'UNKNOWN',
  updated_by_execution_id text
);
comment on table programacion.engineering_workstreams is
'Backlog transversal de trabajo de ingeniería por frente/persona. No reemplaza agent_tasks ni backlog de errores; agrupa trabajo humano/mixto y permite seguimiento derivado.';

create sequence if not exists programacion.engineering_work_items_id_seq;
create table if not exists programacion.engineering_work_items (
  id bigint primary key default nextval('programacion.engineering_work_items_id_seq'),
  work_code text not null unique,
  workstream_id bigint not null references programacion.engineering_workstreams(id),
  parent_work_item_id bigint references programacion.engineering_work_items(id),
  title text not null,
  objective text not null,
  expected_result text not null,
  work_type text not null
    check (work_type in ('ARCHITECTURE','AGENT_PLATFORM','FRONTEND','BACKEND','DATABASE','AWS_IAC','INTEGRATION','QA','DOCUMENTATION','PRODUCT_TECH','OTHER')),
  priority text not null default 'P2'
    check (priority in ('P0','P1','P2','P3')),
  status text not null default 'BACKLOG'
    check (status in ('BACKLOG','READY','IN_PROGRESS','BLOCKED','IN_REVIEW','DONE','CANCELLED')),
  assignee_type text not null default 'HUMAN'
    check (assignee_type in ('HUMAN','AGENT','MIXED')),
  assignee_ref text not null,
  target_repo text,
  target_domain text,
  target_component text,
  source_ref text,
  acceptance_criteria jsonb not null default '[]'::jsonb
    check (jsonb_typeof(acceptance_criteria)='array'),
  agent_task_id bigint references programacion.agent_tasks(id),
  due_date date,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_execution_id text not null default 'UNKNOWN',
  updated_by_execution_id text,
  check ((status='DONE' and completed_at is not null) or status<>'DONE')
);
comment on table programacion.engineering_work_items is
'Backlog canónico de trabajo de ingeniería. El avance porcentual no se declara aquí: se deriva de checkpoints ponderados.';

create sequence if not exists programacion.engineering_work_checkpoints_id_seq;
create table if not exists programacion.engineering_work_checkpoints (
  id bigint primary key default nextval('programacion.engineering_work_checkpoints_id_seq'),
  work_item_id bigint not null references programacion.engineering_work_items(id),
  checkpoint_code text not null,
  title text not null,
  sequence_no integer not null check (sequence_no > 0),
  weight numeric(7,4) not null check (weight > 0),
  required boolean not null default true,
  status text not null default 'PENDING'
    check (status in ('PENDING','IN_PROGRESS','BLOCKED','DONE','NOT_APPLICABLE')),
  evidence_ref text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_execution_id text not null default 'UNKNOWN',
  updated_by_execution_id text,
  unique(work_item_id, checkpoint_code),
  unique(work_item_id, sequence_no),
  check ((status='DONE' and completed_at is not null) or status<>'DONE')
);
comment on table programacion.engineering_work_checkpoints is
'Checkpoints ponderados para calcular avance real por work item; evita porcentajes manuales o auto-declarados.';

create sequence if not exists programacion.engineering_work_updates_id_seq;
create table if not exists programacion.engineering_work_updates (
  id bigint primary key default nextval('programacion.engineering_work_updates_id_seq'),
  work_item_id bigint not null references programacion.engineering_work_items(id),
  update_type text not null
    check (update_type in ('PROGRESS','DECISION','RISK','BLOCKER','NEXT_STEP','DELIVERY','NOTE')),
  summary text not null,
  detail text,
  next_action text,
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array'),
  reported_by text not null,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by_execution_id text not null default 'UNKNOWN'
);
comment on table programacion.engineering_work_updates is
'Bitácora append-only de avances, decisiones y próximos pasos. No es fuente del porcentaje; el porcentaje se deriva de checkpoints.';

create sequence if not exists programacion.engineering_work_blockers_id_seq;
create table if not exists programacion.engineering_work_blockers (
  id bigint primary key default nextval('programacion.engineering_work_blockers_id_seq'),
  work_item_id bigint not null references programacion.engineering_work_items(id),
  blocker_code text not null,
  description text not null,
  owner_ref text,
  required_action text not null,
  source_ref text,
  status text not null default 'OPEN'
    check (status in ('OPEN','RESOLVED','WAIVED')),
  opened_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution_ref text,
  created_by_execution_id text not null default 'UNKNOWN',
  updated_by_execution_id text,
  unique(work_item_id, blocker_code),
  check ((status='RESOLVED' and resolved_at is not null) or status<>'RESOLVED')
);
comment on table programacion.engineering_work_blockers is
'Bloqueos operativos del backlog humano/mixto de ingeniería. Separado de task_blockers, que pertenece al contrato de agent_tasks.';

create sequence if not exists programacion.engineering_work_dependencies_id_seq;
create table if not exists programacion.engineering_work_dependencies (
  id bigint primary key default nextval('programacion.engineering_work_dependencies_id_seq'),
  work_item_id bigint not null references programacion.engineering_work_items(id),
  depends_on_work_item_id bigint not null references programacion.engineering_work_items(id),
  relation_type text not null default 'REQUIRES'
    check (relation_type in ('REQUIRES','BLOCKED_BY','ENABLES','RELATED')),
  created_at timestamptz not null default now(),
  created_by_execution_id text not null default 'UNKNOWN',
  unique(work_item_id, depends_on_work_item_id, relation_type),
  check (work_item_id <> depends_on_work_item_id)
);
comment on table programacion.engineering_work_dependencies is
'Dependencias entre pendientes de ingeniería; permite ordenar el plan sin reutilizar indebidamente task_dependencies de agent_tasks.';

create or replace function programacion.fn_touch_engineering_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, programacion
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_engineering_workstreams_touch on programacion.engineering_workstreams;
create trigger trg_engineering_workstreams_touch
before update on programacion.engineering_workstreams
for each row execute function programacion.fn_touch_engineering_updated_at();

drop trigger if exists trg_engineering_work_items_touch on programacion.engineering_work_items;
create trigger trg_engineering_work_items_touch
before update on programacion.engineering_work_items
for each row execute function programacion.fn_touch_engineering_updated_at();

drop trigger if exists trg_engineering_work_checkpoints_touch on programacion.engineering_work_checkpoints;
create trigger trg_engineering_work_checkpoints_touch
before update on programacion.engineering_work_checkpoints
for each row execute function programacion.fn_touch_engineering_updated_at();

alter table programacion.engineering_workstreams enable row level security;
alter table programacion.engineering_work_items enable row level security;
alter table programacion.engineering_work_checkpoints enable row level security;
alter table programacion.engineering_work_updates enable row level security;
alter table programacion.engineering_work_blockers enable row level security;
alter table programacion.engineering_work_dependencies enable row level security;

drop policy if exists p_engineering_workstreams_read on programacion.engineering_workstreams;
create policy p_engineering_workstreams_read on programacion.engineering_workstreams
for select to programacion_auditor, programacion_builder, programacion_human_authority, programacion_verifier
using (true);
drop policy if exists p_engineering_workstreams_write on programacion.engineering_workstreams;
create policy p_engineering_workstreams_write on programacion.engineering_workstreams
for all to programacion_builder, programacion_human_authority
using (true) with check (true);

drop policy if exists p_engineering_work_items_read on programacion.engineering_work_items;
create policy p_engineering_work_items_read on programacion.engineering_work_items
for select to programacion_auditor, programacion_builder, programacion_human_authority, programacion_verifier
using (true);
drop policy if exists p_engineering_work_items_write on programacion.engineering_work_items;
create policy p_engineering_work_items_write on programacion.engineering_work_items
for all to programacion_builder, programacion_human_authority
using (true) with check (true);

drop policy if exists p_engineering_work_checkpoints_read on programacion.engineering_work_checkpoints;
create policy p_engineering_work_checkpoints_read on programacion.engineering_work_checkpoints
for select to programacion_auditor, programacion_builder, programacion_human_authority, programacion_verifier
using (true);
drop policy if exists p_engineering_work_checkpoints_write on programacion.engineering_work_checkpoints;
create policy p_engineering_work_checkpoints_write on programacion.engineering_work_checkpoints
for all to programacion_builder, programacion_human_authority
using (true) with check (true);

drop policy if exists p_engineering_work_updates_read on programacion.engineering_work_updates;
create policy p_engineering_work_updates_read on programacion.engineering_work_updates
for select to programacion_auditor, programacion_builder, programacion_human_authority, programacion_verifier
using (true);
drop policy if exists p_engineering_work_updates_insert on programacion.engineering_work_updates;
create policy p_engineering_work_updates_insert on programacion.engineering_work_updates
for insert to programacion_builder, programacion_human_authority
with check (true);

drop policy if exists p_engineering_work_blockers_read on programacion.engineering_work_blockers;
create policy p_engineering_work_blockers_read on programacion.engineering_work_blockers
for select to programacion_auditor, programacion_builder, programacion_human_authority, programacion_verifier
using (true);
drop policy if exists p_engineering_work_blockers_write on programacion.engineering_work_blockers;
create policy p_engineering_work_blockers_write on programacion.engineering_work_blockers
for all to programacion_builder, programacion_human_authority
using (true) with check (true);

drop policy if exists p_engineering_work_dependencies_read on programacion.engineering_work_dependencies;
create policy p_engineering_work_dependencies_read on programacion.engineering_work_dependencies
for select to programacion_auditor, programacion_builder, programacion_human_authority, programacion_verifier
using (true);
drop policy if exists p_engineering_work_dependencies_write on programacion.engineering_work_dependencies;
create policy p_engineering_work_dependencies_write on programacion.engineering_work_dependencies
for all to programacion_builder, programacion_human_authority
using (true) with check (true);

create or replace view programacion.v_engineering_work_progress
with (security_invoker = true)
as
select
  wi.id,
  wi.work_code,
  wi.workstream_id,
  ws.stream_code,
  ws.name as workstream_name,
  wi.title,
  wi.work_type,
  wi.priority,
  wi.status,
  wi.assignee_type,
  wi.assignee_ref,
  wi.target_repo,
  wi.target_domain,
  wi.target_component,
  wi.due_date,
  wi.started_at,
  wi.completed_at,
  count(cp.id) as checkpoint_count,
  count(cp.id) filter (where cp.required and cp.status <> 'NOT_APPLICABLE') as required_checkpoint_count,
  count(cp.id) filter (where cp.status='DONE') as done_checkpoint_count,
  coalesce(sum(cp.weight) filter (where cp.status <> 'NOT_APPLICABLE'),0) as applicable_weight,
  coalesce(sum(cp.weight) filter (where cp.status='DONE'),0) as done_weight,
  case
    when wi.status='DONE' then 100.00
    when coalesce(sum(cp.weight) filter (where cp.status <> 'NOT_APPLICABLE'),0)=0 then 0.00
    else round(
      100.0 * coalesce(sum(cp.weight) filter (where cp.status='DONE'),0)
      / nullif(sum(cp.weight) filter (where cp.status <> 'NOT_APPLICABLE'),0), 2
    )
  end as progress_pct,
  count(b.id) filter (where b.status='OPEN') as open_blockers,
  max(u.observed_at) as last_update_at,
  wi.updated_at
from programacion.engineering_work_items wi
join programacion.engineering_workstreams ws on ws.id=wi.workstream_id
left join programacion.engineering_work_checkpoints cp on cp.work_item_id=wi.id
left join programacion.engineering_work_blockers b on b.work_item_id=wi.id
left join programacion.engineering_work_updates u on u.work_item_id=wi.id
group by wi.id, ws.id;

comment on view programacion.v_engineering_work_progress is
'Vista operativa de progreso derivado por checkpoint, bloqueos abiertos y última actualización. No usa porcentaje auto-reportado.';
