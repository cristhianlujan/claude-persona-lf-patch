
create or replace function programacion.fn_engineering_effective_dependencies_v1(p_work_item_id bigint)
returns table(
  dependency_id bigint,
  relation_type text,
  raw_depends_on_work_item_id bigint,
  raw_work_code text,
  raw_status text,
  effective_work_item_id bigint,
  effective_work_code text,
  effective_status text,
  resolution text,
  is_unmet boolean
)
language sql
stable
as $$
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
$$;

create or replace function programacion.fn_engineering_effective_open_blockers_v1(p_work_item_id bigint)
returns table(blocker_id bigint, blocker_code text, description text, required_action text, source_ref text)
language sql
stable
as $$
  with dep_state as materialized (
    select exists (
      select 1
      from programacion.fn_engineering_effective_dependencies_v1(p_work_item_id) d
      where d.is_unmet
    ) as has_unmet_requires
  )
  select
    b.id,
    b.blocker_code,
    b.description,
    b.required_action,
    b.source_ref
  from programacion.engineering_work_blockers b
  cross join dep_state ds
  where b.work_item_id=p_work_item_id
    and b.status='OPEN'
    and not (
      b.source_ref like 'supabase://programacion.engineering_work_items+programacion.engineering_work_dependencies%'
      and ds.has_unmet_requires=false
    );
$$;

