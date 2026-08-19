create or replace function programacion.fn_functional_preparation_readiness(p_functional_version_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','programacion'
as $$
declare
  f public.lf_functional_versions%rowtype;
  s public.lf_user_stories%rowtype;
  v_authority jsonb;
  v_repo jsonb;
  v_unresolved jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_ready_to_seal boolean := true;
  v_ready_for_task boolean := true;
begin
  select * into f from public.lf_functional_versions where id=p_functional_version_id;
  if f.id is null then raise exception 'functional version % not found',p_functional_version_id; end if;
  select * into s from public.lf_user_stories where story_code=f.story_code;
  if s.story_code is null then raise exception 'story % not found',f.story_code; end if;

  v_authority := programacion.fn_source_rule_authority(f.source_rule_codes);

  select jsonb_build_object(
    'decision_id',d.id_decision,
    'decision_number',d.decision_number,
    'status',d.estado_normalizado,
    'repo_full_name',d.raw_payload->>'repo_full_name',
    'branch',d.raw_payload->>'branch',
    'pinned_head_sha',d.raw_payload->>'pinned_head_sha',
    'write_authorized',coalesce((d.raw_payload->>'write_authorized')::boolean,false),
    'production_authorized',coalesce((d.raw_payload->>'production_authorized')::boolean,false),
    'requires_head_revalidation_before_execution',coalesce((d.raw_payload->>'requires_head_revalidation_before_execution')::boolean,true)
  ) into v_repo
  from public.lf_decisiones_gov d
  where d.estado_normalizado='APROBADO_READ_ONLY'
    and d.raw_payload->>'decision_type'='TECHNICAL_REPOSITORY_BINDING'
    and coalesce((d.raw_payload->>'read_only_preparation')::boolean,false)=true
    and (
      d.raw_payload->>'story_code'=f.story_code
      or (d.raw_payload->>'story_code' is null and d.raw_payload->>'module_code'=s.module_code)
    )
  order by case when d.raw_payload->>'story_code'=f.story_code then 0 else 1 end, d.updated_at desc, d.decision_number desc
  limit 1;

  with deps as (
    select value #>> '{}' as dependency_text
    from jsonb_array_elements(coalesce(s.dependencies,'[]'::jsonb))
    where jsonb_typeof(value)='string'
  )
  select coalesce(jsonb_agg(dependency_text order by dependency_text),'[]'::jsonb)
  into v_unresolved
  from deps x
  where not exists (
    select 1
    from public.lf_decisiones_gov d
    where d.estado_normalizado='APROBADO_READ_ONLY'
      and d.raw_payload->>'decision_type'='STORY_DEPENDENCY_CLASSIFICATION'
      and d.raw_payload->>'story_code'=f.story_code
      and d.raw_payload->>'dependency_text'=x.dependency_text
      and d.raw_payload->>'classification' in ('IN_TASK_IMPLEMENTATION','EXTERNAL_RESOLVED','PREDECESSOR_TASK')
  );

  if coalesce((v_authority->>'authoritative')::boolean,false) is not true then
    v_ready_to_seal:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','SOURCE_RULE_AUTHORITY_BLOCKED','owner_type','FUNCTIONAL_RULE_OWNER',
      'required_action','PROMOTE_SOURCE_RULES_TO_APROBADO_OR_VIGENTE',
      'source_ref','functional-version://'||f.id,
      'details',v_authority->'problems'));
  end if;

  if v_repo is null then
    v_ready_to_seal:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','TECHNICAL_REPOSITORY_UNRESOLVED','owner_type','TECHNICAL_OWNER',
      'required_action','REGISTER_APPROVED_READ_ONLY_REPOSITORY_BINDING',
      'source_ref','story://'||f.story_code));
  end if;

  if jsonb_array_length(v_unresolved)>0 then
    v_ready_to_seal:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','DEPENDENCY_CLASSIFICATION_REQUIRED','owner_type','TASK_PREPARATION',
      'required_action','CLASSIFY_STORY_DEPENDENCIES',
      'source_ref','story://'||f.story_code,
      'details',v_unresolved));
  end if;

  v_ready_for_task := v_ready_to_seal and f.status='SEALED';
  if f.status<>'SEALED' then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','FUNCTIONAL_VERSION_NOT_SEALED','owner_type','FUNCTIONAL_OWNER',
      'required_action',case when v_ready_to_seal then 'SEAL_FUNCTIONAL_VERSION' else 'RESOLVE_PRE_TASK_BLOCKERS_THEN_SEAL' end,
      'source_ref','functional-version://'||f.id));
  end if;

  return jsonb_build_object(
    'functional_version_id',f.id,
    'artifact_code',f.artifact_code,
    'story_code',f.story_code,
    'status',f.status,
    'ready_to_seal',v_ready_to_seal,
    'ready_for_task',v_ready_for_task,
    'source_rule_authority',v_authority,
    'repository_resolution',v_repo,
    'unresolved_dependencies',v_unresolved,
    'blockers',v_blockers
  );
end;
$$;

revoke all on function programacion.fn_functional_preparation_readiness(bigint) from public;
grant execute on function programacion.fn_functional_preparation_readiness(bigint) to programacion_builder,programacion_auditor,programacion_verifier,programacion_human_authority;

create or replace view programacion.v_functional_pre_task_blockers
with (security_invoker=true)
as
select
  f.id as functional_version_id,
  f.artifact_code,
  f.story_code,
  b->>'code' as blocker_code,
  b->>'owner_type' as owner_type,
  b->>'required_action' as required_action,
  b->>'source_ref' as source_ref,
  b->'details' as details
from public.lf_functional_versions f
cross join lateral jsonb_array_elements(programacion.fn_functional_preparation_readiness(f.id)->'blockers') b
where not exists (
  select 1 from public.lf_functional_versions n where n.supersedes_version_id=f.id
);

revoke all on programacion.v_functional_pre_task_blockers from public;
grant select on programacion.v_functional_pre_task_blockers to programacion_builder,programacion_auditor,programacion_verifier,programacion_human_authority;

do $$
declare v_def text;
begin
  select pg_get_functiondef('programacion.fn_task_readiness(bigint)'::regprocedure) into v_def;
  if position('REVIEW_SPLIT' in v_def)=0 then
    raise exception 'expected REVIEW_SPLIT marker missing from fn_task_readiness';
  end if;
  v_def:=replace(v_def,'''REVIEW_SPLIT''','''DECOMPOSE_REQUIRED''');
  v_def:=replace(v_def,'''SIZING_REVIEW_SPLIT''','''SIZING_DECOMPOSE_REQUIRED''');
  execute v_def;

  select pg_get_functiondef('programacion.fn_guard_agent_task()'::regprocedure) into v_def;
  if position('REVIEW_SPLIT' in v_def)=0 then
    raise exception 'expected REVIEW_SPLIT marker missing from fn_guard_agent_task';
  end if;
  v_def:=replace(v_def,'task sizing REVIEW_SPLIT','task sizing DECOMPOSE_REQUIRED');
  execute v_def;
end;
$$;