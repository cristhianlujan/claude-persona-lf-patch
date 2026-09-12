alter table programacion.provenance_channels disable trigger trg_provenance_channels_immutable;
insert into programacion.provenance_channels(channel_code,secret_sha256,allowed_kinds,description)
select 'F03_OIDC_AUDITOR_V1', secret_sha256, array['AUDIT_VERDICT']::text[],
       'AUD24-F03 machine auditor bound to GitHub reusable-workflow OIDC; channel token is internal provenance transport only'
from programacion.provenance_channels
where channel_code='EVIDENCE_VERIFIER_V1'
on conflict (channel_code) do update
set secret_sha256=excluded.secret_sha256,
    allowed_kinds=excluded.allowed_kinds,
    description=excluded.description;
alter table programacion.provenance_channels enable trigger trg_provenance_channels_immutable;

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
declare
  v_task programacion.agent_tasks%rowtype;
  v_current_task_id bigint;
  v_expected_generation_source text;
  v_policy_id text;
  v_hidden_ref text;
  v_hidden_sha text;
  v_broker_sha text;
  v_subject_sha text;
  v_identity text;
  v_verification_ref text;
  v_payload jsonb;
  v_token text;
  v_token_hash text;
  v_channel_hash text;
  v_receipt_id bigint;
  v_receipt_sha text;
