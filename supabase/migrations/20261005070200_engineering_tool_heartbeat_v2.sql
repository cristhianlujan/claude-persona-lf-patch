create or replace function programacion.fn_engineering_checkpoint_heartbeat_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_phase text,
  p_step_code text default null,
  p_actor text default 'ENGINEERING_ACTION_HEARTBEAT_V1',
  p_detail jsonb default '{}'::jsonb,
  p_evidence_ref text default null
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_work_item_id bigint;
  v_current_checkpoint text;
  v_action_spec jsonb;
  v_step_valid boolean:=true;
  v_payload jsonb;
  v_detail jsonb;
  v_material boolean;
begin
  if p_phase not in ('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED') then
    raise exception 'Unsupported heartbeat phase: %',p_phase;
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

  v_action_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code);
  if coalesce(v_action_spec->>'status','')<>'READY' then
    raise exception 'ACTION_SPEC_INCOMPLETE for %/%/%',p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  v_material:=coalesce((v_action_spec->>'requires_material_execution')::boolean,false);

  -- Tool failures/retries are observable for every checkpoint, including read-only ones.
  if not v_material and p_phase not in ('CONNECTOR_BLOCKED','RETRYING') then
    return programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code)
      || jsonb_build_object('heartbeat_write',jsonb_build_object(
        'status','NOOP_NOT_REQUIRED','checkpoint_code',p_checkpoint_code,
        'action_spec_schema',v_action_spec->>'schema_version'));
  end if;

  if p_step_code is not null and v_material then
    select exists(
      select 1 from jsonb_array_elements_text(coalesce(v_action_spec->'action_steps','[]'::jsonb)) s(step_code)
      where s.step_code=p_step_code
    ) into v_step_valid;
    if not v_step_valid then
      raise exception 'Heartbeat step % is not declared in ACTION_SPEC for %/%/%',p_step_code,p_plan_code,p_unit_code,p_checkpoint_code;
    end if;
  end if;

  v_detail:=jsonb_build_object(
    'schema_version','ENGINEERING_TOOL_HEARTBEAT_V2',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'phase',p_phase,
    'step_code',p_step_code,
    'action_kind',v_action_spec->>'action_kind',
    'detail',coalesce(p_detail,'{}'::jsonb),
    'recorded_at',now()
  );

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,
    case when p_phase='CONNECTOR_BLOCKED' then 'RISK' else 'PROGRESS' end,
    'ACTION_HEARTBEAT|'||p_checkpoint_code||'|'||p_phase||coalesce('|'||p_step_code,''),
    v_detail::text,
    case p_phase
      when 'CONNECTOR_BLOCKED' then 'RETRY_SAME_ACTION_STEP_ONLY'
      when 'RETRYING' then 'CONTINUE_SAME_ACTION_STEP_ONLY'
      when 'ACTION_DONE' then 'VERIFY_AND_PERSIST_CURRENT_CHECKPOINT'
      when 'ACTION_FAILED' then 'APPLY_FALLBACK_ONLY_IF_AUTHORIZED_TRIGGER'
      else 'CONTINUE_CURRENT_ACTION_ONLY'
    end,
    case when nullif(p_evidence_ref,'') is null then '[]'::jsonb else jsonb_build_array(p_evidence_ref) end,
    'ENGINEERING_ACTION_HEARTBEAT_V1',now(),coalesce(nullif(p_actor,''),'ENGINEERING_ACTION_HEARTBEAT_V1')
  );

  v_payload:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  return v_payload || jsonb_build_object('heartbeat_write',jsonb_build_object(
    'status','RECORDED','checkpoint_code',p_checkpoint_code,'phase',p_phase,'step_code',p_step_code,
    'action_spec_schema',v_action_spec->>'schema_version','progress_authority_unchanged',true));
end;
$$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-EXECUTION-PACKET-001','ENGINEERING_GOVERNANCE',
  'Action spec must compile to an exact connector execution packet',
  'Action specs that still require tool discovery or undeclared material design create long agent delays and unsafe improvisation.',
  'Checkpoint semantics were compiled, but connector routing, material output artifact and retry behavior were not closed.',
  'action_spec READY -> agent rediscovery/tool selection -> retries or freeform materialization',
  'Bootstrap V3 must expose ENGINEERING_EXECUTION_PACKET_V1. Material work without declared target, verification and executable output artifact/operation is blocked. Read-only observations are not materialized. Retry is same failed operation only and never restarts the checkpoint.',
  'PASS when current executable checkpoints expose execution_packet.status=READY; ambiguous material checkpoints return STOP_EXECUTION_PACKET_INCOMPLETE; M3.5 routes GitHub->Supabase, M9.11 is readback-only, and tool failures can be recorded without changing ledger progress.',
  'HIGH','ACTIVO','EXECUTION',array['IG','ENGINEERING_AGENT'],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT','IG generic runner tool routing and retry latency',
  'supabase://programacion.fn_engineering_execution_packet_from_spec_v1'
)
on conflict (codigo) do update set
  titulo=excluded.titulo,descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,patron=excluded.patron,
  prevencion=excluded.prevencion,validacion=excluded.validacion,severidad=excluded.severidad,estado='ACTIVO',
  lifecycle_phase=excluded.lifecycle_phase,consumer_role=excluded.consumer_role,root_cause_family=excluded.root_cause_family,
  detectability=excluded.detectability,source_context=excluded.source_context,source_ref=excluded.source_ref;

update public.lf_error_knowledge
set prevencion='For material ACTION_SPEC_V3 steps, persist heartbeat stages before and after each declared action. CONNECTOR_BLOCKED and RETRYING are recordable for material and read-only checkpoints. Retry only the failed execution_packet operation; never restart the checkpoint. Heartbeats never alter checkpoint progress.',
    validacion='PASS when material heartbeats consume ACTION_SPEC_V3; CONNECTOR_BLOCKED can be persisted for read-only checkpoints; terminal units preserve STOP_TERMINAL_DONE; checkpoint progress remains ledger-derived.'
where codigo='ENGINEERING-MATERIAL-HEARTBEAT-001';
