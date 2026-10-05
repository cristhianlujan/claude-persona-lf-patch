create or replace function programacion.fn_engineering_unit_bootstrap_v3(p_plan_code text,p_unit_code text)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
with b as materialized (
  select programacion.fn_engineering_unit_bootstrap_v2(p_plan_code,p_unit_code) payload
), base as materialized (
  select payload,
         case when jsonb_typeof(payload->'current_checkpoint')='object' then payload#>>'{current_checkpoint,checkpoint_code}' end checkpoint_code,
         nullif(payload#>>'{identity,work_item_id}','')::bigint work_item_id
  from b
), a as materialized (
  select base.*,
         case when checkpoint_code is null then null else programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,checkpoint_code) end action_spec
  from base
), p as materialized (
  select a.*,
         case when checkpoint_code is null then null else coalesce(action_spec->'execution_input_override',payload->'execution_input') end resolved_execution_input,
         case when checkpoint_code is null then null else programacion.fn_engineering_execution_packet_from_spec_v1(
           p_plan_code,p_unit_code,checkpoint_code,action_spec,
           coalesce(action_spec->'execution_input_override',payload->'execution_input')
         ) end execution_packet
  from a
), g as materialized (
  select p.*,
         (
           coalesce(payload->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
           and checkpoint_code is not null
           and coalesce(action_spec->>'status','')='READY'
           and coalesce(execution_packet->>'status','')='READY'
         ) execution_allowed
  from p
), hb as materialized (
  select g.*,h.heartbeat_detail,h.observed_at heartbeat_at
  from g
  left join lateral (
    select wu.detail::jsonb heartbeat_detail,wu.observed_at
    from programacion.engineering_work_updates wu
    where wu.work_item_id=g.work_item_id
      and wu.reported_by='ENGINEERING_ACTION_HEARTBEAT_V1'
      and wu.detail is not null
      and wu.detail::jsonb->>'checkpoint_code'=g.checkpoint_code
    order by wu.observed_at desc,wu.id desc
    limit 1
  ) h on true
), ekb_extra as materialized (
  select coalesce(jsonb_agg(jsonb_build_object(
    'codigo',e.codigo,'titulo',e.titulo,'estado',e.estado,'severidad',e.severidad,
    'validacion',e.validacion,'source_ref',e.source_ref
  ) order by e.codigo),'[]'::jsonb) items
  from public.lf_error_knowledge e
  where e.codigo in ('ENGINEERING-MATERIAL-HEARTBEAT-001','ENGINEERING-EXECUTION-PACKET-001')
    and e.estado='ACTIVO'
)
select payload || jsonb_build_object(
  'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V3',
  'connector_route',jsonb_build_object('provider','SUPABASE','project_id','mhwmirqcgxxukpctffuv','discovery_required',false),
  'action_spec',action_spec,
  'execution_packet',execution_packet,
  'execution_allowed',execution_allowed,
  'action_spec_gate',case
    when checkpoint_code is null then 'NOT_APPLICABLE'
    when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then 'BLOCK_TERMINAL_ACTION'
    when action_spec->>'status'='READY' then 'PASS'
    else 'BLOCK'
  end,
  'execution_packet_gate',case
    when checkpoint_code is null then 'NOT_APPLICABLE'
    when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then 'BLOCK_TERMINAL_ACTION'
    when coalesce(action_spec->>'status','')<>'READY' then 'BLOCK_ACTION_SPEC'
    when execution_packet->>'status'='READY' then 'PASS'
    else 'BLOCK_SPEC_INCOMPLETE'
  end,
  'terminal_action',case
    when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then payload->>'terminal_action'
    when checkpoint_code is not null and coalesce(action_spec->>'status','')<>'READY' then 'STOP_ACTION_SPEC_INCOMPLETE'
    when checkpoint_code is not null and coalesce(execution_packet->>'status','')<>'READY' then 'STOP_EXECUTION_PACKET_INCOMPLETE'
    else payload->>'terminal_action'
  end,
  'execution_input',resolved_execution_input,
  'execution_contract',jsonb_build_object(
    'sequence',jsonb_build_array(
      'BOOTSTRAP_V3','OBEY_TERMINAL_ACTION','OBEY_ACTION_SPEC','OBEY_EXECUTION_PACKET',
      'HEARTBEAT_BEFORE_MATERIAL_STEP','EXECUTE_PACKET_OPERATION_ONLY','HEARTBEAT_AFTER_MATERIAL_STEP',
      'VERIFY_CURRENT_CHECKPOINT','PERSIST_ATOMIC_TRANSITION','USE_RETURNED_BOOTSTRAP'
    ),
    'terminal_action_precedence',true,
    'freeform_design_before_action_spec','FORBIDDEN',
    'tool_discovery','FORBIDDEN_WHEN_EXECUTION_PACKET_READY',
    'restart_checkpoint_after_tool_failure',false,
    'progress','LEDGER_DERIVED_ONLY'
  ),
  'material_execution',jsonb_build_object(
    'heartbeat_entrypoint','programacion.fn_engineering_checkpoint_heartbeat_v1',
    'heartbeat_required',execution_allowed and coalesce((execution_packet->>'requires_material_execution')::boolean,false),
    'heartbeat_phases',jsonb_build_array('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED'),
    'rule','EXECUTE ONLY DECLARED PACKET OPERATION; HEARTBEAT NEVER CHANGES LEDGER PROGRESS',
    'latest_heartbeat',heartbeat_detail,
    'last_heartbeat_at',heartbeat_at,
    'last_heartbeat_age_seconds',case when heartbeat_at is null then null else greatest(0,extract(epoch from (now()-heartbeat_at))::bigint) end,
    'execution_state',case
      when checkpoint_code is null then 'NOT_APPLICABLE'
      when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then 'BLOCKED_BY_TERMINAL_ACTION'
      when coalesce(action_spec->>'status','')<>'READY' then 'BLOCKED_BY_ACTION_SPEC'
      when coalesce(execution_packet->>'status','')<>'READY' then 'BLOCKED_BY_EXECUTION_PACKET'
      when coalesce((execution_packet->>'requires_material_execution')::boolean,false)=false then 'NOT_REQUIRED'
      when heartbeat_detail is null then 'NOT_STARTED'
      when heartbeat_detail->>'phase'='CONNECTOR_BLOCKED' then 'BLOCKED_CONNECTOR'
      when heartbeat_detail->>'phase'='ACTION_DONE' then 'ACTION_DONE'
      when heartbeat_detail->>'phase'='ACTION_FAILED' then 'ACTION_FAILED'
      else 'ACTIVE'
    end
  ),
  'ekb_exact',coalesce(payload->'ekb_exact','[]'::jsonb) || (select items from ekb_extra)
)
from hb;
$$;
