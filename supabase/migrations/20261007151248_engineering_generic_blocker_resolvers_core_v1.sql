create or replace function programacion.fn_engineering_dependency_auto_release_v1(
  p_plan_code text,p_unit_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare v_work_item_id bigint; v_open_count int:=0; v_open jsonb:='[]'::jsonb;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    return jsonb_build_object('schema_version','ENGINEERING_DEPENDENCY_AUTO_RELEASE_V1','status','UNIT_NOT_FOUND','state_changed',false);
  end if;

  select count(*)::int,
         coalesce(jsonb_agg(jsonb_build_object(
           'work_item_id',dw.id,'work_code',dw.work_code,'status',dw.status,
           'unit_code',dpu.unit_code,'disposition',dpu.disposition
         ) order by dw.id),'[]'::jsonb)
    into v_open_count,v_open
  from programacion.engineering_work_dependencies d
  join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id
  left join programacion.engineering_plan_units dpu
    on dpu.plan_code=p_plan_code and dpu.work_item_id=dw.id
  where d.work_item_id=v_work_item_id
    and d.relation_type='REQUIRES'
    and dw.status<>'DONE'
    and coalesce(dpu.disposition,'ASSIGNED') not in ('FUSED','CANCELLED');

  return jsonb_build_object(
    'schema_version','ENGINEERING_DEPENDENCY_AUTO_RELEASE_V1',
    'status',case when v_open_count=0 then 'RELEASED' else 'WAIT_DEPENDENCIES' end,
    'unmet_dependencies',v_open_count,'dependencies',v_open,
    'selection_rule','ONLY_LIVE_REQUIRES_BLOCK; DONE_FUSED_CANCELLED_DO_NOT_BLOCK',
    'state_changed',false
  );
end; $$;

create or replace function programacion.fn_engineering_currentness_drift_reconcile_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare v_work_item_id bigint; v_blocker text; v_current jsonb; v_spec jsonb; v_resolution text; v_res jsonb;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  select b.blocker_code into v_blocker
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
    and b.blocker_code ilike '%CURRENTNESS_DRIFT%'
  order by b.id limit 1;

  if v_blocker is null then
    return jsonb_build_object('schema_version','ENGINEERING_CURRENTNESS_DRIFT_RECONCILER_V1','status','NOT_APPLICABLE','state_changed',false);
  end if;

  v_current:=programacion.fn_engineering_source_pack_currentness_v1(p_plan_code,p_unit_code,p_checkpoint_code);
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code);

  if coalesce(v_current->>'status','')<>'CURRENT' or coalesce(v_spec->>'status','')<>'READY' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CURRENTNESS_DRIFT_RECONCILER_V1','status','WAIT_CURRENT_AUTHORITY',
      'blocker_code',v_blocker,'source_currentness',v_current->>'status',
      'action_spec_status',v_spec->>'status','state_changed',false
    );
  end if;

  v_resolution:='supabase://programacion.fn_engineering_source_pack_currentness_v1/'
    ||p_plan_code||'/'||p_unit_code||'/'||p_checkpoint_code||'#CURRENT;action_spec=READY';

  if not p_apply then
    return jsonb_build_object('schema_version','ENGINEERING_CURRENTNESS_DRIFT_RECONCILER_V1','status','DRY_RUN_READY',
      'blocker_code',v_blocker,'resolution_ref',v_resolution,'state_changed',false);
  end if;

  v_res:=programacion.fn_engineering_blocker_resolve_v1(
    p_plan_code,p_unit_code,v_blocker,v_resolution,'ENGINEERING_CURRENTNESS_DRIFT_RECONCILER_V1'
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_CURRENTNESS_DRIFT_RECONCILER_V1',
    'status',case when coalesce(v_res->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then 'RECONCILED' else 'RESOLUTION_FAILED' end,
    'blocker_code',v_blocker,'resolution_ref',v_resolution,'result',v_res,
    'state_changed',coalesce(v_res->>'status','')='RESOLVED'
  );
end; $$;

create or replace function programacion.fn_engineering_canonical_identity_resolve_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_blocker text; v_subject text; v_count int:=0;
  v_kind text; v_code text; v_version text; v_digest text; v_resolution text; v_res jsonb;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  select b.blocker_code into v_blocker
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
    and b.blocker_code ilike '%CANONICAL_IDENTITY_MISSING%'
  order by b.id limit 1;

  if v_blocker is null then
    return jsonb_build_object('schema_version','ENGINEERING_CANONICAL_IDENTITY_RESOLVER_V1','status','NOT_APPLICABLE','state_changed',false);
  end if;

  v_subject:=regexp_replace(v_blocker,'_CANONICAL_IDENTITY_MISSING$','','i');

  with c as (
    select 'CAPABILITY'::text kind,r.capability_code code,cc.version,cc.manifest_sha256 digest,
           case when upper(r.capability_code)=upper(v_subject) then 0 else 1 end priority
    from public.lf_capability_registry r
    join public.lf_capability_current cc on cc.capability_code=r.capability_code
    where cc.manifest_sha256 ~ '^[0-9a-f]{64}$'
      and (upper(r.capability_code)=upper(v_subject)
        or r.capability_code ilike '%'||v_subject||'%'
        or r.capability_name ilike '%'||v_subject||'%')
    union all
    select 'ASSET',a.codigo_activo,a.version,coalesce(a.metadata->>'sha256',a.raw_payload->>'sha256'),
           case when upper(a.codigo_activo)=upper(v_subject) then 0 else 1 end
    from public.lf_activos a
    where a.archived_at is null
      and coalesce(a.metadata->>'sha256',a.raw_payload->>'sha256','') ~ '^[0-9a-f]{64}$'
      and (upper(a.codigo_activo)=upper(v_subject)
        or a.codigo_activo ilike '%'||v_subject||'%'
        or a.nombre_canonico ilike '%'||v_subject||'%')
  ), ranked as (select *,min(priority) over() min_priority from c)
  select count(*)::int,min(kind),min(code),min(version),min(digest)
    into v_count,v_kind,v_code,v_version,v_digest
  from ranked where priority=min_priority;

  if v_count=0 then
    return jsonb_build_object('schema_version','ENGINEERING_CANONICAL_IDENTITY_RESOLVER_V1',
      'status','WAIT_UPSTREAM_CANONICAL_IDENTITY','blocker_code',v_blocker,'subject',v_subject,
      'local_substitute','FORBIDDEN','state_changed',false);
  elsif v_count>1 then
    return jsonb_build_object('schema_version','ENGINEERING_CANONICAL_IDENTITY_RESOLVER_V1',
      'status','AMBIGUOUS_CANONICAL_IDENTITY','blocker_code',v_blocker,'subject',v_subject,
      'candidate_count',v_count,'state_changed',false);
  end if;

  v_resolution:='supabase://canonical-identity/'||v_kind||'/'||v_code
    ||'#version='||coalesce(v_version,'')||';sha256='||v_digest;

  if not p_apply then
    return jsonb_build_object('schema_version','ENGINEERING_CANONICAL_IDENTITY_RESOLVER_V1',
      'status','DRY_RUN_READY','blocker_code',v_blocker,'identity_kind',v_kind,'identity_code',v_code,
      'version',v_version,'sha256',v_digest,'state_changed',false);
  end if;

  v_res:=programacion.fn_engineering_blocker_resolve_v1(
    p_plan_code,p_unit_code,v_blocker,v_resolution,'ENGINEERING_CANONICAL_IDENTITY_RESOLVER_V1'
  );

  return jsonb_build_object('schema_version','ENGINEERING_CANONICAL_IDENTITY_RESOLVER_V1',
    'status',case when coalesce(v_res->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then 'RECONCILED' else 'RESOLUTION_FAILED' end,
    'blocker_code',v_blocker,'identity_kind',v_kind,'identity_code',v_code,'version',v_version,'sha256',v_digest,
    'result',v_res,'state_changed',coalesce(v_res->>'status','')='RESOLVED');
end; $$;