begin;

do $guard$
declare
  v_action text;
  v_packet text;
begin
  select md5(p.prosrc) into v_action
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

  select md5(p.prosrc) into v_packet
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';

  if v_action is distinct from '222f0488ad15ec43249404526d8af02d' then
    raise exception 'ACTION_SPEC_V3_DRIFT:%',v_action;
  end if;
  if v_packet is distinct from '8eb16266609b0557d54fe4be7ae96e05' then
    raise exception 'EXECUTION_PACKET_DRIFT:%',v_packet;
  end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='ORQUESTACION_PIPELINE_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'ORCHESTRATOR_OPERATION_NOT_OPERATIONAL';
  end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='GITHUB_CONTRACT_GATE_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'T_EQUIV_CONSUMER_OPERATION_NOT_OPERATIONAL';
  end if;

  if not exists (
    select 1 from public.lf_capability_current
    where capability_code='CONTROL_EQUIVALENCE_JUDGE'
      and version='1.0.0'
      and manifest_sha256='57679dfcdc4de7bd70aa5458547722f3e8d8aba00d9407baad3566137abd3b52'
  ) then
    raise exception 'T_EQUIV_CURRENT_DRIFT';
  end if;
end
$guard$;

create or replace function programacion.fn_engineering_capability_bind_receipt_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog','extensions'
as $function$
declare
  v_spec jsonb;
  v_ce jsonb;
  v_capability_code text;
  v_orchestrator_operation_code text;
  v_consumer_operation_code text;
  v_target_type text;
  v_target_code text;
  v_plan_digest text;
  v_policy_mode text;
  v_orchestrator_prefix text;
  v_consumer_prefix text;
  v_suffix text;
  v_orchestrator_execution_id text;
  v_consumer_execution_id text;
  v_current_version text;
  v_current_manifest_sha256 text;
  v_orchestrator_manifest jsonb;
  v_consumer_manifest jsonb;
  v_orchestrator_request_sha256 text;
  v_consumer_request_sha256 text;
  v_orchestrator_reservation jsonb;
  v_consumer_reservation jsonb;
  v_dispatch jsonb;
  v_binding jsonb;
