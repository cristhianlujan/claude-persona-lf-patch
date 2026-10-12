-- IG M9.9: paired local and generic-governance repair; fail-closed.
-- No runtime promotion, switch, POST_PASE activation, or production edit.
do $repair$
declare src text;
begin
 src:=pg_get_functiondef('programacion.fn_engineering_blocker_reconcile_v1(text,text,boolean)'::regprocedure);
 if md5(src)<>'ab8b64c66d37f837d77067024bbcd036' then raise exception 'M99_BASELINE_DRIFT'; end if;
 if position($a$      elsif v_kind='LATEST_SUITE_RUN_PASS' then$a$ in src)=0 then raise exception 'M99_INJECTION_MISSING_ANCHOR'; end if;
 execute replace(src,$a$      elsif v_kind='LATEST_SUITE_RUN_PASS' then$a$,$b$
      elsif v_kind='CURRENT_CAPABILITY_COHORT_BINDING' then
        if jsonb_typeof(v_rule->'required_work_codes')='array'
          and jsonb_array_length(v_rule->'required_work_codes')>0
          and nullif(v_rule->>'capability_code','') is not null
          and nullif(v_rule->>'checkpoint_code','') is not null then
          select ct.cohort_type_code || ':' || cm.pantalla_id::text into v_source
          from programacion.input_governance_cohort_types ct
          join programacion.input_governance_cohort_memberships cm using(cohort_type_code)
          where ct.status='ACTIVE' and cm.status='ACTIVE'
            and nullif(ct.authority_ref,'') is not null
            and nullif(cm.authority_ref,'') is not null
            and (v_rule->>'cohort_type_code' is null or ct.cohort_type_code=v_rule->>'cohort_type_code')
          order by ct.display_order, cm.representative_rank, cm.pantalla_id limit 1;
          v_pass := v_source is not null
            and exists (select 1 from public.lf_capability_current cc join public.lf_capability_registry cr using(capability_code)
                        where cc.capability_code=v_rule->>'capability_code' and cr.status='ACTIVE'
                          and nullif(cc.version,'') is not null and nullif(cc.manifest_sha256,'') is not null)
            and not exists (select 1 from jsonb_array_elements_text(v_rule->'required_work_codes') req(code)
                            where not exists (select 1 from programacion.engineering_work_items w
                                              where w.work_code=req.code and w.status='DONE'))
            and (programacion.fn_engineering_checkpoint_action_spec_v3(
                  p_plan_code,p_unit_code,v_rule->>'checkpoint_code')->>'status')='READY'
            and (programacion.fn_engineering_checkpoint_action_spec_v3(
                  p_plan_code,p_unit_code,v_rule->>'checkpoint_code')->>'action_kind')='READBACK_ONCE';
          if v_pass then
            v_resolution_ref:='supabase://public.lf_capability_current/'||
                (v_rule->>'capability_code')||
                ';programacion.input_governance_cohort_memberships/'||v_source;
          end if;
        end if;

$b$||$a$      elsif v_kind='LATEST_SUITE_RUN_PASS' then$a$);
end $repair$;
update programacion.engineering_plan_units u
set unit_metadata=jsonb_set(
  jsonb_set(
   jsonb_set(u.unit_metadata,'{action_specs_v1,COHORT_BINDING}',
     (u.unit_metadata#>'{action_specs_v1,COHORT_BINDING}')||
     jsonb_build_object('status','READY','action_kind','READBACK_ONCE',
       'precision','EXPLICIT_CAPABILITY_READBACK_BOUND_V1',
       'recipe_mode','CURRENT_CAPABILITY_SET_ASSERT_V1',
       'expected','Current M9.2 versioned IG binding and M9.4 governed cohort readback; no switch.',
       'requires_material_execution',false,'mutation_policy','NO_DOMAIN_MUTATION',
       'target',jsonb_build_object('checkpoint','COHORT_BINDING',
          'declared_assets',jsonb_build_array('INPUT_GOVERNANCE'),
          'declared_events','[]'::jsonb,
          'declared_objects',jsonb_build_array('public.lf_capability_registry','public.lf_capability_current','programacion.engineering_work_items','programacion.input_governance_cohort_types','programacion.input_governance_cohort_memberships'),
          'declared_artifacts','[]'::jsonb),
       'verification_queries',jsonb_build_array(
          'select capability_code,version,manifest_sha256 from public.lf_capability_current where capability_code=''INPUT_GOVERNANCE''',
          'select work_code,status from programacion.engineering_work_items where work_code in (''PAULO-089'',''PAULO-154'')',
          'select ct.cohort_type_code,cm.pantalla_id from programacion.input_governance_cohort_types ct join programacion.input_governance_cohort_memberships cm using(cohort_type_code) where ct.status=''ACTIVE'' and cm.status=''ACTIVE'' order by ct.display_order,cm.representative_rank,cm.pantalla_id')
     ),true),
   '{source_pack_v1,checkpoint_inputs,COHORT_BINDING,missing}','[]'::jsonb,true),
  '{blocker_reconciliation_v1}',
   coalesce(u.unit_metadata->'blocker_reconciliation_v1','{}'::jsonb)
   ||jsonb_build_object('IG_M99_CUTOVER_CONTRACT_AUTHORITY_DRIFT',
      jsonb_build_object('kind','CURRENT_CAPABILITY_COHORT_BINDING',
        'checkpoint_code','COHORT_BINDING','capability_code','INPUT_GOVERNANCE',
        'required_work_codes',jsonb_build_array('PAULO-089','PAULO-154'))),true)
where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and u.unit_code='M9.9'
  and u.unit_metadata#>>'{action_specs_v1,COHORT_BINDING,status}'='BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED'
  and (select count(distinct d.depends_on_work_item_id)
       from programacion.engineering_work_dependencies d
       join programacion.engineering_work_items w on w.id=d.depends_on_work_item_id
       where d.work_item_id=u.work_item_id and w.work_code in ('PAULO-154','PAULO-156'))=2;
do $guard$
begin
 if not exists(select 1 from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.9'
      and unit_metadata#>>'{action_specs_v1,COHORT_BINDING,status}'='READY'
      and unit_metadata#>'{blocker_reconciliation_v1,IG_M99_CUTOVER_CONTRACT_AUTHORITY_DRIFT}' is not null)
 then raise exception 'M99_METADATA_POSTWRITE_MISSING'; end if;
end $guard$;