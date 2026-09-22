-- MC-01: transport an externally resolved, exact research bundle through the
-- existing profile-runtime queue without adding a parallel runtime.
--
-- This overload reuses the canonical text enqueue, then binds a queue-native
-- research envelope before the worker can claim the PENDING row.

create or replace function programacion.fn_lf_profile_runtime_enqueue_text_v1(
  p_request_text text,
  p_profile_code text,
  p_research_bundle jsonb,
  p_requested_by text,
  p_github_backup_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_request_id uuid;
  v_manifest jsonb;
  v_resolved jsonb;
begin
  if nullif(btrim(coalesce(p_github_backup_reason,'')),'') is not null then
    raise exception using
      errcode='23514',
      message='SRCR_EXTERNAL_RESEARCH_REQUIRES_HETZNER_RUNTIME';
  end if;

  if jsonb_typeof(p_research_bundle) is distinct from 'object'
     or coalesce(p_research_bundle->>'schema','') <> 'SRCR_EXTERNAL_AUTHORITY_RESOLUTION_V1'
     or coalesce(p_research_bundle->>'research_execution_mode','') <> 'EXTERNAL_AUTHORITY_RESOLVER' then
    raise exception using
      errcode='23514',
      message='SRCR_LIVE_RESEARCH_EXECUTION_PATH_MISSING';
  end if;

  v_manifest := p_research_bundle->'evidence_manifest';
  v_resolved := p_research_bundle->'resolved_authority_context';

  if jsonb_typeof(v_manifest) is distinct from 'object'
     or jsonb_typeof(v_manifest->'evidence') is distinct from 'array'
     or jsonb_array_length(v_manifest->'evidence') < 1
     or jsonb_typeof(v_manifest->'query_trace') is distinct from 'array'
     or jsonb_array_length(v_manifest->'query_trace') < 1 then
    raise exception using
      errcode='23514',
      message='SRCR_RESEARCH_EVIDENCE_BUNDLE_INCOMPLETE';
  end if;

  if jsonb_typeof(v_resolved) is distinct from 'object'
     or v_resolved = '{}'::jsonb then
    raise exception using
      errcode='23514',
      message='SRCR_RESOLVED_AUTHORITY_CONTEXT_REQUIRED';
  end if;

  if pg_column_size(v_resolved) > 120000 then
    raise exception using
      errcode='23514',
      message='SRCR_RESOLVED_AUTHORITY_CONTEXT_BUDGET_EXCEEDED';
  end if;

  v_base := programacion.fn_lf_profile_runtime_enqueue_text_v1(
    p_request_text,
    p_profile_code,
    p_requested_by,
    null
  );
  v_request_id := (v_base->>'request_id')::uuid;

  update private.lf_profile_runtime_queue_v1
     set runtime_request_envelope = jsonb_build_object(
           'schema','LF_PROFILE_RUNTIME_QUEUE_RESEARCH_V1',
           'route_kind','QUEUE_NATIVE_RESEARCH',
           'research_execution_mode','EXTERNAL_AUTHORITY_RESOLVER',
           'evidence_manifest',v_manifest,
           'resolved_authority_context',v_resolved
         ),
         updated_at = now()
   where request_id = v_request_id
     and status = 'PENDING'
     and runtime_target = 'HETZNER';

  if not found then
    raise exception using
      errcode='23514',
      message='SRCR_RESEARCH_QUEUE_BINDING_FAILED';
  end if;

  return v_base || jsonb_build_object(
    'research_execution_mode','EXTERNAL_AUTHORITY_RESOLVER',
    'research_bundle_bound',true,
    'research_envelope_schema','LF_PROFILE_RUNTIME_QUEUE_RESEARCH_V1'
  );
end;
$function$;

revoke all on function programacion.fn_lf_profile_runtime_enqueue_text_v1(text,text,jsonb,text,text) from public;
grant execute on function programacion.fn_lf_profile_runtime_enqueue_text_v1(text,text,jsonb,text,text) to service_role;
