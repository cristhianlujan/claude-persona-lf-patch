
create or replace function programacion.fn_engineering_run_test_persist_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_execution_id text,
  p_suite_code text,
  p_results jsonb,
  p_executor_name text default 'ENGINEERING_AGENT_RUN_TEST_V1'::text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_suite_run_id uuid;
  v_existing public.lf_test_suite_runs%rowtype;
  v_expected_count integer;
  v_result_count integer;
  v_distinct_count integer;
  v_passed integer;
  v_failed integer;
  v_blocked integer;
  v_review integer;
  v_suite_status text;
  v_case record;
  v_test_run_id uuid;
  v_actual_output jsonb;
  v_evidence jsonb;
  v_status text;
  v_assertion_code text;
  v_bundle jsonb;
begin
  if nullif(btrim(coalesce(p_plan_code,'')),'') is null
     or nullif(btrim(coalesce(p_unit_code,'')),'') is null
     or nullif(btrim(coalesce(p_checkpoint_code,'')),'') is null
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_suite_code,'')),'') is null then
    raise exception 'ENGINEERING_RUN_TEST_IDENTITY_INVALID';
  end if;
  if jsonb_typeof(p_results) is distinct from 'array' or jsonb_array_length(p_results)=0 then
    raise exception 'ENGINEERING_RUN_TEST_RESULTS_ARRAY_REQUIRED';
  end if;
  if jsonb_typeof(p_manifest) is distinct from 'object' then
    raise exception 'ENGINEERING_RUN_TEST_MANIFEST_OBJECT_REQUIRED';
  end if;
  if coalesce((p_manifest->>'actual_execution')::boolean,false) is not true
     or coalesce((p_manifest->>'synthetic_pass')::boolean,true) is not false then
    raise exception 'ENGINEERING_RUN_TEST_REAL_EXECUTION_ATTESTATION_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('engineering-run-test:'||p_execution_id,0));

  select * into v_existing
  from public.lf_test_suite_runs
  where execution_id=p_execution_id
    and suite_code=p_suite_code
    and metadata->>'plan_code'=p_plan_code
    and metadata->>'unit_code'=p_unit_code
    and metadata->>'checkpoint_code'=p_checkpoint_code
  order by created_at desc
  limit 1;
  if found then
    v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_existing.suite_run_id);
    return jsonb_build_object(
      'schema_version','ENGINEERING_RUN_TEST_PERSIST_V1_1',
      'result','REPLAY_EXISTING_SUITE_RUN',
      'suite_run_id',v_existing.suite_run_id,
      'status',v_existing.status,
      'tests_total',v_existing.tests_total,
      'tests_passed',v_existing.tests_passed,
      'tests_failed',v_existing.tests_failed,
      'tests_blocked',v_existing.tests_blocked,
      'tests_review_required',v_existing.tests_review_required,
      'receipt_bundle_status',v_bundle->>'status',
      'failure_evidence_persisted',v_existing.status<>'PASSED',
      'checkpoint_closure_eligible',
        v_existing.status='PASSED' and v_bundle->>'status'='VERIFIED',
      'receipt_bundle',v_bundle
    );
  end if;

  select count(*)::int into v_expected_count
  from public.lf_test_suite_cases c
  where c.suite_code=p_suite_code
    and c.metadata->>'unit_code'=p_unit_code
    and c.metadata->>'checkpoint_code'=p_checkpoint_code;
  if v_expected_count=0 then
    raise exception 'ENGINEERING_RUN_TEST_NO_CANONICAL_CASES';
  end if;

  select count(*)::int,count(distinct x->>'test_code')::int
    into v_result_count,v_distinct_count
  from jsonb_array_elements(p_results) x;
  if v_result_count<>v_expected_count or v_distinct_count<>v_expected_count then
    raise exception 'ENGINEERING_RUN_TEST_CASE_CARDINALITY_MISMATCH:expected=% result=% distinct=%',v_expected_count,v_result_count,v_distinct_count;
  end if;

  if exists (
    select 1
    from public.lf_test_suite_cases c
    where c.suite_code=p_suite_code
      and c.metadata->>'unit_code'=p_unit_code
      and c.metadata->>'checkpoint_code'=p_checkpoint_code
      and not exists (
        select 1 from jsonb_array_elements(p_results) x where x->>'test_code'=c.test_code
      )
  ) or exists (
    select 1
    from jsonb_array_elements(p_results) x
    where not exists (
      select 1 from public.lf_test_suite_cases c
      where c.suite_code=p_suite_code
        and c.metadata->>'unit_code'=p_unit_code
        and c.metadata->>'checkpoint_code'=p_checkpoint_code
        and c.test_code=x->>'test_code'
    )
  ) then
    raise exception 'ENGINEERING_RUN_TEST_CASE_SET_MISMATCH';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_results) x
    where coalesce(x->>'status','') not in ('PASS','FAIL','BLOCKED','REVIEW_REQUIRED')
       or jsonb_typeof(coalesce(x->'evidence_payload','null'::jsonb)) is distinct from 'object'
       or coalesce(x->'evidence_payload','{}'::jsonb)='{}'::jsonb
  ) then
    raise exception 'ENGINEERING_RUN_TEST_RESULT_SHAPE_INVALID';
  end if;

  select
    count(*) filter (where x->>'status'='PASS')::int,
    count(*) filter (where x->>'status'='FAIL')::int,
    count(*) filter (where x->>'status'='BLOCKED')::int,
    count(*) filter (where x->>'status'='REVIEW_REQUIRED')::int
  into v_passed,v_failed,v_blocked,v_review
  from jsonb_array_elements(p_results) x;

  v_suite_status:=case
    when v_failed>0 then 'FAILED'
    when v_blocked>0 then 'BLOCKED'
    when v_review>0 then 'REVIEW_REQUIRED'
    else 'PASSED'
  end;

  insert into public.lf_test_suite_runs(
    suite_code,execution_id,environment,application_version,executor_type,executor_name,status,
    started_at,completed_at,duration_ms,tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,
    manifest,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    p_suite_code,p_execution_id,'sandbox',p_unit_code,'RUN_TEST',p_executor_name,v_suite_status,
    clock_timestamp(),clock_timestamp(),0,v_result_count,v_passed,v_failed,v_blocked,v_review,
    p_manifest || jsonb_build_object('actual_execution',true,'synthetic_pass',false),
    jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
    p_execution_id,p_execution_id
  ) returning suite_run_id into v_suite_run_id;

  for v_case in
    select c.*,x.result
    from public.lf_test_suite_cases c
    join lateral (
      select e result from jsonb_array_elements(p_results) e where e->>'test_code'=c.test_code
    ) x on true
    where c.suite_code=p_suite_code
      and c.metadata->>'unit_code'=p_unit_code
      and c.metadata->>'checkpoint_code'=p_checkpoint_code
    order by c.test_order
  loop
    v_status:=v_case.result->>'status';
    v_actual_output:=coalesce(v_case.result->'actual_output','{}'::jsonb);
    v_evidence:=v_case.result->'evidence_payload';
    v_assertion_code:=coalesce(nullif(btrim(v_case.result->>'assertion_code'),''),v_case.test_code||'_ASSERT');

    insert into public.lf_test_runs(
      suite_run_id,suite_code,test_code,execution_id,rule_codes,story_code,environment,application_version,
      executor_type,executor_name,attempt_no,status,input_payload,expected_output,actual_output,severity,
      started_at,completed_at,duration_ms,evidence_payload,metadata,created_by_execution_id,updated_by_execution_id
    ) values (
      v_suite_run_id,p_suite_code,v_case.test_code,p_execution_id,v_case.rule_codes,v_case.story_code,'sandbox',p_unit_code,
      'RUN_TEST',p_executor_name,1,v_status,v_case.input_payload,v_case.expected_output,v_actual_output,v_case.severity,
      clock_timestamp(),clock_timestamp(),0,v_evidence,
      jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
      p_execution_id,p_execution_id
    ) returning test_run_id into v_test_run_id;

    insert into public.lf_test_assertion_results(
      test_run_id,assertion_code,assertion_order,assertion_type,description,expected_value,actual_value,operator,
      status,severity,failure_reason,evidence_payload,metadata,created_by_execution_id,updated_by_execution_id
    ) values (
      v_test_run_id,v_assertion_code,1,'EXPECTED_OUTPUT',v_case.title,v_case.expected_output,v_actual_output,'OBSERVED',
      v_status,v_case.severity,case when v_status='PASS' then null else coalesce(v_case.result->>'failure_reason',v_status) end,
      v_evidence,jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
      p_execution_id,p_execution_id
    );
  end loop;

  v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite_run_id);

  if v_suite_status='PASSED'
     and v_bundle->>'status' is distinct from 'VERIFIED' then
    raise exception 'ENGINEERING_RUN_TEST_PASS_RECEIPT_BUNDLE_NOT_VERIFIED:%',v_bundle;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_RUN_TEST_PERSIST_V1_1',
    'result','PERSISTED_NEW_SUITE_RUN',
    'suite_run_id',v_suite_run_id,
    'status',v_suite_status,
    'tests_total',v_result_count,
    'tests_passed',v_passed,
    'tests_failed',v_failed,
    'tests_blocked',v_blocked,
    'tests_review_required',v_review,
    'evidence_ref','supabase://public.lf_test_suite_runs/'||v_suite_run_id,
    'receipt_bundle_status',v_bundle->>'status',
    'failure_evidence_persisted',v_suite_status<>'PASSED',
    'checkpoint_closure_eligible',
      v_suite_status='PASSED' and v_bundle->>'status'='VERIFIED',
    'receipt_bundle',v_bundle
  );
end;
$function$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-RUN-TEST-FAILURE-EVIDENCE-PERSIST-001',
  'ENGINEERING_ORCHESTRATION',
  'Failed RUN_TEST results must persist instead of rolling back their evidence',
  'RUN_TEST persistence now stores FAILED/BLOCKED/REVIEW_REQUIRED suite graphs as durable evidence. VERIFIED receipt remains mandatory only for PASSED suites and checkpoint closure.',
  'The persistence procedure required receipt_bundle=VERIFIED for every suite status, but receipt verification itself requires an all-pass suite, making failed test evidence impossible to persist.',
  'FAILED_SUITE -> RECEIPT_INCOMPLETE -> RAISE -> EVIDENCE_ROLLBACK',
  'Persist real non-passing suite/test/assertion evidence. Require VERIFIED only when suite_status=PASSED. Never allow non-passing evidence to authorize checkpoint DONE.',
  'PASS when a real FAILED suite is durably stored with failure_evidence_persisted=true and checkpoint_closure_eligible=false; PASSED suites still fail closed unless receipt_bundle=VERIFIED.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_run_test_persist_v1',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'RUN_TEST failed-suite persistence',
  'supabase://programacion.fn_engineering_run_test_persist_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
