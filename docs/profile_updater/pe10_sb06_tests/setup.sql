alter table programacion.engineering_plan_units add column if not exists fused_into_plan_unit_id bigint;
alter table programacion.engineering_work_items add column if not exists completed_at timestamptz;
create or replace function programacion.fn_engineering_effective_dependencies_v1(p_work_item_id bigint)
 returns table(dependency_id bigint, relation_type text, raw_depends_on_work_item_id bigint, raw_work_code text, raw_status text, effective_work_item_id bigint, effective_work_code text, effective_status text, resolution text, is_unmet boolean)
 language sql stable
as $function$
with raw as (
  select
    d.id as dependency_id,
    d.relation_type,
    d.depends_on_work_item_id,
    dw.work_code as raw_work_code,
    dw.status as raw_status,
    fpu.id as fused_plan_unit_id,
    fpu.fused_into_plan_unit_id
  from programacion.engineering_work_dependencies d
  join programacion.engineering_work_items dw
    on dw.id=d.depends_on_work_item_id
  left join lateral (
    select pu.id,pu.fused_into_plan_unit_id
    from programacion.engineering_plan_units pu
    where pu.work_item_id=d.depends_on_work_item_id
      and pu.disposition='FUSED'
    order by pu.id
    limit 1
  ) fpu on true
  where d.work_item_id=p_work_item_id
    and d.relation_type='REQUIRES'
), resolved as (
  select
    raw.*,
    ft.work_item_id as fused_target_work_item_id,
    ftwi.work_code as fused_target_work_code,
    ftwi.status as fused_target_status
  from raw
  left join programacion.engineering_plan_units ft
    on ft.id=raw.fused_into_plan_unit_id
  left join programacion.engineering_work_items ftwi
    on ftwi.id=ft.work_item_id
)
select
  dependency_id,
  relation_type,
  depends_on_work_item_id as raw_depends_on_work_item_id,
  raw_work_code,
  raw_status,
  case when fused_plan_unit_id is not null then fused_target_work_item_id else depends_on_work_item_id end as effective_work_item_id,
  case when fused_plan_unit_id is not null then fused_target_work_code else raw_work_code end as effective_work_code,
  case
    when fused_plan_unit_id is not null then coalesce(fused_target_status,'MISSING_FUSED_TARGET')
    else raw_status
  end as effective_status,
  case
    when fused_plan_unit_id is not null then 'FUSED_TO_TARGET'
    when raw_status='CANCELLED' then 'CANCELLED_IGNORED'
    else 'DIRECT'
  end as resolution,
  case
    when fused_plan_unit_id is not null then coalesce(fused_target_status,'MISSING_FUSED_TARGET')<>'DONE'
    when raw_status='CANCELLED' then false
    else coalesce(raw_status,'BACKLOG')<>'DONE'
  end as is_unmet
from resolved;
$function$;

-- STUB de from_context_v1 (la real depende de ~10 funciones mas; aqui devuelve una salida controlada con la misma forma)
create or replace function programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(p_checkpoint_code text, p_action_spec jsonb, p_packet jsonb, p_unit_metadata jsonb)
 returns jsonb language plpgsql stable as $f$
begin
  if p_unit_metadata is null then
    return jsonb_build_object('schema_version','ENGINEERING_EXECUTION_READINESS_V1','status','NOT_READY','execution_ready',false,'reasons',jsonb_build_array('UNIT_NOT_FOUND'),'context_reused',false);
  end if;
  if p_checkpoint_code like '%\_NR' then
    return jsonb_build_object('schema_version','ENGINEERING_EXECUTION_READINESS_V1','status','NOT_READY','execution_ready',false,'checkpoint_code',p_checkpoint_code,
      'gates',jsonb_build_object('COMPILE_READY',false,'ACTION_EXACT',true,'ERROR_CLOSED',true),'reasons',jsonb_build_array('COMPILE_NOT_READY'),'context_reused',true);
  end if;
  return jsonb_build_object('schema_version','ENGINEERING_EXECUTION_READINESS_V1','status','READY','execution_ready',true,'checkpoint_code',p_checkpoint_code,
    'gates',jsonb_build_object('COMPILE_READY',true,'ACTION_EXACT',true,'ERROR_CLOSED',true),'reasons','[]'::jsonb,'context_reused',true);
end $f$;

-- from_payload_v1 ORIGINAL, fuente identica a produccion
create or replace function programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_packet jsonb)
 returns jsonb language plpgsql stable
as $function$
declare
  v_meta jsonb;
begin
  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  return programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(
    p_checkpoint_code,p_action_spec,p_packet,v_meta
  );
end;
$function$;
do $$ begin if not exists (select 1 from pg_roles where rolname='lf_app_r') then create role lf_app_r; end if; end $$;
revoke all on function programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(text,text,text,jsonb,jsonb) from public;
grant execute on function programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(text,text,text,jsonb,jsonb) to lf_app_r, pgtest;
