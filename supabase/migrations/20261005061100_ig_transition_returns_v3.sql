-- Canonical transition must return the same authority contract used by the runner.
create or replace function programacion.fn_engineering_checkpoint_transition_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_new_status text,
  p_evidence_ref text,
  p_actor text,
  p_detail text default null
) returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_work_item_id bigint;
  v_current_code text;
  v_existing_status text;
  v_remaining int;
  v_open_blockers int;
  v_unmet_deps int;
  v_result jsonb;
  v_progress text;
  v_next text;
begin
  if p_new_status not in ('DONE','NOT_APPLICABLE','IN_PROGRESS') then
    raise exception 'Unsupported checkpoint transition status: %',p_new_status;
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;
  if v_work_item_id is null then raise exception 'Canonical unit not found: %/%',p_plan_code,p_unit_code; end if;

  select c.status into v_existing_status
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.checkpoint_code=p_checkpoint_code;

  if v_existing_status in ('DONE','NOT_APPLICABLE') then
    return programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code)
      || jsonb_build_object('transition',jsonb_build_object('status','NOOP_ALREADY_TERMINAL','checkpoint_code',p_checkpoint_code));
  end if;

  select c.checkpoint_code into v_current_code
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no limit 1;
  if v_current_code is distinct from p_checkpoint_code then
    raise exception 'Checkpoint % is not current; current=%',p_checkpoint_code,v_current_code;
  end if;

  if p_new_status in ('DONE','NOT_APPLICABLE')
     and coalesce(nullif(btrim(p_evidence_ref),''),nullif(btrim(p_detail),'')) is null then
    raise exception 'Terminal checkpoint transition requires evidence_ref or detail';
  end if;

  update programacion.engineering_work_checkpoints
     set status=p_new_status,
         evidence_ref=coalesce(nullif(p_evidence_ref,''),evidence_ref),
         completed_at=case when p_new_status='DONE' then now() else completed_at end,
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1')
   where work_item_id=v_work_item_id and checkpoint_code=p_checkpoint_code;

  if p_new_status='IN_PROGRESS' then
    update programacion.engineering_work_items
       set status='IN_PROGRESS',started_at=coalesce(started_at,now()),updated_at=now()
     where id=v_work_item_id and status not in ('DONE','CANCELLED');
  else
    select count(*) into v_remaining
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id and c.required and c.status not in ('DONE','NOT_APPLICABLE');

    select count(*) into v_open_blockers
    from programacion.engineering_work_blockers b
    where b.work_item_id=v_work_item_id and b.status='OPEN';

    select count(*) into v_unmet_deps
    from programacion.engineering_work_dependencies d
    join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id
    where d.work_item_id=v_work_item_id and d.relation_type='REQUIRES' and coalesce(dw.status,'BACKLOG')<>'DONE';

    if v_remaining=0 and v_open_blockers=0 and v_unmet_deps=0 then
      update programacion.engineering_work_items
         set status='DONE',completed_at=coalesce(completed_at,now()),started_at=coalesce(started_at,now()),updated_at=now()
       where id=v_work_item_id and status<>'CANCELLED';
    else
      update programacion.engineering_work_items
         set status='IN_PROGRESS',started_at=coalesce(started_at,now()),completed_at=null,updated_at=now()
       where id=v_work_item_id and status not in ('DONE','CANCELLED');
    end if;
  end if;

  v_result:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  v_progress:=coalesce(v_result#>>'{state,progress_pct}','0');
  v_next:=coalesce(v_result#>>'{terminal_action}','UNKNOWN');

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,'PROGRESS',
    'Checkpoint '||p_checkpoint_code||' -> '||p_new_status||'; ledger_progress='||v_progress||'%',
    p_detail,
    v_next||coalesce(' / '||(v_result#>>'{current_checkpoint,checkpoint_code}'),''),
    case when nullif(p_evidence_ref,'') is null then '[]'::jsonb else jsonb_build_array(p_evidence_ref) end,
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1'),now(),
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1')
  );

  return v_result || jsonb_build_object(
    'transition',jsonb_build_object(
      'status','APPLIED','checkpoint_code',p_checkpoint_code,'new_status',p_new_status,
      'ledger_progress_pct',v_progress,'next_terminal_action',v_next
    )
  );
end;
$$;
