begin;

alter table private.lf_profile_runtime_queue_v1
  add column if not exists runtime_backup_reason text;

alter table private.lf_profile_runtime_queue_v1
  drop constraint if exists lf_profile_runtime_queue_hetzner_envelope_ck;

alter table private.lf_profile_runtime_queue_v1
  add constraint lf_profile_runtime_queue_hetzner_envelope_ck
  check (
    runtime_target <> 'HETZNER'
    or (
      runtime_request_envelope is not null
      and jsonb_typeof(runtime_request_envelope) = 'object'
    )
    or (
      runtime_request_envelope is null
      and input_image_base64 is null
      and input_image_media_type is null
      and input_image_sha256 is null
    )
  );

create or replace function private.fn_lf_profile_runtime_default_route_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.runtime_target = 'HETZNER'
     and new.runtime_request_envelope is null
     and (
       new.input_image_base64 is not null
       or new.input_image_media_type is not null
       or new.input_image_sha256 is not null
     ) then
    raise exception using
      errcode = '23514',
      message = 'HETZNER_IMAGE_REQUEST_ENVELOPE_REQUIRED_NO_IMPLICIT_GITHUB_FALLBACK';
  end if;

  if new.runtime_target = 'GITHUB_ACTIONS'
     and nullif(btrim(coalesce(new.runtime_backup_reason, '')), '') is null then
    raise exception using
      errcode = '23514',
      message = 'GITHUB_ACTIONS_EXPLICIT_BACKUP_REASON_REQUIRED';
  end if;

  return new;
end;
$function$;

revoke all on function private.fn_lf_profile_runtime_default_route_v1() from public;

comment on column private.lf_profile_runtime_queue_v1.runtime_target is
  'Authoritative execution transport. Default HETZNER. Text-only queue-native HETZNER requests may omit runtime_request_envelope. Image/screen-bound HETZNER requests require a governed envelope. GITHUB_ACTIONS is explicit backup only.';

comment on column private.lf_profile_runtime_queue_v1.runtime_backup_reason is
  'Required on NEW GITHUB_ACTIONS rows by the insert routing trigger. Records the explicit reason the backup transport was selected.';

create or replace function programacion.fn_lf_profile_runtime_enqueue_text_v1(
  p_request_text text,
  p_profile_code text,
  p_requested_by text default 'ACT-0001',
  p_github_backup_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_slug text;
  v_entrypoint_path text;
  v_route jsonb;
  v_request_id uuid := gen_random_uuid();
  v_runtime_target text;
begin
  if nullif(btrim(coalesce(p_request_text, '')), '') is null then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_REQUEST_TEXT_REQUIRED';
  end if;
  if nullif(btrim(coalesce(p_profile_code, '')), '') is null then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_PROFILE_CODE_REQUIRED';
  end if;
  if nullif(btrim(coalesce(p_requested_by, '')), '') is null then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_REQUESTED_BY_REQUIRED';
  end if;

  select a.metadata->>'profile_slug',
         coalesce(
           nullif(a.metadata->>'entrypoint_path',''),
           case
             when a.ruta_esperada like '%.md' then a.ruta_esperada
             when nullif(a.ruta_esperada,'') is not null then rtrim(a.ruta_esperada,'/') || '/SKILL.md'
             else null
           end
         )
    into v_profile_slug, v_entrypoint_path
  from public.lf_activos a
  where a.codigo_activo = p_profile_code
    and a.tipo_activo = 'PERFIL'
    and a.archived_at is null
  limit 1;

  if nullif(v_profile_slug,'') is null or nullif(v_entrypoint_path,'') is null then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_PROFILE_BINDING_UNRESOLVED';
  end if;

  v_route := public.lf_router_resolve_v1(
    p_request_text,
    p_profile_code,
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );

  if coalesce(v_route->>'status','') <> 'READY_TO_EXECUTE'
     or coalesce((v_route->>'downstream_execution_allowed')::boolean,false) is not true
     or coalesce(v_route->>'operation_code','') <> 'EJECUCION_PERFIL_LF' then
    raise exception using
      errcode='23514',
      message='PROFILE_RUNTIME_ROUTER_NOT_READY',
      detail=left(coalesce(v_route::text,'{}'),1000);
  end if;

  v_runtime_target := case
    when nullif(btrim(coalesce(p_github_backup_reason,'')),'') is null then 'HETZNER'
    else 'GITHUB_ACTIONS'
  end;

  insert into private.lf_profile_runtime_queue_v1 (
    request_id,
    operation_code,
    profile_code,
    profile_slug,
    profile_source_paths,
    input_literal,
    status,
    requested_by,
    runtime_target,
    runtime_request_envelope,
    runtime_backup_reason
  ) values (
    v_request_id,
    'EJECUCION_PERFIL_LF',
    p_profile_code,
    v_profile_slug,
    jsonb_build_array(v_entrypoint_path),
    p_request_text,
    'PENDING',
    p_requested_by,
    v_runtime_target,
    null,
    nullif(btrim(coalesce(p_github_backup_reason,'')),'')
  );

  return jsonb_build_object(
    'request_id',v_request_id,
    'status','PENDING',
    'runtime_target',v_runtime_target,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',p_profile_code,
    'profile_slug',v_profile_slug,
    'profile_source_paths',jsonb_build_array(v_entrypoint_path),
    'router_status',v_route->>'status',
    'input_governance',v_route->'input_governance',
    'github_backup_explicit',v_runtime_target='GITHUB_ACTIONS'
  );
end;
$function$;

revoke all on function programacion.fn_lf_profile_runtime_enqueue_text_v1(text,text,text,text) from public;
grant execute on function programacion.fn_lf_profile_runtime_enqueue_text_v1(text,text,text,text) to service_role;

comment on function programacion.fn_lf_profile_runtime_enqueue_text_v1(text,text,text,text) is
  'Canonical ACT-0001 producer for text-only EJECUCION_PERFIL_LF requests. Resolves Router first, derives profile binding from the live asset registry, targets HETZNER by default, and permits GITHUB_ACTIONS only with an explicit backup reason. Screen/image-bound work is outside this function and must use a governed runtime_request_envelope.';

commit;
