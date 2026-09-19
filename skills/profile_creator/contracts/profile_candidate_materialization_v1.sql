-- PROFILE_CANDIDATE_MATERIALIZATION_V1
-- SOURCE_ONLY_NOT_DEPLOYED
-- Owner: S22 / CREACION_PERFIL_LF
-- Purpose: materialize a Profile candidate in public.lf_activos only after a clean
-- GitHub readback, preserving CANDIDATO/READ_ONLY/NO_HABILITADO/BLOQUEADO.
-- This file is NOT a migration and MUST NOT be applied directly. A future governed
-- migration must reserve one immutable migration identity first and bind governance
-- table mutations to an authorized provenance route.

create or replace function public.lf_profile_candidate_materialize_v1(
  p_execution_id text,
  p_profile_pack_id text,
  p_display_name text,
  p_version text default 'v0.1',
  p_source_pr integer default null,
  p_actor_execution_id text default null
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public','extensions'
as $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_step public.lf_operation_steps%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_readback public.lf_operation_execution_steps%rowtype;
  v_existing public.lf_activos%rowtype;
  v_inserted public.lf_activos%rowtype;
  v_actor text;
  v_repo text;
  v_branch text;
  v_commit text;
  v_tree text;
  v_entrypoint text;
  v_slug text;
  v_source_row integer;
begin
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_profile_pack_id,''))='' or btrim(coalesce(p_display_name,''))='' then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_INPUT_INVALID';
  end if;

  v_actor := coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  if v_actor <> p_execution_id then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_ACTOR_MUST_EQUAL_CREATOR_EXECUTION';
  end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_EXECUTION_NOT_FOUND:%',p_execution_id;
  end if;
  if v_exec.operation_code<>'CREACION_PERFIL_LF' or v_exec.target_type<>'PERFIL' then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_EXECUTION_SCOPE_MISMATCH';
  end if;
  if v_exec.status<>'IN_PROGRESS' then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_EXECUTION_NOT_ACTIVE:%',v_exec.status;
  end if;
  if btrim(coalesce(v_exec.target_code,''))='' or btrim(coalesce(v_exec.target_repo,''))='' or btrim(coalesce(v_exec.target_path,''))='' then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_TARGET_INCOMPLETE';
  end if;
  if v_exec.target_path !~ '^profiles/[a-z0-9_/-]+$' then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_TARGET_PATH_INVALID:%',v_exec.target_path;
  end if;

  select * into v_step
  from public.lf_operation_steps
  where operation_code='CREACION_PERFIL_LF' and step_id='github_readback' and active=true;
  if not found then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_READBACK_STEP_MISSING';
  end if;

  select * into v_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='CREACION_PERFIL_LF'
    and step_id='github_readback'
    and step_order=v_step.step_order
    and status='ACTIVE_ENFORCEMENT';
  if not found then
    raise exception 'LF_PROFILE_CANDIDATE_MATERIALIZE_READBACK_BINDING_MISSING';
  end if;

  select * into v_readback
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id
    and step_order=v_step.step_order
    and step_id='github_readback';
  if not found then
    raise exception 'LF_PROFILE_CANDIDATE_SOURCE_READBACK_MISSING';
  end if;
  if v_readback.status<>v_binding.clean_result_value then
    raise exception 'LF_PROFILE_CANDIDATE_SOURCE_READBACK_NOT_CLEAN:%',v_readback.status;
  end if;
  if coalesce(v_readback.evidence_payload->>'sha_match_status','')<>'PASS' then
    raise exception 'LF_PROFILE_CANDIDATE_SOURCE_SHA_NOT_VERIFIED';
  end if;

  v_repo := btrim(coalesce(v_readback.evidence_payload->>'repo',''));
  v_branch := btrim(coalesce(v_readback.evidence_payload->>'branch',''));
  v_commit := btrim(coalesce(v_readback.evidence_payload->>'commit_sha',''));
  v_tree := btrim(coalesce(v_readback.evidence_payload->>'tree_sha',''));
  v_entrypoint := rtrim(v_exec.target_path,'/')||'/SKILL.md';
  v_slug := regexp_replace(v_exec.target_path,'^profiles/','','i');

  if v_repo<>v_exec.target_repo then
    raise exception 'LF_PROFILE_CANDIDATE_REPO_MISMATCH:%:%',v_repo,v_exec.target_repo;
  end if;
  if v_branch='' or v_commit !~ '^[0-9a-f]{40}$' or v_tree !~ '^[0-9a-f]{40}$' then
    raise exception 'LF_PROFILE_CANDIDATE_SOURCE_IDENTITY_INVALID';
  end if;
  if jsonb_typeof(v_readback.evidence_payload->'readback_files')<>'array'
     or not exists (
       select 1 from jsonb_array_elements_text(v_readback.evidence_payload->'readback_files') f(path)
       where f.path=v_entrypoint
     ) then
    raise exception 'LF_PROFILE_CANDIDATE_ENTRYPOINT_NOT_READBACK:%',v_entrypoint;
  end if;

  select * into v_existing
  from public.lf_activos
  where codigo_activo=v_exec.target_code and archived_at is null;
  if found then
    raise exception 'LF_PROFILE_CANDIDATE_ALREADY_REGISTERED:%',v_exec.target_code;
  end if;

  -- Legacy physical compatibility only. These fields are not authority.
  v_source_row := coalesce(p_source_pr,to_char(clock_timestamp(),'YYYYMMDD')::integer);

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,estado_original,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    version,ruta_esperada,url,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,raw_payload,
    metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    v_exec.target_code,
    upper(regexp_replace(v_exec.target_code,'[^A-Za-z0-9]+','_','g')),
    'PERFIL',
    p_display_name,
    'CANDIDATE_READ_ONLY',
    'CANDIDATO','READ_ONLY','PROFILE_REGISTRY','NO_HABILITADO','BLOQUEADO',
    nullif(btrim(p_version),''),
    v_exec.target_path,
    'supabase://public/lf_activos/'||v_exec.target_code,
    'GITHUB_PROFILE_REGISTRY','GitHub profile registry','profiles',v_source_row,gen_random_uuid(),
    jsonb_build_object(
      'path',v_entrypoint,
      'repo',v_repo,
      'source_commit',v_commit,
      'profile_pack_id',p_profile_pack_id,
      'registration_reason','governed_profile_create_candidate_materialization',
      'compatibility_source_row_semantics',case when p_source_pr is null then 'materialization_date' else 'source_pr_number' end
    ),
    jsonb_build_object(
      'repo',v_repo,
      'repo_path',v_exec.target_path,
      'display_name',p_display_name,
      'profile_slug',v_slug,
      'entrypoint_path',v_entrypoint,
      'profile_pack_id',p_profile_pack_id,
      'registry_source','SUPABASE',
      'runtime_enabled',false,
      'automatic_impact_enabled',false,
      'creator_execution_id',p_execution_id,
      'source_pr',p_source_pr,
      'source_branch',v_branch,
      'source_commit',v_commit,
      'source_tree',v_tree,
      'source_readback_status','PASS',
      'source_governance',jsonb_build_object(
        'authority_system','SUPABASE',
        'github_role','TECHNICAL_IMPLEMENTATION_ARTIFACT',
        'github_is_authority',false,
        'operational_source_ref','supabase://public/lf_activos/'||v_exec.target_code
      )
    ),
    p_execution_id,
    p_execution_id
  ) returning * into v_inserted;

  if v_inserted.estado_documental<>'CANDIDATO'
     or v_inserted.estado_operativo<>'READ_ONLY'
     or v_inserted.nivel_control<>'PROFILE_REGISTRY'
     or v_inserted.runtime_estado<>'NO_HABILITADO'
     or v_inserted.impacto_automatico<>'BLOQUEADO' then
    raise exception 'LF_PROFILE_CANDIDATE_STATE_ESCALATION';
  end if;

  return jsonb_build_object(
    'result','PROFILE_CANDIDATE_MATERIALIZED',
    'execution_id',p_execution_id,
    'profile_code',v_inserted.codigo_activo,
    'profile_pack_id',p_profile_pack_id,
    'source_commit',v_commit,
    'source_branch',v_branch,
    'estado_documental',v_inserted.estado_documental,
    'estado_operativo',v_inserted.estado_operativo,
    'nivel_control',v_inserted.nivel_control,
    'runtime_estado',v_inserted.runtime_estado,
    'impacto_automatico',v_inserted.impacto_automatico,
    'operational_source_ref',v_inserted.url
  );
end;
$function$;
