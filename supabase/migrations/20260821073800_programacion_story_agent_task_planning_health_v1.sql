-- Story -> Agent Task planning health.
-- Scope: planning/readback only. Does not create tasks, mutate source screens, or authorize execution.

create or replace function programacion.fn_story_task_plan_health(p_functional_version_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','public','programacion'
as $$
with f as (
  select
    v.id,
    v.artifact_code,
    v.artifact_type,
    v.story_code,
    v.version_no,
    v.status,
    v.supersedes_version_id,
    v.content_sha256,
    programacion.fn_p0_json_codes(v.acceptance_criteria,'AC') as required_ac,
    programacion.fn_p0_json_codes(v.invariants,'INV') as required_inv,
    programacion.fn_p0_json_codes(v.negative_controls,'NEG') as required_neg
  from public.lf_functional_versions v
  where v.id=p_functional_version_id
), tasks as (
  select
    t.id,
    t.task_code,
    t.task_version,
    t.definition_status,
    t.acceptance_refs,
    t.invariant_refs,
    t.negative_refs,
    t.write_path_patterns,
    programacion.fn_task_readiness(t.id) as readiness
  from programacion.agent_tasks t
  where t.functional_version_id=p_functional_version_id
    and not exists (
      select 1
      from programacion.agent_tasks n
      where n.supersedes_task_id=t.id
    )
), ac_owners as (
  select x.ref,count(*)::integer as owner_count
  from tasks t
  cross join lateral unnest(t.acceptance_refs) x(ref)
  group by x.ref
), inv_owners as (
  select x.ref,count(*)::integer as owner_count
  from tasks t
  cross join lateral unnest(t.invariant_refs) x(ref)
  group by x.ref
), neg_owners as (
  select x.ref,count(*)::integer as owner_count
  from tasks t
  cross join lateral unnest(t.negative_refs) x(ref)
  group by x.ref
), coverage as (
  select
    coalesce((select array_agg(x order by x) from f cross join lateral unnest(f.required_ac) x where not exists (select 1 from ac_owners o where o.ref=x)),'{}'::text[]) as missing_ac,
    coalesce((select array_agg(x order by x) from f cross join lateral unnest(f.required_inv) x where not exists (select 1 from inv_owners o where o.ref=x)),'{}'::text[]) as missing_inv,
    coalesce((select array_agg(x order by x) from f cross join lateral unnest(f.required_neg) x where not exists (select 1 from neg_owners o where o.ref=x)),'{}'::text[]) as missing_neg,
    coalesce((select array_agg(ref order by ref) from ac_owners where owner_count>1),'{}'::text[]) as multi_owner_ac,
    coalesce((select array_agg(ref order by ref) from inv_owners where owner_count>1),'{}'::text[]) as multi_owner_inv,
    coalesce((select array_agg(ref order by ref) from neg_owners where owner_count>1),'{}'::text[]) as multi_owner_neg
), stats as (
  select
    count(*)::integer as task_count,
    count(*) filter (where definition_status='SEALED')::integer as sealed_task_count,
    count(*) filter (where definition_status='DRAFT')::integer as draft_task_count,
    count(*) filter (
      where coalesce(readiness->>'sizing_policy_status','')<>'CALIBRATED'
    )::integer as sizing_policy_missing_count,
    coalesce(
      array_agg(distinct readiness->>'sizing_profile_code' order by readiness->>'sizing_profile_code')
        filter (where nullif(readiness->>'sizing_profile_code','') is not null),
      '{}'::text[]
    ) as sizing_profile_codes,
    coalesce(
      array_agg(task_code order by task_code),
      '{}'::text[]
    ) as current_task_codes
  from tasks
), dag as (
  select programacion.fn_task_dag_metrics(p_functional_version_id) as metrics
), assembled as (
  select
    f.*,
    c.*,
    s.*,
    d.metrics,
    cardinality(c.missing_ac) as missing_ac_count,
    cardinality(c.missing_inv) as missing_inv_count,
    cardinality(c.missing_neg) as missing_neg_count,
    coalesce((d.metrics->>'pure_chain')::boolean,false) as pure_chain,
    coalesce((d.metrics->>'edge_count')::integer,0) as edge_count,
    coalesce((d.metrics->>'branch_count')::integer,0) as branch_count
  from f
  cross join coverage c
  cross join stats s
  cross join dag d
), classified as (
  select
    a.*,
    case
      when a.status<>'SEALED' then 'FUNCTIONAL_VERSION_NOT_SEALED'
      when a.task_count=0 then 'PLAN_REQUIRED'
      when a.missing_ac_count+a.missing_inv_count+a.missing_neg_count>0 then 'COVERAGE_GAP'
      when a.sealed_task_count<a.task_count then 'TASK_DEFINITIONS_PENDING'
      when a.sizing_policy_missing_count>0 then 'SIZING_POLICY_MISSING'
      when a.pure_chain then 'RECOMBINE_REQUIRED'
      when a.task_count=1 then 'SINGLE_TASK_JUSTIFIED'
      when a.branch_count>0 then 'MULTI_TASK_BRANCHED'
      when a.edge_count=0 then 'MULTI_TASK_PARALLEL'
      else 'MULTI_TASK_DEPENDENCY_PLAN'
    end as plan_state
  from assembled a
)
select coalesce(
  (
    select jsonb_build_object(
      'schema_version',1,
      'functional_version_id',c.id,
      'artifact_code',c.artifact_code,
      'artifact_type',c.artifact_type,
      'story_code',c.story_code,
      'functional_version_no',c.version_no,
      'functional_status',c.status,
      'functional_sha256',c.content_sha256,
      'supersedes_functional_version_id',c.supersedes_version_id,
      'task_count',c.task_count,
      'sealed_task_count',c.sealed_task_count,
      'draft_task_count',c.draft_task_count,
      'current_task_codes',to_jsonb(c.current_task_codes),
      'coverage',jsonb_build_object(
        'required_acceptance_count',cardinality(c.required_ac),
        'required_invariant_count',cardinality(c.required_inv),
        'required_negative_count',cardinality(c.required_neg),
        'missing_acceptance_refs',to_jsonb(c.missing_ac),
        'missing_invariant_refs',to_jsonb(c.missing_inv),
        'missing_negative_refs',to_jsonb(c.missing_neg),
        'multi_owner_acceptance_refs',to_jsonb(c.multi_owner_ac),
        'multi_owner_invariant_refs',to_jsonb(c.multi_owner_inv),
        'multi_owner_negative_refs',to_jsonb(c.multi_owner_neg)
      ),
      'sizing',jsonb_build_object(
        'policy_missing_task_count',c.sizing_policy_missing_count,
        'profile_codes',to_jsonb(c.sizing_profile_codes)
      ),
      'dag',c.metrics,
      'plan_state',c.plan_state,
      'plan_ready',c.plan_state in ('SINGLE_TASK_JUSTIFIED','MULTI_TASK_BRANCHED','MULTI_TASK_PARALLEL','MULTI_TASK_DEPENDENCY_PLAN'),
      'next_action',case c.plan_state
        when 'FUNCTIONAL_VERSION_NOT_SEALED' then 'SEAL_FUNCTIONAL_VERSION'
        when 'PLAN_REQUIRED' then 'CREATE_AGENT_TASK_PLAN'
        when 'COVERAGE_GAP' then 'ASSIGN_UNOWNED_AC_INV_NEG_TO_TASKS'
        when 'TASK_DEFINITIONS_PENDING' then 'COMPLETE_AND_SEAL_TASK_DEFINITIONS'
        when 'SIZING_POLICY_MISSING' then 'CALIBRATE_OR_SELECT_EXACT_REPOSITORY_MODULE_PROFILE'
        when 'RECOMBINE_REQUIRED' then 'RECOMBINE_ARTIFICIAL_PURE_CHAIN'
        else 'PLAN_READY_FOR_TEST_CONTRACT_AND_BACKLOG_GATES'
      end,
      'authority_model','DERIVED_FROM_SEALED_FUNCTIONAL_VERSION_AND_CURRENT_AGENT_TASKS',
      'execution_authorized',false
    )
    from classified c
  ),
  jsonb_build_object(
    'schema_version',1,
    'functional_version_id',p_functional_version_id,
    'plan_state','FUNCTIONAL_VERSION_NOT_FOUND',
    'plan_ready',false,
    'next_action','RESOLVE_FUNCTIONAL_VERSION',
    'authority_model','DERIVED_FROM_CANONICAL_SUPABASE',
    'execution_authorized',false
  )
)
$$;

revoke all on function programacion.fn_story_task_plan_health(bigint) from public;
grant execute on function programacion.fn_story_task_plan_health(bigint)
  to programacion_builder,programacion_auditor,programacion_verifier,programacion_human_authority;

create or replace view programacion.v_story_task_plan_health_v1
with (security_invoker = true)
as
select
  f.id as functional_version_id,
  f.artifact_code,
  f.story_code,
  f.version_no,
  programacion.fn_story_task_plan_health(f.id) as plan_health
from public.lf_functional_versions f
where not exists (
  select 1
  from public.lf_functional_versions n
  where n.supersedes_version_id=f.id
);

revoke all on programacion.v_story_task_plan_health_v1 from public;
grant select on programacion.v_story_task_plan_health_v1
  to programacion_builder,programacion_auditor,programacion_verifier,programacion_human_authority;
