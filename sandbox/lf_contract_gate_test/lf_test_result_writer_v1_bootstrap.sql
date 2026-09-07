create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create or replace function private.fn_payload_sha256_v7(p_payload jsonb)
returns text language sql immutable strict set search_path to '' as $$
  select encode(extensions.digest(convert_to(p_payload::text,'UTF8'),'sha256'),'hex');
$$;
create table public.lf_test_suite_runs(
  suite_run_id uuid primary key default gen_random_uuid(), suite_code text not null, execution_id text,
  environment text not null, application_version text, commit_sha text, rule_set_version text,
  executor_type text not null, executor_name text, status text not null default 'QUEUED',
  started_at timestamptz, completed_at timestamptz, duration_ms bigint,
  tests_total int not null default 0, tests_passed int not null default 0, tests_failed int not null default 0,
  tests_blocked int not null default 0, tests_review_required int not null default 0,
  rules_covered text[] not null default '{}', stories_covered text[] not null default '{}', contracts_covered text[] not null default '{}',
  manifest jsonb not null default '{}', metadata jsonb not null default '{}', created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), created_by_execution_id text not null default 'UNKNOWN', updated_by_execution_id text
);
create table public.lf_test_suite_cases(
  suite_code text not null, test_code text not null, primary key(suite_code,test_code)
);
create table public.lf_test_runs(
  test_run_id uuid primary key default gen_random_uuid(), suite_run_id uuid not null references public.lf_test_suite_runs(suite_run_id) on delete cascade,
  suite_code text not null, test_code text not null, execution_id text, operation_code text, rule_codes text[] not null default '{}', story_code text,
  contract_codes text[] not null default '{}', environment text not null, application_version text, commit_sha text, rule_set_version text,
  executor_type text not null, executor_name text, attempt_no int not null default 1, status text not null default 'QUEUED',
  input_payload jsonb not null default '{}', expected_output jsonb not null default '{}', actual_output jsonb not null default '{}',
  error_code text, error_detail text, severity text not null default 'MEDIUM', started_at timestamptz, completed_at timestamptz, duration_ms bigint,
  evidence_payload jsonb not null default '{}', metadata jsonb not null default '{}', created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), created_by_execution_id text not null default 'UNKNOWN', updated_by_execution_id text,
  foreign key(suite_code,test_code) references public.lf_test_suite_cases(suite_code,test_code)
);
create table public.lf_test_assertion_results(
  assertion_result_id uuid primary key default gen_random_uuid(), test_run_id uuid not null references public.lf_test_runs(test_run_id) on delete cascade,
  assertion_code text not null, assertion_order int not null, assertion_type text not null, description text not null,
  expected_value jsonb not null default 'null', actual_value jsonb not null default 'null', operator text, status text not null,
  severity text not null default 'MEDIUM', failure_reason text, evidence_payload jsonb not null default '{}', observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(), metadata jsonb not null default '{}', created_by_execution_id text not null default 'UNKNOWN',
  updated_by_execution_id text, updated_at timestamptz,
  unique(test_run_id,assertion_code), unique(test_run_id,assertion_order)
);
create table public.lf_test_judge_results(
  judge_result_id uuid primary key default gen_random_uuid(), test_run_id uuid not null references public.lf_test_runs(test_run_id) on delete cascade,
  judge_code text not null, judge_type text not null, model_name text, model_version text, prompt_version text, verdict text not null, confidence numeric,
  severity text not null default 'MEDIUM', findings jsonb not null default '[]', evidence_payload jsonb not null default '{}', rationale_summary text,
  observed_at timestamptz not null default now(), created_at timestamptz not null default now(), metadata jsonb not null default '{}',
  created_by_execution_id text not null default 'UNKNOWN', updated_by_execution_id text, updated_at timestamptz,
  unique(test_run_id,judge_code)
);
create table public.lf_test_artifacts(
  artifact_id uuid primary key default gen_random_uuid(), suite_run_id uuid references public.lf_test_suite_runs(suite_run_id) on delete cascade,
  test_run_id uuid references public.lf_test_runs(test_run_id) on delete cascade, artifact_type text not null, name text not null,
  storage_provider text not null, storage_ref text not null, sha256 text, mime_type text, size_bytes bigint, metadata jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by_execution_id text not null default 'UNKNOWN', updated_by_execution_id text, updated_at timestamptz
);
insert into public.lf_test_suite_runs(
 suite_run_id,suite_code,environment,commit_sha,executor_type,executor_name,status,created_by_execution_id
) values (
 '11111111-1111-4111-8111-111111111111','TS-S27-WRITER-V1','SANDBOX','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','HARNESS','P9_WRITER_TEST','RUNNING','BOOTSTRAP'
);
insert into public.lf_test_suite_cases(suite_code,test_code) values
 ('TS-S27-WRITER-V1','CASE-POS'),('TS-S27-WRITER-V1','CASE-HASH'),('TS-S27-WRITER-V1','CASE-HEAD'),
 ('TS-S27-WRITER-V1','CASE-CHANNEL'),('TS-S27-WRITER-V1','CASE-JUDGE'),('TS-S27-WRITER-V1','CASE-ORIGIN');