begin
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code);
  if v_spec is null then
    raise exception 'ENGINEERING_CAPABILITY_BIND_SPEC_MISSING';
  end if;
  if coalesce(v_spec->>'action_kind','')<>'DECLARED_CAPABILITY_TEST_EXECUTION' then
    raise exception 'ENGINEERING_CAPABILITY_BIND_WRONG_ACTION_KIND:%',coalesce(v_spec->>'action_kind','');
  end if;

  v_ce:=coalesce(v_spec->'capability_execution','{}'::jsonb);
  v_capability_code:=nullif(btrim(coalesce(v_ce->>'capability_code','')),'');
  v_orchestrator_operation_code:=nullif(btrim(coalesce(v_ce->>'orchestrator_operation_code','')),'');
  v_consumer_operation_code:=nullif(btrim(coalesce(v_ce->>'consumer_operation_code','')),'');
  v_target_type:=nullif(btrim(coalesce(v_ce->>'target_type','')),'');
  v_target_code:=nullif(btrim(coalesce(v_ce->>'target_code','')),'');
  v_plan_digest:=nullif(btrim(coalesce(v_ce->>'plan_digest','')),'');
  v_policy_mode:=nullif(btrim(coalesce(v_ce->>'policy_mode','')),'');
  v_orchestrator_prefix:=nullif(btrim(coalesce(v_ce->>'orchestrator_execution_id_prefix','')),'');
  v_consumer_prefix:=nullif(btrim(coalesce(v_ce->>'execution_id_prefix','')),'');

  if v_capability_code is null
     or v_orchestrator_operation_code is null
     or v_consumer_operation_code is null
     or v_target_type is null
     or v_target_code is null
     or v_plan_digest is null
     or v_policy_mode is null
     or v_orchestrator_prefix is null
     or v_consumer_prefix is null then
    raise exception 'ENGINEERING_CAPABILITY_BIND_RECIPE_INCOMPLETE';
  end if;
  if v_plan_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'ENGINEERING_CAPABILITY_BIND_PLAN_DIGEST_INVALID';
  end if;

  select version,manifest_sha256
    into v_current_version,v_current_manifest_sha256
  from public.lf_capability_current
  where capability_code=v_capability_code;
  if not found then
    raise exception 'ENGINEERING_CAPABILITY_BIND_CURRENT_MISSING:%',v_capability_code;
  end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code=v_orchestrator_operation_code
      and operation_family='ORCHESTRATION'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'ENGINEERING_CAPABILITY_BIND_ORCHESTRATOR_NOT_OPERATIONAL:%',v_orchestrator_operation_code;
  end if;
  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code=v_consumer_operation_code
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'ENGINEERING_CAPABILITY_BIND_CONSUMER_NOT_OPERATIONAL:%',v_consumer_operation_code;
  end if;

  v_suffix:=to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||left(replace(gen_random_uuid()::text,'-',''),8);
  v_orchestrator_execution_id:=v_orchestrator_prefix||v_suffix;
  v_consumer_execution_id:=v_consumer_prefix||v_suffix;

  v_orchestrator_manifest:=jsonb_build_object(
    'schema_version','ENGINEERING_CAPABILITY_ORCHESTRATOR_V1',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'capability_code',v_capability_code,
    'policy_mode',v_policy_mode,
    'plan_digest',v_plan_digest,
    'purpose','ENGINEERING_DECLARED_CAPABILITY_TEST_BIND',
    'effects_executed',false
  );
  v_consumer_manifest:=jsonb_build_object(
    'schema_version','ENGINEERING_CAPABILITY_CONSUMER_V1',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'capability_code',v_capability_code,
    'policy_mode',v_policy_mode,
    'plan_digest',v_plan_digest,
    'orchestrator_execution_id',v_orchestrator_execution_id,
    'effects_executed',false
  );

  v_orchestrator_request_sha256:=encode(extensions.digest(convert_to(
    jsonb_build_object('execution_id',v_orchestrator_execution_id,'manifest',v_orchestrator_manifest)::text,'UTF8'
  ),'sha256'),'hex');
  v_consumer_request_sha256:=encode(extensions.digest(convert_to(
    jsonb_build_object('execution_id',v_consumer_execution_id,'manifest',v_consumer_manifest)::text,'UTF8'
  ),'sha256'),'hex');

  v_orchestrator_reservation:=public.fn_lf_operation_reserve_execution_v1(
    v_orchestrator_execution_id,
    v_orchestrator_operation_code,
    v_target_type,
    v_target_code,
    left('engineering-bind:'||p_plan_code||':'||p_unit_code||':'||p_checkpoint_code||':orch:'||v_suffix,200),
    v_orchestrator_request_sha256,
    v_orchestrator_execution_id,
    null,
    null,
    v_orchestrator_manifest
  );
  if coalesce((v_orchestrator_reservation->>'dispatch_permitted')::boolean,false) is not true then
    raise exception 'ENGINEERING_CAPABILITY_BIND_ORCHESTRATOR_RESERVE_FAILED:%',v_orchestrator_reservation;
  end if;

  v_consumer_reservation:=public.fn_lf_operation_reserve_execution_v1(
    v_consumer_execution_id,
    v_consumer_operation_code,
    v_target_type,
    v_target_code,
    left('engineering-bind:'||p_plan_code||':'||p_unit_code||':'||p_checkpoint_code||':consumer:'||v_suffix,200),
    v_consumer_request_sha256,
    v_consumer_execution_id,
    null,
    null,
    v_consumer_manifest
  );
  if coalesce((v_consumer_reservation->>'dispatch_permitted')::boolean,false) is not true then
    raise exception 'ENGINEERING_CAPABILITY_BIND_CONSUMER_RESERVE_FAILED:%',v_consumer_reservation;
  end if;

  v_dispatch:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orchestrator_execution_id,
    v_consumer_execution_id,
    v_capability_code,
    v_plan_digest,
    jsonb_build_object(
      'purpose','ENGINEERING_DECLARED_CAPABILITY_TEST_BIND',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'policy_mode',v_policy_mode,
      'effects_executed',false
    ),
    v_orchestrator_execution_id
  );
  if coalesce((v_dispatch->>'ready')::boolean,false) is not true then
    raise exception 'ENGINEERING_CAPABILITY_BIND_DISPATCH_FAILED:%',v_dispatch;
  end if;

  v_binding:=public.fn_lf_capability_bind_from_orchestrator_v1(
    v_consumer_execution_id,
    v_capability_code,
    v_current_manifest_sha256,
    v_plan_digest,
    (v_dispatch->>'receipt_id')::uuid,
    v_consumer_execution_id
  );
  if coalesce((v_binding->>'ready')::boolean,false) is not true then
    raise exception 'ENGINEERING_CAPABILITY_BIND_CURRENT_FAILED:%',v_binding;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_CAPABILITY_BIND_RECEIPT_V1',
    'ready',true,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'capability_code',v_capability_code,
    'current_version',v_current_version,
    'current_manifest_sha256',v_current_manifest_sha256,
    'plan_digest',v_plan_digest,
    'orchestrator_operation_code',v_orchestrator_operation_code,
    'consumer_operation_code',v_consumer_operation_code,
    'orchestrator_execution_id',v_orchestrator_execution_id,
    'consumer_execution_id',v_consumer_execution_id,
    'dispatch_receipt_id',v_dispatch->>'receipt_id',
    'dispatch_receipt_sha256',v_dispatch->>'receipt_sha256',
    'binding',v_binding,
    'evidence_refs',jsonb_build_array(
      'supabase://public.lf_operation_execution/'||v_orchestrator_execution_id,
      'supabase://public.lf_operation_execution/'||v_consumer_execution_id,
      'supabase://public.lf_capability_binding/'||v_consumer_execution_id||'/'||v_capability_code
    )
  );
