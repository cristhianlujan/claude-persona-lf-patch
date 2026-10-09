create or replace function programacion.fn_engineering_structured_source_ref_resolve_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_blocker text; v_legacy_run bigint; v_eligibility jsonb;
  v_currentness jsonb; v_resolution text; v_res jsonb;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  select b.blocker_code into v_blocker
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
    and b.blocker_code ilike '%INVALID_STRUCTURED_SOURCE_REF%'
  order by b.id limit 1;

  if v_blocker is null then
    return jsonb_build_object('schema_version','ENGINEERING_STRUCTURED_SOURCE_REF_RESOLVER_V1',
      'status','NOT_APPLICABLE','state_changed',false);
  end if;

  select max(a.run_id) into v_legacy_run
  from programacion.input_family_assessments a
  where exists (
    select 1 from jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) e(value)
    where jsonb_typeof(e.value)<>'object' or coalesce(e.value->>'kind','')=''
  );

  if v_legacy_run is null then
    return jsonb_build_object('schema_version','ENGINEERING_STRUCTURED_SOURCE_REF_RESOLVER_V1',
      'status','NO_LEGACY_REFS_FOUND','blocker_code',v_blocker,'state_changed',false);
  end if;

  v_eligibility:=programacion.fn_input_source_ref_eligibility_v1(v_legacy_run);
  begin
    v_currentness:=programacion.fn_input_run_source_currentness_v1(v_legacy_run);
  exception when others then
    return jsonb_build_object(
      'schema_version','ENGINEERING_STRUCTURED_SOURCE_REF_RESOLVER_V1',
      'status','CURRENTNESS_STILL_THROWS','blocker_code',v_blocker,
      'legacy_run_id',v_legacy_run,'error',sqlerrm,'state_changed',false
    );
  end;

  if coalesce((v_eligibility->>'legacy_unstructured_refs')::int,0)=0
     or coalesce((v_currentness->>'source_current')::boolean,false) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_STRUCTURED_SOURCE_REF_RESOLVER_V1',
      'status','FAIL_CLOSED_GUARD_NOT_PROVEN','blocker_code',v_blocker,
      'legacy_run_id',v_legacy_run,'eligibility',v_eligibility,
      'currentness',v_currentness,'state_changed',false
    );
  end if;

  v_resolution:='supabase://programacion.fn_input_build_source_manifest_safe_v1'
    ||'#legacy_run='||v_legacy_run||';classification=STALE_NOT_EXCEPTION';

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_STRUCTURED_SOURCE_REF_RESOLVER_V1',
      'status','DRY_RUN_READY','blocker_code',v_blocker,
      'legacy_run_id',v_legacy_run,'eligibility',v_eligibility,
      'currentness',v_currentness,'state_changed',false
    );
  end if;

  v_res:=programacion.fn_engineering_blocker_resolve_v1(
    p_plan_code,p_unit_code,v_blocker,v_resolution,'ENGINEERING_STRUCTURED_SOURCE_REF_RESOLVER_V1'
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_STRUCTURED_SOURCE_REF_RESOLVER_V1',
    'status',case when coalesce(v_res->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then 'LEGACY_FAIL_CLOSED_REPAIRED' else 'RESOLUTION_FAILED' end,
    'blocker_code',v_blocker,'legacy_run_id',v_legacy_run,'result',v_res,
    'state_changed',coalesce(v_res->>'status','')='RESOLVED'
  );
end; $$;