create or replace function public.fn_lf_p0_store_source_image_v1(
  p_review_id text,
  p_execution_id text,
  p_object_name text,
  p_mime_type text,
  p_content_base64 text,
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
  v_content bytea;
  v_actual_bytes bigint;
  v_actual_sha256 text;
  v_id uuid;
begin
  if nullif(btrim(coalesce(p_review_id,'')),'') is null
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_object_name,'')),'') is null then
    raise exception using errcode='23514', message='source evidence identity fields are required';
  end if;
  if p_mime_type <> 'image/png' then
    raise exception using errcode='23514', message='source evidence mime_type must be image/png';
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
  if p_content_base64 is null or length(p_content_base64) = 0 then
    raise exception using errcode='23514', message='source evidence content missing';
  end if;

  begin
    v_content := decode(p_content_base64,'base64');
  exception when others then
    raise exception using errcode='22023', message='source evidence base64 invalid';
  end;

  v_actual_bytes := octet_length(v_content);
  v_actual_sha256 := encode(extensions.digest(v_content,'sha256'),'hex');
  if v_actual_bytes <> p_expected_bytes then
    raise exception using errcode='23514', message='source evidence byte length mismatch';
  end if;
  if v_actual_sha256 <> p_expected_sha256 then
    raise exception using errcode='23514', message='source evidence sha256 mismatch';
  end if;

  insert into private.lf_p0_review_evidence_objects_v1(
    review_id, execution_id, object_role, object_name, mime_type,
    content_bytes, content_sha256, content, data_classification,
    source_head_sha, retention_policy, metadata
  ) values (
    p_review_id, p_execution_id, 'SOURCE_IMAGE', p_object_name, p_mime_type,
    v_actual_bytes, v_actual_sha256, v_content, p_data_classification,
    p_source_head_sha, 'UNTIL_TERMINAL_REVIEW', coalesce(p_metadata,'{}'::jsonb)
  ) returning evidence_object_id into v_id;

  return v_id;
end
$function$;

revoke all on function public.fn_lf_p0_store_source_image_v1(text,text,text,text,text,bigint,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.fn_lf_p0_store_source_image_v1(text,text,text,text,text,bigint,text,text,text,jsonb) to service_role;
comment on function public.fn_lf_p0_store_source_image_v1(text,text,text,text,text,bigint,text,text,text,jsonb) is 'Service-role-only source image persistence RPC. Decodes base64 and enforces byte length + SHA-256 before inserting into private P0 evidence storage.';
