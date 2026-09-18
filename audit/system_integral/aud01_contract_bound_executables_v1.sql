-- AUD-1 declared contract-bound executables/judges V1
-- Read-only. Complements aud01_repo_universe_v1.py; no filename heuristics.
with bound as (
  select distinct b.operation_code,b.judge_code,j.judge_path,j.status as judge_status,b.status as binding_status
  from public.lf_operation_step_judge_bindings b
  join public.lf_operation_judges j
    on j.operation_code=b.operation_code and j.judge_code=b.judge_code
  where b.status='ACTIVE_ENFORCEMENT'
)
select jsonb_build_object(
  'binding_rows',(select count(*) from public.lf_operation_step_judge_bindings where status='ACTIVE_ENFORCEMENT'),
  'distinct_bound_judges',(select count(distinct operation_code||'|'||judge_code) from bound),
  'distinct_declared_paths',(select count(distinct judge_path) from bound where nullif(btrim(coalesce(judge_path,'')),'') is not null),
  'repo_paths',coalesce((
    select jsonb_agg(distinct judge_path order by judge_path)
    from bound
    where judge_path !~ '^[a-z]+://' and judge_path like '%/%'
  ),'[]'::jsonb),
  'github_paths',coalesce((
    select jsonb_agg(distinct judge_path order by judge_path)
    from bound where judge_path like 'github://%'
  ),'[]'::jsonb),
  'supabase_refs',coalesce((
    select jsonb_agg(distinct judge_path order by judge_path)
    from bound where judge_path like 'supabase://%' or judge_path like 'public.%'
  ),'[]'::jsonb)
) as aud01_contract_bound_executables;
