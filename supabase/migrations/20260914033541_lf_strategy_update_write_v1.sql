create or replace function public.lf_strategy_update_write_v1(
  p_execution_id text,
  p_snapshot_id bigint,
  p_expected_revision_sha256 text,
  p_patch jsonb
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public','extensions'
as $function$
declare
  x public.lf_operation_execution%rowtype;
  s public.lf_strategy_snapshots%rowtype;
  a public.lf_strategy_snapshots%rowtype;
  before_sha text;
  after_sha text;
  nowv timestamptz := clock_timestamp();
  old_progress_keys text[];
  new_progress_keys text[];
  patch_key text;
  new_metadata jsonb;
begin
  if btrim(coalesce(p_execution_id,''))='' or p_snapshot_id is null or coalesce(p_expected_revision_sha256,'') !~ '^[0-9a-f]{64}$' or p_patch is null or jsonb_typeof(p_patch)<>'object' then
    raise exception 'LF_STRATEGY_UPDATE_INPUT_INVALID';
  end if;

  for patch_key in select jsonb_object_keys(p_patch) loop
    if patch_key not in ('progress','metadata_merge','backlog','evidence_refs_append','change_log_append') then
      raise exception 'LF_STRATEGY_UPDATE_PATCH_KEY_NOT_ALLOWED:%', patch_key;
    end if;
  end loop;

  if jsonb_typeof(p_patch->'progress')<>'object'
     or jsonb_typeof(coalesce(p_patch->'metadata_merge','{}'::jsonb))<>'object'
     or jsonb_typeof(p_patch->'backlog')<>'array'
     or jsonb_typeof(p_patch->'evidence_refs_append')<>'array'
     or jsonb_typeof(p_patch->'change_log_append')<>'array'
     or jsonb_array_length(p_patch->'evidence_refs_append')=0
     or jsonb_array_length(p_patch->'change_log_append')=0 then
    raise exception 'LF_STRATEGY_UPDATE_PATCH_SHAPE_INVALID';
  end if;

  if coalesce(p_patch->'metadata_merge','{}'::jsonb) ?| array['progress','strategy_close'] then
    raise exception 'LF_STRATEGY_UPDATE_PROTECTED_METADATA_KEY';
  end if;

  select * into x from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or x.operation_code<>'ACTUALIZACION_ESTRATEGIA_LF' or x.status<>'IN_PROGRESS' or x.target_type<>'STRATEGY' then
    raise exception 'LF_STRATEGY_UPDATE_EXECUTION_BINDING_MISMATCH';
  end if;

  select * into s from public.lf_strategy_snapshots where id=p_snapshot_id for update;
  if not found or x.target_code<>s.snapshot_code or x.target_path is distinct from format('supabase://public/lf_strategy_snapshots/%s',s.id) then
    raise exception 'LF_STRATEGY_UPDATE_TARGET_MISMATCH';
  end if;

  if coalesce(s.metadata->'strategy_close'->>'status','')='CLOSED' then
    raise exception 'LF_STRATEGY_UPDATE_CLOSED_SNAPSHOT';
  end if;

  if s.status<>'CANDIDATO_READ_ONLY' or s.visibility<>'READ_ONLY_INTERNAL' or s.runtime_state<>'NO_HABILITADO' or s.impact_policy<>'BLOQUEADO' then
    raise exception 'LF_STRATEGY_UPDATE_CANDIDATE_READ_ONLY_CEILING_REQUIRED';
  end if;

  before_sha:=encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex');
  if before_sha<>p_expected_revision_sha256 then
    raise exception 'LF_STRATEGY_UPDATE_STALE_REVISION';
  end if;

  if jsonb_typeof(s.metadata->'progress')<>'object' or s.metadata->'progress'->>'contract_version'<>'STRATEGY_PROGRESS_CONTRACT_V1' then
    raise exception 'LF_STRATEGY_UPDATE_BASELINE_PROGRESS_CONTRACT_INVALID';
  end if;

  if p_patch->'progress'->>'contract_version'<>'STRATEGY_PROGRESS_CONTRACT_V1' then
    raise exception 'LF_STRATEGY_UPDATE_PROGRESS_CONTRACT_INVALID';
  end if;

  select array_agg(k order by k) into old_progress_keys from jsonb_object_keys(s.metadata->'progress') k;
  select array_agg(k order by k) into new_progress_keys from jsonb_object_keys(p_patch->'progress') k;
  if old_progress_keys is distinct from new_progress_keys then
    raise exception 'LF_STRATEGY_UPDATE_PROGRESS_KEYSET_MISMATCH';
  end if;

  if p_patch->'progress'->>'strategy_id' is distinct from s.id::text
     or p_patch->'progress'->>'strategy_code' is distinct from s.snapshot_code
     or p_patch->'progress'->>'strategy_version' is distinct from s.version
     or p_patch->'progress'->>'snapshot_status' is distinct from s.status
     or p_patch->'progress'->>'runtime_state' is distinct from s.runtime_state
     or p_patch->'progress'->>'impact_policy' is distinct from s.impact_policy
     or p_patch->'progress'->>'claim_ceiling' is distinct from s.metadata->'progress'->>'claim_ceiling' then
    raise exception 'LF_STRATEGY_UPDATE_PROGRESS_IDENTITY_OR_CEILING_MISMATCH';
  end if;

  new_metadata := (coalesce(s.metadata,'{}'::jsonb) || coalesce(p_patch->'metadata_merge','{}'::jsonb));
  new_metadata := jsonb_set(new_metadata,'{progress}',p_patch->'progress',true);

  update public.lf_strategy_snapshots
     set metadata = new_metadata,
         backlog = p_patch->'backlog',
         evidence_refs = coalesce(evidence_refs,'[]'::jsonb) || p_patch->'evidence_refs_append',
         change_log = coalesce(change_log,'[]'::jsonb) || p_patch->'change_log_append',
         updated_at = nowv,
         updated_by_execution_id = p_execution_id
   where id=s.id
   returning * into a;

  if a.status is distinct from s.status
     or a.visibility is distinct from s.visibility
     or a.runtime_state is distinct from s.runtime_state
     or a.impact_policy is distinct from s.impact_policy
     or a.content_payload is distinct from s.content_payload
     or a.risks is distinct from s.risks
     or a.snapshot_code is distinct from s.snapshot_code
     or a.version is distinct from s.version
     or coalesce(a.metadata->'strategy_close','null'::jsonb) is distinct from coalesce(s.metadata->'strategy_close','null'::jsonb) then
    raise exception 'LF_STRATEGY_UPDATE_POSTWRITE_INVARIANT';
  end if;

  after_sha:=encode(extensions.digest(to_jsonb(a)::text,'sha256'),'hex');
  return jsonb_build_object(
    'result','STRATEGY_UPDATED_WITH_EVIDENCE',
    'snapshot_id',a.id,
    'snapshot_code',a.snapshot_code,
    'before_revision_sha256',before_sha,
    'after_revision_sha256',after_sha,
    'progress_key_count',coalesce(array_length(new_progress_keys,1),0),
    'changed_paths',jsonb_build_array('metadata.progress','metadata.merge','backlog','evidence_refs.append','change_log.append','updated_at','updated_by_execution_id'),
    'status_runtime_impact_preserved',true
  );
end
$function$;

revoke all on function public.lf_strategy_update_write_v1(text,bigint,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_strategy_update_write_v1(text,bigint,text,jsonb) to service_role;
comment on function public.lf_strategy_update_write_v1(text,bigint,text,jsonb) is 'Governed CAS writer for ACTUALIZACION_ESTRATEGIA_LF. Existing candidate/read-only strategy snapshots only; preserves runtime/impact/visibility/content/risks and STRATEGY_PROGRESS_CONTRACT_V1 keyset.';