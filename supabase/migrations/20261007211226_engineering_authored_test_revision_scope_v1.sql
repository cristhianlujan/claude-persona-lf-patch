-- Scope authored-test repair/retest attempts by criterion revision when declared.
-- Historical failed runs remain immutable; a materially revised test contract gets a fresh attempt budget.

create or replace function programacion.fn_engineering_action_spec_apply_failed_authored_test_repair_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_spec jsonb
) returns jsonb
language plpgsql
stable
as $$
declare
  v_meta jsonb;
  v_targets jsonb;
  v_declared jsonb := coalesce(p_spec#>'{target,declared_objects}','[]'::jsonb);
  v_run_count integer := 0;
  v_latest_status text;
  v_latest_suite_run_id uuid;
  v_missing integer := 0;
  v_revision text := nullif(p_spec#>>'{test_execution_contract,criterion_revision}','');
begin
  if coalesce(p_spec->>'status','')<>'READY'
     or coalesce(p_spec->>'contract_family','')<>'BOUNDED_CHECKPOINT_TEST'
     or coalesce(p_spec->>'action_kind','')<>'BOUNDED_CHECKPOINT_TEST_AUTHORING' then
    return p_spec;
  end if;

  select count(*)::int,
         (array_agg(s.status order by s.created_at desc,s.suite_run_id desc))[1],
         (array_agg(s.suite_run_id order by s.created_at desc,s.suite_run_id desc))[1]
    into v_run_count,v_latest_status,v_latest_suite_run_id
  from public.lf_test_suite_runs s
  where s.metadata->>'plan_code'=p_plan_code
    and s.metadata->>'unit_code'=p_unit_code
    and s.metadata->>'checkpoint_code'=p_checkpoint_code
    and (
      v_revision is null
      or s.manifest->>'criterion_revision'=v_revision
    );

  if v_run_count=0 or v_latest_status is distinct from 'FAILED' then
    return p_spec;
  end if;

  if v_run_count>=2 then
    return p_spec || jsonb_build_object(
      'status','BLOCK_REPAIR_RETEST_EXHAUSTED',
      'repair_policy',jsonb_build_object(
        'mode','REPAIR_EXHAUSTED',
        'max_repairs',1,
        'criterion_revision',v_revision,
        'observed_run_count',v_run_count,
        'latest_suite_run_id',v_latest_suite_run_id,
        'latest_status',v_latest_status
      )
    );
  end if;

  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  v_targets:=v_meta#>array['runtime_repair_inputs_v1',p_checkpoint_code,'mutation_target','db_objects'];

  if coalesce(jsonb_typeof(v_targets),'')<>'array'
     or jsonb_array_length(v_targets)=0 then
    return p_spec || jsonb_build_object(
      'status','BLOCK_FAILED_TEST_REPAIR_TARGETS_REQUIRED',
      'repair_policy',jsonb_build_object(
        'mode','INPUT_REQUIRED_EXACT_TARGETS',
        'criterion_revision',v_revision,
        'required','unit_metadata.runtime_repair_inputs_v1.<checkpoint>.mutation_target.db_objects[]',
        'inference','FORBIDDEN',
        'latest_suite_run_id',v_latest_suite_run_id
      )
    );
  end if;

  select count(*)::int into v_missing
  from jsonb_array_elements_text(v_targets) t(target)
  where not (v_declared ? t.target);

  if v_missing>0 then
    return p_spec || jsonb_build_object(
      'status','BLOCK_FAILED_TEST_REPAIR_TARGET_OUT_OF_SCOPE',
      'repair_policy',jsonb_build_object(
        'mode','TARGET_SCOPE_REJECTED',
        'criterion_revision',v_revision,
        'mutation_targets',v_targets,
        'declared_objects',v_declared,
        'out_of_scope_count',v_missing,
        'inference','FORBIDDEN'
      )
    );
  end if;

  return p_spec || jsonb_build_object(
    'mutation_policy','ONLY_DECLARED_TARGETS',
    'repair_policy',jsonb_build_object(
      'mode','REPAIR_DECLARED_TARGET_THEN_RETEST',
      'trigger','DURABLE_FAILED_TEST',
      'criterion_revision',v_revision,
      'latest_suite_run_id',v_latest_suite_run_id,
      'mutation_scope','DECLARED_TARGETS_ONLY',
      'mutation_targets',v_targets,
      'repair_route',jsonb_build_array('WRITE_GIT','WRITE_DB'),
      'retest_capability','RUN_TEST',
      'retest_scope','SAME_CASE_SET',
      'max_repairs',1,
      'no_new_router_capability',true,
      'source_of_targets','EXPLICIT_RUNTIME_REPAIR_INPUT'
    ),
    'action_steps',coalesce(p_spec->'action_steps','[]'::jsonb)
      || jsonb_build_array(
        'REPAIR_DECLARED_TARGET',
        'APPLY_EXACT_MERGED_REPAIR',
        'RETEST_SAME_CASE_SET',
        'PERSIST_DONE_ONLY_ON_REAL_PASS'
      )
  );
end;
$$;

comment on function programacion.fn_engineering_action_spec_apply_failed_authored_test_repair_v1(text,text,text,jsonb)
is 'Generic authored-test failure overlay. Repair/retest attempts are scoped by test_execution_contract.criterion_revision when present, preserving immutable historical runs without stale exhaustion across materially revised test contracts.';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1,NEGATIVE_NO_CLASSIFY,test_execution_contract,criterion_revision}',
  to_jsonb('M5_4_AUTHORITY_ESCAPE_NEGATIVE_V3'::text),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M5.4'
  and disposition='ASSIGNED';
