begin;

-- Fail early when a manually inserted Hetzner envelope claims the Router's
-- NON_CANONICAL_ARTIFACT advisory path but does not use the canonical artifact-set
-- transport shape. Canonical-screen and queue-native text paths remain unchanged.
create or replace function private.fn_lf_profile_runtime_default_route_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_gov jsonb;
  v_set jsonb;
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

  if new.runtime_target = 'HETZNER'
     and new.runtime_request_envelope is not null
     and jsonb_typeof(new.runtime_request_envelope) = 'object' then
    v_gov := new.runtime_request_envelope->'input_governance';
    if jsonb_typeof(v_gov) = 'object'
       and coalesce(v_gov->>'subject_mode','') = 'NON_CANONICAL_ARTIFACT' then
      v_set := new.runtime_request_envelope->'artifact_set';
      if coalesce(v_gov->>'status','') <> 'ADVISORY_READ_ONLY'
         or coalesce(v_gov->>'decision','') <> 'ADVISORY'
         or coalesce((v_gov->>'continuation_allowed')::boolean,false) is not true
         or nullif(v_gov->>'blocking_code','') is not null
         or coalesce(v_gov#>>'{constraints,operation_must_equal}','') <> 'EJECUCION_PERFIL_LF'
         or coalesce((v_gov#>>'{constraints,read_only}')::boolean,false) is not true
         or coalesce((v_gov#>>'{constraints,no_write}')::boolean,false) is not true
         or coalesce((v_gov#>>'{constraints,no_promotion}')::boolean,false) is not true
         or coalesce((v_gov#>>'{constraints,canonical_registration_required}')::boolean,true) is not false
         or coalesce((v_gov#>>'{constraints,artifact_binding_required_before_profile_execution}')::boolean,false) is not true
         or jsonb_typeof(v_gov->'required_artifact_binding') <> 'array'
         or jsonb_array_length(v_gov->'required_artifact_binding') <> 3
         or not (v_gov->'required_artifact_binding' @> '["artifact_ref","artifact_sha256","dimensions"]'::jsonb) then
        raise exception using errcode='23514', message='HETZNER_NONCANONICAL_ADVISORY_CONTRACT_INVALID';
      end if;
      if jsonb_typeof(v_set) <> 'object'
         or coalesce(v_set->>'schema','') <> 'NON_CANONICAL_ARTIFACT_SET_V1'
         or coalesce(v_set->>'subject_mode','') <> 'NON_CANONICAL_ARTIFACT'
         or new.runtime_request_envelope ? 'artifact'
         or new.runtime_request_envelope ? 'related_artifacts'
         or jsonb_typeof(v_set->'artifacts') <> 'array'
         or jsonb_array_length(v_set->'artifacts') not between 1 and 8 then
        raise exception using errcode='23514', message='HETZNER_NONCANONICAL_ARTIFACT_SET_REQUIRED';
      end if;
    end if;
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

create or replace function programacion.fn_lf_profile_runtime_enqueue_noncanonical_artifact_set_v1(
  p_request_text text,
  p_profile_code text,
  p_artifacts jsonb,
  p_runtime_output_mode text default 'AUTO',
  p_requested_by text default 'ACT-0001'
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
  v_gov jsonb;
  v_request_id uuid := gen_random_uuid();
  v_artifact_set jsonb := '[]'::jsonb;
  v_item jsonb;
  v_artifact jsonb;
  v_ref text;
  v_filename text;
  v_sha text;
  v_width integer;
  v_height integer;
  v_screen_code text;
  v_index integer := 0;
  v_refs text[] := array[]::text[];
  v_shas text[] := array[]::text[];
begin
  if nullif(btrim(coalesce(p_request_text,'')), '') is null then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_REQUEST_TEXT_REQUIRED';
  end if;
  if nullif(btrim(coalesce(p_profile_code,'')), '') is null then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_PROFILE_CODE_REQUIRED';
  end if;
  if nullif(btrim(coalesce(p_requested_by,'')), '') is null then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_REQUESTED_BY_REQUIRED';
  end if;
  if p_runtime_output_mode not in ('AUTO','UI_FOCUSED_DECISION','UI_PRODUCTION_SPEC','UI_MISSING_INPUT') then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_OUTPUT_MODE_INVALID';
  end if;
  if jsonb_typeof(p_artifacts) <> 'array' or jsonb_array_length(p_artifacts) not between 1 and 8 then
    raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_SET_SIZE_INVALID';
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
  if p_runtime_output_mode <> 'AUTO' and v_profile_slug <> 'ui_architect' then
    raise exception using errcode='23514', message='RUNTIME_OUTPUT_MODE_PROFILE_MISMATCH';
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
    raise exception using errcode='23514', message='PROFILE_RUNTIME_ROUTER_NOT_READY', detail=left(coalesce(v_route::text,'{}'),1000);
  end if;

  v_gov := v_route->'input_governance';
  if jsonb_typeof(v_gov) <> 'object'
     or coalesce(v_gov->>'subject_mode','') <> 'NON_CANONICAL_ARTIFACT'
     or coalesce(v_gov->>'status','') <> 'ADVISORY_READ_ONLY'
     or coalesce(v_gov->>'decision','') <> 'ADVISORY'
     or coalesce((v_gov->>'continuation_allowed')::boolean,false) is not true
     or nullif(v_gov->>'blocking_code','') is not null
     or coalesce(v_gov#>>'{constraints,operation_must_equal}','') <> 'EJECUCION_PERFIL_LF'
     or coalesce((v_gov#>>'{constraints,read_only}')::boolean,false) is not true
     or coalesce((v_gov#>>'{constraints,no_write}')::boolean,false) is not true
     or coalesce((v_gov#>>'{constraints,no_promotion}')::boolean,false) is not true
     or coalesce((v_gov#>>'{constraints,canonical_registration_required}')::boolean,true) is not false
     or coalesce((v_gov#>>'{constraints,artifact_binding_required_before_profile_execution}')::boolean,false) is not true
     or jsonb_typeof(v_gov->'required_artifact_binding') <> 'array'
     or jsonb_array_length(v_gov->'required_artifact_binding') <> 3
     or not (v_gov->'required_artifact_binding' @> '["artifact_ref","artifact_sha256","dimensions"]'::jsonb) then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_NONCANONICAL_ADVISORY_NOT_AUTHORIZED';
  end if;

  for v_item in select value from jsonb_array_elements(p_artifacts)
  loop
    v_index := v_index + 1;
    if jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_ITEM_INVALID';
    end if;
    v_ref := nullif(btrim(coalesce(v_item->>'artifact_ref','')), '');
    v_filename := nullif(btrim(coalesce(v_item->>'filename','')), '');
    v_sha := lower(nullif(btrim(coalesce(v_item->>'image_sha256','')), ''));
    begin
      v_width := (v_item->>'width_px')::integer;
      v_height := (v_item->>'height_px')::integer;
    exception when others then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_DIMENSIONS_INVALID';
    end;
    if v_ref is null or v_filename is null then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_IDENTITY_MISSING';
    end if;
    if v_sha is null or v_sha !~ '^[0-9a-f]{64}$' then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_SHA256_INVALID';
    end if;
    if v_width is null or v_width <= 0 or v_width > 20000 or v_height is null or v_height <= 0 or v_height > 20000 then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_DIMENSIONS_INVALID';
    end if;
    if v_ref = any(v_refs) then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_REF_DUPLICATE';
    end if;
    if v_sha = any(v_shas) then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_SHA256_DUPLICATE';
    end if;
    if jsonb_typeof(v_item->'observations') <> 'array' or jsonb_array_length(v_item->'observations') = 0 then
      raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_OBSERVATIONS_REQUIRED';
    end if;
    v_refs := array_append(v_refs, v_ref);
    v_shas := array_append(v_shas, v_sha);
    v_screen_code := coalesce(nullif(btrim(v_item->>'screen_code'),''), 'NONCANONICAL_ARTIFACT_' || lpad(v_index::text,2,'0'));
    v_artifact := jsonb_build_object(
      'screen_code',v_screen_code,
      'filename',v_filename,
      'image_sha256',v_sha,
      'width_px',v_width,
      'height_px',v_height,
      'observations',v_item->'observations'
    );
    if nullif(v_item->>'image_base64','') is not null or nullif(v_item->>'image_media_type','') is not null then
      if nullif(v_item->>'image_base64','') is null or coalesce(v_item->>'image_media_type','') not in ('image/png','image/jpeg','image/webp') then
        raise exception using errcode='23514', message='NONCANONICAL_ARTIFACT_IMAGE_BINDING_INCOMPLETE';
      end if;
      v_artifact := v_artifact || jsonb_build_object('image_base64',v_item->>'image_base64','image_media_type',v_item->>'image_media_type');
    end if;
    v_artifact_set := v_artifact_set || jsonb_build_array(jsonb_build_object('artifact_ref',v_ref,'artifact',v_artifact));
  end loop;

  insert into private.lf_profile_runtime_queue_v1 (
    request_id, operation_code, profile_code, profile_slug, profile_source_paths,
    input_literal, status, requested_by, runtime_target, runtime_request_envelope,
    runtime_backup_reason
  ) values (
    v_request_id, 'EJECUCION_PERFIL_LF', p_profile_code, v_profile_slug,
    jsonb_build_array(v_entrypoint_path), p_request_text, 'PENDING', p_requested_by,
    'HETZNER',
    jsonb_build_object(
      'artifact_set',jsonb_build_object(
        'schema','NON_CANONICAL_ARTIFACT_SET_V1',
        'subject_mode','NON_CANONICAL_ARTIFACT',
        'artifacts',v_artifact_set
      ),
      'input_governance',v_gov,
      'profile',jsonb_build_object(
        'request_id',v_request_id::text,
        'operation_code','EJECUCION_PERFIL_LF',
        'profile_code',p_profile_code,
        'profile_slug',v_profile_slug,
        'profile_source_paths',jsonb_build_array(v_entrypoint_path),
        'input_literal',p_request_text,
        'input_fields','{}'::jsonb,
        'runtime_output_mode',p_runtime_output_mode,
        'required_adapter_codes',coalesce(v_gov->'required_by_adapters','[]'::jsonb),
        'required_card_refs','[]'::jsonb,
        'lf_card_sources','[]'::jsonb,
        'send_image_to_model',false
      )
    ),
    null
  );

  return jsonb_build_object(
    'request_id',v_request_id,
    'status','PENDING',
    'runtime_target','HETZNER',
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',p_profile_code,
    'profile_slug',v_profile_slug,
    'runtime_output_mode',p_runtime_output_mode,
    'router_status',v_route->>'status',
    'subject_mode',v_gov->>'subject_mode',
    'input_governance_status',v_gov->>'status',
    'continuation_allowed',(v_gov->>'continuation_allowed')::boolean,
    'artifact_count',jsonb_array_length(v_artifact_set),
    'canonical_registration_required',false
  );
end;
$function$;

revoke all on function programacion.fn_lf_profile_runtime_enqueue_noncanonical_artifact_set_v1(text,text,jsonb,text,text) from public;
grant execute on function programacion.fn_lf_profile_runtime_enqueue_noncanonical_artifact_set_v1(text,text,jsonb,text,text) to service_role;

comment on function programacion.fn_lf_profile_runtime_enqueue_noncanonical_artifact_set_v1(text,text,jsonb,text,text) is
  'Canonical ACT-0001 producer for governed NON_CANONICAL_ARTIFACT_SET_V1 profile execution. It resolves the live Router first, requires ADVISORY_READ_ONLY + continuation_allowed, exact artifact identity/dimensions/observations, and emits a Hetzner-only read-only envelope. It never creates or promotes canonical screens.';

commit;