begin
  if p_task_id is null or p_task_id < 1 then raise exception 'F03_TASK_ID_INVALID'; end if;
  select * into v_task from programacion.agent_tasks where id=p_task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then raise exception 'F03_CURRENT_SEALED_TASK_REQUIRED'; end if;
  select t.id into v_current_task_id
  from programacion.agent_tasks t
  where t.task_code=v_task.task_code and t.definition_status='SEALED'
  order by t.task_version desc,t.id desc limit 1;
  if v_current_task_id is distinct from p_task_id then raise exception 'F03_CURRENT_TASK_REQUIRED:% current=%',p_task_id,v_current_task_id; end if;
  if p_task_sha256 is distinct from v_task.task_sha256 then raise exception 'F03_TASK_SHA_MISMATCH'; end if;
  select to_jsonb(r)->>'generation_source_sha256' into v_expected_generation_source
  from programacion.fn_test_contract_generation_source(p_task_id) r;
  if p_generation_source_sha256 is distinct from v_expected_generation_source then raise exception 'F03_GENERATION_SOURCE_SHA_MISMATCH'; end if;

  if p_github_repository<>'cristhianlujan/libertad-financiera' or p_github_repository_id<>'1301234955' then raise exception 'F03_OIDC_REPOSITORY_MISMATCH'; end if;
  if p_github_ref<>'refs/heads/story-agent-f03-oidc-probe' then raise exception 'F03_OIDC_REF_MISMATCH'; end if;
  if p_github_workflow<>'Story Agent F03 OIDC Probe' then raise exception 'F03_OIDC_WORKFLOW_MISMATCH'; end if;
  if p_github_workflow_ref<>'cristhianlujan/libertad-financiera/.github/workflows/story-agent-f03-oidc-probe.yml@refs/heads/story-agent-f03-oidc-probe' then raise exception 'F03_OIDC_WORKFLOW_REF_MISMATCH'; end if;
  if p_job_workflow_ref<>'cristhianlujan/programming-agent/.github/workflows/story-agent-hidden-authority-v1.yml@refs/heads/story-agent-f03-mutation-oracle-v1' then raise exception 'F03_OIDC_JOB_WORKFLOW_REF_MISMATCH'; end if;
  if coalesce(p_job_workflow_sha,'')!~'^[0-9a-f]{40}$' or coalesce(p_github_workflow_sha,'')!~'^[0-9a-f]{40}$' then raise exception 'F03_OIDC_WORKFLOW_SHA_INVALID'; end if;
  if p_run_id is null or p_run_id<1 or p_run_attempt is null or p_run_attempt<1 or p_event_name<>'push' then raise exception 'F03_OIDC_RUN_BINDING_INVALID'; end if;
  if coalesce(p_selftest_result_sha256,'')!~'^[0-9a-f]{64}$' or coalesce(p_seed_commitment,'')!~'^[0-9a-f]{64}$' or coalesce(p_case_manifest_sha256,'')!~'^[0-9a-f]{64}$' then raise exception 'F03_SELFTEST_DIGEST_INVALID'; end if;
  if p_mutation_count<8 or p_killed_count<>p_mutation_count then raise exception 'F03_SELFTEST_MUTATION_SENSITIVITY_REQUIRED'; end if;

  v_policy_id:=encode(extensions.digest(convert_to('F03_OIDC_MUTATION_ORACLE_V1|receipt_contract=4|seed=github_oidc|source=generic_runtime_mutation|minimum_mutants=8|required_kill_ratio=1.0|hidden_output=hash_only','UTF8'),'sha256'),'hex');
  v_hidden_sha:=v_policy_id;
  v_hidden_ref:='github-oidc://cristhianlujan/programming-agent/.github/workflows/story-agent-hidden-authority-v1.yml@'||p_job_workflow_sha||'#policy='||v_policy_id;
  v_broker_sha:=encode(extensions.digest(convert_to(p_job_workflow_ref||'@'||p_job_workflow_sha,'UTF8'),'sha256'),'hex');
  v_subject_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,
    'finding_code','AUD24-F03',
    'agent_task_id',v_task.id,
    'task_sha256',v_task.task_sha256,
    'hidden_oracle_ref',v_hidden_ref,
    'hidden_oracle_sha256',v_hidden_sha,
    'generation_source_sha256',p_generation_source_sha256
  ));
  v_identity:='github-actions://'||p_job_workflow_ref||'#run-'||p_run_id::text||'-attempt-'||p_run_attempt::text;
  v_verification_ref:='github-actions://cristhianlujan/libertad-financiera/actions/runs/'||p_run_id::text||'/attempts/'||p_run_attempt::text;
  v_payload:=jsonb_build_object(
    'schema_version',1,
    'head_sha',p_job_workflow_sha,
    'subject_type','hidden_oracle_audit',
    'subject_ref','agent-task://'||v_task.id::text||'/hidden-oracle',
    'subject_sha256',v_subject_sha,
    'verdict','PASS',
    'independent',true,
    'auditor_identity',v_identity,
    'finding_code','AUD24-F03',
    'semantic_nonreconstructibility_verified',true,
    'replay_binding_verified',true,
    'hidden_output_nonexposure_verified',true,
    'agent_task_id',v_task.id::text,
    'task_sha256',v_task.task_sha256,
    'hidden_oracle_ref',v_hidden_ref,
    'hidden_oracle_sha256',v_hidden_sha,
    'generation_source_sha256',p_generation_source_sha256,
    'audited_head_sha',p_job_workflow_sha,
    'broker_function_sha256',v_broker_sha,
    'broker_policy_id',v_policy_id,
    'receipt_contract_version','4',
    'github_repository',p_github_repository,
    'github_repository_id',p_github_repository_id,
    'github_ref',p_github_ref,
    'github_workflow',p_github_workflow,
    'github_workflow_ref',p_github_workflow_ref,
    'github_workflow_sha',p_github_workflow_sha,
    'job_workflow_ref',p_job_workflow_ref,
    'job_workflow_sha',p_job_workflow_sha,
    'run_id',p_run_id::text,
    'run_attempt',p_run_attempt::text,
    'event_name',p_event_name,
    'selftest_result_sha256',p_selftest_result_sha256,
    'seed_commitment',p_seed_commitment,
    'case_manifest_sha256',p_case_manifest_sha256,
    'mutation_count',p_mutation_count,
    'killed_count',p_killed_count,
    'hidden_output','HASH_ONLY'
  );

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='EVIDENCE_VERIFIER_V1_TOKEN'
  order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'F03_INTERNAL_PROVENANCE_TOKEN_MISSING'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');
  select secret_sha256 into v_channel_hash from programacion.provenance_channels where channel_code='F03_OIDC_AUDITOR_V1';
  if v_channel_hash is distinct from v_token_hash then raise exception 'F03_INTERNAL_PROVENANCE_CHANNEL_MISMATCH'; end if;

  select id,receipt_sha256 into v_receipt_id,v_receipt_sha
  from programacion.issue_provenance_receipt(
    'F03_OIDC_AUDITOR_V1',v_token,'AUDIT_VERDICT',null,p_job_workflow_sha,
    'hidden_oracle_audit','agent-task://'||v_task.id::text||'/hidden-oracle',v_subject_sha,
    v_identity,v_verification_ref,v_payload
  );
  return jsonb_build_object(
    'status','ATTESTED',
    'authority_receipt_id',v_receipt_id,
    'authority_receipt_sha256',v_receipt_sha,
    'hidden_oracle_ref',v_hidden_ref,
    'hidden_oracle_sha256',v_hidden_sha,
    'generation_source_sha256',p_generation_source_sha256,
    'broker_policy_id',v_policy_id,
    'broker_function_sha256',v_broker_sha
  );
