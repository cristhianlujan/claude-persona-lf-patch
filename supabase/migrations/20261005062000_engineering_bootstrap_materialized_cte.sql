create or replace function programacion.fn_engineering_unit_bootstrap_v2(p_plan_code text,p_unit_code text)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
with b as materialized (
  select programacion.fn_engineering_unit_bootstrap_v1(p_plan_code,p_unit_code) payload
)
select payload || jsonb_build_object(
  'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V2',
  'decision_recipe',case when payload->'current_checkpoint' is null then null else programacion.fn_engineering_checkpoint_recipe_v1(p_plan_code,p_unit_code,payload#>>'{current_checkpoint,checkpoint_code}') end,
  'ledger_sync',jsonb_build_object('transition_entrypoint','programacion.fn_engineering_checkpoint_transition_v1','progress_source','programacion.engineering_work_checkpoints','progress_rule','LEDGER_DERIVED_ONLY','checkpoint_transition','PERSIST_THEN_RETURN_REBOOTSTRAP')
) from b;
$function$;

create or replace function programacion.fn_engineering_unit_bootstrap_v3(p_plan_code text,p_unit_code text)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
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
), g as materialized (
  select a.*,
         (coalesce(payload->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT' and checkpoint_code is not null and coalesce(action_spec->>'status','')='READY') execution_allowed
  from a
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
    order by wu.observed_at desc,wu.id desc limit 1
  ) h on true
), ekb_hb as materialized (
  select jsonb_build_object('codigo',e.codigo,'titulo',e.titulo,'estado',e.estado,'severidad',e.severidad,'validacion',e.validacion,'source_ref',e.source_ref) item
  from public.lf_error_knowledge e
  where e.codigo='ENGINEERING-MATERIAL-HEARTBEAT-001' and e.estado='ACTIVO'
)
select payload || jsonb_build_object(
  'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V3',
  'connector_route',jsonb_build_object('provider','SUPABASE','project_id','mhwmirqcgxxukpctffuv','discovery_required',false),
  'action_spec',action_spec,
  'execution_allowed',execution_allowed,
  'action_spec_gate',case when checkpoint_code is null then 'NOT_APPLICABLE' when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then 'BLOCK_TERMINAL_ACTION' when action_spec->>'status'='READY' then 'PASS' else 'BLOCK' end,
  'terminal_action',case when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then payload->>'terminal_action' when checkpoint_code is not null and coalesce(action_spec->>'status','')<>'READY' then 'STOP_ACTION_SPEC_INCOMPLETE' else payload->>'terminal_action' end,
  'execution_input',case when checkpoint_code is null then null else coalesce(action_spec->'execution_input_override',payload->'execution_input') end,
  'execution_contract',jsonb_build_object('sequence',jsonb_build_array('BOOTSTRAP_V3','OBEY_TERMINAL_ACTION','OBEY_ACTION_SPEC','HEARTBEAT_BEFORE_MATERIAL_STEP','EXECUTE_CURRENT_ACTION_ONLY','HEARTBEAT_AFTER_MATERIAL_STEP','VERIFY_CURRENT_CHECKPOINT','PERSIST_ATOMIC_TRANSITION','USE_RETURNED_BOOTSTRAP'),'terminal_action_precedence',true,'freeform_design_before_action_spec','FORBIDDEN','progress','LEDGER_DERIVED_ONLY'),
  'material_execution',jsonb_build_object(
    'heartbeat_entrypoint','programacion.fn_engineering_checkpoint_heartbeat_v1',
    'heartbeat_required',execution_allowed and coalesce((action_spec->>'requires_material_execution')::boolean,false),
    'heartbeat_phases',jsonb_build_array('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED'),
    'rule','FOR_MATERIAL_ACTIONS_WRITE_BEFORE_AND_AFTER_EACH_DECLARED_STEP; HEARTBEAT_NEVER_CHANGES_LEDGER_PROGRESS',
    'latest_heartbeat',heartbeat_detail,
    'last_heartbeat_at',heartbeat_at,
    'last_heartbeat_age_seconds',case when heartbeat_at is null then null else greatest(0,extract(epoch from (now()-heartbeat_at))::bigint) end,
    'execution_state',case when checkpoint_code is null then 'NOT_APPLICABLE' when not execution_allowed then 'BLOCKED_BY_TERMINAL_OR_ACTION_GATE' when coalesce((action_spec->>'requires_material_execution')::boolean,false)=false then 'NOT_REQUIRED' when heartbeat_detail is null then 'NOT_STARTED' when heartbeat_detail->>'phase'='CONNECTOR_BLOCKED' then 'BLOCKED_CONNECTOR' when heartbeat_detail->>'phase'='ACTION_DONE' then 'ACTION_DONE' when heartbeat_detail->>'phase'='ACTION_FAILED' then 'ACTION_FAILED' else 'ACTIVE' end
  ),
  'ekb_exact',case when (select item from ekb_hb) is null then coalesce(payload->'ekb_exact','[]'::jsonb) when coalesce(payload->'ekb_exact','[]'::jsonb) @> jsonb_build_array((select item from ekb_hb)) then coalesce(payload->'ekb_exact','[]'::jsonb) else coalesce(payload->'ekb_exact','[]'::jsonb) || jsonb_build_array((select item from ekb_hb)) end
)
from hb;
$function$;
