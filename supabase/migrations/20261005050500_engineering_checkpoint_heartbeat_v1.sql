create or replace function programacion.fn_engineering_checkpoint_heartbeat_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_phase text,
  p_step_code text default null,
  p_actor text default 'ENGINEERING_ACTION_HEARTBEAT_V1',
  p_detail jsonb default '{}'::jsonb,
  p_evidence_ref text default null
) returns jsonb
language plpgsql
volatile
set search_path = programacion, public, pg_catalog
as $function$
declare
  v_work_item_id bigint;
  v_current_checkpoint text;
  v_action_spec jsonb;
  v_step_valid boolean := true;
  v_payload jsonb;
  v_detail jsonb;
begin
  if p_phase not in ('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED') then
    raise exception 'Unsupported heartbeat phase: %', p_phase;
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  if v_work_item_id is null then
    raise exception 'Canonical unit not found: %/%',p_plan_code,p_unit_code;
  end if;

  select c.checkpoint_code into v_current_checkpoint
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no limit 1;

  if v_current_checkpoint is null then
    return programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code)
      || jsonb_build_object('heartbeat_write',jsonb_build_object('status','NOOP_NO_CURRENT_CHECKPOINT'));
  end if;

  if v_current_checkpoint is distinct from p_checkpoint_code then
    raise exception 'Heartbeat checkpoint % is not current; current=%',p_checkpoint_code,v_current_checkpoint;
  end if;

  v_action_spec:=programacion.fn_engineering_checkpoint_action_spec_v1(p_plan_code,p_unit_code,p_checkpoint_code);
  if coalesce(v_action_spec->>'status','')<>'READY' then
    raise exception 'ACTION_SPEC_INCOMPLETE for %/%/%',p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  if coalesce((v_action_spec->>'requires_material_execution')::boolean,false)=false then
    return programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code)
      || jsonb_build_object('heartbeat_write',jsonb_build_object('status','NOOP_NOT_REQUIRED','checkpoint_code',p_checkpoint_code));
  end if;

  if p_step_code is not null then
    select exists(
      select 1 from jsonb_array_elements_text(coalesce(v_action_spec->'action_steps','[]'::jsonb)) s(step_code)
      where s.step_code=p_step_code
    ) into v_step_valid;
    if not v_step_valid then
      raise exception 'Heartbeat step % is not declared in ACTION_SPEC for %/%/%',p_step_code,p_plan_code,p_unit_code,p_checkpoint_code;
    end if;
  end if;

  v_detail:=jsonb_build_object(
    'schema_version','ENGINEERING_MATERIAL_HEARTBEAT_V1','plan_code',p_plan_code,'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,'phase',p_phase,'step_code',p_step_code,
    'action_kind',v_action_spec->>'action_kind','detail',coalesce(p_detail,'{}'::jsonb),'recorded_at',now()
  );

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,'PROGRESS','ACTION_HEARTBEAT|'||p_checkpoint_code||'|'||p_phase||coalesce('|'||p_step_code,''),v_detail::text,
    case p_phase when 'CONNECTOR_BLOCKED' then 'RETRY_SAME_ACTION_STEP_WITH_MINIMAL_ALLOWED_CALL'
      when 'ACTION_DONE' then 'VERIFY_AND_PERSIST_CURRENT_CHECKPOINT'
      when 'ACTION_FAILED' then 'APPLY_FALLBACK_ONLY_IF_AUTHORIZED_TRIGGER'
      else 'CONTINUE_CURRENT_ACTION_ONLY' end,
    case when nullif(p_evidence_ref,'') is null then '[]'::jsonb else jsonb_build_array(p_evidence_ref) end,
    'ENGINEERING_ACTION_HEARTBEAT_V1',now(),coalesce(nullif(p_actor,''),'ENGINEERING_ACTION_HEARTBEAT_V1')
  );

  v_payload:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  return v_payload || jsonb_build_object('heartbeat_write',jsonb_build_object(
    'status','RECORDED','checkpoint_code',p_checkpoint_code,'phase',p_phase,'step_code',p_step_code,'progress_authority_unchanged',true
  ));
end;
$function$;
