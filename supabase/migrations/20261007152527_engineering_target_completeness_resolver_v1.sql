create or replace function programacion.fn_engineering_target_completeness_resolve_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_meta jsonb; v_blocker text; v_exact jsonb;
  v_candidates jsonb:='[]'::jsonb; v_spec jsonb; v_obj text; v_invalid jsonb:='[]'::jsonb;
  v_declared jsonb; v_authoring jsonb; v_resolution text; v_res jsonb;
begin
  select pu.work_item_id,pu.unit_metadata into v_work_item_id,v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  select b.blocker_code into v_blocker
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
    and b.blocker_code ilike '%TARGET_INCOMPLETE%'
  order by b.id limit 1;

  if v_blocker is null then
    return jsonb_build_object('schema_version','ENGINEERING_TARGET_COMPLETENESS_RESOLVER_V1',
      'status','NOT_APPLICABLE','state_changed',false);
  end if;

  v_exact:=coalesce(v_meta#>array['runtime_repair_inputs_v1',p_checkpoint_code,'target_resolution','exact_db_objects'],'[]'::jsonb);

  select coalesce(jsonb_agg(distinct m.member order by m.member),'[]'::jsonb)
    into v_candidates
  from jsonb_array_elements_text(coalesce(
         programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code)
           #>'{target,declared_assets}','[]'::jsonb
       )) a(asset_code)
  join public.lf_activos la on la.codigo_activo=a.asset_code
  cross join lateral jsonb_array_elements_text(coalesce(la.raw_payload->'members','[]'::jsonb)) m(member);

  if jsonb_array_length(v_exact)=0 then
    return jsonb_build_object(
      'schema_version','ENGINEERING_TARGET_COMPLETENESS_RESOLVER_V1',
      'status','INPUT_REQUIRED_EXACT_TARGET','blocker_code',v_blocker,
      'candidate_members',v_candidates,
      'selection_rule','EXACT_REGISTERED_TARGET_ONLY_NO_TITLE_INFERENCE',
      'state_changed',false
    );
  end if;

  for v_obj in select value from jsonb_array_elements_text(v_exact)
  loop
    if to_regprocedure(v_obj) is null and to_regclass(v_obj) is null then
      v_invalid:=v_invalid||jsonb_build_array(v_obj);
    end if;
  end loop;

  if jsonb_array_length(v_invalid)>0 then
    return jsonb_build_object(
      'schema_version','ENGINEERING_TARGET_COMPLETENESS_RESOLVER_V1',
      'status','EXACT_TARGET_NOT_CURRENT','blocker_code',v_blocker,
      'invalid_targets',v_invalid,'state_changed',false
    );
  end if;

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_TARGET_COMPLETENESS_RESOLVER_V1',
      'status','DRY_RUN_READY','blocker_code',v_blocker,
      'exact_db_objects',v_exact,'state_changed',false
    );
  end if;

  v_spec:=v_meta#>array['action_specs_v1',p_checkpoint_code];
  if v_spec is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_TARGET_COMPLETENESS_RESOLVER_V1',
      'status','EXPLICIT_ACTION_SPEC_REQUIRED','blocker_code',v_blocker,'state_changed',false
    );
  end if;

  select coalesce(jsonb_agg(distinct x order by x),'[]'::jsonb)
    into v_declared
  from (
    select value x from jsonb_array_elements_text(coalesce(v_spec#>'{target,declared_objects}','[]'::jsonb))
    union
    select value x from jsonb_array_elements_text(v_exact)
  ) s;

  v_spec:=jsonb_set(v_spec,'{target,declared_objects}',v_declared,true);
  v_authoring:=coalesce(v_spec->'authoring_contract','{}'::jsonb);
  v_authoring:=jsonb_set(v_authoring,'{db_targets_exact}',v_declared,true);
  v_spec:=jsonb_set(v_spec,'{authoring_contract}',v_authoring,true);

  update programacion.engineering_plan_units
     set unit_metadata=jsonb_set(unit_metadata,array['action_specs_v1',p_checkpoint_code],v_spec,true)
   where plan_code=p_plan_code and unit_code=p_unit_code and disposition='ASSIGNED';

  v_resolution:='supabase://programacion.engineering_plan_units/'||p_plan_code||'/'||p_unit_code
    ||'#checkpoint='||p_checkpoint_code||';exact_targets='||jsonb_array_length(v_exact);

  v_res:=programacion.fn_engineering_blocker_resolve_v1(
    p_plan_code,p_unit_code,v_blocker,v_resolution,'ENGINEERING_TARGET_COMPLETENESS_RESOLVER_V1'
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_TARGET_COMPLETENESS_RESOLVER_V1',
    'status',case when coalesce(v_res->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then 'TARGET_DECLARED' else 'RESOLUTION_FAILED' end,
    'blocker_code',v_blocker,'exact_db_objects',v_exact,'result',v_res,
    'state_changed',coalesce(v_res->>'status','')='RESOLVED'
  );
end; $$;