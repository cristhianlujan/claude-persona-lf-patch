-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.4 / SEMANTIC_PLAN_RESOLVERS
-- Current family registry -> M3 eligibility -> declared semantic resolver -> composition -> stage policy.
-- CAPABILITY_SELECTOR is bound as selection-only; this checkpoint does not claim runtime selector qualification.

do $preflight$
declare
  v_def text;
  v_family_count integer;
  v_invalid integer;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_def;

  if position('M5_4_SEMANTIC_PLAN_V1' in v_def)>0 then
    raise exception 'M5_4_SEMANTIC_PLAN_ALREADY_APPLIED';
  end if;
  if position('M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1' in v_def)=0 then
    raise exception 'M5_4_CORE_INVOCATION_REQUIRED';
  end if;

  with c as (
    select ct.especificacion
    from programacion.contratos ct
    where ct.version_id=public.fn_lf_version_compatibility_current_version_id_v1(
      'PROGRAMACION_CONTRACT','INPUT_FAMILY_POLICY_REGISTRY',null
    )
      and ct.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
      and ct.estado='defined'
      and ct.fail_closed
    order by ct.id desc limit 1
  ), f as (
    select e.key family_code,e.value policy
    from c cross join lateral jsonb_each(c.especificacion->'families') e
  )
  select count(*),
         count(*) filter (
           where jsonb_typeof(policy->'semantic_resolvers')<>'array'
              or jsonb_array_length(policy->'semantic_resolvers')<1
              or nullif(policy#>>'{semantic_resolvers,0,function}','') is null
              or jsonb_typeof(policy->'stage_policy')<>'object'
         )
    into v_family_count,v_invalid
  from f;

  if v_family_count<>47 or v_invalid<>0 then
    raise exception 'M5_4_FAMILY_REGISTRY_INVALID:%:%',v_family_count,v_invalid;
  end if;

  if not exists (
    select 1
    from public.lf_capability_registry r
    join public.lf_capability_current c using(capability_code)
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code and v.version=c.version
    where r.capability_code='CAPABILITY_SELECTOR'
      and r.status='ACTIVE'
      and v.release_state='RELEASED'
      and coalesce((v.manifest#>>'{contract,multi_label}')::boolean,false)
      and coalesce((v.manifest#>>'{contract,selection_is_admission}')::boolean,false)=false
  ) then
    raise exception 'M5_4_CAPABILITY_SELECTOR_CURRENT_UNRESOLVED';
  end if;
end;
$preflight$;

do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_def;

  v_def:=replace(
    v_def,
    E'  v_core_invocation_count integer:=0;\n',
    E'  v_core_invocation_count integer:=0;\n'
    || E'  v_semantic_registry jsonb;\n'
    || E'  v_semantic_registry_sha text;\n'
    || E'  v_semantic_policy jsonb;\n'
    || E'  v_semantic_resolver text;\n'
    || E'  v_semantic_probe jsonb;\n'
    || E'  v_semantic_eligibility text;\n'
    || E'  v_semantic_execution_state text;\n'
    || E'  v_semantic_plan_count integer:=0;\n'
    || E'  v_selector_version text;\n'
    || E'  v_selector_manifest_sha text;\n'
  );

  v_def:=replace(
    v_def,
    E'    for v_core_assessment in\n      select * from programacion.input_family_assessments\n',
    E'    select c.especificacion,c.especificacion->>''registry_sha256''\n'
    || E'      into v_semantic_registry,v_semantic_registry_sha\n'
    || E'    from programacion.contratos c\n'
    || E'    where c.version_id=public.fn_lf_version_compatibility_current_version_id_v1(\n'
    || E'      ''PROGRAMACION_CONTRACT'',''INPUT_FAMILY_POLICY_REGISTRY'',null\n'
    || E'    )\n'
    || E'      and c.contrato_codigo=''INPUT_FAMILY_POLICY_REGISTRY''\n'
    || E'      and c.estado=''defined'' and c.fail_closed\n'
    || E'    order by c.id desc limit 1;\n'
    || E'    if v_semantic_registry is null or v_semantic_registry_sha is null then\n'
    || E'      raise exception ''M5_4_FAMILY_POLICY_REGISTRY_UNRESOLVED'';\n'
    || E'    end if;\n'
    || E'    if v_semantic_registry->>''registry_sha256'' is distinct from v_semantic_registry_sha then\n'
    || E'      raise exception ''M5_4_FAMILY_POLICY_REGISTRY_SHA_DRIFT'';\n'
    || E'    end if;\n'
    || E'    select c.version,c.manifest_sha256\n'
    || E'      into v_selector_version,v_selector_manifest_sha\n'
    || E'    from public.lf_capability_current c\n'
    || E'    join public.lf_capability_version_registry v\n'
    || E'      on v.capability_code=c.capability_code and v.version=c.version\n'
    || E'    where c.capability_code=''CAPABILITY_SELECTOR'' and v.release_state=''RELEASED'';\n'
    || E'    if v_selector_version is null or v_selector_manifest_sha is null then\n'
    || E'      raise exception ''M5_4_CAPABILITY_SELECTOR_BINDING_UNRESOLVED'';\n'
    || E'    end if;\n'
    || E'    for v_core_assessment in\n'
    || E'      select * from programacion.input_family_assessments\n'
  );

  v_def:=replace(
    v_def,
    E'      where a.id=v_core_assessment.id;\n      v_core_invocation_count:=v_core_invocation_count+1;\n',
    E'      where a.id=v_core_assessment.id;\n'
    || E'      v_semantic_policy:=v_semantic_registry->''families''->v_core_assessment.family_code;\n'
    || E'      if v_semantic_policy is null then\n'
    || E'        raise exception ''M5_4_FAMILY_POLICY_MISSING:%'',v_core_assessment.family_code;\n'
    || E'      end if;\n'
    || E'      v_semantic_resolver:=v_semantic_policy#>>''{semantic_resolvers,0,function}'';\n'
    || E'      if v_semantic_resolver is distinct from ''programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)''\n'
    || E'         or to_regprocedure(v_semantic_resolver) is null then\n'
    || E'        raise exception ''M5_4_SEMANTIC_RESOLVER_UNSUPPORTED:%:%'',v_core_assessment.family_code,v_semantic_resolver;\n'
    || E'      end if;\n'
    || E'      v_semantic_probe:=programacion.fn_input_governance_semantic_probe_v3(\n'
    || E'        p_pantalla_id,v_core_assessment.family_code,v_version\n'
    || E'      );\n'
    || E'      v_semantic_eligibility:=case\n'
    || E'        when coalesce(v_core_assessment.applicability,'''')=''NOT_APPLICABLE'' then ''NOT_REQUIRED''\n'
    || E'        when upper(coalesce(v_semantic_policy#>>''{stage_policy,coverage_required_by}'',''''))=''STORY'' then ''REQUIRED''\n'
    || E'        else ''CONDITIONAL'' end;\n'
    || E'      v_semantic_execution_state:=case\n'
    || E'        when v_semantic_eligibility=''NOT_REQUIRED'' then ''NOT_REQUIRED''\n'
    || E'        when coalesce(v_core_assessment.coverage_status,'''')=''COMPLETE'' then ''DONE''\n'
    || E'        when v_semantic_eligibility=''REQUIRED'' then ''BLOCKED''\n'
    || E'        else ''PENDING'' end;\n'
    || E'      update programacion.input_family_assessments a set\n'
    || E'        curator_evidence=coalesce(a.curator_evidence,''{}''::jsonb) || jsonb_build_object(\n'
    || E'          ''semantic_plan'',jsonb_build_object(\n'
    || E'            ''contract'',''M5_4_SEMANTIC_PLAN_V1'',\n'
    || E'            ''family_registry'',jsonb_build_object(\n'
    || E'              ''contract_code'',''INPUT_FAMILY_POLICY_REGISTRY'',\n'
    || E'              ''registry_sha256'',v_semantic_registry_sha\n'
    || E'            ),\n'
    || E'            ''deterministic_resolver'',v_semantic_policy->''deterministic_resolver'',\n'
    || E'            ''semantic_resolvers'',v_semantic_policy->''semantic_resolvers'',\n'
    || E'            ''resolver_result'',v_semantic_probe,\n'
    || E'            ''eligibility'',v_semantic_eligibility,\n'
    || E'            ''execution_state'',v_semantic_execution_state,\n'
    || E'            ''stage_policy'',v_semantic_policy->''stage_policy'',\n'
    || E'            ''selector_binding'',jsonb_build_object(\n'
    || E'              ''capability_code'',''CAPABILITY_SELECTOR'',\n'
    || E'              ''version'',v_selector_version,\n'
    || E'              ''manifest_sha256'',v_selector_manifest_sha,\n'
    || E'              ''selection_only'',true,\n'
    || E'              ''fallback_capabilities'',jsonb_build_array(''FULL_SAFE_MIX_V1_CANDIDATE''),\n'
    || E'              ''runtime_selection_claim'',false\n'
    || E'            )\n'
    || E'          )\n'
    || E'        )\n'
    || E'      where a.id=v_core_assessment.id;\n'
    || E'      v_semantic_plan_count:=v_semantic_plan_count+1;\n'
    || E'      v_core_invocation_count:=v_core_invocation_count+1;\n'
  );

  v_def:=replace(
    v_def,
    E'        ''assessment_count'',v_core_invocation_count,\n        ''legacy_seed_removal_checkpoint'',''NEGATIVE_NO_CLASSIFY''\n',
    E'        ''assessment_count'',v_core_invocation_count,\n'
    || E'        ''semantic_plan_count'',v_semantic_plan_count,\n'
    || E'        ''semantic_plan_contract'',''M5_4_SEMANTIC_PLAN_V1'',\n'
    || E'        ''selector_binding'',jsonb_build_object(\n'
    || E'          ''capability_code'',''CAPABILITY_SELECTOR'',\n'
    || E'          ''version'',v_selector_version,\n'
    || E'          ''manifest_sha256'',v_selector_manifest_sha,\n'
    || E'          ''runtime_selection_claim'',false\n'
    || E'        ),\n'
    || E'        ''legacy_seed_removal_checkpoint'',''NEGATIVE_NO_CLASSIFY''\n'
  );

  execute v_def;
end;
$migration$;

comment on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)
is 'M5.4: deterministic Core bridge plus current family-policy semantic plan, explicit M3 eligibility/state, declared semantic resolver execution, stage policy composition, and CAPABILITY_SELECTOR selection-only binding.';

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_def;
  if position('M5_4_SEMANTIC_PLAN_V1' in v_def)=0
     or position('INPUT_FAMILY_POLICY_REGISTRY' in v_def)=0
     or position('fn_input_governance_semantic_probe_v3' in v_def)=0
     or position('CAPABILITY_SELECTOR' in v_def)=0
     or position('runtime_selection_claim' in v_def)=0 then
    raise exception 'M5_4_SEMANTIC_PLAN_VERIFY_FAILED';
  end if;
end;
$verify$;
