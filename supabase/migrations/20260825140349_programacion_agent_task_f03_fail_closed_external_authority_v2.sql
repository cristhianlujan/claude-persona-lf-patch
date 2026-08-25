create or replace function programacion.fn_record_f03_oidc_audit_verdict_v1(
  p_task_id bigint,
  p_task_sha256 text,
  p_generation_source_sha256 text,
  p_job_workflow_ref text,
  p_job_workflow_sha text,
  p_github_repository text,
  p_github_repository_id text,
  p_github_ref text,
  p_github_workflow text,
  p_github_workflow_ref text,
  p_github_workflow_sha text,
  p_run_id bigint,
  p_run_attempt integer,
  p_event_name text,
  p_selftest_result_sha256 text,
  p_seed_commitment text,
  p_case_manifest_sha256 text,
  p_mutation_count integer,
  p_killed_count integer
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
begin
  raise exception 'AUD24_F03_EXTERNAL_AUTHORITY_UNRESOLVED';
end;
$function$;

create or replace function programacion.fn_guard_test_contract_hidden_authority_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
begin
  if tg_op='UPDATE' and old.status='DRAFT' and new.status='SEALED' then
    raise exception 'TEST_CONTRACT_EXTERNAL_HIDDEN_AUTHORITY_UNRESOLVED:%',new.task_id;
  end if;
  return new;
end;
$function$;

do $align$
declare
  vdef text;
begin
  select pg_get_functiondef('programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)'::regprocedure)
    into vdef;
  if position('pr.issuer_channel=''F03_OIDC_AUDITOR_V1''' in vdef)=0 then
    raise exception 'F03_FAIL_CLOSED_EXPECTED_CHANNEL_MARKER_MISSING';
  end if;
  if position('pr.issuer_channel=''F03_OIDC_AUDITOR_V1'' and false' in vdef)=0 then
    vdef:=replace(
      vdef,
      'pr.issuer_channel=''F03_OIDC_AUDITOR_V1''',
      'pr.issuer_channel=''F03_OIDC_AUDITOR_V1'' and false'
    );
    execute vdef;
  end if;
end;
$align$;

comment on function programacion.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer)
is 'Fail-closed after AUD24-F03 recurrence: OIDC run provenance alone is insufficient to assert semantic independence. Disabled until a non-Builder target-bound hidden authority is independently evidenced.';
comment on function programacion.fn_guard_test_contract_hidden_authority_v1()
is 'Fail-closed while AUD24-F03 external hidden authority remains unresolved. Existing SEALED contracts remain immutable historical evidence; new DRAFT->SEALED transitions are blocked.';
comment on function programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)
is 'Worker v10 authority context. F03_OIDC_AUDITOR_V1 receipts are historical but not accepted for hidden_ok after AUD24-F03 recurrence; external non-Builder authority remains required.';

do $selftest$
declare
  v_record text;
  v_guard text;
  v_ctx text;
begin
  select pg_get_functiondef('programacion.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer)'::regprocedure) into v_record;
  select pg_get_functiondef('programacion.fn_guard_test_contract_hidden_authority_v1()'::regprocedure) into v_guard;
  select pg_get_functiondef('programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)'::regprocedure) into v_ctx;
  if position('AUD24_F03_EXTERNAL_AUTHORITY_UNRESOLVED' in v_record)=0 then raise exception 'SELFTEST_F03_WRITER_NOT_BLOCKED'; end if;
  if position('TEST_CONTRACT_EXTERNAL_HIDDEN_AUTHORITY_UNRESOLVED' in v_guard)=0 then raise exception 'SELFTEST_F03_SEAL_GUARD_NOT_BLOCKED'; end if;
  if position('pr.issuer_channel=''F03_OIDC_AUDITOR_V1'' and false' in v_ctx)=0 then raise exception 'SELFTEST_F03_WORKER_CONTEXT_STILL_ACCEPTS_RECEIPT'; end if;
end;
$selftest$;
