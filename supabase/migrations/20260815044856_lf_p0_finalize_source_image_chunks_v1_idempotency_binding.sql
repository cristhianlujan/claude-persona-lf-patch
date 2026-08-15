create or replace function public.fn_lf_p0_finalize_source_image_chunks_v1(
  p_upload_id uuid,
  p_review_id text,
  p_execution_id text,
  p_object_name text,
  p_expected_chunk_count integer,
  p_expected_bytes bigint,
  p_expected_sha256 text,
  p_data_classification text,
  p_source_head_sha text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, private, extensions
as $function$
declare
  v_chunk_count integer;
  v_min_chunk integer;
  v_max_chunk integer;
  v_distinct_chunk_count integer;
  v_encoded_chars bigint;
  v_content_base64 text;
  v_content bytea;
  v_actual_bytes bigint;
  v_actual_sha256 text;
  v_existing_id uuid;
  v_evidence_object_id uuid;
  v_deleted_chunks integer;
begin
  if p_upload_id is null then
    raise exception using errcode='23514', message='upload_id is required';
  end if;
  if nullif(btrim(coalesce(p_review_id,'')),'') is null
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_object_name,'')),'') is null then
    raise exception using errcode='23514', message='source evidence identity fields are required';
  end if;
  if p_expected_chunk_count < 1 or p_expected_chunk_count > 2048 then
    raise exception using errcode='23514', message='expected chunk count out of range';
  end if;
  if p_expected_bytes < 1 or p_expected_bytes > 10485760 then
    raise exception using errcode='23514', message='source evidence expected bytes out of range';
  end if;
  if p_expected_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='23514', message='source evidence expected sha256 invalid';
  end if;
  if p_source_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception using errcode='23514', message='source evidence head sha invalid';
  end if;
  if p_data_classification not in ('CONFIDENTIAL','SENSITIVE') then
    raise exception using errcode='23514', message='source evidence classification invalid';
  end if;

  select
    count(*)::integer,
    min(chunk_no),
    max(chunk_no),
    count(distinct chunk_no)::integer,
    coalesce(sum(length(chunk_base64)),0)::bigint
  into
    v_chunk_count,
    v_min_chunk,
    v_max_chunk,
    v_distinct_chunk_count,
    v_encoded_chars
  from private.lf_p0_evidence_upload_chunks_v1
  where upload_id = p_upload_id;

  if v_chunk_count <> p_expected_chunk_count
     or v_distinct_chunk_count <> p_expected_chunk_count
     or v_min_chunk <> 0
     or v_max_chunk <> p_expected_chunk_count - 1 then
    raise exception using errcode='23514', message='source evidence chunks are missing, duplicated, or non-contiguous';
  end if;

  if v_encoded_chars < 4
     or v_encoded_chars > (((p_expected_bytes + 2) / 3) * 4 + 4) then
    raise exception using errcode='23514', message='source evidence encoded length out of range';
  end if;

  select string_agg(chunk_base64, '' order by chunk_no)
  into v_content_base64
  from private.lf_p0_evidence_upload_chunks_v1
  where upload_id = p_upload_id;

  if v_content_base64 is null or length(v_content_base64) = 0 then
    raise exception using errcode='23514', message='source evidence content missing';
  end if;

  begin
    v_content := decode(v_content_base64, 'base64');
  exception when others then
    raise exception using errcode='22023', message='source evidence base64 invalid';
  end;

  v_actual_bytes := octet_length(v_content);
  v_actual_sha256 := encode(extensions.digest(v_content, 'sha256'), 'hex');

  if v_actual_bytes <> p_expected_bytes then
    raise exception using errcode='23514', message='source evidence byte length mismatch';
  end if;
  if v_actual_sha256 <> p_expected_sha256 then
    raise exception using errcode='23514', message='source evidence sha256 mismatch';
  end if;

  select evidence_object_id
  into v_existing_id
  from private.lf_p0_review_evidence_objects_v1
  where object_role = 'SOURCE_IMAGE'
    and review_id = p_review_id
    and execution_id = p_execution_id
    and object_name = p_object_name
    and source_head_sha = p_source_head_sha
    and content_sha256 = p_expected_sha256
    and content_bytes = p_expected_bytes
  order by created_at asc
  limit 1;

  if v_existing_id is not null then
    v_evidence_object_id := v_existing_id;
  else
    v_evidence_object_id := public.fn_lf_p0_store_source_image_v1(
      p_review_id,
      p_execution_id,
      p_object_name,
      'image/png',
      v_content_base64,
      p_expected_bytes,
      p_expected_sha256,
      p_data_classification,
      p_source_head_sha,
      coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
        'source_transfer', 'PRIVATE_CHUNK_STAGING_CRYPTO_FINALIZE',
        'upload_id', p_upload_id,
        'expected_chunk_count', p_expected_chunk_count
      )
    );
  end if;

  perform 1
  from private.lf_p0_review_evidence_objects_v1
  where evidence_object_id = v_evidence_object_id
    and object_role = 'SOURCE_IMAGE'
    and review_id = p_review_id
    and execution_id = p_execution_id
    and object_name = p_object_name
    and source_head_sha = p_source_head_sha
    and mime_type = 'image/png'
    and content_bytes = p_expected_bytes
    and content_sha256 = p_expected_sha256
    and octet_length(content) = p_expected_bytes
    and encode(extensions.digest(content, 'sha256'), 'hex') = p_expected_sha256;

  if not found then
    raise exception using errcode='23514', message='source evidence durable readback mismatch';
  end if;

  delete from private.lf_p0_evidence_upload_chunks_v1
  where upload_id = p_upload_id;
  get diagnostics v_deleted_chunks = row_count;

  if v_deleted_chunks <> p_expected_chunk_count then
    raise exception using errcode='23514', message='source evidence staging cleanup mismatch';
  end if;

  return v_evidence_object_id;
end
$function$;

revoke all on function public.fn_lf_p0_finalize_source_image_chunks_v1(
  uuid,text,text,text,integer,bigint,text,text,text,jsonb
) from public, anon, authenticated;
grant execute on function public.fn_lf_p0_finalize_source_image_chunks_v1(
  uuid,text,text,text,integer,bigint,text,text,text,jsonb
) to service_role;

comment on function public.fn_lf_p0_finalize_source_image_chunks_v1(
  uuid,text,text,text,integer,bigint,text,text,text,jsonb
) is 'Service-role-only fail-closed finalizer for private chunked SOURCE_IMAGE uploads. Exact retry reuse is bound to review+execution+object+source-head+SHA+bytes; chunks must be contiguous, bytes+SHA must match, durable identity+content readback must pass, and staging is deleted only after verified persistence.';