create or replace function programacion.fn_engineering_unit_bootstrap_v1(p_plan_code text,p_unit_code text)
returns jsonb
language sql
stable
as $$
with u as (
  select pu.id as plan_unit_id, pu.plan_code, pu.unit_code, pu.unit_class, pu.lot_code,
         pu.title, pu.exit_criterion, pu.disposition, pu.fused_into_plan_unit_id,
         pu.work_item_id, pu.unit_metadata, wi.work_code, wi.status as work_status
  from programacion.engineering_plan_units pu
  left join programacion.engineering_work_items wi on wi.id=pu.work_item_id
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code
),
progress as (
  select c.work_item_id,
         count(*) as checkpoint_count,
         count(*) filter(where c.status='DONE') as done_checkpoint_count,
         coalesce(sum(c.weight) filter(where c.status<>'NOT_APPLICABLE'),0) as applicable_weight,
         coalesce(sum(c.weight) filter(where c.status='DONE'),0) as done_weight
  from programacion.engineering_work_checkpoints c
  join u on u.work_item_id=c.work_item_id
  group by c.work_item_id
),
current_cp as (
  select c.work_item_id,c.checkpoint_code,c.title,c.status,c.sequence_no,c.evidence_ref
  from programacion.engineering_work_checkpoints c
  join u on u.work_item_id=c.work_item_id
  where c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1
),
deps as (
  select
    count(*) filter(where d.is_unmet) as unmet_deps,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'work_code',d.effective_work_code,
          'status',d.effective_status,
          'relation_type',d.relation_type,
          'raw_work_code',d.raw_work_code,
          'raw_status',d.raw_status,
          'resolution',d.resolution
        )
        order by d.effective_work_code
      ) filter(where d.is_unmet),
      '[]'::jsonb
    ) as unmet_detail
  from u
  left join lateral programacion.fn_engineering_effective_dependencies_v1(u.work_item_id) d on true
),
blockers as (
  select count(*) as open_blockers,
         coalesce(jsonb_agg(jsonb_build_object('blocker_code',b.blocker_code,'description',b.description,'required_action',b.required_action,'source_ref',b.source_ref) order by b.blocker_id),'[]'::jsonb) as open_detail
  from u
  left join lateral programacion.fn_engineering_effective_open_blockers_v1(u.work_item_id) b on true
  where b.blocker_id is not null
),
fused_target as (
  select f.id,f.unit_code,f.work_item_id
  from programacion.engineering_plan_units f
  join u on f.id=u.fused_into_plan_unit_id
),
input_resolved as (
  select case
    when cp.checkpoint_code is null then null
    when u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code] is not null then u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code] is not null then u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' is not null and u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}'<>'null'::jsonb then u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}'
    when u.unit_metadata#>'{source_fast_path_v1,semantic_preferred_input_v2}' is not null then u.unit_metadata#>'{source_fast_path_v1,semantic_preferred_input_v2}'
    when u.unit_metadata#>'{source_fast_path_v1,semantic_preferred_input}' is not null then u.unit_metadata#>'{source_fast_path_v1,semantic_preferred_input}'
    else null end as execution_input,
    case
    when cp.checkpoint_code is null then 'NO_PENDING_CHECKPOINT'
    when u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code] is not null then 'SOURCE_PACK_V2_CHECKPOINT'
    when u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code] is not null then 'SOURCE_PACK_V1_CHECKPOINT'
    when u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' is not null and u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}'<>'null'::jsonb then 'CANONICAL_SEMANTIC_SOURCE'
    when u.unit_metadata#>'{source_fast_path_v1,semantic_preferred_input_v2}' is not null then 'LEGACY_SEMANTIC_PREFERRED_V2'
    when u.unit_metadata#>'{source_fast_path_v1,semantic_preferred_input}' is not null then 'LEGACY_SEMANTIC_PREFERRED_V1'
    else 'MISSING_INPUT' end as execution_input_origin
  from u left join current_cp cp on true
),
ekb_codes as (
  select distinct x.code
  from u
  cross join lateral (
    select jsonb_array_elements_text(case when jsonb_typeof(u.unit_metadata#>'{canonical_bootstrap_v1,ekb_codes}')='array' then u.unit_metadata#>'{canonical_bootstrap_v1,ekb_codes}' else '[]'::jsonb end) as code
    union all
    select jsonb_array_elements_text(case when jsonb_typeof(u.unit_metadata#>'{source_pack_v2,ekb_reuse}')='array' then u.unit_metadata#>'{source_pack_v2,ekb_reuse}' else '[]'::jsonb end)
    union all
    select jsonb_array_elements_text(case when jsonb_typeof(u.unit_metadata#>'{source_pack_v1,ekb_reuse}')='array' then u.unit_metadata#>'{source_pack_v1,ekb_reuse}' else '[]'::jsonb end)
    union all
    select u.unit_metadata#>>'{run_history_effectiveness_policy_v1,ekb_code}' where u.unit_metadata#>>'{run_history_effectiveness_policy_v1,ekb_code}' is not null
    union all
    select u.unit_metadata#>>'{plan_inherited_execution_policies_v1,RUN_HISTORY_EFFECTIVENESS_SAMPLE_V1,ekb_code}' where u.unit_metadata#>>'{plan_inherited_execution_policies_v1,RUN_HISTORY_EFFECTIVENESS_SAMPLE_V1,ekb_code}' is not null
    union all
    select 'ENGINEERING-CHECKPOINT-MICROLOOP-001' where u.unit_metadata#>>'{checkpoint_execution_microloop_v1,contract}'='ENGINEERING_CHECKPOINT_MICROLOOP_V1'
  ) x
  where x.code is not null and x.code<>''
),
ekb as (
  select coalesce(jsonb_agg(jsonb_build_object('codigo',e.codigo,'titulo',e.titulo,'estado',e.estado,'severidad',e.severidad,'validacion',e.validacion,'source_ref',e.source_ref) order by e.codigo),'[]'::jsonb) as items
  from public.lf_error_knowledge e
  join ekb_codes c on c.code=e.codigo
  where e.estado='ACTIVO'
),
source_policy as (
  select jsonb_build_object('policy_code',p.policy_code,'policy_version',p.policy_version,'policy_sha',p.policy_sha,'status',p.status,'source_ref',p.source_ref) as policy
  from public.lf_policy_versions p
  where p.policy_code='POL-LF-SOURCE-RESOLUTION' and p.status='ACTIVE'
  order by p.effective_at desc limit 1
),
resolved as (
 select jsonb_build_object(
  'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V1',
  'identity',jsonb_build_object('plan_code',u.plan_code,'unit_code',u.unit_code,'plan_unit_id',u.plan_unit_id,'unit_class',u.unit_class,'lot_code',u.lot_code,'work_item_id',u.work_item_id,'work_code',u.work_code,'disposition',u.disposition,'fused_into_unit_code',ft.unit_code),
  'state',jsonb_build_object(
    'status',u.work_status,
    'progress_pct',case when u.work_status='DONE' then 100.00 when coalesce(pr.applicable_weight,0)=0 then 0.00 else round(100.0*pr.done_weight/nullif(pr.applicable_weight,0),2) end,
    'checkpoint_count',coalesce(pr.checkpoint_count,0),'done_checkpoint_count',coalesce(pr.done_checkpoint_count,0),
    'open_blockers',coalesce(bl.open_blockers,0),'blockers',coalesce(bl.open_detail,'[]'::jsonb),
    'unmet_deps',coalesce(dp.unmet_deps,0),'unmet_dependencies',coalesce(dp.unmet_detail,'[]'::jsonb)
  ),
  'terminal_action',case
    when u.disposition='FUSED' then 'STOP_TERMINAL_FUSED'
    when u.work_status='DONE' then 'STOP_TERMINAL_DONE'
    when coalesce(dp.unmet_deps,0)>0 then 'WAIT_DEPENDENCIES'
    when coalesce(bl.open_blockers,0)>0 then 'STOP_OPEN_BLOCKER'
    when u.work_status='BLOCKED' then 'RECONCILE_BLOCKED_STATE'
    when cp.checkpoint_code is null then 'RECONCILE_NO_PENDING_CHECKPOINT'
    when ir.execution_input is null then 'STOP_MISSING_EXECUTION_INPUT'
    else 'CONTINUE_CURRENT_CHECKPOINT' end,
  'current_checkpoint',case when cp.checkpoint_code is null then null else jsonb_build_object('checkpoint_code',cp.checkpoint_code,'checkpoint_title',cp.title,'status',cp.status,'sequence_no',cp.sequence_no,'evidence_ref',cp.evidence_ref) end,
  'execution_input_origin',ir.execution_input_origin,
  'execution_input',ir.execution_input,
  'execution_policy',u.unit_metadata->'checkpoint_execution_microloop_v1',
  'ekb_exact',coalesce(ekb.items,'[]'::jsonb),
  'source_resolution_policy',sp.policy,
  'guards',jsonb_build_object(
    'canonical_identity','PLAN_CODE_PLUS_UNIT_CODE','work_code_is_derived_not_lookup_key',true,
    'free_search_before_canonical_lookup',false,'project_discovery',false,'schema_introspection_preflight',false,
    'all_checkpoint_scan',false,'done_dependency_recheck',false,'full_inventory_scan',false,
    'pre_execution_read_budget',coalesce(u.unit_metadata#>'{canonical_bootstrap_v1,read_budget}',jsonb_build_object('bootstrap_calls',1,'execution_input_reads_max',1,'authority_confirmation_reads_max',1)),
    'fallback_only_on',coalesce(u.unit_metadata#>'{canonical_bootstrap_v1,fallback_only_on}','["MISSING_CANONICAL_OBJECT","CONTRADICTION","STALE_CURRENTNESS","DEMONSTRATED_DRIFT","MATERIAL_FINGERPRINT_CHANGE"]'::jsonb)
  )
 ) as payload
 from u
 left join progress pr on pr.work_item_id=u.work_item_id
 left join current_cp cp on true
 cross join deps dp
 cross join blockers bl
 left join fused_target ft on true
 cross join input_resolved ir
 cross join ekb
 left join source_policy sp on true
)
select coalesce((select payload from resolved),jsonb_build_object('schema_version','ENGINEERING_UNIT_BOOTSTRAP_V1','identity',jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code),'terminal_action','STOP_CANONICAL_UNIT_NOT_FOUND','guards',jsonb_build_object('canonical_identity','PLAN_CODE_PLUS_UNIT_CODE','free_search_before_canonical_lookup',false,'registered_alias_only',true)));
$$;

create or replace function programacion.fn_engineering_checkpoint_transition_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_new_status text,
  p_evidence_ref text,
  p_actor text,
  p_detail text default null::text
)
returns jsonb
language plpgsql
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

    select programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id)
      into v_open_blockers;

    select count(*) into v_unmet_deps
    from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
    where d.is_unmet;

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
