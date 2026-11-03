
-- LF Global Technical Inventory - dirty-driven orchestrator v1
-- Replaces five periodic jobs with one lightweight hourly orchestrator.
-- This migration does NOT force a refresh; the first natural run owns any pending rebuild.

create table if not exists inventory.refresh_state (
  state_id smallint primary key default 1 check (state_id = 1),
  change_seq bigint not null default 0,
  dirty boolean not null default true,
  dirty_since timestamptz,
  last_run_at timestamptz,
  last_full_run_at timestamptz,
  last_status text not null default 'PENDING',
  last_result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into inventory.refresh_state(
  state_id,change_seq,dirty,dirty_since,last_status,last_result
)
values(
  1,0,true,now(),'PENDING',jsonb_build_object('reason','INITIAL_ORCHESTRATOR_BOOTSTRAP')
)
on conflict(state_id) do nothing;

alter table inventory.refresh_state enable row level security;

drop policy if exists inventory_refresh_state_read on inventory.refresh_state;
create policy inventory_refresh_state_read
on inventory.refresh_state
for select
to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier
using (true);

grant select on inventory.refresh_state
to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier,service_role;

comment on table inventory.refresh_state is
'Singleton state for dirty-driven LF global technical inventory refresh orchestration.';

create or replace function inventory.fn_mark_dirty_v1()
returns void
language plpgsql
security definer
set search_path=inventory,pg_catalog
as $$
begin
  begin
    update inventory.refresh_state
    set dirty=true,
        change_seq=change_seq+1,
        dirty_since=coalesce(dirty_since,clock_timestamp()),
        updated_at=clock_timestamp()
    where state_id=1;
  exception
    when others then
      null;
  end;
end;
$$;

revoke all on function inventory.fn_mark_dirty_v1() from public;

create or replace function inventory.fn_mark_dirty_ddl_event_v1()
returns event_trigger
language plpgsql
security definer
set search_path=inventory,pg_catalog
as $$
begin
  begin
    if tg_tag = any(array[
      'CREATE SCHEMA','ALTER SCHEMA',
      'CREATE TABLE','CREATE TABLE AS','ALTER TABLE',
      'CREATE VIEW','ALTER VIEW',
      'CREATE MATERIALIZED VIEW','ALTER MATERIALIZED VIEW',
      'CREATE FUNCTION','ALTER FUNCTION',
      'CREATE PROCEDURE','ALTER PROCEDURE',
      'CREATE TRIGGER','ALTER TRIGGER',
      'CREATE POLICY','ALTER POLICY',
      'CREATE INDEX','ALTER INDEX'
    ]::text[]) then
      perform inventory.fn_mark_dirty_v1();
    end if;
  exception
    when others then
      null;
  end;
end;
$$;

create or replace function inventory.fn_mark_dirty_drop_event_v1()
returns event_trigger
language plpgsql
security definer
set search_path=inventory,pg_catalog
as $$
begin
  begin
    perform inventory.fn_mark_dirty_v1();
  exception
    when others then
      null;
  end;
end;
$$;

revoke all on function inventory.fn_mark_dirty_ddl_event_v1() from public;
revoke all on function inventory.fn_mark_dirty_drop_event_v1() from public;

drop event trigger if exists lf_inventory_mark_dirty_ddl_v1;
create event trigger lf_inventory_mark_dirty_ddl_v1
on ddl_command_end
execute function inventory.fn_mark_dirty_ddl_event_v1();

drop event trigger if exists lf_inventory_mark_dirty_drop_v1;
create event trigger lf_inventory_mark_dirty_drop_v1
on sql_drop
execute function inventory.fn_mark_dirty_drop_event_v1();

create or replace function inventory.fn_mark_dirty_statement_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=inventory,pg_catalog
as $$
begin
  begin
    perform inventory.fn_mark_dirty_v1();
  exception
    when others then
      null;
  end;
  return null;
end;
$$;

revoke all on function inventory.fn_mark_dirty_statement_trigger_v1() from public;

do $$
begin
  if to_regclass('public.lf_activos') is not null then
    execute 'drop trigger if exists trg_inventory_dirty_lf_activos_v1 on public.lf_activos';
    execute 'create trigger trg_inventory_dirty_lf_activos_v1 after insert or update or delete on public.lf_activos for each statement execute function inventory.fn_mark_dirty_statement_trigger_v1()';
  end if;

  if to_regclass('public.lf_activo_relaciones') is not null then
    execute 'drop trigger if exists trg_inventory_dirty_lf_activo_relaciones_v1 on public.lf_activo_relaciones';
    execute 'create trigger trg_inventory_dirty_lf_activo_relaciones_v1 after insert or update or delete on public.lf_activo_relaciones for each statement execute function inventory.fn_mark_dirty_statement_trigger_v1()';
  end if;

  if to_regclass('programacion.contratos') is not null then
    execute 'drop trigger if exists trg_inventory_dirty_programacion_contratos_v1 on programacion.contratos';
    execute 'create trigger trg_inventory_dirty_programacion_contratos_v1 after insert or update or delete on programacion.contratos for each statement execute function inventory.fn_mark_dirty_statement_trigger_v1()';
  end if;

  if to_regclass('public.lf_operation_registry') is not null then
    execute 'drop trigger if exists trg_inventory_dirty_lf_operation_registry_v1 on public.lf_operation_registry';
    execute 'create trigger trg_inventory_dirty_lf_operation_registry_v1 after insert or update or delete on public.lf_operation_registry for each statement execute function inventory.fn_mark_dirty_statement_trigger_v1()';
  end if;
end;
$$;

create or replace function inventory.fn_refresh_run_v1(p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=inventory,pg_catalog
as $$
declare
  v_started_at timestamptz := clock_timestamp();
  v_step_started_at timestamptz;
  v_seq_start bigint;
  v_seq_end bigint;
  v_dirty boolean;
  v_last_full_run_at timestamptz;
  v_catalog jsonb;
  v_details jsonb;
  v_exact jsonb;
  v_static jsonb;
  v_finalize jsonb;
  v_steps jsonb := '{}'::jsonb;
  v_result jsonb;
begin
  if not pg_try_advisory_xact_lock(20261001,1) then
    return jsonb_build_object(
      'status','SKIPPED_ALREADY_RUNNING',
      'started_at',v_started_at,
      'duration_ms',round(extract(epoch from clock_timestamp()-v_started_at)*1000)
    );
  end if;

  insert into inventory.refresh_state(state_id,change_seq,dirty,dirty_since,last_status,last_result)
  values(1,0,true,clock_timestamp(),'PENDING','{}'::jsonb)
  on conflict(state_id) do nothing;

  select change_seq,dirty,last_full_run_at
    into v_seq_start,v_dirty,v_last_full_run_at
  from inventory.refresh_state
  where state_id=1;

  if not coalesce(p_force,false)
     and not coalesce(v_dirty,true)
     and v_last_full_run_at is not null
     and v_last_full_run_at > clock_timestamp() - interval '24 hours'
  then
    v_result := jsonb_build_object(
      'status','SKIPPED_NO_CHANGES',
      'forced',false,
      'change_seq',v_seq_start,
      'last_full_run_at',v_last_full_run_at,
      'duration_ms',round(extract(epoch from clock_timestamp()-v_started_at)*1000)
    );

    update inventory.refresh_state
    set last_run_at=clock_timestamp(),
        last_status='SKIPPED_NO_CHANGES',
        last_result=v_result,
        updated_at=clock_timestamp()
    where state_id=1;

    return v_result;
  end if;

  update inventory.refresh_state
  set last_run_at=v_started_at,
      last_status='RUNNING',
      last_result=jsonb_build_object(
        'status','RUNNING',
        'forced',coalesce(p_force,false),
        'change_seq_start',v_seq_start,
        'started_at',v_started_at
      ),
      updated_at=clock_timestamp()
  where state_id=1;

  begin
    v_step_started_at := clock_timestamp();
    v_catalog := inventory.fn_refresh_catalog_v2();
    v_steps := v_steps || jsonb_build_object(
      'catalog',jsonb_build_object(
        'duration_ms',round(extract(epoch from clock_timestamp()-v_step_started_at)*1000),
        'result',v_catalog
      )
    );

    v_step_started_at := clock_timestamp();
    v_details := inventory.fn_refresh_db_details_v2();
    v_steps := v_steps || jsonb_build_object(
      'details',jsonb_build_object(
        'duration_ms',round(extract(epoch from clock_timestamp()-v_step_started_at)*1000),
        'result',v_details
      )
    );

    v_step_started_at := clock_timestamp();
    v_exact := inventory.fn_refresh_dependencies_exact_v1();
    v_steps := v_steps || jsonb_build_object(
      'exact_dependencies',jsonb_build_object(
        'duration_ms',round(extract(epoch from clock_timestamp()-v_step_started_at)*1000),
        'result',v_exact
      )
    );

    v_step_started_at := clock_timestamp();
    v_static := inventory.fn_refresh_static_incremental_v1();
    v_steps := v_steps || jsonb_build_object(
      'static_incremental',jsonb_build_object(
        'duration_ms',round(extract(epoch from clock_timestamp()-v_step_started_at)*1000),
        'result',v_static
      )
    );

    v_step_started_at := clock_timestamp();
    v_finalize := inventory.fn_finalize_refresh_v1();
    v_steps := v_steps || jsonb_build_object(
      'finalize',jsonb_build_object(
        'duration_ms',round(extract(epoch from clock_timestamp()-v_step_started_at)*1000),
        'result',v_finalize
      )
    );
  exception
    when others then
      v_result := jsonb_build_object(
        'status','FAILED',
        'forced',coalesce(p_force,false),
        'change_seq_start',v_seq_start,
        'sqlstate',sqlstate,
        'error',sqlerrm,
        'steps',v_steps,
        'duration_ms',round(extract(epoch from clock_timestamp()-v_started_at)*1000)
      );

      update inventory.refresh_state
      set dirty=true,
          dirty_since=coalesce(dirty_since,v_started_at),
          last_run_at=clock_timestamp(),
          last_status='FAILED',
          last_result=v_result,
          updated_at=clock_timestamp()
      where state_id=1;

      return v_result;
  end;

  update inventory.refresh_state
  set dirty=(change_seq<>v_seq_start),
      dirty_since=case
        when change_seq<>v_seq_start then coalesce(dirty_since,v_started_at)
        else null
      end,
      last_run_at=clock_timestamp(),
      last_full_run_at=clock_timestamp(),
      last_status=case
        when change_seq<>v_seq_start then 'COMPLETED_DIRTY_AGAIN'
        else 'COMPLETED'
      end,
      last_result=jsonb_build_object(
        'status',case
          when change_seq<>v_seq_start then 'COMPLETED_DIRTY_AGAIN'
          else 'COMPLETED'
        end,
        'forced',coalesce(p_force,false),
        'change_seq_start',v_seq_start,
        'change_seq_end',change_seq,
        'dirty_after',(change_seq<>v_seq_start),
        'steps',v_steps,
        'duration_ms',round(extract(epoch from clock_timestamp()-v_started_at)*1000)
      ),
      updated_at=clock_timestamp()
  where state_id=1
  returning change_seq,last_result
    into v_seq_end,v_result;

  return v_result;
end;
$$;

revoke all on function inventory.fn_refresh_run_v1(boolean) from public;
grant execute on function inventory.fn_refresh_run_v1(boolean) to service_role;

comment on function inventory.fn_refresh_run_v1(boolean) is
'Runs LF global inventory refresh only when dirty or when the 24-hour safety refresh is due. Uses an advisory transaction lock to prevent overlap.';

do $$
declare r record;
begin
  for r in
    select jobid
    from cron.job
    where jobname like 'lf-global-inventory-%'
  loop
    perform cron.unschedule(r.jobid);
  end loop;

  perform cron.schedule(
    'lf-global-inventory-refresh-v1',
    '17 * * * *',
    'select inventory.fn_refresh_run_v1(false);'
  );
end;
$$;

-- The migration intentionally leaves the state dirty.
-- The first natural orchestrator run will reconcile pending catalog/static-analysis work.
select inventory.fn_mark_dirty_v1();
