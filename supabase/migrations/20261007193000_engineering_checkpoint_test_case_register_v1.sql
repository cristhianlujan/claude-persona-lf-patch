-- Generic registration for checkpoint-owned authored tests.
create or replace function programacion.fn_engineering_checkpoint_test_case_register_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_test_code text,
  p_title text,
  p_test_type text,
  p_source_path text,
  p_input_payload jsonb,
  p_expected_output jsonb,
  p_prohibited_output jsonb,
  p_actor text
) returns jsonb
language plpgsql
as $$
declare
  v_suite_code text;
  v_suite_count integer;
  v_work_code text;
  v_existing public.lf_test_suite_cases%rowtype;
  v_test_order integer;
begin
  if nullif(btrim(coalesce(p_plan_code,'')),'') is null
     or nullif(btrim(coalesce(p_unit_code,'')),'') is null
     or nullif(btrim(coalesce(p_checkpoint_code,'')),'') is null
     or nullif(btrim(coalesce(p_test_code,'')),'') is null
     or nullif(btrim(coalesce(p_title,'')),'') is null
     or nullif(btrim(coalesce(p_source_path,'')),'') is null
     or nullif(btrim(coalesce(p_actor,'')),'') is null then
    raise exception 'ENGINEERING_CHECKPOINT_TEST_CASE_IDENTITY_INVALID';
  end if;
  if upper(coalesce(p_test_type,'')) not in ('NEGATIVE','POSITIVE','REGRESSION','METAMORPHIC','PROPERTY','INTEGRATION') then
    raise exception 'ENGINEERING_CHECKPOINT_TEST_CASE_TYPE_INVALID:%',p_test_type;
  end if;
  if jsonb_typeof(coalesce(p_input_payload,'null'::jsonb)) is distinct from 'object'
     or jsonb_typeof(coalesce(p_expected_output,'null'::jsonb)) is distinct from 'object'
     or jsonb_typeof(coalesce(p_prohibited_output,'null'::jsonb)) is distinct from 'object' then
    raise exception 'ENGINEERING_CHECKPOINT_TEST_CASE_PAYLOAD_SHAPE_INVALID';
  end if;

  select wi.work_code into v_work_code
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items wi on wi.id=pu.work_item_id
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code
  limit 1;
  if v_work_code is null then
    raise exception 'ENGINEERING_CHECKPOINT_TEST_CASE_UNIT_NOT_FOUND:%:%',p_plan_code,p_unit_code;
  end if;

  select count(*),min(s.suite_code)
    into v_suite_count,v_suite_code
  from public.lf_test_suites s
  where s.metadata->>'plan_id'=p_plan_code
    and s.status in ('CANDIDATO','ACTIVE','ACTIVO');
  if v_suite_count<>1 or v_suite_code is null then
    raise exception 'ENGINEERING_CHECKPOINT_TEST_SUITE_RESOLUTION_INVALID:plan=% count=%',p_plan_code,v_suite_count;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('engineering-checkpoint-test-case:'||v_suite_code,0));

  select * into v_existing
  from public.lf_test_suite_cases
  where test_code=p_test_code
  order by updated_at desc
  limit 1;
  if found then
    if v_existing.suite_code<>v_suite_code
       or v_existing.metadata->>'unit_code' is distinct from p_unit_code
       or v_existing.metadata->>'checkpoint_code' is distinct from p_checkpoint_code then
      raise exception 'ENGINEERING_CHECKPOINT_TEST_CASE_OWNERSHIP_CONFLICT:%',p_test_code;
    end if;
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_TEST_CASE_REGISTER_V1',
      'status','ALREADY_REGISTERED',
      'suite_code',v_existing.suite_code,
      'test_code',v_existing.test_code,
      'test_order',v_existing.test_order
    );
  end if;

  select coalesce(max(c.test_order),0)+1 into v_test_order
  from public.lf_test_suite_cases c
  where c.suite_code=v_suite_code;

  insert into public.lf_test_suite_cases(
    suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
    preconditions,input_payload,expected_output,prohibited_output,status,metadata,
    created_by_execution_id,updated_by_execution_id
  ) values (
    v_suite_code,p_test_code,v_test_order,null,array[]::text[],p_title,upper(p_test_type),'AUTOMATED','HIGH',
    '[]'::jsonb,p_input_payload,p_expected_output,p_prohibited_output,'CANDIDATO',
    jsonb_build_object(
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'work_code',v_work_code,
      'checkpoint_code',p_checkpoint_code,
      'source_path',p_source_path,
      'ownership','CHECKPOINT_OWNED',
      'registration_contract','ENGINEERING_CHECKPOINT_TEST_CASE_REGISTER_V1'
    ),
    p_actor,p_actor
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_CHECKPOINT_TEST_CASE_REGISTER_V1',
    'status','REGISTERED',
    'suite_code',v_suite_code,
    'test_code',p_test_code,
    'test_order',v_test_order,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code
  );
end;
$$;

comment on function programacion.fn_engineering_checkpoint_test_case_register_v1(
  text,text,text,text,text,text,text,jsonb,jsonb,jsonb,text
) is 'Generic idempotent registrar for checkpoint-owned authored tests. Resolves exactly one canonical suite by lf_test_suites.metadata.plan_id; never transfers ownership across units.';
