create unique index if not exists uq_lf_test_suite_runs_external_ci_key_v1
  on public.lf_test_suite_runs ((metadata->>'external_ci_key'))
  where metadata ? 'external_ci_key';

create or replace function public.lf_record_external_ci_suite_evidence_v1(
  p_suite_code text,
  p_repository text,
  p_workflow_name text,
  p_job_name text,
  p_source_workflow_run_id bigint,
  p_source_job_id bigint,
  p_source_commit_sha text,
  p_results jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public','extensions'
as $function$
declare
  v_suite public.lf_test_suites%rowtype;
  v_existing public.lf_test_suite_runs%rowtype;
  v_suite_run_id uuid;
  v_now timestamptz := clock_timestamp();
  v_case_count integer;
  v_result_count integer;
  v_distinct_result_count integer;
  v_existing_count integer;
  v_existing_test_count integer;
  v_pass integer;
  v_fail integer;
  v_blocked integer;
  v_review integer;
  v_suite_status text;
  v_normalized_results jsonb;
  v_external_key text;
  v_evidence_sha256 text;
  v_source_ref text;
  v_expected_actor_execution_id text;
  v_rules text[] := '{}'::text[];
  v_stories text[] := '{}'::text[];
  v_test_run_ids jsonb := '[]'::jsonb;
begin
  if btrim(coalesce(p_suite_code,''))='' then
    raise exception 'LF_EXTERNAL_CI_SUITE_CODE_MISSING';
  end if;
  if coalesce(p_repository,'') !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then
    raise exception 'LF_EXTERNAL_CI_REPOSITORY_INVALID';
  end if;
  if btrim(coalesce(p_workflow_name,''))='' or btrim(coalesce(p_job_name,''))='' then
    raise exception 'LF_EXTERNAL_CI_WORKFLOW_JOB_MISSING';
  end if;
  if coalesce(p_source_workflow_run_id,0)<=0 or coalesce(p_source_job_id,0)<=0 then
    raise exception 'LF_EXTERNAL_CI_RUN_JOB_ID_INVALID';
  end if;
  if coalesce(p_source_commit_sha,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'LF_EXTERNAL_CI_COMMIT_SHA_INVALID';
  end if;
  if p_results is null or jsonb_typeof(p_results)<>'array' or jsonb_array_length(p_results)=0 then
    raise exception 'LF_EXTERNAL_CI_RESULTS_INVALID';
  end if;

  v_expected_actor_execution_id:=format(
    'GITHUB_ACTIONS:%s:%s:%s',
    p_repository,
    p_source_workflow_run_id,
    p_source_job_id
  );
  if p_actor_execution_id is distinct from v_expected_actor_execution_id then
    raise exception 'LF_EXTERNAL_CI_ACTOR_IDENTITY_MISMATCH expected=% actual=%',
      v_expected_actor_execution_id,p_actor_execution_id;
  end if;

  select * into v_suite
  from public.lf_test_suites
  where suite_code=p_suite_code;
  if not found then
    raise exception 'LF_EXTERNAL_CI_SUITE_NOT_FOUND:%',p_suite_code;
  end if;
  if v_suite.status not in ('CANDIDATO','ACTIVE','VIGENTE') then
    raise exception 'LF_EXTERNAL_CI_SUITE_STATUS_NOT_ELIGIBLE:%',v_suite.status;
  end if;
  if coalesce((v_suite.execution_policy->>'normalized_ci_evidence_required')::boolean,false) is not true
     or coalesce((v_suite.execution_policy->>'db_matrix_runner_applicable')::boolean,true) is not false then
    raise exception 'LF_EXTERNAL_CI_SUITE_POLICY_NOT_EXTERNAL:%',p_suite_code;
  end if;

  select count(*) into v_case_count
  from public.lf_test_suite_cases c
  where c.suite_code=p_suite_code
    and c.status in ('CANDIDATO','ACTIVE','VIGENTE');
  if v_case_count=0 then
    raise exception 'LF_EXTERNAL_CI_SUITE_HAS_NO_ELIGIBLE_CASES:%',p_suite_code;
  end if;

  if exists(
    select 1
    from jsonb_array_elements(p_results) e
    where jsonb_typeof(e)<>'object'
       or btrim(coalesce(e->>'test_code',''))=''
       or upper(coalesce(e->>'status','')) not in ('PASS','FAIL','BLOCKED','REVIEW_REQUIRED')
       or not (e ? 'actual_output')
       or jsonb_typeof(e->'actual_output')<>'object'
       or not (e ? 'evidence_payload')
       or jsonb_typeof(e->'evidence_payload')<>'object'
  ) then
    raise exception 'LF_EXTERNAL_CI_RESULT_SHAPE_INVALID';
  end if;

  select count(*),count(distinct e->>'test_code')
    into v_result_count,v_distinct_result_count
  from jsonb_array_elements(p_results) e;
  if v_result_count<>v_case_count or v_distinct_result_count<>v_result_count then
    raise exception 'LF_EXTERNAL_CI_CASESET_COUNT_OR_DUPLICATE expected=% actual=% distinct=%',
      v_case_count,v_result_count,v_distinct_result_count;
  end if;
  if exists(
    select 1
    from jsonb_array_elements(p_results) e
    left join public.lf_test_suite_cases c
      on c.suite_code=p_suite_code
     and c.test_code=e->>'test_code'
     and c.status in ('CANDIDATO','ACTIVE','VIGENTE')
    where c.test_code is null
  ) then
    raise exception 'LF_EXTERNAL_CI_CASESET_UNEXPECTED_TEST';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'test_code',e->>'test_code',
      'status',upper(e->>'status'),
      'actual_output',e->'actual_output',
      'evidence_payload',e->'evidence_payload'
    ) order by e->>'test_code'
  ) into v_normalized_results
  from jsonb_array_elements(p_results) e;

  v_source_ref:=format(
    'github://%s@%s/actions/runs/%s/jobs/%s',
    p_repository,p_source_commit_sha,p_source_workflow_run_id,p_source_job_id
  );
  v_external_key:=encode(
    extensions.digest(
      convert_to(
        concat_ws('|','GITHUB_ACTIONS',p_suite_code,p_repository,p_source_workflow_run_id::text,p_source_job_id::text,p_source_commit_sha),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
  v_evidence_sha256:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'suite_code',p_suite_code,
          'repository',p_repository,
          'workflow_name',p_workflow_name,
          'job_name',p_job_name,
          'workflow_run_id',p_source_workflow_run_id,
          'job_id',p_source_job_id,
          'commit_sha',p_source_commit_sha,
          'results',v_normalized_results
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended('lf_external_ci:'||v_external_key,0));

  select count(*) into v_existing_count
  from public.lf_test_suite_runs
  where metadata->>'external_ci_key'=v_external_key;
  if v_existing_count>1 then
    raise exception 'LF_EXTERNAL_CI_DUPLICATE_EXISTING_KEY:%',v_external_key;
  end if;
  if v_existing_count=1 then
    select * into v_existing
    from public.lf_test_suite_runs
    where metadata->>'external_ci_key'=v_external_key
    limit 1;
    if v_existing.suite_code is distinct from p_suite_code
       or v_existing.commit_sha is distinct from p_source_commit_sha
       or v_existing.metadata->>'external_ci_evidence_sha256' is distinct from v_evidence_sha256 then
      raise exception 'LF_EXTERNAL_CI_REPLAY_CONFLICT:%',v_external_key;
    end if;
    select count(*) into v_existing_test_count
    from public.lf_test_runs
    where suite_run_id=v_existing.suite_run_id;
    if v_existing_test_count<>v_case_count then
      raise exception 'LF_EXTERNAL_CI_REPLAY_INCOMPLETE_TESTSET expected=% actual=%',
        v_case_count,v_existing_test_count;
    end if;
    select coalesce(jsonb_agg(test_run_id order by test_code),'[]'::jsonb)
      into v_test_run_ids
    from public.lf_test_runs
    where suite_run_id=v_existing.suite_run_id;
    return jsonb_build_object(
      'result','EXTERNAL_CI_EVIDENCE_ALREADY_RECORDED_IDENTICAL',
      'suite_run_id',v_existing.suite_run_id,
      'test_run_ids',v_test_run_ids,
      'suite_status',v_existing.status,
      'external_ci_key',v_external_key,
      'evidence_sha256',v_evidence_sha256,
      'source_ref',v_source_ref
    );
  end if;

  select
    count(*) filter (where upper(e->>'status')='PASS'),
    count(*) filter (where upper(e->>'status')='FAIL'),
    count(*) filter (where upper(e->>'status')='BLOCKED'),
    count(*) filter (where upper(e->>'status')='REVIEW_REQUIRED')
    into v_pass,v_fail,v_blocked,v_review
  from jsonb_array_elements(v_normalized_results) e;

  v_suite_status:=case
    when v_fail>0 then 'FAILED'
    when v_blocked>0 then 'BLOCKED'
    when v_review>0 then 'REVIEW_REQUIRED'
    else 'PASSED'
  end;

  select coalesce(array_agg(distinct r order by r),'{}'::text[])
    into v_rules
  from public.lf_test_suite_cases c
  cross join lateral unnest(c.rule_codes) r
  where c.suite_code=p_suite_code
    and c.status in ('CANDIDATO','ACTIVE','VIGENTE');

  select coalesce(
    array_agg(distinct c.story_code order by c.story_code)
      filter (where c.story_code is not null),
    '{}'::text[]
  ) into v_stories
  from public.lf_test_suite_cases c
  where c.suite_code=p_suite_code
    and c.status in ('CANDIDATO','ACTIVE','VIGENTE');

  insert into public.lf_test_suite_runs(
    suite_code,execution_id,environment,commit_sha,executor_type,executor_name,status,
    started_at,completed_at,duration_ms,tests_total,tests_passed,tests_failed,
    tests_blocked,tests_review_required,rules_covered,stories_covered,contracts_covered,
    manifest,metadata,created_by_execution_id
  ) values (
    p_suite_code,
    p_actor_execution_id,
    'REAL_GOVERNED',
    p_source_commit_sha,
    'GITHUB_ACTIONS_NORMALIZED_CI',
    p_workflow_name||'/'||p_job_name,
    v_suite_status,
    v_now,v_now,0,
    v_case_count,v_pass,v_fail,v_blocked,v_review,
    v_rules,v_stories,'{}'::text[],
    jsonb_build_object(
      'evidence_schema_version','lf-external-ci-suite/v1',
      'source_provider','GITHUB_ACTIONS',
      'source_ref',v_source_ref,
      'repository',p_repository,
      'workflow_name',p_workflow_name,
      'job_name',p_job_name,
      'source_workflow_run_id',p_source_workflow_run_id,
      'source_job_id',p_source_job_id,
      'source_commit_sha',p_source_commit_sha,
      'external_ci_evidence_sha256',v_evidence_sha256,
      'exact_case_set',true,
      'append_only',true,
      'no_qualification_or_binding_side_effect',true
    ),
    jsonb_build_object(
      'external_ci_key',v_external_key,
      'external_ci_evidence_sha256',v_evidence_sha256,
      'recorder','lf_record_external_ci_suite_evidence_v1',
      'source_provider','GITHUB_ACTIONS',
      'source_bound_by_ci_context',true,
      'database_remote_attestation',false,
      'claim_ceiling','NORMALIZED_SOURCE_BOUND_CI_EVIDENCE'
    ),
    p_actor_execution_id
  ) returning suite_run_id into v_suite_run_id;

  insert into public.lf_test_runs(
    suite_run_id,suite_code,test_code,execution_id,operation_code,rule_codes,story_code,
    contract_codes,environment,commit_sha,executor_type,executor_name,attempt_no,status,
    input_payload,expected_output,actual_output,error_code,error_detail,severity,
    started_at,completed_at,duration_ms,evidence_payload,metadata,created_by_execution_id
  )
  select
    v_suite_run_id,
    c.suite_code,
    c.test_code,
    p_actor_execution_id,
    nullif(c.metadata->>'operation_code',''),
    c.rule_codes,
    c.story_code,
    '{}'::text[],
    'REAL_GOVERNED',
    p_source_commit_sha,
    'GITHUB_ACTIONS_NORMALIZED_CI',
    p_workflow_name||'/'||p_job_name,
    1,
    upper(r.item->>'status'),
    c.input_payload,
    c.expected_output,
    r.item->'actual_output',
    nullif(r.item->'actual_output'->>'error_code',''),
    nullif(r.item->'actual_output'->>'error_detail',''),
    c.severity,
    v_now,v_now,0,
    (r.item->'evidence_payload') || jsonb_build_object(
      'source_provider','GITHUB_ACTIONS',
      'source_ref',v_source_ref,
      'source_workflow_run_id',p_source_workflow_run_id,
      'source_job_id',p_source_job_id,
      'source_commit_sha',p_source_commit_sha,
      'external_ci_evidence_sha256',v_evidence_sha256
    ),
    c.metadata || jsonb_build_object(
      'evidence_mode','NORMALIZED_EXTERNAL_CI',
      'external_ci_key',v_external_key,
      'recorder','lf_record_external_ci_suite_evidence_v1',
      'source_bound_by_ci_context',true,
      'database_remote_attestation',false
    ),
    p_actor_execution_id
  from public.lf_test_suite_cases c
  join lateral jsonb_array_elements(v_normalized_results) as r(item)
    on r.item->>'test_code'=c.test_code
  where c.suite_code=p_suite_code
    and c.status in ('CANDIDATO','ACTIVE','VIGENTE');

  insert into public.lf_test_artifacts(
    suite_run_id,test_run_id,artifact_type,name,storage_provider,storage_ref,sha256,
    mime_type,metadata,created_by_execution_id
  ) values (
    v_suite_run_id,
    null,
    'CI_RUN',
    'GitHub Actions normalized evidence: '||p_suite_code,
    'GITHUB',
    v_source_ref,
    v_evidence_sha256,
    'application/json',
    jsonb_build_object(
      'source_provider','GITHUB_ACTIONS',
      'repository',p_repository,
      'workflow_name',p_workflow_name,
      'job_name',p_job_name,
      'source_workflow_run_id',p_source_workflow_run_id,
      'source_job_id',p_source_job_id,
      'source_commit_sha',p_source_commit_sha,
      'external_ci_key',v_external_key
    ),
    p_actor_execution_id
  );

  select coalesce(jsonb_agg(test_run_id order by test_code),'[]'::jsonb)
    into v_test_run_ids
  from public.lf_test_runs
  where suite_run_id=v_suite_run_id;

  return jsonb_build_object(
    'result','EXTERNAL_CI_EVIDENCE_RECORDED',
    'suite_run_id',v_suite_run_id,
    'test_run_ids',v_test_run_ids,
    'suite_status',v_suite_status,
    'tests_total',v_case_count,
    'tests_passed',v_pass,
    'tests_failed',v_fail,
    'tests_blocked',v_blocked,
    'tests_review_required',v_review,
    'external_ci_key',v_external_key,
    'evidence_sha256',v_evidence_sha256,
    'source_ref',v_source_ref,
    'no_qualification_or_binding_side_effect',true
  );
end
$function$;

revoke all on function public.lf_record_external_ci_suite_evidence_v1(
  text,text,text,text,bigint,bigint,text,jsonb,text
) from public;
revoke all on function public.lf_record_external_ci_suite_evidence_v1(
  text,text,text,text,bigint,bigint,text,jsonb,text
) from anon, authenticated;
grant execute on function public.lf_record_external_ci_suite_evidence_v1(
  text,text,text,text,bigint,bigint,text,jsonb,text
) to postgres, service_role;