end;
$function$;
revoke all on function programacion.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function programacion.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer) to service_role;

create or replace function programacion.fn_guard_test_contract_hidden_authority_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_task programacion.agent_tasks%rowtype;
  v_subject_sha text;
  v_audit_receipt_id bigint;
begin
  if tg_op<>'UPDATE' or old.status<>'DRAFT' or new.status<>'SEALED' then return new; end if;
  select * into v_task from programacion.agent_tasks where id=new.task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then raise exception 'TEST_CONTRACT_CURRENT_TASK_REQUIRED:%',new.task_id; end if;
  if exists(
    select 1 from programacion.agent_tasks t
    where t.task_code=v_task.task_code and t.definition_status='SEALED'
      and (t.task_version>v_task.task_version or (t.task_version=v_task.task_version and t.id>v_task.id))
  ) then raise exception 'TEST_CONTRACT_CURRENT_TASK_REQUIRED:%',new.task_id; end if;

  v_subject_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,
    'finding_code','AUD24-F03',
    'agent_task_id',v_task.id,
    'task_sha256',v_task.task_sha256,
    'hidden_oracle_ref',new.hidden_oracle_ref,
    'hidden_oracle_sha256',new.hidden_oracle_sha256,
    'generation_source_sha256',new.generation_source_sha256
  ));

  select pr.id into v_audit_receipt_id
  from programacion.provenance_receipts pr
  where pr.receipt_kind='AUDIT_VERDICT'
    and pr.execution_id is null
    and pr.issuer_channel='F03_OIDC_AUDITOR_V1'
    and pr.subject_type='hidden_oracle_audit'
    and pr.subject_ref='agent-task://'||v_task.id::text||'/hidden-oracle'
    and pr.subject_sha256=v_subject_sha
    and pr.payload->>'verdict'='PASS'
    and pr.payload->'independent'='true'::jsonb
    and length(btrim(coalesce(pr.payload->>'auditor_identity','')))>0
    and pr.payload->>'finding_code'='AUD24-F03'
    and pr.payload->'semantic_nonreconstructibility_verified'='true'::jsonb
    and pr.payload->'replay_binding_verified'='true'::jsonb
    and pr.payload->'hidden_output_nonexposure_verified'='true'::jsonb
    and pr.payload->>'agent_task_id'=v_task.id::text
    and pr.payload->>'task_sha256'=coalesce(v_task.task_sha256,'')
    and pr.payload->>'hidden_oracle_ref'=new.hidden_oracle_ref
    and pr.payload->>'hidden_oracle_sha256'=new.hidden_oracle_sha256
    and pr.payload->>'generation_source_sha256'=new.generation_source_sha256
    and pr.payload->>'audited_head_sha'=pr.head_sha
    and pr.payload->>'job_workflow_sha'=pr.head_sha
    and pr.payload->>'github_repository'='cristhianlujan/libertad-financiera'
    and pr.payload->>'event_name'='push'
    and coalesce(pr.payload->>'run_id','')~'^[1-9][0-9]*$'
    and coalesce(pr.payload->>'run_attempt','')~'^[1-9][0-9]*$'
    and coalesce(pr.payload->>'broker_function_sha256','')~'^[0-9a-f]{64}$'
    and pr.payload->>'broker_policy_id'=new.hidden_oracle_sha256
    and coalesce(pr.payload->>'receipt_contract_version','')~'^[0-9]+$'
    and (pr.payload->>'receipt_contract_version')::integer>=4
    and coalesce((pr.payload->>'mutation_count')::integer,0)>=8
    and (pr.payload->>'killed_count')::integer=(pr.payload->>'mutation_count')::integer
  order by pr.id desc limit 1;

  if v_audit_receipt_id is null then raise exception 'TEST_CONTRACT_INDEPENDENT_HIDDEN_AUTHORITY_REQUIRED:%',new.task_id; end if;
  return new;
end;
$function$;

comment on function programacion.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer)
is 'AUD24-F03 receipt writer. GitHub reusable-workflow OIDC is authority; service_role and the provenance token are transport only. Hidden challenge outputs are represented by digests/counts only.';