end;
$function$;

create or replace function programacion.fn_engineering_run_test_persist_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_execution_id text,
  p_suite_code text,
  p_results jsonb,
  p_executor_name text default 'ENGINEERING_AGENT_RUN_TEST_V1',
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
    return jsonb_build_object(
      'schema_version','ENGINEERING_RUN_TEST_PERSIST_V1',
      'result','REPLAY_EXISTING_SUITE_RUN',
      'suite_run_id',v_existing.suite_run_id,
      'status',v_existing.status,
      'tests_total',v_existing.tests_total,
      'tests_passed',v_existing.tests_passed,
      'tests_failed',v_existing.tests_failed,
      'tests_blocked',v_existing.tests_blocked,
      'tests_review_required',v_existing.tests_review_required
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

  return jsonb_build_object(
    'schema_version','ENGINEERING_RUN_TEST_PERSIST_V1',
    'result','PERSISTED_NEW_SUITE_RUN',
    'suite_run_id',v_suite_run_id,
    'status',v_suite_status,
    'tests_total',v_result_count,
    'tests_passed',v_passed,
    'tests_failed',v_failed,
    'tests_blocked',v_blocked,
    'tests_review_required',v_review,
    'evidence_ref','supabase://public.lf_test_suite_runs/'||v_suite_run_id
  );
end;
$function$;

create or replace function pg_temp.rep(src text,o text,n text)
returns text
language plpgsql
as $r$
begin
  if position(o in src)=0 then
    raise exception 'PATCH_ANCHOR_MISSING:%',left(o,180);
  end if;
  if position(o in substr(src,position(o in src)+length(o)))>0 then
    raise exception 'PATCH_ANCHOR_NON_UNIQUE:%',left(o,180);
  end if;
  return replace(src,o,n);
end
$r$;

do $patch_action$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

  d:=pg_temp.rep(
    d,
    $orig$        'currentness_source','public.lf_capability_current',
        'orchestrator_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',$orig$,
    $repl$        'currentness_source','public.lf_capability_current',
        'orchestrator_operation_code','ORQUESTACION_PIPELINE_LF',
        'consumer_operation_code','GITHUB_CONTRACT_GATE_LF',
        'target_type','ENGINEERING_PLAN_UNIT_BINDING_PROOF',
        'target_code',p_plan_code||':'||p_unit_code,
        'plan_digest',encode(extensions.digest(convert_to('IG_CURATOR_VALIDATOR_REFACTOR_V2:M3.9|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY','UTF8'),'sha256'),'hex'),
        'binding_recipe_entrypoint','programacion.fn_engineering_capability_bind_receipt_v1',
        'run_test_persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1',
        'result_contract',jsonb_build_object(
          'suite_code','INPUT_GOVERNANCE_REGRESSION',
          'test_code','M3_9_SHADOW_T_EQUIV_CORPUS',
          'pass_when',jsonb_build_object(
            'shadow_contract','M3_9_T_EQUIV_CORPUS_V1',
            'screen_count',13,
            'fresh_t_equiv_binding_receipt',true,
            'domain_mutation',false,
            'diff_adjudication','NEXT_CHECKPOINT'
          )
        ),
        'orchestrator_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',$repl$
  );
  execute d;
end
$patch_action$;

do $patch_packet$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';

  d:=pg_temp.rep(
    d,
    $orig$      when spec_status<>'READY' then 'BLOCK_ACTION_SPEC'
      when action_kind='VERIFY_QUERY_ONCE' and not has_verification and not has_predecessor then 'BLOCK_SPEC_INCOMPLETE'$orig$,
    $repl$      when spec_status<>'READY' then 'BLOCK_ACTION_SPEC'
      when action_kind='DECLARED_CAPABILITY_TEST_EXECUTION' and (
        nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,orchestrator_operation_code}','')),'') is null
        or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,consumer_operation_code}','')),'') is null
        or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,target_type}','')),'') is null
        or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,target_code}','')),'') is null
        or coalesce(p_action_spec#>>'{capability_execution,plan_digest}','') !~ '^[0-9a-f]{64}$'
        or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,binding_recipe_entrypoint}','')),'') is null
        or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,run_test_persistence_entrypoint}','')),'') is null
      ) then 'BLOCK_SPEC_INCOMPLETE'
      when action_kind='VERIFY_QUERY_ONCE' and not has_verification and not has_predecessor then 'BLOCK_SPEC_INCOMPLETE'$repl$
  );

  d:=pg_temp.rep(
    d,
    $orig$    || (case when action_kind<>'DECLARED_TEST_PERSISTENCE_EXECUTION' and ((effective_material and not has_migration_artifact) or (action_kind='VERIFY_QUERY_ONCE' and not effective_material and not has_predecessor)) and not has_verification then jsonb_build_array('MISSING_VERIFICATION') else '[]'::jsonb end)$orig$,
    $repl$    || (case when action_kind<>'DECLARED_TEST_PERSISTENCE_EXECUTION' and ((effective_material and not has_migration_artifact) or (action_kind='VERIFY_QUERY_ONCE' and not effective_material and not has_predecessor)) and not has_verification then jsonb_build_array('MISSING_VERIFICATION') else '[]'::jsonb end)
    || (case when action_kind='DECLARED_CAPABILITY_TEST_EXECUTION' and (
      nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,orchestrator_operation_code}','')),'') is null
      or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,consumer_operation_code}','')),'') is null
      or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,target_type}','')),'') is null
      or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,target_code}','')),'') is null
      or coalesce(p_action_spec#>>'{capability_execution,plan_digest}','') !~ '^[0-9a-f]{64}$'
      or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,binding_recipe_entrypoint}','')),'') is null
      or nullif(btrim(coalesce(p_action_spec#>>'{capability_execution,run_test_persistence_entrypoint}','')),'') is null
    ) then jsonb_build_array('MISSING_CAPABILITY_EXECUTION_RECIPE') else '[]'::jsonb end)$repl$
  );

  d:=pg_temp.rep(
    d,
    $orig$            'return_binding_evidence_to_next_step',true
          )$orig$,
    $repl$            'return_binding_evidence_to_next_step',true,
            'entrypoint','programacion.fn_engineering_capability_bind_receipt_v1',
            'call_sql',format('select programacion.fn_engineering_capability_bind_receipt_v1(%L,%L,%L)',p_plan_code,p_unit_code,p_checkpoint_code),
            'orchestrator_operation_code',p_action_spec#>>'{capability_execution,orchestrator_operation_code}',
            'consumer_operation_code',p_action_spec#>>'{capability_execution,consumer_operation_code}',
            'target_type',p_action_spec#>>'{capability_execution,target_type}',
            'target_code',p_action_spec#>>'{capability_execution,target_code}',
            'plan_digest',p_action_spec#>>'{capability_execution,plan_digest}'
          )$repl$
  );

  d:=pg_temp.rep(
    d,
    $orig$            'execute_declared_queries',true,
            'return_evidence_for_transition',true$orig$,
    $repl$            'execute_declared_queries',true,
            'persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1',
            'persistence_contract',coalesce(p_action_spec#>'{capability_execution,result_contract}','{}'::jsonb),
            'result_source','DECLARED_QUERY_OUTPUT_PLUS_BIND_RECEIPT',
            'return_evidence_for_transition',true$repl$
  );
  execute d;
end
$patch_packet$;

do $verify$
declare
  v_spec jsonb;
  v_packet jsonb;
  v_bind_step jsonb;
  v_run_step jsonb;
  v_smoke jsonb;
  v_smoke_execution_id text:='ENGINEERING-RUN-TEST-PERSIST-SMOKE-20261005194500';
  v_smoke_suite_run_id uuid;
begin
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9','SHADOW_RUN'
  );
  if v_spec#>>'{capability_execution,orchestrator_operation_code}' is distinct from 'ORQUESTACION_PIPELINE_LF'
     or v_spec#>>'{capability_execution,consumer_operation_code}' is distinct from 'GITHUB_CONTRACT_GATE_LF'
     or v_spec#>>'{capability_execution,target_type}' is distinct from 'ENGINEERING_PLAN_UNIT_BINDING_PROOF'
     or v_spec#>>'{capability_execution,target_code}' is distinct from 'IG_CURATOR_VALIDATOR_REFACTOR_V2:M3.9'
     or v_spec#>>'{capability_execution,plan_digest}' is distinct from '7729bc48b28a408cb17f333951cc0322296dea9edd34ece454da71ea62a1cc75' then
    raise exception 'M3_9_CAPABILITY_EXECUTION_RECIPE_INVALID:%',v_spec->'capability_execution';
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9','SHADOW_RUN',v_spec,'{}'::jsonb
  );
  if v_packet->>'status' is distinct from 'READY'
     or v_packet->>'execution_capability' is distinct from 'RUN_TEST' then
    raise exception 'M3_9_PACKET_NOT_READY_RUN_TEST:%',v_packet;
  end if;
  v_bind_step:=v_packet#>'{connector_plan,0}';
  v_run_step:=v_packet#>'{connector_plan,1}';
  if v_bind_step#>>'{executor_contract,entrypoint}' is distinct from 'programacion.fn_engineering_capability_bind_receipt_v1'
     or v_bind_step#>>'{executor_contract,consumer_operation_code}' is distinct from 'GITHUB_CONTRACT_GATE_LF'
     or v_run_step#>>'{executor_contract,persistence_entrypoint}' is distinct from 'programacion.fn_engineering_run_test_persist_v1'
     or v_run_step#>>'{executor_contract,persistence_contract,test_code}' is distinct from 'M3_9_SHADOW_T_EQUIV_CORPUS' then
    raise exception 'M3_9_PACKET_EXECUTION_RECIPE_INCOMPLETE:%',v_packet->'connector_plan';
  end if;

  v_smoke:=programacion.fn_engineering_run_test_persist_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M3.9',
    'SHADOW_RUN',
    v_smoke_execution_id,
    'INPUT_GOVERNANCE_REGRESSION',
    jsonb_build_array(jsonb_build_object(
      'test_code','M3_9_SHADOW_T_EQUIV_CORPUS',
      'status','BLOCKED',
      'actual_output',jsonb_build_object('contract_smoke',true),
      'evidence_payload',jsonb_build_object('contract_smoke',true,'reason','PERSISTENCE_GRAPH_ONLY_NO_DOMAIN_PASS')
    )),
    'ENGINEERING_AGENT_RUN_TEST_V1',
    jsonb_build_object('actual_execution',true,'synthetic_pass',false,'contract_smoke',true)
  );
  v_smoke_suite_run_id:=(v_smoke->>'suite_run_id')::uuid;
  if v_smoke->>'status' is distinct from 'BLOCKED' then
    raise exception 'RUN_TEST_PERSIST_SMOKE_STATUS_INVALID:%',v_smoke;
  end if;
  if (select count(*) from public.lf_test_runs where suite_run_id=v_smoke_suite_run_id)<>1
     or (select count(*) from public.lf_test_assertion_results a join public.lf_test_runs t on t.test_run_id=a.test_run_id where t.suite_run_id=v_smoke_suite_run_id)<>1 then
    raise exception 'RUN_TEST_PERSIST_SMOKE_GRAPH_INVALID:%',v_smoke_suite_run_id;
  end if;

  delete from public.lf_test_suite_runs where suite_run_id=v_smoke_suite_run_id;
  if exists(select 1 from public.lf_test_runs where suite_run_id=v_smoke_suite_run_id) then
    raise exception 'RUN_TEST_PERSIST_SMOKE_RESIDUE_TEST_RUN';
  end if;
  if exists(select 1 from public.lf_test_suite_runs where execution_id=v_smoke_execution_id) then
    raise exception 'RUN_TEST_PERSIST_SMOKE_RESIDUE_SUITE_RUN';
  end if;
end
$verify$;

commit;
