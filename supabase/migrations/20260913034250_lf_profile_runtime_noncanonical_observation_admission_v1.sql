begin;

-- Strengthen the existing HETZNER queue admission gate so malformed
-- NON_CANONICAL_ARTIFACT observations fail before a request is persisted.
-- This mirrors the runtime Observation contract closely enough to prevent
-- producer/transport drift while preserving canonical-screen and text paths.
create or replace function private.fn_lf_profile_runtime_default_route_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_gov jsonb;
  v_set jsonb;
  v_entry jsonb;
  v_artifact jsonb;
  v_obs jsonb;
  v_bbox_value jsonb;
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

      for v_entry in select value from jsonb_array_elements(v_set->'artifacts')
      loop
        if jsonb_typeof(v_entry) <> 'object'
           or nullif(btrim(coalesce(v_entry->>'artifact_ref','')), '') is null
           or jsonb_typeof(v_entry->'artifact') <> 'object' then
          raise exception using errcode='23514', message='HETZNER_NONCANONICAL_ARTIFACT_ITEM_INVALID';
        end if;
        v_artifact := v_entry->'artifact';
        if jsonb_typeof(v_artifact->'observations') <> 'array'
           or jsonb_array_length(v_artifact->'observations') = 0 then
          raise exception using errcode='23514', message='HETZNER_NONCANONICAL_ARTIFACT_OBSERVATIONS_REQUIRED';
        end if;
        for v_obs in select value from jsonb_array_elements(v_artifact->'observations')
        loop
          if jsonb_typeof(v_obs) <> 'object' then
            raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_OBJECT_REQUIRED';
          end if;
          if exists (
            select 1
              from jsonb_object_keys(v_obs) as k(key)
             where k.key not in ('id','text','bbox','conf')
          ) then
            raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_KEYS_INVALID';
          end if;
          if nullif(btrim(coalesce(v_obs->>'text','')), '') is null
             or length(v_obs->>'text') > 1000 then
            raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_TEXT_INVALID';
          end if;
          if jsonb_typeof(v_obs->'bbox') <> 'array'
             or jsonb_array_length(v_obs->'bbox') <> 4 then
            raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_BBOX_INVALID';
          end if;
          for v_bbox_value in select value from jsonb_array_elements(v_obs->'bbox')
          loop
            if jsonb_typeof(v_bbox_value) <> 'number' then
              raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_BBOX_INVALID';
            end if;
          end loop;
          if (v_obs->'bbox'->>2)::numeric <= 0
             or (v_obs->'bbox'->>3)::numeric <= 0 then
            raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_BBOX_INVALID';
          end if;
          if v_obs ? 'conf'
             and (
               jsonb_typeof(v_obs->'conf') <> 'number'
               or (v_obs->>'conf')::numeric < -1
               or (v_obs->>'conf')::numeric > 100
             ) then
            raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_CONF_INVALID';
          end if;
          if v_obs ? 'id'
             and jsonb_typeof(v_obs->'id') not in ('null','string','number') then
            raise exception using errcode='23514', message='HETZNER_NONCANONICAL_OBSERVATION_ID_INVALID';
          end if;
        end loop;
      end loop;
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

comment on function private.fn_lf_profile_runtime_default_route_v1() is
'Queue admission guard. HETZNER noncanonical artifact-set observations must match the runtime Observation object contract before persistence; canonical and queue-native paths retain existing behavior.';

commit;
