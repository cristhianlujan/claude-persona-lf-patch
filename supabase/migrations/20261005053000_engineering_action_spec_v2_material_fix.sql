-- ENGINEERING_ACTION_SPEC_V2_MATERIAL_FIX
-- Materialization checkpoints are material work even when their titles do not contain
-- test verbs. Patch V1 output instead of duplicating its classification logic.

create or replace function programacion.fn_engineering_checkpoint_action_spec_v2(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null
) returns jsonb
language sql
stable
set search_path = programacion, public, pg_catalog
as $function$
with s as (
  select programacion.fn_engineering_checkpoint_action_spec_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  ) as spec
)
select case
  when spec is null then null
  when spec->>'action_kind'='MATERIALIZE_DECLARED_DELIVERABLE' then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V2',
      'precision','COMPILED_MATERIAL_HANDLER',
      'requires_material_execution',true,
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode',case
          when jsonb_array_length(coalesce(spec->'verification_queries','[]'::jsonb))>0 then 'DECLARED_QUERY_READBACK'
          when jsonb_array_length(coalesce(spec#>'{target,declared_artifacts}','[]'::jsonb))>0 then 'ARTIFACT_AND_TARGET_READBACK'
          else 'DECLARED_TARGET_READBACK'
        end,
        'design_boundary','ONLY_CURRENT_CHECKPOINT_DELIVERABLE',
        'persist_on_pass','programacion.fn_engineering_checkpoint_transition_v1'
      )
    )
  else
    spec || jsonb_build_object('schema_version','ENGINEERING_ACTION_SPEC_V2')
end
from s;
$function$;

create or replace function programacion.fn_engineering_unit_bootstrap_v3(
  p_plan_code text,
  p_unit_code text
) returns jsonb
language sql
stable
set search_path = programacion, public, pg_catalog
as $function$
with b as (
  select programacion.fn_engineering_unit_bootstrap_v2(p_plan_code,p_unit_code) payload
), base as (
  select payload,
         case when jsonb_typeof(payload->'current_checkpoint')='object' then payload#>>'{current_checkpoint,checkpoint_code}' end as checkpoint_code,
         nullif(payload#>>'{identity,work_item_id}','')::bigint as work_item_id
  from b
), a as (
  select base.*,
         case when checkpoint_code is null then null else programacion.fn_engineering_checkpoint_action_spec_v2(p_plan_code,p_unit_code,checkpoint_code) end as action_spec
  from base
), hb as (
  select a.*,h.heartbeat_detail,h.observed_at as heartbeat_at
  from a
  left join lateral (
    select wu.detail::jsonb heartbeat_detail,wu.observed_at
    from programacion.engineering_work_updates wu
    where wu.work_item_id=a.work_item_id
      and wu.reported_by='ENGINEERING_ACTION_HEARTBEAT_V1'
      and wu.detail is not null
      and wu.detail::jsonb->>'checkpoint_code'=a.checkpoint_code
    order by wu.observed_at desc,wu.id desc limit 1
  ) h on true
), ekb_hb as (
  select jsonb_build_object('codigo',e.codigo,'titulo',e.titulo,'estado',e.estado,'severidad',e.severidad,'validacion',e.validacion,'source_ref',e.source_ref) item
  from public.lf_error_knowledge e
  where e.codigo='ENGINEERING-MATERIAL-HEARTBEAT-001' and e.estado='ACTIVO'
)
select payload || jsonb_build_object(
  'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V3',
  'action_spec',action_spec,
  'action_spec_gate',case when checkpoint_code is null then 'NOT_APPLICABLE' when action_spec->>'status'='READY' then 'PASS' else 'BLOCK' end,
  'terminal_action',case when checkpoint_code is not null and coalesce(action_spec->>'status','')<>'READY' then 'STOP_ACTION_SPEC_INCOMPLETE' else payload->>'terminal_action' end,
  'execution_input',case when checkpoint_code is null then null else coalesce(action_spec->'execution_input_override',payload->'execution_input') end,
  'execution_contract',jsonb_build_object(
    'sequence',jsonb_build_array('BOOTSTRAP_V3','OBEY_ACTION_SPEC','HEARTBEAT_BEFORE_MATERIAL_STEP','EXECUTE_CURRENT_ACTION_ONLY','HEARTBEAT_AFTER_MATERIAL_STEP','VERIFY_CURRENT_CHECKPOINT','PERSIST_ATOMIC_TRANSITION','USE_RETURNED_BOOTSTRAP'),
    'freeform_design_before_action_spec','FORBIDDEN','progress','LEDGER_DERIVED_ONLY'
  ),
  'material_execution',jsonb_build_object(
    'heartbeat_entrypoint','programacion.fn_engineering_checkpoint_heartbeat_v1',
    'heartbeat_required',case when checkpoint_code is null then false else coalesce((action_spec->>'requires_material_execution')::boolean,false) end,
    'heartbeat_phases',jsonb_build_array('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED'),
    'rule','FOR_MATERIAL_ACTIONS_WRITE_BEFORE_AND_AFTER_EACH_DECLARED_STEP; WRITE_CONNECTOR_BLOCKED_ON_CONNECTOR_REJECTION; HEARTBEAT_NEVER_CHANGES_LEDGER_PROGRESS',
    'latest_heartbeat',heartbeat_detail,
    'last_heartbeat_at',heartbeat_at,
    'last_heartbeat_age_seconds',case when heartbeat_at is null then null else greatest(0,extract(epoch from (now()-heartbeat_at))::bigint) end,
    'execution_state',case
      when checkpoint_code is null then 'NOT_APPLICABLE'
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
$function$;

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{canonical_bootstrap_v3,action_spec_entrypoint}',
  '"programacion.fn_engineering_checkpoint_action_spec_v2"'::jsonb,
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';

update public.lf_error_knowledge
set prevencion='Use ENGINEERING_UNIT_BOOTSTRAP_V3 with ACTION_SPEC_V2. Every pending checkpoint must return an executable action spec. MATERIALIZE_DECLARED_DELIVERABLE is always material execution and therefore requires heartbeat even when its title has no test verb.',
    validacion='PASS when every pending MATERIALIZE_DECLARED_DELIVERABLE reports requires_material_execution=true, Bootstrap V3 exposes heartbeat_required=true for those current checkpoints, and terminal/readback progress remains ledger-derived.',
    source_ref='supabase://programacion.fn_engineering_checkpoint_action_spec_v2',
    updated_at=now()
where codigo='ENGINEERING-ACTION-SPEC-CONTRACT-001';
