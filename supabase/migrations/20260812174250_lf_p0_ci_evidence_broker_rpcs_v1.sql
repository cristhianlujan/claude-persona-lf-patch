create or replace function public.fn_lf_p0_get_source_image_v1(
  p_evidence_object_id uuid,
  p_expected_sha256 text,
  p_expected_bytes bigint
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, extensions
as $function$
declare
  v_row private.lf_p0_review_evidence_objects_v1%rowtype;
begin
  if p_expected_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='23514', message='source expected sha256 invalid';
  end if;
  if p_expected_bytes < 1 or p_expected_bytes > 10485760 then
    raise exception using errcode='23514', message='source expected bytes out of range';
  end if;
  select * into v_row
  from private.lf_p0_review_evidence_objects_v1
  where evidence_object_id = p_evidence_object_id
    and object_role = 'SOURCE_IMAGE'
    and content_sha256 = p_expected_sha256
    and content_bytes = p_expected_bytes;
  if not found then
    raise exception using errcode='P0002', message='source evidence object not found or integrity mismatch';
  end if;
  if octet_length(v_row.content) <> p_expected_bytes
     or encode(extensions.digest(v_row.content,'sha256'),'hex') <> p_expected_sha256 then
    raise exception using errcode='23514', message='source evidence cryptographic readback mismatch';
  end if;
  return jsonb_build_object(
    'evidence_object_id', v_row.evidence_object_id,
    'object_name', v_row.object_name,
    'mime_type', v_row.mime_type,
    'content_bytes', v_row.content_bytes,
    'content_sha256', v_row.content_sha256,
    'source_head_sha', v_row.source_head_sha,
    'content_base64', encode(v_row.content,'base64')
  );
end
$function$;

revoke all on function public.fn_lf_p0_get_source_image_v1(uuid,text,bigint) from public, anon, authenticated;
grant execute on function public.fn_lf_p0_get_source_image_v1(uuid,text,bigint) to service_role;
comment on function public.fn_lf_p0_get_source_image_v1(uuid,text,bigint) is 'Service-role-only cryptographic source readback for the exact-head CI evidence broker.';

create or replace function public.fn_lf_p0_store_exact_head_receipt_v1(
  p_review_id text,
  p_execution_id text,
  p_content_base64 text,
  p_expected_bytes bigint,
  p_expected_sha256 text,
  p_source_evidence_object_id uuid,
  p_source_sha256 text,
  p_source_head_sha text,
  p_configuration_sha256 text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, private, extensions
as $function$
declare
  v_content bytea;
  v_json jsonb;
  v_id uuid;
  v_source_ok boolean;
begin
  if nullif(btrim(coalesce(p_review_id,'')),'') is null
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception using errcode='23514', message='receipt identity fields are required';
  end if;
  if p_expected_bytes < 1 or p_expected_bytes > 10485760 then
    raise exception using errcode='23514', message='receipt expected bytes out of range';
  end if;
  if p_expected_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_sha256 !~ '^[0-9a-f]{64}$'
     or p_configuration_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='23514', message='receipt/source/config sha256 invalid';
  end if;
  if p_source_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception using errcode='23514', message='receipt source head sha invalid';
  end if;
  select exists(
    select 1 from private.lf_p0_review_evidence_objects_v1
    where evidence_object_id = p_source_evidence_object_id
      and object_role = 'SOURCE_IMAGE'
      and content_sha256 = p_source_sha256
      and encode(extensions.digest(content,'sha256'),'hex') = p_source_sha256
  ) into v_source_ok;
  if not v_source_ok then
    raise exception using errcode='23514', message='receipt source evidence dependency invalid';
  end if;
  begin
    v_content := decode(p_content_base64,'base64');
  exception when others then
    raise exception using errcode='22023', message='receipt base64 invalid';
  end;
  if octet_length(v_content) <> p_expected_bytes
     or encode(extensions.digest(v_content,'sha256'),'hex') <> p_expected_sha256 then
    raise exception using errcode='23514', message='receipt cryptographic integrity mismatch';
  end if;
  begin
    v_json := convert_from(v_content,'UTF8')::jsonb;
  exception when others then
    raise exception using errcode='22023', message='receipt JSON invalid';
  end;
  if v_json->>'source_sha256' <> p_source_sha256
     or v_json->>'code_head_sha' <> p_source_head_sha
     or v_json->>'configuration_sha256' <> p_configuration_sha256 then
    raise exception using errcode='23514', message='receipt semantic binding mismatch';
  end if;
  insert into private.lf_p0_review_evidence_objects_v1(
    review_id, execution_id, object_role, object_name, mime_type,
    content_bytes, content_sha256, content, data_classification,
    source_head_sha, retention_policy, metadata
  ) values (
    p_review_id, p_execution_id, 'PACKET_MANIFEST', 'p0-real-rerun-v4.json', 'application/json',
    p_expected_bytes, p_expected_sha256, v_content, 'SENSITIVE',
    p_source_head_sha, 'UNTIL_TERMINAL_REVIEW', coalesce(p_metadata,'{}'::jsonb)
  ) on conflict (review_id, object_role, content_sha256) do update
    set metadata = private.lf_p0_review_evidence_objects_v1.metadata || excluded.metadata
  returning evidence_object_id into v_id;
  return v_id;
end
$function$;

revoke all on function public.fn_lf_p0_store_exact_head_receipt_v1(text,text,text,bigint,text,uuid,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.fn_lf_p0_store_exact_head_receipt_v1(text,text,text,bigint,text,uuid,text,text,text,jsonb) to service_role;
comment on function public.fn_lf_p0_store_exact_head_receipt_v1(text,text,text,bigint,text,uuid,text,text,text,jsonb) is 'Service-role-only exact-head rerun receipt persistence with source/head/config semantic binding and SHA-256 readback.';
