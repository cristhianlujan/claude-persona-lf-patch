-- Strategy 27 / P9 source-first governed normalized test result writer.
-- Durable apply is intentionally separate from source review/qualification.

do $preflight$
begin
  if to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is null then
    raise exception 'LF_TEST_RESULT_WRITER_HASH_DEPENDENCY_MISSING';
  end if;
  if to_regclass('public.lf_test_suite_runs') is null
     or to_regclass('public.lf_test_suite_cases') is null
     or to_regclass('public.lf_test_runs') is null
     or to_regclass('public.lf_test_assertion_results') is null
     or to_regclass('public.lf_test_judge_results') is null
     or to_regclass('public.lf_test_artifacts') is null then
    raise exception 'LF_TEST_RESULT_WRITER_STORE_DEPENDENCY_MISSING';
  end if;
end;
$preflight$;

create or replace function public.lf_test_result_writer_v1(
  p_receipt jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_suite_run_id uuid;
  v_suite_code text;
  v_test_code text;
  v_attempt_no integer;
  v_execution_id text;
  v_environment text;
  v_code_head_sha text;
  v_source_sha256 text;
  v_configuration_sha256 text;
  v_receipt_sha256 text;
  v_computed_sha256 text;
  v_evidence_origin text;
  v_executor_type text;
  v_executor_name text;
  v_status text;
  v_exit_code integer;
  v_started_at timestamptz;
  v_completed_at timestamptz;
  v_duration_ms bigint;
  v_timing_source text;
  v_assertions jsonb;
  v_judges jsonb;
  v_artifacts jsonb;
  v_assertions_applicable boolean;
  v_judges_applicable boolean;
  v_artifacts_applicable boolean;
  v_existing_count integer;
  v_existing_id uuid;
  v_existing_sha text;
  v_test_run_id uuid;
  v_item jsonb;
  v_suite public.lf_test_suite_runs%rowtype;
  v_lock_key text;
begin
  if p_receipt is null or jsonb_typeof(p_receipt) <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','RECEIPT_INVALID');
  end if;
  if p_actor_execution_id is null or btrim(p_actor_execution_id) = '' then
    return jsonb_build_object('outcome','BLOCKED','code','ACTOR_EXECUTION_ID_MISSING');
  end if;
  if p_receipt->>'schema_version' <> 'lf-test-result-writer/v1' then
    return jsonb_build_object('outcome','BLOCKED','code','RECEIPT_SCHEMA_VERSION_INVALID');
  end if;
  if p_receipt->'executed' is distinct from 'true'::jsonb then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTED_PROOF_REQUIRED');
  end if;

  v_receipt_sha256 := lower(coalesce(p_receipt->>'receipt_sha256',''));
  if v_receipt_sha256 !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('outcome','BLOCKED','code','RECEIPT_SHA256_INVALID');
  end if;
  v_computed_sha256 := private.fn_payload_sha256_v7(p_receipt - 'receipt_sha256');
  if v_computed_sha256 is distinct from v_receipt_sha256 then
    return jsonb_build_object(
      'outcome','BLOCKED','code','RECEIPT_SHA256_MISMATCH',
      'provided_sha256',v_receipt_sha256,'computed_sha256',v_computed_sha256
    );
  end if;

  if coalesce(p_receipt->>'suite_run_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_RUN_ID_INVALID');
  end if;
  v_suite_run_id := (p_receipt->>'suite_run_id')::uuid;
  v_suite_code := btrim(coalesce(p_receipt->>'suite_code',''));
  v_test_code := btrim(coalesce(p_receipt->>'test_code',''));
  v_execution_id := btrim(coalesce(p_receipt->>'execution_id',''));
  v_environment := btrim(coalesce(p_receipt->>'environment',''));
  if v_suite_code = '' or v_test_code = '' or v_execution_id = '' or v_environment = '' then
    return jsonb_build_object('outcome','BLOCKED','code','TEST_IDENTITY_INCOMPLETE');
  end if;

  if jsonb_typeof(p_receipt->'attempt_no') <> 'number'
     or coalesce(p_receipt->>'attempt_no','') !~ '^[1-9][0-9]*$' then
    return jsonb_build_object('outcome','BLOCKED','code','ATTEMPT_NO_INVALID');
  end if;
  v_attempt_no := (p_receipt->>'attempt_no')::integer;

  v_code_head_sha := lower(coalesce(p_receipt->>'code_head_sha',''));
  v_source_sha256 := lower(coalesce(p_receipt->>'source_sha256',''));
  v_configuration_sha256 := lower(coalesce(p_receipt->>'configuration_sha256',''));
  if v_code_head_sha !~ '^[0-9a-f]{40}$' then
    return jsonb_build_object('outcome','BLOCKED','code','CODE_HEAD_SHA_INVALID');
  end if;
  if v_source_sha256 !~ '^[0-9a-f]{64}$' or v_configuration_sha256 !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('outcome','BLOCKED','code','SOURCE_OR_CONFIGURATION_SHA_INVALID');
  end if;

  v_evidence_origin := btrim(coalesce(p_receipt->>'evidence_origin',''));
  if v_evidence_origin not in ('LIVE_EXECUTOR_RECEIPT','DIRECT_EXECUTOR_REPLAY') then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_ORIGIN_INVALID');
  end if;

  if jsonb_typeof(p_receipt->'executor') <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTOR_INVALID');
  end if;
  v_executor_type := btrim(coalesce(p_receipt#>>'{executor,type}',''));
  v_executor_name := btrim(coalesce(p_receipt#>>'{executor,name}',''));
  if v_executor_type = '' or v_executor_name = '' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTOR_IDENTITY_MISSING');
  end if;

  if jsonb_typeof(p_receipt->'outcome') <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','OUTCOME_INVALID');
  end if;
  v_status := btrim(coalesce(p_receipt#>>'{outcome,status}',''));
  if v_status not in ('PASSED','FAILED','BLOCKED','REVIEW_REQUIRED') then
    return jsonb_build_object('outcome','BLOCKED','code','STATUS_INVALID');
  end if;
  if jsonb_typeof(p_receipt->'exit_code') <> 'number'
     or coalesce(p_receipt->>'exit_code','') !~ '^[0-2]$' then
    return jsonb_build_object('outcome','BLOCKED','code','EXIT_CODE_INVALID');
  end if;
  v_exit_code := (p_receipt->>'exit_code')::integer;
  if (v_status = 'PASSED' and v_exit_code <> 0)
     or (v_status in ('FAILED','REVIEW_REQUIRED') and v_exit_code <> 1)
     or (v_status = 'BLOCKED' and v_exit_code <> 2) then
    return jsonb_build_object('outcome','BLOCKED','code','STATUS_EXIT_CODE_MISMATCH');
  end if;

  if jsonb_typeof(p_receipt->'timing') <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','TIMING_INVALID');
  end if;
  begin
    v_started_at := (p_receipt#>>'{timing,started_at}')::timestamptz;
    v_completed_at := (p_receipt#>>'{timing,completed_at}')::timestamptz;
  exception when others then
    return jsonb_build_object('outcome','BLOCKED','code','TIMESTAMP_INVALID');
  end;
  if v_started_at is null or v_completed_at is null or v_completed_at < v_started_at then
    return jsonb_build_object('outcome','BLOCKED','code','TIMING_INTERVAL_INVALID');
  end if;
  if jsonb_typeof(p_receipt#>'{timing,duration_ms}') <> 'number'
     or coalesce(p_receipt#>>'{timing,duration_ms}','') !~ '^[0-9]+$' then
    return jsonb_build_object('outcome','BLOCKED','code','DURATION_MS_INVALID');
  end if;
  v_duration_ms := (p_receipt#>>'{timing,duration_ms}')::bigint;
  v_timing_source := btrim(coalesce(p_receipt#>>'{timing,measurement_source}',''));
  if v_timing_source <> 'MONOTONIC_PRODUCER' then
    return jsonb_build_object('outcome','BLOCKED','code','TIMING_SOURCE_INVALID');
  end if;

  if jsonb_typeof(p_receipt->'channels') <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','CHANNELS_INVALID');
  end if;

  if jsonb_typeof(p_receipt#>'{channels,assertions}') <> 'object'
     or jsonb_typeof(p_receipt#>'{channels,judges}') <> 'object'
     or jsonb_typeof(p_receipt#>'{channels,artifacts}') <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','CHANNEL_DECLARATION_INVALID');
  end if;

  if jsonb_typeof(p_receipt#>'{channels,assertions,applicable}') <> 'boolean'
     or jsonb_typeof(p_receipt#>'{channels,judges,applicable}') <> 'boolean'
     or jsonb_typeof(p_receipt#>'{channels,artifacts,applicable}') <> 'boolean' then
    return jsonb_build_object('outcome','BLOCKED','code','CHANNEL_APPLICABILITY_INVALID');
  end if;
  if jsonb_typeof(p_receipt#>'{channels,assertions,items}') <> 'array'
     or jsonb_typeof(p_receipt#>'{channels,judges,items}') <> 'array'
     or jsonb_typeof(p_receipt#>'{channels,artifacts,items}') <> 'array' then
    return jsonb_build_object('outcome','BLOCKED','code','CHANNEL_ITEMS_INVALID');
  end if;

  v_assertions_applicable := (p_receipt#>>'{channels,assertions,applicable}')::boolean;
  v_judges_applicable := (p_receipt#>>'{channels,judges,applicable}')::boolean;
  v_artifacts_applicable := (p_receipt#>>'{channels,artifacts,applicable}')::boolean;
  v_assertions := p_receipt#>'{channels,assertions,items}';
  v_judges := p_receipt#>'{channels,judges,items}';
  v_artifacts := p_receipt#>'{channels,artifacts,items}';

  if (v_assertions_applicable and jsonb_array_length(v_assertions)=0)
     or (not v_assertions_applicable and jsonb_array_length(v_assertions)>0)
     or (v_judges_applicable and jsonb_array_length(v_judges)=0)
     or (not v_judges_applicable and jsonb_array_length(v_judges)>0)
     or (v_artifacts_applicable and jsonb_array_length(v_artifacts)=0)
     or (not v_artifacts_applicable and jsonb_array_length(v_artifacts)>0) then
    return jsonb_build_object('outcome','BLOCKED','code','CHANNEL_APPLICABILITY_CONFLICT');
  end if;
  if (not v_assertions_applicable and length(btrim(coalesce(p_receipt#>>'{channels,assertions,reason}',''))) < 3)
     or (not v_judges_applicable and length(btrim(coalesce(p_receipt#>>'{channels,judges,reason}',''))) < 3)
     or (not v_artifacts_applicable and length(btrim(coalesce(p_receipt#>>'{channels,artifacts,reason}',''))) < 3) then
    return jsonb_build_object('outcome','BLOCKED','code','CHANNEL_NA_REASON_REQUIRED');
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_assertions) x
    where jsonb_typeof(x) <> 'object'
       or btrim(coalesce(x->>'assertion_code','')) = ''
       or btrim(coalesce(x->>'assertion_type','')) = ''
       or btrim(coalesce(x->>'description','')) = ''
       or jsonb_typeof(x->'assertion_order') <> 'number'
       or coalesce(x->>'assertion_order','') !~ '^[1-9][0-9]*$'
       or coalesce(x->>'status','') not in ('PASS','FAIL')
  ) then
    return jsonb_build_object('outcome','BLOCKED','code','ASSERTION_ITEM_INVALID');
  end if;
  if (select count(*) from jsonb_array_elements(v_assertions))
     <> (select count(distinct x->>'assertion_code') from jsonb_array_elements(v_assertions) x)
     or (select count(*) from jsonb_array_elements(v_assertions))
     <> (select count(distinct x->>'assertion_order') from jsonb_array_elements(v_assertions) x) then
    return jsonb_build_object('outcome','BLOCKED','code','ASSERTION_IDENTITY_DUPLICATE');
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_judges) x
    where jsonb_typeof(x) <> 'object'
       or btrim(coalesce(x->>'judge_code','')) = ''
       or btrim(coalesce(x->>'judge_type','')) = ''
       or btrim(coalesce(x->>'executor_identity','')) = ''
       or btrim(coalesce(x->>'judge_version','')) = ''
       or coalesce(x->>'verdict','') not in ('PASS','FAIL','REVIEW')
       or jsonb_typeof(coalesce(x->'findings','[]'::jsonb)) <> 'array'
  ) then
    return jsonb_build_object('outcome','BLOCKED','code','JUDGE_PROVENANCE_INVALID');
  end if;
  if (select count(*) from jsonb_array_elements(v_judges))
     <> (select count(distinct x->>'judge_code') from jsonb_array_elements(v_judges) x) then
    return jsonb_build_object('outcome','BLOCKED','code','JUDGE_IDENTITY_DUPLICATE');
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_artifacts) x
    where jsonb_typeof(x) <> 'object'
       or btrim(coalesce(x->>'artifact_type','')) = ''
       or btrim(coalesce(x->>'name','')) = ''
       or btrim(coalesce(x->>'storage_provider','')) = ''
       or btrim(coalesce(x->>'storage_ref','')) = ''
       or lower(coalesce(x->>'sha256','')) !~ '^[0-9a-f]{64}$'
  ) then
    return jsonb_build_object('outcome','BLOCKED','code','ARTIFACT_ITEM_INVALID');
  end if;

  select * into v_suite
  from public.lf_test_suite_runs
  where suite_run_id = v_suite_run_id
  for update;
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_RUN_NOT_FOUND');
  end if;
  if v_suite.suite_code is distinct from v_suite_code then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_CODE_MISMATCH');
  end if;
  if v_suite.commit_sha is null or lower(v_suite.commit_sha) is distinct from v_code_head_sha then
    return jsonb_build_object('outcome','BLOCKED','code','CODE_HEAD_MISMATCH');
  end if;
  if v_suite.environment is distinct from v_environment then
    return jsonb_build_object('outcome','BLOCKED','code','ENVIRONMENT_MISMATCH');
  end if;
  if not exists (
    select 1 from public.lf_test_suite_cases
    where suite_code = v_suite_code and test_code = v_test_code
  ) then
    return jsonb_build_object('outcome','BLOCKED','code','TEST_CASE_NOT_REGISTERED');
  end if;

  v_lock_key := v_suite_run_id::text || '|' || v_test_code || '|' || v_attempt_no::text || '|LF_TEST_RESULT_WRITER_V1';
  perform pg_advisory_xact_lock(hashtextextended(v_lock_key,0));

  select count(*), min(test_run_id::text)::uuid
  into v_existing_count, v_existing_id
  from public.lf_test_runs
  where suite_run_id = v_suite_run_id
    and test_code = v_test_code
    and attempt_no = v_attempt_no
    and metadata->>'writer_contract' = 'LF_TEST_RESULT_WRITER_V1';

  if v_existing_count > 1 then
    return jsonb_build_object('outcome','BLOCKED','code','WRITER_IDENTITY_DUPLICATE','count',v_existing_count);
  elsif v_existing_count = 1 then
    select evidence_payload->>'receipt_sha256' into v_existing_sha
    from public.lf_test_runs where test_run_id=v_existing_id;
    if v_existing_sha = v_receipt_sha256 then
      return jsonb_build_object(
        'outcome','REPLAY','replay',true,'test_run_id',v_existing_id,
        'receipt_sha256',v_receipt_sha256
      );
    end if;
    return jsonb_build_object(
      'outcome','BLOCKED','code','TEST_RUN_IDEMPOTENCY_CONFLICT',
      'test_run_id',v_existing_id,'existing_receipt_sha256',v_existing_sha,
      'candidate_receipt_sha256',v_receipt_sha256
    );
  end if;

  insert into public.lf_test_runs(
    suite_run_id,suite_code,test_code,execution_id,operation_code,rule_codes,story_code,contract_codes,
    environment,application_version,commit_sha,rule_set_version,executor_type,executor_name,attempt_no,status,
    input_payload,expected_output,actual_output,error_code,error_detail,severity,
    started_at,completed_at,duration_ms,evidence_payload,metadata,created_by_execution_id
  ) values (
    v_suite_run_id,v_suite_code,v_test_code,v_execution_id,null,'{}'::text[],null,'{}'::text[],
    v_environment,p_receipt->>'application_version',v_code_head_sha,p_receipt->>'rule_set_version',
    v_executor_type,v_executor_name,v_attempt_no,v_status,
    coalesce(p_receipt->'input_payload','{}'::jsonb),
    coalesce(p_receipt#>'{outcome,expected_output}','{}'::jsonb),
    coalesce(p_receipt#>'{outcome,actual_output}','{}'::jsonb),
    nullif(p_receipt#>>'{outcome,error_code}',''),nullif(p_receipt#>>'{outcome,error_detail}',''),
    coalesce(nullif(p_receipt#>>'{outcome,severity}',''),'MEDIUM'),
    v_started_at,v_completed_at,v_duration_ms,
    jsonb_build_object(
      'receipt',p_receipt,
      'receipt_sha256',v_receipt_sha256,
      'hash_contract','PRIVATE_CANONICAL_JSON_V7_SHA256_EXCLUDE_RECEIPT_SHA256',
      'source_sha256',v_source_sha256,
      'configuration_sha256',v_configuration_sha256,
      'code_head_sha',v_code_head_sha,
      'evidence_origin',v_evidence_origin
    ),
    jsonb_build_object(
      'writer_contract','LF_TEST_RESULT_WRITER_V1',
      'schema_version','lf-test-result-writer/v1',
      'timing_source',v_timing_source,
      'assertions_applicable',v_assertions_applicable,
      'judges_applicable',v_judges_applicable,
      'artifacts_applicable',v_artifacts_applicable
    ),
    p_actor_execution_id
  ) returning test_run_id into v_test_run_id;

  for v_item in select value from jsonb_array_elements(v_assertions) loop
    insert into public.lf_test_assertion_results(
      test_run_id,assertion_code,assertion_order,assertion_type,description,expected_value,actual_value,
      operator,status,severity,failure_reason,evidence_payload,metadata,created_by_execution_id
    ) values (
      v_test_run_id,v_item->>'assertion_code',(v_item->>'assertion_order')::integer,v_item->>'assertion_type',
      v_item->>'description',coalesce(v_item->'expected_value','null'::jsonb),coalesce(v_item->'actual_value','null'::jsonb),
      nullif(v_item->>'operator',''),v_item->>'status',coalesce(nullif(v_item->>'severity',''),'MEDIUM'),
      nullif(v_item->>'failure_reason',''),coalesce(v_item->'evidence_payload','{}'::jsonb),
      coalesce(v_item->'metadata','{}'::jsonb) || jsonb_build_object(
        'writer_contract','LF_TEST_RESULT_WRITER_V1','receipt_sha256',v_receipt_sha256
      ),p_actor_execution_id
    );
  end loop;

  for v_item in select value from jsonb_array_elements(v_judges) loop
    insert into public.lf_test_judge_results(
      test_run_id,judge_code,judge_type,model_name,model_version,prompt_version,verdict,confidence,severity,
      findings,evidence_payload,rationale_summary,metadata,created_by_execution_id
    ) values (
      v_test_run_id,v_item->>'judge_code',v_item->>'judge_type',nullif(v_item->>'model_name',''),
      nullif(v_item->>'model_version',''),nullif(v_item->>'prompt_version',''),v_item->>'verdict',
      case when jsonb_typeof(v_item->'confidence')='number' then (v_item->>'confidence')::numeric else null end,
      coalesce(nullif(v_item->>'severity',''),'MEDIUM'),coalesce(v_item->'findings','[]'::jsonb),
      coalesce(v_item->'evidence_payload','{}'::jsonb),nullif(v_item->>'rationale_summary',''),
      coalesce(v_item->'metadata','{}'::jsonb) || jsonb_build_object(
        'writer_contract','LF_TEST_RESULT_WRITER_V1','receipt_sha256',v_receipt_sha256,
        'executor_identity',v_item->>'executor_identity','judge_version',v_item->>'judge_version',
        'code_head_sha',v_code_head_sha
      ),p_actor_execution_id
    );
  end loop;

  for v_item in select value from jsonb_array_elements(v_artifacts) loop
    insert into public.lf_test_artifacts(
      suite_run_id,test_run_id,artifact_type,name,storage_provider,storage_ref,sha256,mime_type,size_bytes,
      metadata,created_by_execution_id
    ) values (
      v_suite_run_id,v_test_run_id,v_item->>'artifact_type',v_item->>'name',v_item->>'storage_provider',
      v_item->>'storage_ref',lower(v_item->>'sha256'),nullif(v_item->>'mime_type',''),
      case when jsonb_typeof(v_item->'size_bytes')='number' then (v_item->>'size_bytes')::bigint else null end,
      coalesce(v_item->'metadata','{}'::jsonb) || jsonb_build_object(
        'writer_contract','LF_TEST_RESULT_WRITER_V1','receipt_sha256',v_receipt_sha256,'code_head_sha',v_code_head_sha
      ),p_actor_execution_id
    );
  end loop;

  return jsonb_build_object(
    'outcome','MATERIALIZED','replay',false,'test_run_id',v_test_run_id,
    'receipt_sha256',v_receipt_sha256,'duration_ms',v_duration_ms,
    'assertion_rows',jsonb_array_length(v_assertions),
    'judge_rows',jsonb_array_length(v_judges),
    'artifact_rows',jsonb_array_length(v_artifacts)
  );
exception
  when unique_violation then
    return jsonb_build_object('outcome','BLOCKED','code','NORMALIZED_STORE_UNIQUE_VIOLATION');
end;
$function$;

revoke all on function public.lf_test_result_writer_v1(jsonb,text) from public;
revoke all on function public.lf_test_result_writer_v1(jsonb,text) from anon;
revoke all on function public.lf_test_result_writer_v1(jsonb,text) from authenticated;
grant execute on function public.lf_test_result_writer_v1(jsonb,text) to service_role;

create or replace function public.lf_test_suite_finalize_writer_v1(
  p_receipt jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_suite_run_id uuid;
  v_suite_code text;
  v_code_head_sha text;
  v_source_sha256 text;
  v_configuration_sha256 text;
  v_receipt_sha256 text;
  v_computed_sha256 text;
  v_evidence_origin text;
  v_started_at timestamptz;
  v_completed_at timestamptz;
  v_duration_ms bigint;
  v_expected_total integer;
  v_total integer;
  v_passed integer;
  v_failed integer;
  v_blocked integer;
  v_review integer;
  v_uncontrolled integer;
  v_missing_timing integer;
  v_min_started timestamptz;
  v_max_completed timestamptz;
  v_max_duration bigint;
  v_derived_status text;
  v_suite public.lf_test_suite_runs%rowtype;
begin
  if p_receipt is null or jsonb_typeof(p_receipt) <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_RECEIPT_INVALID');
  end if;
  if p_actor_execution_id is null or btrim(p_actor_execution_id) = '' then
    return jsonb_build_object('outcome','BLOCKED','code','ACTOR_EXECUTION_ID_MISSING');
  end if;
  if p_receipt->>'schema_version' <> 'lf-test-suite-finalize-writer/v1' then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_RECEIPT_SCHEMA_VERSION_INVALID');
  end if;
  if p_receipt->'executed' is distinct from 'true'::jsonb then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTED_PROOF_REQUIRED');
  end if;

  v_receipt_sha256 := lower(coalesce(p_receipt->>'receipt_sha256',''));
  if v_receipt_sha256 !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('outcome','BLOCKED','code','RECEIPT_SHA256_INVALID');
  end if;
  v_computed_sha256 := private.fn_payload_sha256_v7(p_receipt - 'receipt_sha256');
  if v_computed_sha256 is distinct from v_receipt_sha256 then
    return jsonb_build_object('outcome','BLOCKED','code','RECEIPT_SHA256_MISMATCH');
  end if;

  if coalesce(p_receipt->>'suite_run_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_RUN_ID_INVALID');
  end if;
  v_suite_run_id := (p_receipt->>'suite_run_id')::uuid;
  v_suite_code := btrim(coalesce(p_receipt->>'suite_code',''));
  v_code_head_sha := lower(coalesce(p_receipt->>'code_head_sha',''));
  v_source_sha256 := lower(coalesce(p_receipt->>'source_sha256',''));
  v_configuration_sha256 := lower(coalesce(p_receipt->>'configuration_sha256',''));
  if v_suite_code = '' or v_code_head_sha !~ '^[0-9a-f]{40}$'
     or v_source_sha256 !~ '^[0-9a-f]{64}$' or v_configuration_sha256 !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_IDENTITY_OR_SHA_INVALID');
  end if;
  v_evidence_origin := btrim(coalesce(p_receipt->>'evidence_origin',''));
  if v_evidence_origin not in ('LIVE_EXECUTOR_RECEIPT','DIRECT_EXECUTOR_REPLAY') then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_ORIGIN_INVALID');
  end if;

  if jsonb_typeof(p_receipt->'expected_tests_total') <> 'number'
     or coalesce(p_receipt->>'expected_tests_total','') !~ '^[1-9][0-9]*$' then
    return jsonb_build_object('outcome','BLOCKED','code','EXPECTED_TESTS_TOTAL_INVALID');
  end if;
  v_expected_total := (p_receipt->>'expected_tests_total')::integer;

  if jsonb_typeof(p_receipt->'timing') <> 'object'
     or p_receipt#>>'{timing,measurement_source}' <> 'MONOTONIC_PRODUCER'
     or jsonb_typeof(p_receipt#>'{timing,duration_ms}') <> 'number'
     or coalesce(p_receipt#>>'{timing,duration_ms}','') !~ '^[0-9]+$' then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_TIMING_INVALID');
  end if;
  begin
    v_started_at := (p_receipt#>>'{timing,started_at}')::timestamptz;
    v_completed_at := (p_receipt#>>'{timing,completed_at}')::timestamptz;
  exception when others then
    return jsonb_build_object('outcome','BLOCKED','code','TIMESTAMP_INVALID');
  end;
  v_duration_ms := (p_receipt#>>'{timing,duration_ms}')::bigint;
  if v_started_at is null or v_completed_at is null or v_completed_at < v_started_at then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_TIMING_INTERVAL_INVALID');
  end if;

  select * into v_suite
  from public.lf_test_suite_runs
  where suite_run_id=v_suite_run_id
  for update;
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_RUN_NOT_FOUND');
  end if;
  if v_suite.suite_code is distinct from v_suite_code then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_CODE_MISMATCH');
  end if;
  if v_suite.commit_sha is null or lower(v_suite.commit_sha) is distinct from v_code_head_sha then
    return jsonb_build_object('outcome','BLOCKED','code','CODE_HEAD_MISMATCH');
  end if;
  if v_suite.metadata->>'finalizer_contract' = 'LF_TEST_SUITE_FINALIZER_V1' then
    if v_suite.metadata->>'finalizer_receipt_sha256' = v_receipt_sha256 then
      return jsonb_build_object('outcome','REPLAY','replay',true,'suite_run_id',v_suite_run_id,'receipt_sha256',v_receipt_sha256);
    end if;
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_FINALIZE_IDEMPOTENCY_CONFLICT');
  end if;
  if v_suite.status not in ('QUEUED','RUNNING','IN_PROGRESS') then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_NOT_FINALIZABLE','status',v_suite.status);
  end if;

  select
    count(*)::integer,
    count(*) filter (where status='PASSED')::integer,
    count(*) filter (where status='FAILED')::integer,
    count(*) filter (where status='BLOCKED')::integer,
    count(*) filter (where status='REVIEW_REQUIRED')::integer,
    count(*) filter (where metadata->>'writer_contract' is distinct from 'LF_TEST_RESULT_WRITER_V1')::integer,
    count(*) filter (where started_at is null or completed_at is null or duration_ms is null)::integer,
    min(started_at),max(completed_at),max(duration_ms)
  into v_total,v_passed,v_failed,v_blocked,v_review,v_uncontrolled,v_missing_timing,v_min_started,v_max_completed,v_max_duration
  from public.lf_test_runs
  where suite_run_id=v_suite_run_id;

  if v_total <> v_expected_total then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_TEST_COUNT_MISMATCH','expected',v_expected_total,'observed',v_total);
  end if;
  if v_passed+v_failed+v_blocked+v_review <> v_total then
    return jsonb_build_object('outcome','BLOCKED','code','TEST_STATUS_VOCABULARY_INVALID');
  end if;
  if v_uncontrolled <> 0 then
    return jsonb_build_object('outcome','BLOCKED','code','UNCONTROLLED_TEST_ROWS_PRESENT','count',v_uncontrolled);
  end if;
  if v_missing_timing <> 0 then
    return jsonb_build_object('outcome','BLOCKED','code','TEST_TIMING_NOT_MATERIALIZED','count',v_missing_timing);
  end if;
  if v_started_at > v_min_started or v_completed_at < v_max_completed or v_duration_ms < coalesce(v_max_duration,0) then
    return jsonb_build_object('outcome','BLOCKED','code','SUITE_TIMING_DOES_NOT_ENCLOSE_TESTS');
  end if;

  v_derived_status := case
    when v_failed > 0 then 'FAILED'
    when v_blocked > 0 then 'BLOCKED'
    when v_review > 0 then 'REVIEW_REQUIRED'
    else 'PASSED'
  end;

  update public.lf_test_suite_runs
  set status=v_derived_status,
      started_at=v_started_at,
      completed_at=v_completed_at,
      duration_ms=v_duration_ms,
      tests_total=v_total,
      tests_passed=v_passed,
      tests_failed=v_failed,
      tests_blocked=v_blocked,
      tests_review_required=v_review,
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'finalizer_contract','LF_TEST_SUITE_FINALIZER_V1',
        'finalizer_schema_version','lf-test-suite-finalize-writer/v1',
        'finalizer_receipt',p_receipt,
        'finalizer_receipt_sha256',v_receipt_sha256,
        'hash_contract','PRIVATE_CANONICAL_JSON_V7_SHA256_EXCLUDE_RECEIPT_SHA256',
        'source_sha256',v_source_sha256,
        'configuration_sha256',v_configuration_sha256,
        'code_head_sha',v_code_head_sha,
        'evidence_origin',v_evidence_origin,
        'timing_source','MONOTONIC_PRODUCER'
      ),
      updated_by_execution_id=p_actor_execution_id
  where suite_run_id=v_suite_run_id;

  return jsonb_build_object(
    'outcome','MATERIALIZED','replay',false,'suite_run_id',v_suite_run_id,'status',v_derived_status,
    'tests_total',v_total,'tests_passed',v_passed,'tests_failed',v_failed,'tests_blocked',v_blocked,
    'tests_review_required',v_review,'duration_ms',v_duration_ms,'receipt_sha256',v_receipt_sha256
  );
end;
$function$;

revoke all on function public.lf_test_suite_finalize_writer_v1(jsonb,text) from public;
revoke all on function public.lf_test_suite_finalize_writer_v1(jsonb,text) from anon;
revoke all on function public.lf_test_suite_finalize_writer_v1(jsonb,text) from authenticated;
grant execute on function public.lf_test_suite_finalize_writer_v1(jsonb,text) to service_role;