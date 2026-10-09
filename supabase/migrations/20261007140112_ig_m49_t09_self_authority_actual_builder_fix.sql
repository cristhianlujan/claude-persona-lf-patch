
do $patch$
declare
  v_def text;
  v_new text;
  v_old_injection constant text := $old$
      v_injection:=
        'if p_family_code=''ACCESSIBILITY'' then '||
        'v_assertion:=jsonb_build_object('||
          '''assertion_class'',''SOURCE_INTEGRITY'','||
          '''source_ref'',jsonb_build_object(''kind'',''CONTRACT'',''codigo'',''INPUT_READINESS_CONTRACT''),'||
          '''path'',jsonb_build_array(''observed'',''especificacion'',''contract_revision''),'||
          '''actual'',to_jsonb(''5.13''::text),'||
          '''expected'',to_jsonb(''5.13''::text),'||
          '''operator'',''EQ''); '||
        'end if; ';
$old$;
  v_new_injection constant text := $new$
      v_injection:=
        'if p_family_code=''ACCESSIBILITY'' then '||
        'v_rebound:=programacion.fn_input_rebind_assertion('||
          'p_new_run_id,p_family_code,jsonb_build_object('||
          '''assertion_class'',''SOURCE_INTEGRITY'','||
          '''source_ref'',jsonb_build_object(''kind'',''CONTRACT'',''codigo'',''INPUT_READINESS_CONTRACT''),'||
          '''path'',jsonb_build_array(''observed'',''especificacion'',''contract_revision''),'||
          '''actual'',to_jsonb(''5.13''::text),'||
          '''expected'',to_jsonb(''5.13''::text),'||
          '''operator'',''EQ'')); '||
        'end if; ';
$new$;
begin
  v_def:=pg_get_functiondef('programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)'::regprocedure);

  if md5(v_def) <> 'd6b69fab79a34fdbf5551f975ff6b51d' then
    raise exception 'M49_T09_RUNNER_PREIMAGE_DRIFT expected=% actual=%',
      'd6b69fab79a34fdbf5551f975ff6b51d',md5(v_def);
  end if;

  if position(v_old_injection in v_def)=0 then
    raise exception 'M49_T09_OLD_INJECTION_FRAGMENT_MISSING';
  end if;

  v_new:=replace(
    v_def,
    'v_assert_sig regprocedure:=''programacion.fn_input_governance_bootstrap_assertions_v1(bigint,text)''::regprocedure;',
    'v_assert_sig regprocedure:=''programacion.fn_input_v58_build_assertions(bigint,bigint,text)''::regprocedure;'
  );
  v_new:=replace(
    v_new,
    'v_assert_anchor text:=''v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_assertion);'';',
    'v_assert_anchor text:=''  for v_old in'';'
  );
  v_new:=replace(v_new,v_old_injection,v_new_injection);

  if v_new=v_def
     or position('fn_input_v58_build_assertions(bigint,bigint,text)' in v_new)=0
     or position('v_rebound:=programacion.fn_input_rebind_assertion(' in v_new)=0
     or position('v_assert_anchor text:=''  for v_old in'';' in v_new)=0 then
    raise exception 'M49_T09_RUNNER_PATCH_CONSTRUCTION_FAILED';
  end if;

  execute v_new;
end;
$patch$;

do $verify$
declare
  v_def text;
begin
  v_def:=pg_get_functiondef('programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)'::regprocedure);

  if position('fn_input_governance_bootstrap_assertions_v1(bigint,text)' in v_def)>0 then
    raise exception 'M49_T09_STALE_BOOTSTRAP_BUILDER_REFERENCE';
  end if;
  if position('fn_input_v58_build_assertions(bigint,bigint,text)' in v_def)=0 then
    raise exception 'M49_T09_V58_BUILDER_REFERENCE_MISSING';
  end if;
  if position('v_rebound:=programacion.fn_input_rebind_assertion(' in v_def)=0 then
    raise exception 'M49_T09_RELEVANCE_INJECTION_MISSING';
  end if;
end;
$verify$;
