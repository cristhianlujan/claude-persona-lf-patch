do $apply$
declare
  v_body text;
  v_blob text;
begin
  select content into v_body
  from net._http_response
  where id=9886 and status_code=200 and error_msg is null;
  if v_body is null then
    raise exception 'CARD_SUPABASE_NATIVE_SOURCE_BODY_NOT_AVAILABLE';
  end if;
  v_blob:=encode(
    extensions.digest(
      convert_to('blob '||octet_length(v_body)::text,'UTF8') || decode('00','hex') || convert_to(v_body,'UTF8'),
      'sha1'
    ),
    'hex'
  );
  if v_blob is distinct from '7c1d99e60eb6fee24b6c67792279372f5f5a731e' then
    raise exception 'CARD_SUPABASE_NATIVE_SOURCE_BLOB_MISMATCH expected=% actual=%','7c1d99e60eb6fee24b6c67792279372f5f5a731e',v_blob;
  end if;
  execute v_body;
end;
$apply$;