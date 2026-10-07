-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.4 / CORE_INVOCATION
-- Wire the M2.8 deterministic facade at the Curator authority boundary.
-- Legacy classify/probe calls remain transitional seeds until NEGATIVE_NO_CLASSIFY.

do $preflight$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_def;

  if position('M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1' in v_def)>0 then
    raise exception 'M5_4_CORE_INVOCATION_ALREADY_APPLIED';
  end if;

  if position('v_graph_build_count integer;' in v_def)=0
     or position('v_graph_build_count:=coalesce' in v_def)=0
     or position('request_context_summary' in v_def)=0 then
    raise exception 'M5_4_CORE_INVOCATION_ANCHOR_DRIFT';
  end if;

  if to_regprocedure('programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)') is null then
    raise exception 'M5_4_DETERMINISTIC_ASSESS_MISSING';
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
    E'  v_result jsonb;\n  v_graph_build_count integer;\n',
    E'  v_result jsonb;\n'
    || E'  v_graph_build_count integer;\n'
    || E'  v_core_contract jsonb;\n'
    || E'  v_core_run_id bigint;\n'
    || E'  v_core_assessment record;\n'
    || E'  v_core_result jsonb;\n'
    || E'  v_core_invocation_count integer:=0;\n'
  );

  v_def:=replace(
    v_def,
    E'  v_graph_build_count:=coalesce(nullif(current_setting(''lf.input_request_graph_build_count_v1'',true),'''')::integer,0);\n',
    E'  v_core_run_id:=nullif(v_result->>''run_id'','''')::bigint;\n'
    || E'  if v_core_run_id is not null then\n'
    || E'    select c.especificacion into v_core_contract\n'
    || E'    from programacion.contratos c\n'
    || E'    where c.version_id=v_version\n'
    || E'      and c.contrato_codigo=''INPUT_READINESS_CONTRACT''\n'
    || E'      and c.estado=''defined''\n'
    || E'      and c.fail_closed\n'
    || E'    order by c.id desc limit 1;\n'
    || E'    if v_core_contract is null then\n'
    || E'      raise exception ''M5_4_INPUT_READINESS_CONTRACT_UNRESOLVED:%'',v_version;\n'
    || E'    end if;\n'
    || E'    for v_core_assessment in\n'
    || E'      select * from programacion.input_family_assessments\n'
    || E'      where run_id=v_core_run_id order by family_code\n'
    || E'    loop\n'
    || E'      v_core_result:=programacion.fn_input_deterministic_assess(\n'
    || E'        (to_jsonb(v_core_assessment)-''id''-''run_id''-''family_code'')\n'
    || E'          || jsonb_build_object(\n'
    || E'               ''pantalla_id'',p_pantalla_id,\n'
    || E'               ''version_id'',v_version,\n'
    || E'               ''source_class'',''DETERMINISTIC''\n'
    || E'             ),\n'
    || E'        v_core_assessment.family_code,\n'
    || E'        v_graph,\n'
    || E'        v_core_contract\n'
    || E'      );\n'
    || E'      update programacion.input_family_assessments a set\n'
    || E'        severity=coalesce(v_core_result#>>''{assessment,severity}'',a.severity),\n'
    || E'        applicability=coalesce(v_core_result#>>''{assessment,applicability}'',a.applicability),\n'
    || E'        coverage_status=coalesce(v_core_result#>>''{assessment,coverage_status}'',a.coverage_status),\n'
    || E'        well_defined_status=coalesce(v_core_result#>>''{assessment,well_defined_status}'',a.well_defined_status),\n'
    || E'        story_ready_status=coalesce(v_core_result#>>''{assessment,story_ready_status}'',a.story_ready_status),\n'
    || E'        implementation_ready_status=coalesce(v_core_result#>>''{assessment,implementation_ready_status}'',a.implementation_ready_status),\n'
    || E'        qa_ready_status=coalesce(v_core_result#>>''{assessment,qa_ready_status}'',a.qa_ready_status),\n'
    || E'        production_ready_status=coalesce(v_core_result#>>''{assessment,production_ready_status}'',a.production_ready_status),\n'
    || E'        blockers=coalesce(v_core_result#>''{assessment,blockers}'',a.blockers),\n'
    || E'        curator_evidence=coalesce(a.curator_evidence,''{}''::jsonb) || jsonb_build_object(\n'
    || E'          ''core_invocation'',jsonb_build_object(\n'
    || E'            ''contract'',''M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1'',\n'
    || E'            ''facade'',''programacion.fn_input_deterministic_assess'',\n'
    || E'            ''result_sha256'',v_core_result->>''result_sha256'',\n'
    || E'            ''contract_sha256'',v_core_result->>''contract_sha256'',\n'
    || E'            ''legacy_seed_removal_checkpoint'',''NEGATIVE_NO_CLASSIFY''\n'
    || E'          )\n'
    || E'        )\n'
    || E'      where a.id=v_core_assessment.id;\n'
    || E'      v_core_invocation_count:=v_core_invocation_count+1;\n'
    || E'    end loop;\n'
    || E'    if v_core_invocation_count=0 then\n'
    || E'      raise exception ''M5_4_DETERMINISTIC_ASSESS_NO_ASSESSMENTS:%'',v_core_run_id;\n'
    || E'    end if;\n'
    || E'    v_result:=v_result || jsonb_build_object(\n'
    || E'      ''core_invocation'',jsonb_build_object(\n'
    || E'        ''contract'',''M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1'',\n'
    || E'        ''facade'',''programacion.fn_input_deterministic_assess'',\n'
    || E'        ''assessment_count'',v_core_invocation_count,\n'
    || E'        ''legacy_seed_removal_checkpoint'',''NEGATIVE_NO_CLASSIFY''\n'
    || E'      )\n'
    || E'    );\n'
    || E'  end if;\n'
    || E'  v_graph_build_count:=coalesce(nullif(current_setting(''lf.input_request_graph_build_count_v1'',true),'''')::integer,0);\n'
  );

  execute v_def;
end;
$migration$;

comment on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)
is 'M5.4 CORE_INVOCATION: Curator normalizes materialized family readiness through M2.8 fn_input_deterministic_assess; legacy classifier/probe seeds are transitional until NEGATIVE_NO_CLASSIFY.';

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  ) into v_def;

  if position('M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1' in v_def)=0
     or position('fn_input_deterministic_assess' in v_def)=0
     or position('legacy_seed_removal_checkpoint' in v_def)=0 then
    raise exception 'M5_4_CORE_INVOCATION_VERIFY_FAILED';
  end if;
end;
$verify$;
