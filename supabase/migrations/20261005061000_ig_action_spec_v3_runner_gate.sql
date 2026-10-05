-- Generic runner hardening: read-only mutation guard + terminal-action precedence.
create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null
) returns jsonb
language sql stable
set search_path to 'programacion','public','pg_catalog'
as $$
with s as (
  select programacion.fn_engineering_checkpoint_action_spec_v2(p_plan_code,p_unit_code,p_checkpoint_code) spec
), x as (
  select spec,
         lower(coalesce(spec->>'checkpoint_title','')) title_l,
         coalesce(spec->>'checkpoint_code','') checkpoint_code,
         coalesce((spec->>'requires_material_execution')::boolean,false) is_material
  from s
)
select case
  when spec is null then null
  when (
    (checkpoint_code='DEPENDENCY_WIRING' and title_l like '%hallazgo%')
    or (
      coalesce(spec->>'recipe_mode','')='EXECUTE_DECLARED_DELIVERABLE'
      and title_l ~ '^(verificar|comprobar|readback|observar)'
      and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|registrar dependencia)'
    )
  ) then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','COMPILED_READ_ONLY_GUARD',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'action_steps',jsonb_build_array(
        'READ_DECLARED_AUTHORITY_ONCE',
        'ASSERT_EXACT_STATE',
        'PERSIST_CHECKPOINT_ONLY',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array(
        'MUTATE_DEPENDENCY_GRAPH',
        'CREATE_UNDECLARED_SHARED_ABSTRACTION'
      )
    ) - 'material_contract'
  else
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'mutation_policy',case when is_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,
      'scope_guard',jsonb_build_object(
        'new_shared_or_transversal_abstraction','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED',
        'dependency_graph_mutation','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED',
        'cross_checkpoint_design','FORBIDDEN'
      ),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array(
        'CREATE_UNDECLARED_SHARED_ABSTRACTION',
        'MUTATE_UNDECLARED_TARGET'
      )
    )
end
from x;
$$;

create or replace function programacion.fn_engineering_unit_bootstrap_v3(p_plan_code text,p_unit_code text)
returns jsonb
language sql stable
set search_path to 'programacion','public','pg_catalog'
as $$
with b as (
  select programacion.fn_engineering_unit_bootstrap_v2(p_plan_code,p_unit_code) payload
), base as (
  select payload,
         case when jsonb_typeof(payload->'current_checkpoint')='object' then payload#>>'{current_checkpoint,checkpoint_code}' end checkpoint_code,
         nullif(payload#>>'{identity,work_item_id}','')::bigint work_item_id
  from b
), a as (
  select base.*,
         case when checkpoint_code is null then null else programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,checkpoint_code) end action_spec
  from base
), g as (
  select a.*,
         (coalesce(payload->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
          and checkpoint_code is not null
          and coalesce(action_spec->>'status','')='READY') execution_allowed
  from a
), hb as (
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
), ekb_hb as (
  select jsonb_build_object('codigo',e.codigo,'titulo',e.titulo,'estado',e.estado,'severidad',e.severidad,'validacion',e.validacion,'source_ref',e.source_ref) item
  from public.lf_error_knowledge e
  where e.codigo='ENGINEERING-MATERIAL-HEARTBEAT-001' and e.estado='ACTIVO'
)
select payload || jsonb_build_object(
  'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V3',
  'connector_route',jsonb_build_object('provider','SUPABASE','project_id','mhwmirqcgxxukpctffuv','discovery_required',false),
  'action_spec',action_spec,
  'execution_allowed',execution_allowed,
  'action_spec_gate',case
    when checkpoint_code is null then 'NOT_APPLICABLE'
    when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then 'BLOCK_TERMINAL_ACTION'
    when action_spec->>'status'='READY' then 'PASS'
    else 'BLOCK'
  end,
  'terminal_action',case
    when coalesce(payload->>'terminal_action','')<>'CONTINUE_CURRENT_CHECKPOINT' then payload->>'terminal_action'
    when checkpoint_code is not null and coalesce(action_spec->>'status','')<>'READY' then 'STOP_ACTION_SPEC_INCOMPLETE'
    else payload->>'terminal_action'
  end,
  'execution_input',case when checkpoint_code is null then null else coalesce(action_spec->'execution_input_override',payload->'execution_input') end,
  'execution_contract',jsonb_build_object(
    'sequence',jsonb_build_array('BOOTSTRAP_V3','OBEY_TERMINAL_ACTION','OBEY_ACTION_SPEC','HEARTBEAT_BEFORE_MATERIAL_STEP','EXECUTE_CURRENT_ACTION_ONLY','HEARTBEAT_AFTER_MATERIAL_STEP','VERIFY_CURRENT_CHECKPOINT','PERSIST_ATOMIC_TRANSITION','USE_RETURNED_BOOTSTRAP'),
    'terminal_action_precedence',true,
    'freeform_design_before_action_spec','FORBIDDEN',
    'progress','LEDGER_DERIVED_ONLY'
  ),
  'material_execution',jsonb_build_object(
    'heartbeat_entrypoint','programacion.fn_engineering_checkpoint_heartbeat_v1',
    'heartbeat_required',execution_allowed and coalesce((action_spec->>'requires_material_execution')::boolean,false),
    'heartbeat_phases',jsonb_build_array('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED'),
    'rule','FOR_MATERIAL_ACTIONS_WRITE_BEFORE_AND_AFTER_EACH_DECLARED_STEP; HEARTBEAT_NEVER_CHANGES_LEDGER_PROGRESS',
    'latest_heartbeat',heartbeat_detail,
    'last_heartbeat_at',heartbeat_at,
    'last_heartbeat_age_seconds',case when heartbeat_at is null then null else greatest(0,extract(epoch from (now()-heartbeat_at))::bigint) end,
    'execution_state',case
      when checkpoint_code is null then 'NOT_APPLICABLE'
      when not execution_allowed then 'BLOCKED_BY_TERMINAL_OR_ACTION_GATE'
      when coalesce((action_spec->>'requires_material_execution')::boolean,false)=false then 'NOT_REQUIRED'
      when heartbeat_detail is null then 'NOT_STARTED'
      when heartbeat_detail->>'phase'='CONNECTOR_BLOCKED' then 'BLOCKED_CONNECTOR'
      when heartbeat_detail->>'phase'='ACTION_DONE' then 'ACTION_DONE'
      when heartbeat_detail->>'phase'='ACTION_FAILED' then 'ACTION_FAILED'
      else 'ACTIVE' end
  ),
  'ekb_exact',case
    when (select item from ekb_hb) is null then coalesce(payload->'ekb_exact','[]'::jsonb)
    when coalesce(payload->'ekb_exact','[]'::jsonb) @> jsonb_build_array((select item from ekb_hb)) then coalesce(payload->'ekb_exact','[]'::jsonb)
    else coalesce(payload->'ekb_exact','[]'::jsonb) || jsonb_build_array((select item from ekb_hb)) end
)
from hb;
$$;
